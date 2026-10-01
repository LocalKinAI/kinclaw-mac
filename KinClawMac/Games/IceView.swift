import AppKit
import SwiftUI

/// Who is lord of the frozen city.
enum IceSeat: String, CaseIterable, Identifiable {
    case me, computer, jev, tev1, nimble, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "tev1", "nimble", "大模型"][Self.allCases.firstIndex(of: self)!] }
    /// tev1 or nimble: an open decision model on the box's Ollama, asked Jev's own question.
    var open: String? { self == .tev1 || self == .nimble ? rawValue : nil }
    /// Jev, or an open model of its kind.
    var decides: Bool { self == .jev || open != nil }
    /// Does somebody other than the script decide what comes first?
    var commands: Bool { decides || self == .llm }
}

/// 冰河三国（建造）, played with the mouse: the city's clock, who is lord, what
/// is selected and being placed, the matters at the gate, the county map, and
/// the orders a click becomes.
@MainActor
final class IceGame: ObservableObject {
    static let shared = IceGame()

    @Published private(set) var beat = 0
    /// Paused until somebody presses 开始, like every game in the app.
    @Published var speed = 0.0 { didSet { if speed > 0, loop == nil { start() } } }
    private(set) var city: IceCity
    private var brain = IceBrain()
    private(set) var seed: UInt64

    @Published var seat: IceSeat = .me { didSet { seated() } }
    /// For a chat model as lord: "host|model", or "" for the app's own pick.
    @Published var model = "" { didSet { UserDefaults.standard.set(model, forKey: "kinclaw.ice.model") } }
    /// The person's city: the computer decides how many work where, unless the person does.
    @Published var autoStaff = true { didSet { UserDefaults.standard.set(autoStaff, forKey: "kinclaw.ice.autostaff") } }
    /// The most days a city has lasted: the ice age has no end, only a record.
    @Published private(set) var best = UserDefaults.standard.integer(forKey: "kinclaw.ice.bestDays") { didSet { UserDefaults.standard.set(best, forKey: "kinclaw.ice.bestDays") } }
    @Published var jevAdvises = false { didSet { advice = nil; lastAdvised = -99 } }
    @Published private(set) var advice: (option: IceOption, chance: Double)?
    /// What the lord who is not the person last decided, or why a question failed.
    @Published private(set) var note: String?

    @Published var camera = GameCamera(map: CGSize(width: IceCity.width, height: IceCity.height), focus: CGPoint(x: 32, y: 20))
    var viewSize = CGSize(width: 1200, height: 760)
    /// The page's measure (IceScale), for the camera to leave room under the glass strip.
    var scale: CGFloat = 1
    /// Has the camera framed the town for this view size yet?
    var framed = false

    @Published var selected: Int?
    @Published var placing: IceBuildKind? { didSet { if placing != nil { tool = nil; selected = nil } } }
    @Published var tool: IceTool? { didSet { if tool != nil { placing = nil; selected = nil } } }
    var hover: IceTile?
    var drag: (IceTile, IceTile)?

    /// The county map, and what is picked on it.
    @Published var showMap = false
    @Published var mapPick: Int?
    @Published var sendOfficer: Int?
    @Published var sendSoldiers = 20
    /// A general picked in the tray, to be put in charge of the next building clicked.
    @Published var assigning: Int?

    /// The answer a lord who is not the person chose for the matter at the gate, shown a moment before it is carried out.
    @Published private(set) var decided: (choice: Int, by: String, at: Date)?
    private var answering = false

    @Published private(set) var message: String?
    private var said = Date.distantPast
    private var loop: Task<Void, Never>?
    private var frames = 0
    private var asking = false, lastAsked = -99.0
    private var advising = false, lastAdvised = -99.0
    private var told = Set<String>()

    init() {
        seed = UInt64.random(in: 1...9999)
        city = IceCity(seed: seed)
        lookAtFurnace()
        if let kept = UserDefaults.standard.string(forKey: "kinclaw.ice.seat").flatMap(IceSeat.init(rawValue:)) { seat = kept }
        model = UserDefaults.standard.string(forKey: "kinclaw.ice.model") ?? ""
        if UserDefaults.standard.object(forKey: "kinclaw.ice.autostaff") != nil { autoStaff = UserDefaults.standard.bool(forKey: "kinclaw.ice.autostaff") }
    }

    var me: Bool { seat == .me }
    /// The clock stops while the person has a matter at the gate to answer.
    var waiting: Bool { me && city.incident != nil && !city.over }

    private func seated() {
        UserDefaults.standard.set(seat.rawValue, forKey: "kinclaw.ice.seat")
        brain.focus = nil; note = nil; advice = nil; lastAsked = -99; decided = nil
        if !me { placing = nil; tool = nil; assigning = nil }
    }

    func say(_ text: String) { message = text; said = Date() }
    var saying: String? { Date().timeIntervalSince(said) < 4 ? message : nil }

    // MARK: The clock

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                if speed > 0, !city.over, !waiting {
                    let dt = 1.0 / 60
                    for _ in 0..<max(1, Int(speed)) {
                        if !me { brain.think(&city, dt) } else if autoStaff { brain.staffOnly(&city, dt) }
                        city.step(dt)
                        if city.incident != nil, !me { break }
                    }
                    watch()
                    if seat.commands, !asking, city.time - lastAsked >= (seat.decides ? 10 : 20) { consult() }
                    if me, jevAdvises, !advising, city.time - lastAdvised >= 12 { advise() }
                }
                if city.incident != nil, !me, !city.over { settleIncident() }
                frames += 1
                if frames % 10 == 0 { beat += 1 }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    /// A fresh city — from a seed when given, for a game to replay or a test.
    func restart(seed chosen: UInt64? = nil) {
        seed = chosen ?? UInt64.random(in: 1...9999)
        city = IceCity(seed: seed)
        brain = IceBrain()
        selected = nil; placing = nil; tool = nil; message = nil; note = nil; advice = nil; decided = nil
        showMap = false; mapPick = nil; sendOfficer = nil; assigning = nil
        lastAsked = -99; lastAdvised = -99; told = []
        speed = 0; beat += 1
        framed = false
        lookAtFurnace()
    }

    /// Play on at once without drawing, the computer's hands at work, to a day (or until a matter comes to the gate):
    /// for tests, and for a panel tool that skips ahead.
    func fastForward(to day: Double, untilIncident: Bool = false) {
        let dt = 1.0 / 30
        while city.day < day, !city.over {
            brain.think(&city, dt)
            if let e = city.incident {
                if untilIncident { break }
                city.answer(IceBrain.answer(e, city))
            }
            city.step(dt)
        }
        beat += 1
    }

    /// Frame the town: the furnace's heat circle with a little snow round it filling the view below the glass strip.
    func lookAtFurnace() {
        let h = city.hub
        let S1 = min(viewSize.width / CGFloat(IceCity.width), viewSize.height / CGFloat(IceCity.height))
        let top = 78 * scale
        let rows = CGFloat(2 * city.heatRadius + 2.5)
        let S = max(S1, (viewSize.height - top) / rows)
        camera.zoom = min(GameCamera.closest, max(1, S / max(S1, 1)))
        let tile = camera.tile(viewSize)
        camera.focus = CGPoint(x: h.x, y: h.y - Double(top / 2 / max(tile, 1)))
        camera.settle(viewSize)
        framed = true
    }

    func zoom(by factor: CGFloat, at p: CGPoint? = nil) { camera.zoom(by: factor, at: p ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize) }
    func pan(_ dx: CGFloat, _ dy: CGFloat) { camera.pan(dx, dy, viewSize) }
    /// The tile under a point of the map view.
    func tile(at p: CGPoint) -> IceTile { let t = camera.at(p, viewSize); return IceTile(x: Int(floor(t.x)), y: Int(floor(t.y))) }

    /// How the city stands, in a few lines — for ice_status.
    var report: String {
        let w = city, l = IceLedger(w)
        var lines = ["冰河三国：第 \(w.today) 天（最久 \(max(best, w.today)) 天） · \(Int(w.temperature.rounded()))°C · 城主 \(seat.title) · \(speed == 0 ? "暂停" : "\(Int(speed))×")" + (w.ended.map { " · \($0)" } ?? "") + (waiting ? " · 等你回应城门口的事" : "")]
        lines.append("\(l.people) 人（病 \(l.sick) · 住在热圈外 \(l.cold) · 无家 \(l.homeless)）· 民心 \(Int(w.morale)) · 熔炉 \(l.level) 级\(l.upgrading ? "（升级中）" : "")，热圈 \(IceCommander.fmt(w.heatRadius)) 格，暖房 \(l.warmHouses)/\(l.houses) 座")
        let rate = { (g: Int) in Int((w.madeYesterday[g] - w.usedYesterday[g]).rounded()) }
        lines.append("煤 \(Int(l.coal))（\(rate(0) >= 0 ? "+" : "")\(rate(0))/天，烧 \(Int(l.burn))）· 木 \(Int(l.wood)) · 粮 \(Int(l.food))（\(rate(2) >= 0 ? "+" : "")\(rate(2))/天）· 石 \(Int(l.stone)) · 铁 \(Int(l.iron))")
        lines.append("兵 \(w.soldiers)（伤 \(w.wounded)）· 守城 \(Int(w.defenceAtHome)) · 城墙 \(w.wallTiles) 格 · 州 \(w.counties)/\(iceRegions.count - 1) · 武将 " + w.officers.map { iceOfficers[$0.officer].name + ($0.away ? "（出征）" : "") }.joined(separator: "、"))
        if let s = l.coldStart, let e = l.coldEnd { lines.append((l.coldIsBlizzard ? "大寒暴风雪" : "寒潮") + (s <= l.day ? "正在来：到第 \(e) 天" : "：第 \(s)–\(e) 天") + (l.coldIsBlizzard ? "" : " · 大寒暴风雪：第 \(l.blizzardStart)–\(l.blizzardEnd) 天")) }
        lines.append("死：冻 \(w.deaths["cold"] ?? 0) · 病 \(w.deaths["sick"] ?? 0) · 饿 \(w.deaths["hunger"] ?? 0) · 新来 \(w.arrivals) · 离开 \(w.departures) · 突袭 守住 \(w.raidsHeld) 失守 \(w.raidsLost)")
        let kinds = IceBuildKind.allCases.compactMap { k -> String? in let n = w.count(k); return n > 0 ? "\(k.name) \(n)" : nil }
        lines.append("建筑：" + kinds.joined(separator: " · "))
        if let e = w.incident { lines.append("城门口：\(IceCity.incidentTitles[e.kind])（" + IceCity.choices(e.kind).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ") + "）") }
        if let note { lines.append(note) }
        return lines.joined(separator: "\n")
    }

    // MARK: What the city says of its own accord

    private func watch() {
        let l = IceLedger(city)
        for e in city.moments where city.time - e.time < 0.05 {
            switch e.kind {
            case .news(let text): say(text)
            case .arrived(let n): say("新来了 \(n) 个人")
            case .upgraded(let level): say("🔥 熔炉升到 \(level) 级，热圈变大了")
            case .died("cold"): once("冻\(city.today)", "有人冻死了——" + (l.homeless > 0 ? "有人没房子" : "房子在热圈外"))
            case .died("hunger"): once("饿\(city.today)", "有人饿死了——粮食不够")
            default: break
            }
        }
        if let s = l.coldStart, !l.coldIsBlizzard, s - l.day == 2 { once("寒\(s)", "🌨 两天后寒潮：热圈外的人会生病") }
        if l.daysToBlizzard == 10 { once("暴10", "⚠️ 十天后大寒暴风雪：熔炉要升高，北边要筑墙，煤要攒够") }
        if l.daysToBlizzard == 0 { once("暴0", "🌪 大寒暴风雪来了！") }
        if l.people > 0, l.coal < l.burn * 3 { once("煤\(city.today / 5)", "⚠️ 煤只够烧 \(Int(l.coal / max(0.1, l.burn))) 天了") }
        if l.people > 0, l.food < l.eats * 3 { once("粮\(city.today / 5)", "⚠️ 粮食只够 \(Int(l.food / max(0.1, l.eats))) 天了") }
        for goal in [50, 100, 150] where l.people >= goal { once("人\(goal)", "🎉 城里有 \(goal) 人了") }
        if city.counties == iceRegions.count - 1 { once("一统", "🏯 天下一统！冰河还没完，城还要撑下去") }
        for d in [100, 150, 200, 300, 500] where city.today == d { once("天\(d)", "🎉 撑过了 \(d) 天") }
        if city.today > best, city.today > 1 { best = city.today }
        if let id = selected, city.building(id) == nil { selected = nil }
    }

    private func once(_ key: String, _ text: String) {
        guard !told.contains(key) else { return }
        told.insert(key); say(text)
    }

    // MARK: Matters at the gate

    /// The person's answer.
    func answer(_ choice: Int) {
        guard let e = city.incident, IceCity.choices(e.kind).indices.contains(choice) else { return }
        guard city.can(e, choice) else { say("现在做不到：\(IceCity.choices(e.kind)[choice])"); return }
        city.answer(choice)
        say("回应：\(IceCity.choices(e.kind)[choice])")
        beat += 1
    }

    /// A lord who is not the person answers: the script at once, Jev or a chat model by being asked; shown a moment, then done.
    private func settleIncident() {
        guard let e = city.incident else { return }
        if let d = decided {
            guard Date().timeIntervalSince(d.at) > 2.2 else { return }
            city.answer(d.choice)
            note = "\(d.by)（城主）回应「\(IceCity.incidentTitles[e.kind])」：\(IceCity.choices(e.kind)[d.choice])"
            decided = nil
            return
        }
        guard !answering else { return }
        if !seat.commands { decided = (IceBrain.answer(e, city), "电脑", Date()); return }
        let options = IceCommander.answers(city, e)
        guard options.count > 1 else { decided = (IceBrain.answer(e, city), "电脑", Date()); return }
        answering = true
        let situation = IceCommander.situation(city) + "; waiting at the gate: " + IceCity.incidentEN[e.kind], who = seat
        Task { @MainActor in
            defer { answering = false }
            do {
                let (index, _, name) = who.decides
                    ? try await askJev(options, situation, IceCommander.answerQuestion, IceCommander.answerJudge, via: who.open)
                    : try await askChat(options, situation, IceCommander.answerQuestion, IceCommander.answerJudge)
                guard seat == who, city.incident?.kind == e.kind, case .answer(let c) = options[index].plan else { return }
                decided = (c, name, Date())
            } catch {
                note = "\(who.title)没答上：\(error.localizedDescription.prefix(60))；由电脑回应"
                if city.incident != nil { decided = (IceBrain.answer(e, city), "电脑", Date()) }
            }
        }
    }

    // MARK: Asking Jev or a chat model

    /// The lord's question: which need first. The answer is carried out by the computer's hands.
    private func consult() {
        let options = IceCommander.needs(city)
        asking = true; lastAsked = city.time
        let situation = IceCommander.situation(city), who = seat
        Task { @MainActor in
            defer { asking = false }
            do {
                let (index, chance, name) = who.decides
                    ? try await askJev(options, situation, IceCommander.question, IceCommander.howToJudge, via: who.open)
                    : try await askChat(options, situation, IceCommander.question, IceCommander.howToJudge)
                guard seat == who, !city.over else { return }
                IceCommander.execute(options[index].plan, &city, &brain)
                note = "\(name)（城主）：先顾\(options[index].title)" + (chance.map { " · \(Int($0 * 100))%" } ?? "")
            } catch {
                note = "\(who.title)没答上：\(error.localizedDescription.prefix(60))"
            }
        }
    }

    /// Jev's advice for the person: what to build next and where, with a 照做 button.
    private func advise() {
        let options = IceCommander.advice(city)
        guard options.count > 1 else { return }
        advising = true; lastAdvised = city.time
        let situation = IceCommander.situation(city)
        Task { @MainActor in
            defer { advising = false }
            if let (index, chance, _) = try? await askJev(options, situation, IceCommander.adviceQuestion, IceCommander.adviceJudge), me {
                advice = (options[index], chance ?? 0)
            }
        }
    }

    func follow() {
        guard let advice, me else { return }
        IceCommander.execute(advice.option.plan, &city, &brain)
        if case .build(let kind, _) = advice.option.plan, !autoStaff, let b = city.buildings.last, b.kind == kind { city.buildings[city.buildings.count - 1].wanted = kind.slots }
        say("照做了：\(advice.option.title)")
        self.advice = nil; lastAdvised = city.time - 6
        beat += 1
    }

    private func askJev(_ options: [IceOption], _ situation: String, _ question: String, _ judge: String, via: String? = nil) async throws -> (Int, Double?, String) {
        let q = JevClient.Question(id: "order", question: question, howToJudge: judge,
                                   options: options.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.words) })
        let reply = try await JevClient.ask(state: [("game", IceCommander.rules), ("situation", situation)], [q], via: via)
        guard let answer = reply.answers["order"], let n = Int(answer.choice.dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("\(via ?? "Jev") 的回答读不出来")
        }
        return (n - 1, answer.chances[answer.choice], via ?? "Jev")
    }

    private func askChat(_ options: [IceOption], _ situation: String, _ question: String, _ judge: String) async throws -> (Int, Double?, String) {
        var chosen: (host: String, model: String)?
        if model.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = model.firstIndex(of: "|") { chosen = (String(model[..<bar]), String(model[model.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(model) { chosen = (entry.host, model); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = """
            \(IceCommander.rules)
            The situation: \(situation)
            \(question) \(judge)
            Options:
            \(options.enumerated().map { String(format: "p%02d", $0.offset + 1) + ": " + $0.element.words }.joined(separator: "\n"))
            Answer with the option's key only, for example p03. Nothing else.
            """
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": writer.model, "stream": false, "think": false,
                                                                        "messages": [["role": "user", "content": prompt]]] as [String: Any])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let reply = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = (reply["message"] as? [String: Any])?["content"] as? String,
              let range = text.range(of: #"p\d\d"#, options: [.regularExpression, .backwards]),
              let n = Int(text[range].dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("\(writer.model) 没按要求只答编号")
        }
        return (n - 1, nil, writer.model)
    }

    // MARK: What a click means

    func click(_ t: IceTile) {
        guard IceCity.inside(t) else { return }
        if let kind = placing { put(kind, at: t); return }
        if tool == .bulldoze {
            guard me else { return }
            let i = IceCity.index(t)
            if let id = city.occupant[i], let b = city.building(id) {
                if b.kind == .furnace { say("熔炉不能拆"); return }
                city.remove(id); say("拆了\(b.kind.name)，材料回来一半")
            } else if city.wall[i] >= 0 { city.razeWall(t) }
            else if city.road[i] { city.unlay(road: t) }
            beat += 1
            return
        }
        if tool == .road || tool == .wall { return }
        let id = city.occupant[IceCity.index(t)]
        if let h = assigning, me {
            assigning = nil
            if let id, let b = city.building(id), b.done {
                city.govern(h, id); say("\(iceOfficers[h].name)去管\(b.kind.name)了")
            } else { say("点一座盖好的建筑，让武将去管") }
            beat += 1
            return
        }
        // The furnace: a click chooses it, a second click raises it a level.
        if let id, let b = city.building(id), b.kind == .furnace, me {
            if selected == id { upgradeFurnace() }
            else if b.level < IceCity.topLevel, !b.upgrading {
                let c = IceCity.upgradeCost(to: b.level + 1)
                say(String(format: "熔炉 %d 级：再点一次升到 %d 级（%.0f 木 %.0f 石 %.0f 铁）", b.level, b.level + 1, c[1], c[3], c[4]))
            }
        }
        selected = id
    }

    func put(_ kind: IceBuildKind, at t: IceTile) {
        guard me else { placing = nil; return }
        let n = kind.size, origin = IceTile(x: t.x - (n - 1) / 2, y: t.y - (n - 1) / 2)
        guard city.fits(kind, at: origin) else { say(city.whyNot(kind, at: origin)); return }
        guard let id = city.place(kind, at: origin) else { return }
        if !autoStaff, let i = city.buildingIndex(id) { city.buildings[i].wanted = kind.slots }
        let cost = kind.cost
        if city.stored(.wood) < cost[1] || city.stored(.stone) < cost[3] || city.stored(.iron) < cost[4] { say("先放下了，等材料送到才能盖") }
        else if kind == .house, !city.warmed(Double(origin.x) + 1, Double(origin.y) + 1) { say("这座民居在热圈外：住在里面会冷") }
        if !NSEvent.modifierFlags.contains(.shift) { placing = nil }
        beat += 1
    }

    /// A road dragged from one tile to another.
    func road(_ a: IceTile, _ b: IceTile) {
        guard me else { return }
        var laid = 0
        for t in IceCityScene.line(a, b) where city.lay(road: t) { laid += 1 }
        if laid == 0 { say("路只能铺在空雪地上") }
        beat += 1
    }

    /// A wall dragged from one tile to another, paid in stone and wood as it goes up.
    func wall(_ a: IceTile, _ b: IceTile) {
        guard me else { return }
        let tiles = IceCityScene.line(a, b).filter { city.canWall($0) }
        guard !tiles.isEmpty else { say("城墙只能筑在空雪地上"); return }
        let n = city.raise(walls: tiles)
        if n == 0 { say("石头不够：每格城墙要 3 石 1 木") }
        else if n < tiles.count { say("筑了 \(n) 格，石头不够筑完") }
        else { say("筑了 \(n) 格城墙：墙南边避风") }
        beat += 1
    }

    /// More or fewer workers at the selected building — the person's own choice from now on.
    func workers(_ delta: Int) {
        guard me, let id = selected, let i = city.buildingIndex(id) else { return }
        if autoStaff { autoStaff = false; say("改成你自己安排工人了") }
        let kind = city.buildings[i].kind
        city.buildings[i].wanted = max(0, min(kind.slots, city.buildings[i].wanted + delta))
        beat += 1
    }

    func demolish() {
        guard me, let id = selected, let b = city.building(id), b.kind != .furnace else { return }
        city.remove(id); selected = nil
        say("拆了\(b.kind.name)")
    }

    func upgradeFurnace() {
        guard me else { return }
        guard let f = city.furnace else { return }
        if f.level >= IceCity.topLevel { say("熔炉已经是最高级了"); return }
        if f.upgrading { say("熔炉正在升级"); return }
        city.upgradeFurnace()
        let c = IceCity.upgradeCost(to: f.level + 1)
        say(String(format: "熔炉开始升到 %d 级：工人会运来 %.0f 木 %.0f 石 %.0f 铁", f.level + 1, c[1], c[3], c[4]))
        beat += 1
    }

    func train() {
        guard me else { return }
        if city.train() { say("一队 \(IceCity.batchSize) 个兵开始操练（一天）") }
        else if city.count(.barracks) == 0 { say("先盖兵营") }
        else if city.inArms + IceCity.batchSize > city.soldierRoom { say("兵营住满了：再盖一座兵营") }
        else if !city.buildings.contains(where: { $0.kind == .barracks && $0.done && $0.batch == 0 }) { say("兵营正在操练") }
        else { say("练兵要 \(IceCity.batchSize * 2) 粮 \(IceCity.batchSize) 铁") }
        beat += 1
    }

    func recruit(_ h: Int) {
        guard me else { return }
        if city.recruit(h) { say("\(iceOfficers[h].name)来投奔了！") }
        else if city.count(.tavern) == 0 { say("先盖酒馆才能招武将") }
        else if city.officers.count >= city.heroRoom { say("酒馆坐满了：再盖一座酒馆能多招两位") }
        else { say("招\(iceOfficers[h].name)要 \(iceOfficers[h].food) 粮 \(iceOfficers[h].iron) 铁") }
        beat += 1
    }

    /// Send the general picked on the map with soldiers to the county picked.
    func send() {
        guard me, let r = mapPick, let h = sendOfficer else { return }
        let n = min(sendSoldiers, city.soldiers)
        if city.send(h, soldiers: n, to: r) {
            say("\(iceOfficers[h].name)带 \(n) 兵出征\(iceRegions[r].name)")
            mapPick = nil; sendOfficer = nil
        } else { say("出不了兵：看看武将是否空闲、兵够不够、这个州是否连得上") }
        beat += 1
    }

    func pick(_ region: Int) {
        mapPick = region
        guard region > 0, city.owner[region] != 0 else { return }
        let free = city.freeOfficers
        let best = free.max { city.punch($0, against: region, on: city.today + 2) < city.punch($1, against: region, on: city.today + 2) }
        sendOfficer = best
        if let best { sendSoldiers = min(city.soldiers, city.army(best, to: region)) }
    }
}

// MARK: - The view

/// The page's measure: 1 at 1200 points wide, growing with the window up to 1.7 and down to 0.8 for a small one.
/// Every overlay multiplies its fonts, paddings and frames by it, so the text stays crisp.
enum IceScale {
    static func k(_ size: CGSize) -> CGFloat { min(1.7, max(0.8, min(size.width / 1200, size.height / 620))) }
}

/// The navy glass everything over the snow sits on.
struct IceGlass: ViewModifier {
    var k: CGFloat
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius * k).fill(LinearGradient(colors: [Color(red: 0.13, green: 0.19, blue: 0.35).opacity(0.9), Color(red: 0.07, green: 0.11, blue: 0.23).opacity(0.9)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: radius * k).stroke(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, 1.1 * k)))
            .compositingGroup()
            .shadow(color: Color(red: 0.05, green: 0.1, blue: 0.25).opacity(0.3), radius: 8 * k, y: 3 * k)
    }
}

extension View {
    func iceGlass(_ k: CGFloat, radius: CGFloat = 14) -> some View { modifier(IceGlass(k: k, radius: radius)) }
}

/// A key on the keyboard, drawn as a little cap.
struct IceKey: View {
    var text: String
    var k: CGFloat
    var body: some View {
        Text(text).font(.system(size: 10.5 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.3))
            .padding(.horizontal, 5 * k).frame(minWidth: 19 * k, minHeight: 18 * k)
            .background(RoundedRectangle(cornerRadius: 5 * k).fill(LinearGradient(colors: [.white, Color(red: 0.84, green: 0.88, blue: 0.95)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 5 * k).stroke(Color.black.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1.2 * k)
    }
}

/// A switch drawn like the rest of the page (and drawn offscreen too, unlike a checkbox).
struct IceSwitch: View {
    var title: String
    var on: Bool
    var k: CGFloat
    var flip: () -> Void
    var body: some View {
        Button(action: flip) {
            HStack(spacing: 6 * k) {
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Color(red: 0.3, green: 0.72, blue: 0.46) : Color.white.opacity(0.18)).frame(width: 30 * k, height: 17 * k)
                    Circle().fill(Color.white).frame(width: 13 * k, height: 13 * k).padding(.horizontal, 2 * k).shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                }
                Text(title).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
    }
}

/// A good as a small painted thing: a coal lump, a log, a bowl of rice, a stone, an iron ingot.
struct IceGoodIcon: View, Equatable {
    var good: IceGood
    var body: some View {
        Canvas { g, size in IceGoodIcon.paint(&g, good, size) }
    }
    static func paint(_ g: inout GraphicsContext, _ good: IceGood, _ size: CGSize) {
        let s = min(size.width, size.height), c = CGPoint(x: size.width / 2, y: size.height / 2)
        func col(_ v: Art.RGB, _ a: Double = 1) -> Color { Color(red: v.0, green: v.1, blue: v.2).opacity(a) }
        switch good {
        case .coal:
            let lump = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.42, y: c.y + s * 0.26)); p.addLine(to: CGPoint(x: c.x - s * 0.34, y: c.y - s * 0.16))
                p.addLine(to: CGPoint(x: c.x - s * 0.04, y: c.y - s * 0.38)); p.addLine(to: CGPoint(x: c.x + s * 0.36, y: c.y - s * 0.2))
                p.addLine(to: CGPoint(x: c.x + s * 0.42, y: c.y + s * 0.22)); p.addLine(to: CGPoint(x: c.x + s * 0.08, y: c.y + s * 0.38)); p.closeSubpath()
            }
            g.fill(lump, with: .color(col((0.13, 0.13, 0.16))))
            g.fill(Path { p in p.move(to: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.12)); p.addLine(to: CGPoint(x: c.x - s * 0.04, y: c.y - s * 0.32)); p.addLine(to: CGPoint(x: c.x + s * 0.02, y: c.y)); p.closeSubpath() }, with: .color(col((0.5, 0.58, 0.74))))
            g.fill(Path { p in p.move(to: CGPoint(x: c.x + s * 0.02, y: c.y)); p.addLine(to: CGPoint(x: c.x + s * 0.34, y: c.y - s * 0.16)); p.addLine(to: CGPoint(x: c.x + s * 0.38, y: c.y + s * 0.18)); p.closeSubpath() }, with: .color(col((0.28, 0.3, 0.36))))
        case .wood:
            let body = CGRect(x: c.x - s * 0.42, y: c.y - s * 0.2, width: s * 0.7, height: s * 0.4)
            g.fill(Path(roundedRect: body, cornerRadius: s * 0.08), with: .color(col((0.6, 0.4, 0.22))))
            g.fill(Path(CGRect(x: body.minX + s * 0.04, y: body.minY + s * 0.06, width: body.width - s * 0.1, height: s * 0.07)), with: .color(col((0.72, 0.52, 0.3))))
            let end = CGRect(x: c.x + s * 0.1, y: c.y - s * 0.22, width: s * 0.34, height: s * 0.44)
            g.fill(Path(ellipseIn: end), with: .color(col((0.93, 0.8, 0.56))))
            g.stroke(Path(ellipseIn: end.insetBy(dx: s * 0.07, dy: s * 0.09)), with: .color(col((0.72, 0.52, 0.3))), lineWidth: max(0.6, s * 0.04))
            g.fill(Path(ellipseIn: CGRect(x: end.midX - s * 0.03, y: end.midY - s * 0.03, width: s * 0.06, height: s * 0.06)), with: .color(col((0.62, 0.42, 0.24))))
        case .food:
            // A bowl of rice with a red bean on top.
            g.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.34, y: c.y - s * 0.3, width: s * 0.68, height: s * 0.42)), with: .color(.white))
            g.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.2, y: c.y - s * 0.3, width: s * 0.24, height: s * 0.14)), with: .color(col((0.96, 0.96, 1))))
            let bowl = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.44, y: c.y - s * 0.06))
                p.addQuadCurve(to: CGPoint(x: c.x + s * 0.44, y: c.y - s * 0.06), control: CGPoint(x: c.x, y: c.y + s * 0.62))
                p.closeSubpath()
            }
            g.fill(bowl, with: .color(col((0.84, 0.26, 0.2))))
            g.fill(Path(CGRect(x: c.x - s * 0.44, y: c.y - s * 0.07, width: s * 0.88, height: s * 0.06)), with: .color(col((0.98, 0.78, 0.34))))
            g.fill(Path(ellipseIn: CGRect(x: c.x + s * 0.02, y: c.y - s * 0.36, width: s * 0.12, height: s * 0.1)), with: .color(col((0.85, 0.14, 0.14))))
        case .stone:
            let block = CGRect(x: c.x - s * 0.38, y: c.y - s * 0.22, width: s * 0.76, height: s * 0.5)
            g.fill(Path(roundedRect: block, cornerRadius: s * 0.06), with: .color(col((0.62, 0.63, 0.68))))
            g.fill(Path(roundedRect: CGRect(x: block.minX, y: block.minY, width: block.width, height: s * 0.2), cornerRadius: s * 0.06), with: .color(col((0.8, 0.81, 0.85))))
            g.fill(Path(roundedRect: CGRect(x: block.minX - s * 0.02, y: block.minY - s * 0.06, width: block.width * 0.8, height: s * 0.12), cornerRadius: s * 0.06), with: .color(.white))
        case .iron:
            let ingot = Path { p in
                p.move(to: CGPoint(x: c.x - s * 0.44, y: c.y + s * 0.2)); p.addLine(to: CGPoint(x: c.x - s * 0.26, y: c.y - s * 0.16))
                p.addLine(to: CGPoint(x: c.x + s * 0.26, y: c.y - s * 0.16)); p.addLine(to: CGPoint(x: c.x + s * 0.44, y: c.y + s * 0.2)); p.closeSubpath()
            }
            g.fill(ingot, with: .color(col((0.44, 0.5, 0.62))))
            g.fill(Path { p in p.move(to: CGPoint(x: c.x - s * 0.26, y: c.y - s * 0.16)); p.addLine(to: CGPoint(x: c.x + s * 0.26, y: c.y - s * 0.16)); p.addLine(to: CGPoint(x: c.x + s * 0.2, y: c.y - s * 0.02)); p.addLine(to: CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.02)); p.closeSubpath() }, with: .color(col((0.72, 0.78, 0.88))))
            g.fill(Path(CGRect(x: c.x - s * 0.1, y: c.y + s * 0.02, width: s * 0.2, height: s * 0.05)), with: .color(col((0.86, 0.9, 0.96), 0.7)))
        }
    }
}

/// A building of the city as a small picture: the scene's own drawing at the size of a card.
struct IceBuildingIcon: View, Equatable {
    var kind: IceBuildKind?
    var tool: IceTool?
    var body: some View {
        Canvas { g, size in IceCityScene.icon(&g, kind: kind, tool: tool, size: size) }
    }
}

struct IceView: View {
    @ObservedObject private var game = IceGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    /// The mouse catcher over the map; left out only when the page is drawn offscreen for a picture.
    private let mouse: Bool
    init(mouse: Bool = true) { self.mouse = mouse }

    static func price(_ kind: IceBuildKind) -> String {
        let c = kind.cost
        return [c[1] > 0 ? "\(Int(c[1]))木" : nil, c[3] > 0 ? "\(Int(c[3]))石" : nil, c[4] > 0 ? "\(Int(c[4]))铁" : nil].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        GeometryReader { whole in
            let k = IceScale.k(whole.size)
            VStack(spacing: 0) {
                GeometryReader { space in
                    let size = space.size
                    let S = game.camera.tile(size), origin = game.camera.origin(size), view = game.camera.visible(size)
                    ZStack(alignment: .topLeading) {
                        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { timeline in
                            let scene = IceCityScene(city: game.city, selected: game.selected, placing: game.placing, tool: game.tool,
                                                     hover: game.hover, drag: game.drag, now: timeline.date.timeIntervalSinceReferenceDate)
                            Canvas(rendersAsynchronously: true) { context, canvas in
                                context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Color(red: 0.8, green: 0.86, blue: 0.94)))
                                context.translateBy(x: -origin.x * S, y: -origin.y * S)
                                scene.paint(&context, tile: S, view: view)
                            }
                        }
                        if mouse { IceMouse().frame(width: size.width, height: size.height) }
                        overlays(size, k)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10 * k))
                    .onAppear { settle(size, k) }
                    .onChange(of: size) { _, new in settle(new, k) }
                }
                .padding(.horizontal, 8 * k).padding(.top, 6 * k)
                IceBar(game: game, k: k)
            }
        }
        .onAppear { game.start(); IceKeys.install() }
        .onDisappear { game.stop(); IceKeys.remove() }
        .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }

    /// The view's size known: the camera frames the town if nothing has happened yet.
    private func settle(_ size: CGSize, _ k: CGFloat) {
        game.viewSize = size
        game.scale = k
        if game.city.time == 0, !game.framed { game.lookAtFurnace() }
    }

    /// Everything over the snow, sized by `k`.
    @ViewBuilder private func overlays(_ size: CGSize, _ k: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            IceHUD(game: game, chatModels: chatModels, k: k)
            IceGenerals(game: game, k: k)
        }
        .padding(10 * k)
        .frame(width: size.width, alignment: .topLeading)
        if let text = game.saying {
            Text(text).font(.system(size: 14.5 * k, weight: .bold, design: .rounded)).foregroundColor(.white)
                .padding(.horizontal, 18 * k).padding(.vertical, 9 * k)
                .background(Capsule().fill(Color(red: 0.07, green: 0.1, blue: 0.2).opacity(0.78)))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .compositingGroup()
                .frame(width: size.width).padding(.top, 142 * k).allowsHitTesting(false)
        }
        IceInfoCard(game: game, k: k).frame(width: size.width, height: size.height, alignment: .bottomLeading)
        IceTray(game: game, k: k).frame(width: size.width, height: size.height, alignment: .bottom)
        zoomButtons(k).frame(width: size.width, height: size.height, alignment: .bottomTrailing)
        if game.speed == 0, !game.city.over, game.placing == nil, game.tool == nil, !game.showMap, game.city.incident == nil {
            startButton(k).padding(.bottom, 26 * k).frame(width: size.width, height: size.height, alignment: .bottom)
        }
        if game.city.incident != nil, !game.city.over {
            IceEventCard(game: game, k: k).frame(width: size.width, height: size.height)
        }
        if game.showMap {
            IceMapPanel(game: game, k: k).frame(width: size.width, height: size.height)
        }
        if game.city.over { ending(size, k) }
    }

    private func startButton(_ k: CGFloat) -> some View {
        Button { game.speed = 1 } label: {
            HStack(spacing: 12 * k) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.22)).frame(width: 38 * k, height: 38 * k)
                    Image(systemName: game.city.time == 0 ? "flame.fill" : "play.fill").font(.system(size: 19 * k, weight: .bold)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text(game.city.time == 0 ? "开始" : "继续").font(.system(size: 24 * k, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text(game.city.time == 0 ? "点燃熔炉，熬过冰河百日" : "第 \(game.city.today) 天").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.88))
                }
                IceKey(text: "空格", k: k)
            }
            .padding(.leading, 12 * k).padding(.trailing, 18 * k).padding(.vertical, 11 * k)
            .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.24), Color(red: 0.88, green: 0.3, blue: 0.16)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * k))
            .compositingGroup()
            .shadow(color: Color(red: 1, green: 0.5, blue: 0.2).opacity(0.55), radius: 18 * k)
            .shadow(color: .black.opacity(0.25), radius: 4 * k, y: 3 * k)
        }
        .buttonStyle(.plain)
    }

    private func zoomButtons(_ k: CGFloat) -> some View {
        VStack(spacing: 4 * k) {
            ForEach([("plus", 1.25), ("minus", 0.8), ("flame", 0.0)], id: \.0) { item in
                Button { item.1 == 0 ? game.lookAtFurnace() : game.zoom(by: CGFloat(item.1)) } label: {
                    Image(systemName: item.0 == "flame" ? "flame.fill" : item.0).font(.system(size: 17 * k, weight: .bold)).foregroundColor(item.0 == "flame" ? Color(red: 1, green: 0.72, blue: 0.4) : .white)
                        .frame(width: 42 * k, height: 40 * k)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.0 == "plus" ? "放大（=）" : item.0 == "minus" ? "缩小（-）" : "回到熔炉")
            }
        }
        .padding(5 * k)
        .iceGlass(k, radius: 13)
        .padding(14 * k)
    }

    private func ending(_ size: CGSize, _ k: CGFloat) -> some View {
        let w = game.city
        let alive = !w.people.isEmpty && w.outDays < IceCity.outLimit
        return VStack(spacing: 12 * k) {
            Text(alive ? "城还在" : (w.outDays >= IceCity.outLimit ? "城冻住了" : "城里的人都没了"))
                .font(.system(size: 40 * k, weight: .heavy, design: .rounded))
            Text("撑了 \(w.today) 天 · 熬过 \(w.blizzardsSurvived) 场大寒 · 最久 \(max(game.best, w.today)) 天")
                .font(.system(size: 18 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
            Text("\(w.people.count) 人（最多 \(w.peak)）· \(w.counties) 州 · \(w.officers.count) 员武将 · 熔炉 \(w.level) 级 · 冻死 \(w.deaths["cold"] ?? 0) · 病死 \(w.deaths["sick"] ?? 0) · 饿死 \(w.deaths["hunger"] ?? 0)")
                .font(.system(size: 15 * k, weight: .semibold))
            Button { game.restart() } label: {
                Text("再来一局").font(.system(size: 16 * k, weight: .heavy)).foregroundColor(.white)
                    .padding(.horizontal, 24 * k).padding(.vertical, 9 * k)
                    .background(Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.24), Color(red: 0.88, green: 0.3, blue: 0.16)], startPoint: .top, endPoint: .bottom)))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white).padding(34 * k)
        .iceGlass(k, radius: 20)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Along the top: one glass strip — the day and the cold, the stores, the people, the lord and the speed

struct IceHUD: View {
    @ObservedObject var game: IceGame
    var chatModels: [(host: String, models: [String])]
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.city, l = IceLedger(w)
        return HStack(spacing: 0) {
            // The day and the cold.
            HStack(spacing: 7 * k) {
                IceThermometer(temperature: w.temperature).frame(width: 15 * k, height: 36 * k)
                VStack(alignment: .leading, spacing: 1 * k) {
                    HStack(alignment: .firstTextBaseline, spacing: 6 * k) {
                        Text("第 \(w.today) 天").font(.system(size: 17 * k, weight: .heavy, design: .rounded)).fixedSize()
                        Text("\(Int(w.temperature.rounded()))°C").font(.system(size: 17 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                            .foregroundColor(w.temperature < -40 ? Color(red: 0.62, green: 0.84, blue: 1) : w.temperature < -20 ? Color(red: 0.8, green: 0.9, blue: 1) : .white)
                    }
                    Text(coming(l, w)).font(.system(size: 11 * k, weight: .bold)).lineLimit(1).frame(maxWidth: 130 * k, alignment: .leading)
                        .foregroundColor(w.storm ? Color(red: 0.62, green: 0.84, blue: 1) : warning(l, w) ? Color(red: 1, green: 0.78, blue: 0.5) : .white.opacity(0.72))
                }
            }
            .padding(.horizontal, 10 * k)
            rule
            // The five stores.
            HStack(spacing: 8 * k) {
                ForEach(0..<5, id: \.self) { g in
                    let amount = g == 0 ? l.coal : g == 1 ? l.wood : g == 2 ? l.food : g == 3 ? l.stone : l.iron
                    let rate = w.madeYesterday[g] - w.usedYesterday[g]
                    HStack(spacing: 4 * k) {
                        IceGoodIcon(good: IceGood(rawValue: g)!).equatable().frame(width: 23 * k, height: 23 * k)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int(amount))").font(.system(size: 15.5 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                            Text(w.today > 1 ? "\(rate >= 0 ? "+" : "")\(Int(rate.rounded()))/天" : IceGood.names[g]).font(.system(size: 10.5 * k, weight: .bold, design: .rounded)).monospacedDigit().fixedSize()
                                .foregroundColor(w.today <= 1 ? .white.opacity(0.6) : rate < 0 ? Color(red: 1, green: 0.62, blue: 0.56) : Color(red: 0.62, green: 0.94, blue: 0.7))
                        }
                    }
                    .help(g == 0 ? "煤：熔炉每天烧 \(Int(l.burn))，昨天挖 \(Int(w.madeYesterday[0]))" : g == 2 ? "粮：每天吃 \(Int(l.eats))，昨天收 \(Int(w.madeYesterday[2]))" : IceGood.names[g])
                }
            }
            .padding(.horizontal, 8 * k)
            rule
            // The people, their heart, the soldiers.
            HStack(spacing: 9 * k) {
                HStack(spacing: 5 * k) {
                    Image(systemName: "person.2.fill").font(.system(size: 14 * k, weight: .bold)).foregroundColor(Color(red: 0.8, green: 0.88, blue: 1))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(l.people)").font(.system(size: 15.5 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                        Text(l.sick > 0 || l.cold > 0 ? "病\(l.sick) 冷\(l.cold)" : "无病无冻").font(.system(size: 10.5 * k, weight: .bold)).fixedSize()
                            .foregroundColor(l.sick > 0 || l.cold > 0 ? Color(red: 1, green: 0.72, blue: 0.62) : Color(red: 0.62, green: 0.94, blue: 0.7))
                    }
                }
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text("民心").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.78))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.38)).frame(width: 72 * k, height: 14 * k)
                        Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.5), Color(red: 1, green: 0.74, blue: 0.4)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(14 * k, 72 * k * CGFloat(w.morale / 100)), height: 14 * k)
                        Text("♥ \(Int(w.morale))").font(.system(size: 10 * k, weight: .heavy, design: .rounded)).foregroundColor(.white).shadow(color: .black.opacity(0.5), radius: 1).frame(width: 72 * k)
                    }
                }
                HStack(spacing: 5 * k) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 14 * k, weight: .bold)).foregroundColor(Color(red: 0.5, green: 0.86, blue: 0.62))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(w.soldiers)").font(.system(size: 15.5 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                        Text(w.wounded > 0 ? "伤 \(w.wounded)" : "州 \(w.counties)").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(.white.opacity(0.72)).fixedSize()
                    }
                }
                .help("兵：守城 \(Int(w.defenceAtHome))")
            }
            .padding(.horizontal, 8 * k)
            Spacer(minLength: 4 * k)
            // Who is lord, and how fast the days go.
            HStack(spacing: 5 * k) {
                Image(systemName: "crown.fill").font(.system(size: 11 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.4)).help("城主")
                segmented(IceSeat.allCases.map { ($0.title, game.seat == $0) }) { game.seat = IceSeat.allCases[$0] }
                if game.seat == .llm {
                    Menu {
                        Button("自动") { game.model = "" }
                        ForEach(chatModels, id: \.host) { entry in
                            Section(BoxServices.place(of: entry.host)) {
                                ForEach(entry.models, id: \.self) { name in Button(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")) { game.model = "\(entry.host)|\(name)" } }
                            }
                        }
                    } label: { Text(game.model.isEmpty ? "自动" : String(game.model.split(separator: "|").last ?? "")).font(.system(size: 11 * k, weight: .semibold)).lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize().foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8 * k)
            rule
            HStack(spacing: 5 * k) {
                segmented([("⏸", game.speed == 0), ("1×", game.speed == 1), ("2×", game.speed == 2), ("4×", game.speed == 4), ("8×", game.speed == 8)]) { game.speed = [0, 1, 2, 4, 8][$0] }
                Button { game.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white)
                        .frame(width: 28 * k, height: 26 * k).background(RoundedRectangle(cornerRadius: 7 * k).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain).help("重新开始")
            }
            .padding(.horizontal, 8 * k)
        }
        .foregroundColor(.white)
        .padding(.vertical, 8 * k)
        .iceGlass(k, radius: 16)
    }

    private var rule: some View { Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 34 * k) }

    private func warning(_ l: IceLedger, _ w: IceCity) -> Bool {
        if let s = l.coldStart, s - l.day <= 3 { return true }
        return !l.afterBlizzard && l.daysToBlizzard <= 10
    }

    private func coming(_ l: IceLedger, _ w: IceCity) -> String {
        if w.storm { return "🌪 大寒暴风雪！" }
        if let s = l.coldStart, s <= l.day { return "❄️ 寒潮中，到第 \(l.coldEnd ?? l.day) 天" }
        if !l.afterBlizzard, l.daysToBlizzard <= 15 { return "暴风雪还有 \(l.daysToBlizzard) 天" }
        if let s = l.coldStart, s - l.day <= 6 { return "寒潮还有 \(s - l.day) 天" }
        return "下一场大寒约在第 \(l.blizzardStart) 天 · 最久 \(max(game.best, l.day)) 天"
    }

    private func segmented(_ items: [(String, Bool)], _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2 * k) {
            ForEach(items.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(items[i].0).font(.system(size: 12.5 * k, weight: .bold, design: .rounded)).foregroundColor(items[i].1 ? Color(red: 0.12, green: 0.16, blue: 0.3) : .white).fixedSize()
                        .padding(.horizontal, 6.5 * k).padding(.vertical, 5 * k)
                        .background(RoundedRectangle(cornerRadius: 7 * k).fill(items[i].1 ? LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.58), Color(red: 1, green: 0.76, blue: 0.36)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A little thermometer: the red column falls with the cold.
struct IceThermometer: View {
    var temperature: Double
    var body: some View {
        Canvas { g, size in
            let frac = CGFloat(max(0, min(1, (temperature + 60) / 60)))
            let hot = Color(red: 0.3 + 0.7 * Double(frac), green: 0.45, blue: 1 - 0.8 * Double(frac))
            let tubeW = size.width * 0.42, bulb = size.width
            let tube = CGRect(x: size.width / 2 - tubeW / 2, y: 1, width: tubeW, height: size.height - bulb * 0.8)
            g.fill(Path(roundedRect: tube, cornerRadius: tubeW / 2), with: .color(.white.opacity(0.92)))
            let inner = tube.insetBy(dx: tubeW * 0.22, dy: tubeW * 0.22)
            g.fill(Path(roundedRect: CGRect(x: inner.minX, y: inner.minY + inner.height * (1 - frac), width: inner.width, height: inner.height * frac + tubeW), cornerRadius: inner.width / 2), with: .color(hot))
            let b = CGRect(x: size.width / 2 - bulb / 2, y: size.height - bulb, width: bulb, height: bulb)
            g.fill(Path(ellipseIn: b), with: .color(.white.opacity(0.92)))
            g.fill(Path(ellipseIn: b.insetBy(dx: bulb * 0.16, dy: bulb * 0.16)), with: .color(hot))
        }
    }
}

/// The generals in the lord's service as chibi chips, and those waiting at the tavern; the map button.
struct IceGenerals: View {
    @ObservedObject var game: IceGame
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.city
        return HStack(spacing: 7 * k) {
            ForEach(w.officers.indices, id: \.self) { i in
                let hired = w.officers[i]
                chip(hired.officer, state: state(hired, w), ghost: false, picked: game.assigning == hired.officer) {
                    guard game.me, !hired.away else { return }
                    game.assigning = game.assigning == hired.officer ? nil : hired.officer
                    if game.assigning != nil { game.say("点一座建筑，让\(iceOfficers[hired.officer].name)去管它") }
                }
            }
            if w.count(.tavern) > 0, w.officers.count < w.heroRoom {
                ForEach(w.offered, id: \.self) { h in
                    chip(h, state: "招募 \(iceOfficers[h].food)粮 \(iceOfficers[h].iron)铁", ghost: true, picked: false) { game.recruit(h) }
                }
            }
            Button { game.showMap.toggle(); game.mapPick = nil } label: {
                HStack(spacing: 7 * k) {
                    Canvas { g, size in IceGenerals.mapIcon(&g, size) }.frame(width: 26 * k, height: 24 * k)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("舆图").font(.system(size: 14 * k, weight: .heavy))
                        Text("出征 · M").font(.system(size: 9.5 * k, weight: .bold)).opacity(0.85)
                    }
                }
                .foregroundColor(.white).padding(.horizontal, 12 * k).frame(height: 52 * k)
                .background(RoundedRectangle(cornerRadius: 13 * k).fill(LinearGradient(colors: [Color(red: 0.26, green: 0.62, blue: 0.44), Color(red: 0.14, green: 0.42, blue: 0.3)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 13 * k).stroke(Color.white.opacity(0.4), lineWidth: 1))
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 5 * k, y: 2 * k)
            }
            .buttonStyle(.plain).help("冰原舆图：派武将带兵出征（M）")
        }
    }

    /// A folded map, a river on it and a red flag.
    static func mapIcon(_ g: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let sheet = Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.12)); p.addLine(to: CGPoint(x: w * 0.33, y: 0)); p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.12)); p.addLine(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h * 0.88)); p.addLine(to: CGPoint(x: w * 0.66, y: h)); p.addLine(to: CGPoint(x: w * 0.33, y: h * 0.88)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
        }
        g.fill(sheet, with: .color(Color(red: 0.97, green: 0.94, blue: 0.84)))
        g.fill(Path { p in p.move(to: CGPoint(x: w * 0.33, y: 0)); p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.12)); p.addLine(to: CGPoint(x: w * 0.66, y: h)); p.addLine(to: CGPoint(x: w * 0.33, y: h * 0.88)); p.closeSubpath() }, with: .color(Color(red: 0.86, green: 0.82, blue: 0.7)))
        g.stroke(Path { p in p.move(to: CGPoint(x: w * 0.05, y: h * 0.72)); p.addQuadCurve(to: CGPoint(x: w * 0.95, y: h * 0.62), control: CGPoint(x: w * 0.5, y: h * 0.95)) }, with: .color(Color(red: 0.4, green: 0.66, blue: 0.9)), lineWidth: max(1, h * 0.09))
        g.stroke(Path { p in p.move(to: CGPoint(x: w * 0.72, y: h * 0.55)); p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.14)) }, with: .color(Color(red: 0.36, green: 0.24, blue: 0.16)), lineWidth: max(0.8, w * 0.05))
        g.fill(Path { p in p.move(to: CGPoint(x: w * 0.72, y: h * 0.14)); p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.24)); p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.34)); p.closeSubpath() }, with: .color(Color(red: 0.88, green: 0.2, blue: 0.16)))
        g.stroke(sheet, with: .color(Color(red: 0.5, green: 0.4, blue: 0.26)), lineWidth: max(0.6, w * 0.03))
    }

    private func state(_ g: IceHired, _ w: IceCity) -> String {
        if g.away, let e = w.expeditions.first(where: { $0.officer == g.officer }) { return e.back ? "回城 \(e.left) 天" : "出征\(iceRegions[e.region].name) \(e.left) 天" }
        if let id = g.governs, let b = w.building(id) { return "管\(b.kind.name)" }
        return "空闲 · 点我派去管"
    }

    private func chip(_ h: Int, state: String, ghost: Bool, picked: Bool, _ tap: @escaping () -> Void) -> some View {
        let o = iceOfficers[h]
        return Button(action: tap) {
            HStack(spacing: 6 * k) {
                Canvas { g, size in IcePortrait.draw(g, o, at: CGPoint(x: size.width / 2, y: size.height / 2 + 1), size: size.width * 0.4, now: 0) }
                    .frame(width: 42 * k, height: 42 * k)
                VStack(alignment: .leading, spacing: 0) {
                    Text(o.name).font(.system(size: 14 * k, weight: .heavy))
                    Text("武\(o.war) 智\(o.wit) 统\(o.lead)").font(.system(size: 9.5 * k, weight: .semibold)).opacity(0.88)
                    Text(state).font(.system(size: 10 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.9, blue: 0.64)).lineLimit(1)
                }
            }
            .foregroundColor(.white)
            .padding(.leading, 5 * k).padding(.trailing, 10 * k).frame(height: 52 * k)
            .background(RoundedRectangle(cornerRadius: 13 * k).fill(LinearGradient(colors: [IcePortrait.c(Art.lit(o.coat, 0.92), 0.94), IcePortrait.c(Art.lit(o.coat, 0.5), 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 13 * k).stroke(picked ? Color(red: 1, green: 0.84, blue: 0.3) : Color.white.opacity(ghost ? 0.55 : 0.38), style: StrokeStyle(lineWidth: picked ? 2.5 * k : 1, dash: ghost ? [4 * k, 3 * k] : [])))
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 5 * k, y: 2 * k)
            .opacity(ghost ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .help(o.talentCN)
    }
}

// MARK: - The matter at the gate

struct IceEventCard: View {
    @ObservedObject var game: IceGame
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.city
        guard let e = w.incident else { return AnyView(EmptyView()) }
        let choices = IceCity.choices(e.kind)
        let subtitle = e.kind == 0 ? "\(e.amount) 个人，冻得发抖，站在城门口" : e.kind == 2 ? "第 \(w.nextCold(after: w.today)?.start ?? w.today) 天起连冷 \(e.amount) 天" : "城里的人等你拿主意"
        let ink = Color(red: 0.36, green: 0.2, blue: 0.1)
        return AnyView(ZStack {
            Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.22).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 11 * k) {
                HStack(spacing: 12 * k) {
                    Text(IceCity.incidentIcons[e.kind]).font(.system(size: 34 * k))
                        .frame(width: 56 * k, height: 56 * k)
                        .background(Circle().fill(Color.white.opacity(0.75)))
                        .overlay(Circle().stroke(Color(red: 0.86, green: 0.6, blue: 0.3).opacity(0.6), lineWidth: 1.5 * k))
                    VStack(alignment: .leading, spacing: 3 * k) {
                        Text("城门口").font(.system(size: 11 * k, weight: .heavy)).foregroundColor(Color(red: 0.72, green: 0.42, blue: 0.2))
                        Text(IceCity.incidentTitles[e.kind]).font(.system(size: 20 * k, weight: .heavy, design: .rounded)).foregroundColor(ink).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.system(size: 12.5 * k, weight: .semibold)).foregroundColor(Color(red: 0.55, green: 0.36, blue: 0.2))
                    }
                }
                ForEach(choices.indices, id: \.self) { c in
                    let can = w.can(e, c)
                    let chosen = game.decided?.choice == c
                    Button { game.answer(c) } label: {
                        HStack(spacing: 8 * k) {
                            Text("\(c + 1)").font(.system(size: 12 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.62, green: 0.3, blue: 0.1))
                                .frame(width: 22 * k, height: 22 * k).background(Circle().fill(Color.white.opacity(0.85)))
                            Text(choices[c]).font(.system(size: 15 * k, weight: .bold, design: .rounded)).foregroundColor(.white)
                            Spacer(minLength: 0)
                            if chosen { Image(systemName: "checkmark.circle.fill").font(.system(size: 16 * k, weight: .bold)).foregroundColor(.white) }
                        }
                        .padding(.horizontal, 12 * k).padding(.vertical, 10 * k)
                        .background(Capsule().fill(LinearGradient(colors: can ? [Color(red: 0.99, green: 0.72, blue: 0.32), Color(red: 0.9, green: 0.5, blue: 0.2)] : [Color(white: 0.8), Color(white: 0.68)], startPoint: .top, endPoint: .bottom)))
                        .overlay(Capsule().stroke(chosen ? Color(red: 0.2, green: 0.6, blue: 0.3) : Color.white.opacity(0.7), lineWidth: chosen ? 3 * k : 1))
                        .shadow(color: Color(red: 0.6, green: 0.3, blue: 0.1).opacity(can ? 0.25 : 0), radius: 3 * k, y: 2 * k)
                    }
                    .buttonStyle(.plain)
                    .disabled(!can || !game.me)
                    .help(can ? "" : "现在做不到")
                }
                if !game.me {
                    Text(game.decided.map { "\($0.by) 选了：\(choices[$0.choice])" } ?? "\(game.seat.title) 在想…").font(.system(size: 12.5 * k, weight: .semibold)).foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.2))
                } else {
                    HStack(spacing: 6 * k) {
                        Image(systemName: "pause.circle.fill").font(.system(size: 13 * k))
                        Text("时间停着，等你回应").font(.system(size: 12 * k, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.55, green: 0.42, blue: 0.3))
                }
            }
            .padding(20 * k)
            .frame(width: 390 * k)
            .background(RoundedRectangle(cornerRadius: 20 * k).fill(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.9), Color(red: 0.98, green: 0.89, blue: 0.76)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 20 * k).stroke(Color(red: 0.86, green: 0.6, blue: 0.3), lineWidth: 2.5 * k))
            .overlay(RoundedRectangle(cornerRadius: 16 * k).stroke(Color(red: 0.86, green: 0.6, blue: 0.3).opacity(0.35), lineWidth: 1).padding(5 * k))
            .compositingGroup()
            .shadow(color: .black.opacity(0.32), radius: 16 * k, y: 6 * k)
        })
    }
}

// MARK: - The county map

struct IceMapPanel: View {
    @ObservedObject var game: IceGame
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.city
        let mapSize = CGSize(width: 470 * k, height: 420 * k)
        return ZStack {
            Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.35).onTapGesture { game.showMap = false }
            HStack(alignment: .top, spacing: 16 * k) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                    let now = t.date.timeIntervalSinceReferenceDate
                    Canvas { g, size in IceMapPainter(city: w, pick: game.mapPick, now: now, k: k).paint(&g, size) }
                }
                .frame(width: mapSize.width, height: mapSize.height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in
                    if let r = IceMapPainter.hit(p, mapSize, k: k) { game.pick(r) }
                }
                side(w).frame(width: 250 * k, height: mapSize.height)
            }
            .padding(18 * k)
            .background(RoundedRectangle(cornerRadius: 22 * k).fill(LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 1), Color(red: 0.86, green: 0.91, blue: 0.97)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 22 * k).stroke(Color(red: 0.36, green: 0.46, blue: 0.64).opacity(0.7), lineWidth: 1.5 * k))
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 18 * k, y: 6 * k)
        }
    }

    @ViewBuilder private func side(_ w: IceCity) -> some View {
        let ink = Color(red: 0.16, green: 0.2, blue: 0.32)
        VStack(alignment: .leading, spacing: 9 * k) {
            HStack {
                Text("冰原舆图").font(.system(size: 20 * k, weight: .heavy, design: .rounded))
                Spacer()
                Button { game.showMap = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20 * k)).foregroundColor(ink.opacity(0.6)) }.buttonStyle(.plain)
            }
            HStack(spacing: 8 * k) {
                ForEach([(0, "蜀"), (1, "魏"), (2, "吴")], id: \.0) { side in
                    let n = side.0 == 0 ? w.counties : w.owner.filter { $0 == side.0 }.count
                    Text("\(side.1) \(n)").font(.system(size: 12 * k, weight: .heavy)).foregroundColor(.white)
                        .padding(.horizontal, 8 * k).padding(.vertical, 3 * k).background(Capsule().fill(IceCityScene.c(IceMapPainter.colour(side.0))))
                }
                Text("兵 \(w.soldiers)").font(.system(size: 12 * k, weight: .bold)).foregroundColor(ink.opacity(0.7))
            }
            if let raid = w.raidThreat {
                Text("⚠︎ \(iceSideCN[raid.rival + 1])军可能在第 \(raid.day) 天来袭，约 \(Int(raid.raiders)) 人（守城 \(Int(w.defenceAtHome))）").font(.system(size: 11.5 * k, weight: .semibold))
                    .foregroundColor(Color(red: 0.7, green: 0.2, blue: 0.16)).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if let r = game.mapPick {
                let c = iceRegions[r], o = w.owner[r]
                Text(c.name + (r == 0 ? "（我们的城）" : "")).font(.system(size: 18 * k, weight: .heavy))
                if r > 0 {
                    Text(o == 0 ? "已归蜀：每天送来 \(IceGood.names[c.resource.rawValue]) +\(Int(c.amount))" : "\(o == 3 ? iceEnemyCN[c.foe] : iceSideCN[o] + "军")守着，约 \(Int(w.garrison[r].rounded())) 人").font(.system(size: 12.5 * k, weight: .semibold))
                    if o != 0 {
                        HStack(spacing: 5 * k) {
                            Text("打下来：每天").font(.system(size: 12 * k))
                            IceGoodIcon(good: c.resource).equatable().frame(width: 16 * k, height: 16 * k)
                            Text("+\(Int(c.amount))，来投 \(c.people) 人").font(.system(size: 12 * k))
                        }
                        .foregroundColor(ink.opacity(0.8))
                        if w.steps(to: r) == nil { note("还太远：先打下和它相连的州") }
                        else if w.expeditions.contains(where: { $0.region == r && !$0.back }) { note("已经有兵在路上") }
                        else if w.freeOfficers.isEmpty { note("没有空闲的武将") }
                        else {
                            Text("派谁去").font(.system(size: 11.5 * k, weight: .bold)).foregroundColor(ink.opacity(0.7))
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5 * k), GridItem(.flexible(), spacing: 5 * k)], spacing: 5 * k) {
                                ForEach(w.freeOfficers, id: \.self) { h in
                                    let picked = (game.sendOfficer ?? w.freeOfficers[0]) == h
                                    Button { game.sendOfficer = h } label: {
                                        HStack(spacing: 4 * k) {
                                            Canvas { g, size in IcePortrait.draw(g, iceOfficers[h], at: CGPoint(x: size.width / 2, y: size.height / 2 + 1), size: size.width * 0.4, now: 0) }
                                                .frame(width: 26 * k, height: 26 * k)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(iceOfficers[h].name).font(.system(size: 12 * k, weight: .heavy))
                                                Text("武\(iceOfficers[h].war) 统\(iceOfficers[h].lead)").font(.system(size: 9 * k, weight: .semibold)).opacity(0.75)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .foregroundColor(picked ? Color(red: 0.3, green: 0.18, blue: 0.04) : ink)
                                        .padding(4 * k)
                                        .background(RoundedRectangle(cornerRadius: 9 * k).fill(picked ? Color(red: 1, green: 0.84, blue: 0.48) : Color.white.opacity(0.75)))
                                        .overlay(RoundedRectangle(cornerRadius: 9 * k).stroke(picked ? Color(red: 0.86, green: 0.6, blue: 0.2) : ink.opacity(0.15), lineWidth: picked ? 1.5 * k : 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            HStack(spacing: 8 * k) {
                                Text("带兵").font(.system(size: 12.5 * k, weight: .bold))
                                Button { game.sendSoldiers = max(5, min(game.sendSoldiers, w.soldiers) - 5) } label: { stepGlyph("minus") }.buttonStyle(.plain)
                                Text("\(min(game.sendSoldiers, w.soldiers)) / \(w.soldiers)").font(.system(size: 14 * k, weight: .heavy, design: .rounded)).monospacedDigit()
                                Button { game.sendSoldiers = min(w.soldiers, game.sendSoldiers + 5) } label: { stepGlyph("plus") }.buttonStyle(.plain)
                            }
                            let h = game.sendOfficer ?? w.freeOfficers[0], n = min(game.sendSoldiers, w.soldiers)
                            let days = w.travel(h, to: r) ?? 2
                            let b = w.battle(h, max(1, n), r, on: w.today + days)
                            Text("胜算 \(Int((b.chance * 100).rounded()))% · 走 \(days) 天 · 赢了约伤 \(b.winWounded) 亡 \(b.winKilled)").font(.system(size: 12.5 * k, weight: .bold))
                                .foregroundColor(b.chance >= 0.75 ? Color(red: 0.16, green: 0.5, blue: 0.26) : b.chance >= 0.45 ? .orange : .red)
                            Button { game.send() } label: {
                                HStack(spacing: 6 * k) {
                                    Image(systemName: "flag.fill").font(.system(size: 13 * k, weight: .bold))
                                    Text("出征").font(.system(size: 15 * k, weight: .heavy))
                                }
                                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 8 * k)
                                .background(Capsule().fill(LinearGradient(colors: [Color(red: 0.28, green: 0.66, blue: 0.44), Color(red: 0.16, green: 0.46, blue: 0.3)], startPoint: .top, endPoint: .bottom)))
                            }
                            .buttonStyle(.plain).disabled(!game.me || n < 5)
                        }
                    }
                }
            } else {
                Text("点一个州看守军和出产；和我们相连、正在闪的州可以派武将带兵去打。").font(.system(size: 12.5 * k)).foregroundColor(ink.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !w.expeditions.isEmpty {
                Divider()
                ForEach(w.expeditions.indices, id: \.self) { i in
                    let e = w.expeditions[i]
                    Text("🚩 \(iceOfficers[e.officer].name) \(e.soldiers) 兵 · " + (e.back ? (e.won == true ? "凯旋中" : "撤回中") + "，\(e.left) 天到家" : "去\(iceRegions[e.region].name)，\(e.left) 天到")).font(.system(size: 12 * k, weight: .semibold))
                }
            }
            if let last = w.battles.last, w.time - last.time < IceCity.daySeconds * 3 {
                Text((last.won ? "捷报：\(iceOfficers[last.officer].name)攻下\(iceRegions[last.region].name)" : "败报：\(iceOfficers[last.officer].name)败于\(iceRegions[last.region].name)") + " · 伤 \(last.wounded) 亡 \(last.killed)")
                    .font(.system(size: 12.5 * k, weight: .heavy)).foregroundColor(last.won ? Color(red: 0.16, green: 0.5, blue: 0.26) : .red)
            }
        }
        .foregroundColor(ink)
    }

    private func note(_ text: String) -> some View { Text(text).font(.system(size: 12.5 * k, weight: .semibold)).foregroundColor(.orange) }

    private func stepGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 11 * k, weight: .heavy)).foregroundColor(.white)
            .frame(width: 24 * k, height: 22 * k)
            .background(RoundedRectangle(cornerRadius: 6 * k).fill(Color(red: 0.3, green: 0.42, blue: 0.64)))
    }
}

struct IceMapPainter {
    let city: IceCity
    let pick: Int?
    let now: Double
    var k: CGFloat = 1

    static func node(_ c: Int, _ size: CGSize) -> CGPoint {
        let m = size.width / 440
        return CGPoint(x: 22 * m + (size.width - 44 * m) * CGFloat(iceRegions[c].x), y: 30 * m + (size.height - 56 * m) * CGFloat(iceRegions[c].y))
    }
    static func hit(_ p: CGPoint, _ size: CGSize, k: CGFloat = 1) -> Int? {
        let near = iceRegions.indices.min { hypot(node($0, size).x - p.x, node($0, size).y - p.y) < hypot(node($1, size).x - p.x, node($1, size).y - p.y) }!
        return hypot(node(near, size).x - p.x, node(near, size).y - p.y) < 22 * k ? near : nil
    }
    static func colour(_ o: Int) -> Art.RGB { [IceCityScene.shu, IceCityScene.wei, IceCityScene.wu, (0.93, 0.94, 0.97)][o] }

    func paint(_ g: inout GraphicsContext, _ size: CGSize) {
        let w = city
        let sheet = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
        g.fill(sheet, with: .linearGradient(Gradient(colors: [Color(red: 0.97, green: 0.98, blue: 1), Color(red: 0.86, green: 0.91, blue: 0.97)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        var clip = g
        clip.clip(to: sheet)
        // Hills in the north, a frozen river across the south, woods.
        var hills = Path(), caps = Path(), woods = Path()
        for i in 0..<18 {
            let p = CGPoint(x: 16 + CGFloat(Art.unit(i, 21)) * (size.width - 32), y: 24 + CGFloat(Art.unit(i, 22)) * 110)
            let s = 10 + 10 * CGFloat(Art.unit(i, 23))
            hills.move(to: CGPoint(x: p.x - s, y: p.y + s * 0.5)); hills.addLine(to: CGPoint(x: p.x, y: p.y - s * 0.6)); hills.addLine(to: CGPoint(x: p.x + s, y: p.y + s * 0.5)); hills.closeSubpath()
            caps.move(to: CGPoint(x: p.x - s * 0.45, y: p.y - s * 0.05)); caps.addLine(to: CGPoint(x: p.x, y: p.y - s * 0.6)); caps.addLine(to: CGPoint(x: p.x + s * 0.45, y: p.y - s * 0.05)); caps.closeSubpath()
        }
        for i in 0..<60 {
            let p = CGPoint(x: 10 + CGFloat(Art.unit(i, 24)) * (size.width - 20), y: 150 + CGFloat(Art.unit(i, 25)) * (size.height - 170))
            woods.move(to: CGPoint(x: p.x - 3, y: p.y + 3)); woods.addLine(to: CGPoint(x: p.x, y: p.y - 5)); woods.addLine(to: CGPoint(x: p.x + 3, y: p.y + 3)); woods.closeSubpath()
        }
        clip.fill(hills, with: .color(Color(red: 0.64, green: 0.7, blue: 0.82)))
        clip.fill(caps, with: .color(.white))
        clip.fill(woods, with: .color(Color(red: 0.42, green: 0.58, blue: 0.56).opacity(0.5)))
        let river = Path { p in
            p.move(to: CGPoint(x: 0, y: size.height * 0.8))
            p.addCurve(to: CGPoint(x: size.width * 0.56, y: size.height * 0.76), control1: CGPoint(x: size.width * 0.2, y: size.height * 0.88), control2: CGPoint(x: size.width * 0.38, y: size.height * 0.7))
            p.addCurve(to: CGPoint(x: size.width, y: size.height * 0.8), control1: CGPoint(x: size.width * 0.74, y: size.height * 0.82), control2: CGPoint(x: size.width * 0.86, y: size.height * 0.72))
        }
        clip.stroke(river, with: .color(Color(red: 0.62, green: 0.78, blue: 0.92)), lineWidth: 9)
        clip.stroke(river, with: .color(Color(red: 0.86, green: 0.94, blue: 1)), lineWidth: 4)
        // Roads: ours solid in green, the rest dashed.
        var roads = Path(), ours = Path()
        for (a, b) in iceRegionRoads {
            let pa = Self.node(a, size), pb = Self.node(b, size)
            if w.owner[a] == 0 && w.owner[b] == 0 { ours.move(to: pa); ours.addLine(to: pb) } else { roads.move(to: pa); roads.addLine(to: pb) }
        }
        g.stroke(roads, with: .color(Color(red: 0.5, green: 0.58, blue: 0.72).opacity(0.7)), style: StrokeStyle(lineWidth: 1.6 * k, dash: [4 * k, 3 * k]))
        g.stroke(ours, with: .color(IceCityScene.c(IceCityScene.shu, 0.85)), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
        let reach = Set(w.targets)
        for c in iceRegions.indices {
            let p = Self.node(c, size), o = w.owner[c], region = iceRegions[c]
            let r: CGFloat = (region.capital ? 13 : 10) * k
            if c == 0 { g.fill(Path(ellipseIn: CGRect(x: p.x - 24 * k, y: p.y - 24 * k, width: 48 * k, height: 48 * k)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.7, blue: 0.3).opacity(0.55), .clear]), center: p, startRadius: 0, endRadius: 24 * k)) }
            if reach.contains(c) {
                let pulse = 0.5 + 0.5 * sin(now * 3 + Double(c))
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r - 4 * k, y: p.y - r - 4 * k, width: 2 * r + 8 * k, height: 2 * r + 8 * k)), with: .color(Color(red: 0.95, green: 0.62, blue: 0.2).opacity(0.4 + 0.4 * pulse)), lineWidth: 2 * k)
            }
            if pick == c { g.stroke(Path(ellipseIn: CGRect(x: p.x - r - 7 * k, y: p.y - r - 7 * k, width: 2 * r + 14 * k, height: 2 * r + 14 * k)), with: .color(.yellow), lineWidth: 2.5 * k) }
            g.fill(Path(ellipseIn: CGRect(x: p.x - r + 1, y: p.y - r + 2, width: 2 * r, height: 2 * r)), with: .color(.black.opacity(0.18)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .radialGradient(Gradient(colors: [IceCityScene.c(Art.lit(Self.colour(o), 1.25)), IceCityScene.c(Self.colour(o))]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
            g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(o == 3 ? Color(red: 0.5, green: 0.56, blue: 0.68) : .white), lineWidth: 1.5)
            let mark = c == 0 ? "城" : o == 0 ? "蜀" : o == 1 ? "魏" : o == 2 ? "吴" : ["贼", "狼", "寇"][max(0, min(2, region.foe))]
            g.draw(Text(mark).font(.system(size: (region.capital ? 11 : 9.5) * k, weight: .heavy, design: .rounded)).foregroundColor(o == 3 ? Color(red: 0.3, green: 0.34, blue: 0.46) : .white), at: p)
            g.draw(Text(region.name).font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(Color(red: 0.16, green: 0.2, blue: 0.32)), at: CGPoint(x: p.x, y: p.y + r + 8 * k))
            if o != 0, c > 0 { g.draw(Text("\(Int(w.garrison[c].rounded()))").font(.system(size: 9 * k, weight: .semibold, design: .rounded)).foregroundColor(Color(red: 0.42, green: 0.46, blue: 0.58)), at: CGPoint(x: p.x + r + 9 * k, y: p.y - r + 2 * k)) }
        }
        // Armies on the march: a banner going out, or coming home.
        for e in w.expeditions {
            let route = path(to: e.region, size)
            let done = Double(e.travel - e.left) + (w.day - Double(w.today))
            let f = max(0, min(1, done / Double(max(1, e.travel))))
            let p = point(on: route, at: e.back ? 1 - f : f)
            banner(&g, p, name: iceOfficers[e.officer].name, soldiers: e.soldiers, back: e.back, won: e.won)
        }
        for b in w.battles where w.time - b.time < IceCity.daySeconds * 1.5 {
            JevDraw.blast(g, at: Self.node(b.region, size), size: 10 * k, age: (w.time - b.time) / IceCity.daySeconds)
        }
    }

    private func path(to region: Int, _ size: CGSize) -> [CGPoint] {
        var came: [Int: Int] = [0: 0], frontier = [0]
        while !frontier.isEmpty, came[region] == nil {
            var next: [Int] = []
            for a in frontier { for b in iceRegionLinks[a] where came[b] == nil && (b == region || city.owner[b] == 0) { came[b] = a; next.append(b) } }
            frontier = next
        }
        guard came[region] != nil else { return [Self.node(0, size), Self.node(region, size)] }
        var out = [region]
        while let last = out.last, last != 0, let from = came[last] { out.append(from) }
        return out.reversed().map { Self.node($0, size) }
    }
    private func point(on route: [CGPoint], at f: Double) -> CGPoint {
        guard route.count > 1 else { return route.first ?? .zero }
        let lengths = zip(route, route.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = CGFloat(f) * lengths.reduce(0, +)
        for (i, l) in lengths.enumerated() {
            if left <= l || i == lengths.count - 1 {
                let u = l > 0 ? min(1, left / l) : 0
                return CGPoint(x: route[i].x + (route[i + 1].x - route[i].x) * u, y: route[i].y + (route[i + 1].y - route[i].y) * u)
            }
            left -= l
        }
        return route.last!
    }
    private func banner(_ g: inout GraphicsContext, _ p: CGPoint, name: String, soldiers: Int, back: Bool, won: Bool?) {
        let bob = CGFloat(sin(now * 6)) * 0.8 * k, wave = CGFloat(sin(now * 5)) * 1.4 * k
        g.stroke(Path { q in q.move(to: CGPoint(x: p.x, y: p.y + 5 * k)); q.addLine(to: CGPoint(x: p.x, y: p.y - 24 * k + bob)) }, with: .color(Color(red: 0.3, green: 0.22, blue: 0.16)), lineWidth: 1.6 * k)
        let cloth = Path { q in q.move(to: CGPoint(x: p.x, y: p.y - 24 * k + bob)); q.addQuadCurve(to: CGPoint(x: p.x + 26 * k, y: p.y - 21 * k + wave + bob), control: CGPoint(x: p.x + 13 * k, y: p.y - 26 * k - wave + bob)); q.addLine(to: CGPoint(x: p.x + 26 * k, y: p.y - 8 * k + wave + bob)); q.addQuadCurve(to: CGPoint(x: p.x, y: p.y - 9 * k + bob), control: CGPoint(x: p.x + 13 * k, y: p.y - 11 * k - wave + bob)); q.closeSubpath() }
        g.fill(cloth, with: .color(IceCityScene.c(IceCityScene.shu)))
        g.stroke(cloth, with: .color(.white.opacity(0.85)), lineWidth: 0.8 * k)
        g.draw(Text(String(name.prefix(1))).font(.system(size: 10 * k, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: p.x + 12 * k, y: p.y - 16 * k + bob))
        g.draw(Text(back ? (won == true ? "凯旋 \(soldiers)" : "撤回 \(soldiers)") : "\(soldiers) 兵").font(.system(size: 9 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.12, green: 0.3, blue: 0.18)), at: CGPoint(x: p.x + 12 * k, y: p.y + 3 * k))
    }
}

// MARK: - At the bottom left: what is selected and what can be done with it — or how to play

struct IceInfoCard: View {
    @ObservedObject var game: IceGame
    var k: CGFloat

    var body: some View {
        _ = game.beat
        let w = game.city
        return Group {
            if let id = game.selected, let b = w.building(id) {
                selected(b, w)
            } else if !game.me {
                watching
            } else {
                hints
            }
        }
        .padding(12 * k)
        .frame(width: 318 * k, alignment: .leading)
        .iceGlass(k, radius: 16)
        .padding(12 * k)
    }

    private var hints: some View {
        let rows: [[(String, String)]] = [[("空格", "暂停"), ("1–4", "速度"), ("M", "舆图")], [("R", "铺路"), ("W", "筑墙"), ("X", "拆除")], [("Esc", "取消"), ("⇧", "连续放"), ("= -", "缩放")]]
        return VStack(alignment: .leading, spacing: 7 * k) {
            HStack(spacing: 6 * k) {
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 13 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.5))
                Text("点下面的建筑，再点雪地放下").font(.system(size: 13.5 * k, weight: .heavy)).foregroundColor(.white)
            }
            Text("点熔炉两次升级 · 拖动看别处 · ⌘滚轮或捏合缩放").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.72))
            VStack(alignment: .leading, spacing: 5 * k) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r].indices, id: \.self) { i in
                            HStack(spacing: 6 * k) {
                                IceKey(text: rows[r][i].0, k: k)
                                Text(rows[r][i].1).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                            }
                            .frame(width: 98 * k, alignment: .leading)
                        }
                    }
                }
            }
            HStack(spacing: 14 * k) {
                IceSwitch(title: "自动安排工人", on: game.autoStaff, k: k) { game.autoStaff.toggle() }
                IceSwitch(title: "Jev 参谋", on: game.jevAdvises, k: k) { game.jevAdvises.toggle() }
            }
            .padding(.top, 2 * k)
        }
    }

    private var watching: some View {
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack(spacing: 6 * k) {
                Image(systemName: "eye.fill").font(.system(size: 13 * k, weight: .bold)).foregroundColor(Color(red: 0.7, green: 0.86, blue: 1))
                Text("观战：\(game.seat.title)当城主").font(.system(size: 14 * k, weight: .heavy)).foregroundColor(.white)
            }
            if let note = game.note { Text(note).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(Color(red: 1, green: 0.9, blue: 0.66)).fixedSize(horizontal: false, vertical: true) }
            Text("右上角换成「我」就能自己当城主").font(.system(size: 11.5 * k, weight: .semibold)).foregroundColor(.white.opacity(0.7))
        }
    }

    private func selected(_ b: IceBuilding, _ w: IceCity) -> some View {
        VStack(alignment: .leading, spacing: 7 * k) {
            HStack(alignment: .top, spacing: 10 * k) {
                IceBuildingIcon(kind: b.kind, tool: nil).equatable().frame(width: 58 * k, height: 50 * k)
                    .background(RoundedRectangle(cornerRadius: 10 * k).fill(Color.white.opacity(0.9)))
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text(b.kind == .furnace ? "熔炉 \(b.level) 级" : b.kind.name).font(.system(size: 17 * k, weight: .heavy)).foregroundColor(.white)
                    if let h = w.governor(b.id) { Text("\(iceOfficers[h].name) 管着").font(.system(size: 11.5 * k, weight: .bold)).foregroundColor(Color(red: 1, green: 0.8, blue: 0.45)) }
                    Text(detail(b, w)).font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.82)).fixedSize(horizontal: false, vertical: true).lineLimit(3)
                }
            }
            if b.done, b.kind.slots > 0 {
                HStack(spacing: 8 * k) {
                    Image(systemName: "person.3.fill").font(.system(size: 12 * k)).foregroundColor(.white.opacity(0.8))
                    Text("工人 \(w.workers(b.id))/\(b.wanted)（最多 \(b.kind.slots)）").font(.system(size: 12.5 * k, weight: .bold)).foregroundColor(.white).monospacedDigit()
                    if game.me {
                        action("−", nil) { game.workers(-1) }
                        action("+", nil) { game.workers(1) }
                    }
                }
            }
            if game.me {
                HStack(spacing: 8 * k) {
                    if b.kind == .furnace, b.level < IceCity.topLevel, !b.upgrading {
                        let c = IceCity.upgradeCost(to: b.level + 1)
                        action("升到 \(b.level + 1) 级  \(Int(c[1]))木 \(Int(c[3]))石 \(Int(c[4]))铁", "flame.fill", warm: true) { game.upgradeFurnace() }
                    }
                    if b.kind == .barracks, b.done { action("练兵  \(IceCity.batchSize * 2)粮 \(IceCity.batchSize)铁", "shield.fill", warm: true) { game.train() } }
                    if b.kind != .furnace { action("拆", "xmark.bin.fill") { game.demolish() } }
                }
            }
        }
    }

    private func action(_ title: String, _ symbol: String?, warm: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5 * k) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11 * k, weight: .bold)) }
                Text(title).font(.system(size: 12 * k, weight: .heavy))
            }
            .foregroundColor(.white).padding(.horizontal, 10 * k).padding(.vertical, 6 * k)
            .background(Capsule().fill(warm ? LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.86, green: 0.34, blue: 0.16)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ b: IceBuilding, _ w: IceCity) -> String {
        if !b.done || b.upgrading {
            let c = w.cost(of: b)
            var parts: [String] = []
            for (g, name) in [(1, "木"), (3, "石"), (4, "铁")] where c[g] > 0 { parts.append("\(name) \(Int(b.delivered[g]))/\(Int(c[g]))") }
            return (b.upgrading ? "升级中：" : "在盖：") + (parts.isEmpty ? "" : "材料 " + parts.joined(separator: " · ") + "\n") + "进度 \(Int(b.progress * 100))%"
        }
        switch b.kind {
        case .furnace:
            return String(format: "热圈 %@ 格 · 每天烧 %.0f 煤\n炉里有 %.0f 煤 · 暖着 %d 座民居", IceCommander.fmt(w.heatRadius), w.burnRate, b.stock[0], w.warmHouses.count)
        case .storage:
            return "存着：" + (0..<5).filter { b.stock[$0] >= 1 }.map { "\(IceGood.names[$0]) \(Int(b.stock[$0]))" }.joined(separator: " · ")
        case .house:
            return "住 \(w.residents(b.id)) 人 · " + (w.warmed(b) ? "在热圈里，暖和" : "在热圈外，冷") + (w.sheltered(b) ? " · 有墙挡风" : "") + "\n家里存粮 \(Int(b.stock[2]))"
        case .coalMine, .ironMine, .quarry:
            return "还能挖 \(Int(b.reserve))\n今天 \(Int(b.output)) · 昨天 \(Int(b.lastOutput))"
        case .clinic:
            let lying = w.people.filter { if case .heal(b.id) = $0.task { return true }; return false }.count
            return "病床 \(lying)/\(IceCity.clinicBeds)\n全城每天治好约 \(Int(w.heals)) 人"
        case .barracks:
            return "兵 \(w.soldiers)/\(w.soldierRoom)" + (b.batch > 0 ? " · 正在练 \(b.batch) 个" : "")
        case .tavern:
            return "武将 \(w.officers.count)/\(w.heroRoom)\n上面一排虚线的武将，点一下就招募"
        case .greenhouse:
            return "今天 \(Int(b.output)) 粮 · 昨天 \(Int(b.lastOutput))" + (w.burning ? "" : "\n熔炉灭了，长得慢")
        default:
            return "今天 \(Int(b.output)) · 昨天 \(Int(b.lastOutput))" + (b.kind == .lumber ? " 木" : " 粮")
        }
    }
}

// MARK: - At the bottom middle: what the mouse is doing, the storm, Jev's advice

struct IceTray: View {
    @ObservedObject var game: IceGame
    var k: CGFloat
    var body: some View {
        _ = game.beat
        let w = game.city
        return VStack(spacing: 6 * k) {
            if let advice = game.advice, game.me {
                HStack(spacing: 8 * k) {
                    Text("Jev").font(.system(size: 11 * k, weight: .heavy)).foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.3))
                        .padding(.horizontal, 6 * k).padding(.vertical, 2 * k).background(Capsule().fill(Color(red: 0.62, green: 0.86, blue: 1)))
                    Text(advice.option.title).font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text("\(Int(advice.chance * 100))%").font(.system(size: 11 * k, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                    Button { game.follow() } label: {
                        Text("照做").font(.system(size: 12 * k, weight: .heavy)).foregroundColor(.white)
                            .padding(.horizontal, 10 * k).padding(.vertical, 4 * k).background(Capsule().fill(Color(red: 0.28, green: 0.62, blue: 0.42)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12 * k).padding(.vertical, 7 * k).iceGlass(k, radius: 20)
            } else if game.jevAdvises, game.me {
                Text("Jev 在想…").font(.system(size: 12 * k, weight: .semibold)).foregroundColor(.white.opacity(0.8)).padding(.horizontal, 12 * k).padding(.vertical, 6 * k).iceGlass(k, radius: 20)
            }
            Group {
                if game.tool == .wall { pill("拖动筑墙：每格 3 石 1 木 · 北风从上面刮来，墙南边（淡蓝处）避风，暴风雪里暖 10°C") }
                else if game.tool == .road { pill("拖动铺路：人在路上走得快") }
                else if game.tool == .bulldoze { pill("点建筑、城墙或路把它拆掉，材料回来一半") }
                else if let kind = game.placing { pill("点雪地放下\(kind.name) · ⇧ 连续放 · 右键取消") }
                else if let a = game.assigning { pill("点一座建筑，让\(iceOfficers[a].name)去管（右键取消）") }
                if w.storm { pill("🌪 大寒暴风雪：墙外、热圈外的人会冻病冻死", storm: true) }
            }
        }
        .padding(.bottom, 16 * k)
    }

    private func pill(_ text: String, storm: Bool = false) -> some View {
        Text(text).font(.system(size: 13 * k, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 14 * k).padding(.vertical, 7 * k)
            .background(Capsule().fill(storm ? Color(red: 0.2, green: 0.38, blue: 0.74).opacity(0.9) : Color(red: 0.07, green: 0.1, blue: 0.2).opacity(0.8)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

// MARK: - Along the bottom: the building cards, grouped, each with its picture and its price

struct IceBar: View {
    @ObservedObject var game: IceGame
    var k: CGFloat

    /// What a card places or which tool it picks.
    enum Card: Hashable { case build(IceBuildKind), tool(IceTool) }
    static let groups: [(title: String, cards: [Card])] = [
        ("住", [.build(.house), .build(.storage), .build(.clinic)]),
        ("产", [.build(.lumber), .build(.coalMine), .build(.ironMine), .build(.quarry), .build(.hunter), .build(.fishery), .build(.greenhouse)]),
        ("兵", [.build(.barracks), .build(.tavern), .tool(.wall)]),
        ("工", [.tool(.road), .tool(.bulldoze)]),
    ]

    var body: some View {
        _ = game.beat
        return GeometryReader { space in
            let count = CGFloat(Self.groups.reduce(0) { $0 + $1.cards.count })
            let tags = CGFloat(Self.groups.count) * 30 * k
            let gap = 6 * k
            let fit = (space.size.width - 24 * k - tags - gap * (count + CGFloat(Self.groups.count) * 2)) / count
            let width = min(92 * k, max(54 * k, fit))
            let row = HStack(spacing: gap * 2) {
                ForEach(Self.groups.indices, id: \.self) { i in
                    HStack(spacing: gap) {
                        tag(Self.groups[i].title)
                        ForEach(Self.groups[i].cards, id: \.self) { card in self.card(card, width) }
                    }
                }
            }
            .padding(.horizontal, 12 * k)
            Group {
                if fit >= 54 * k { row.frame(width: space.size.width, height: space.size.height) }
                else { ScrollView(.horizontal, showsIndicators: false) { row.frame(height: space.size.height) } }
            }
        }
        .frame(height: 122 * k)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.33), Color(red: 0.06, green: 0.1, blue: 0.21)], startPoint: .top, endPoint: .bottom)
                .overlay(Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1), alignment: .top)
        )
    }

    private func tag(_ title: String) -> some View {
        Text(title).font(.system(size: 14 * k, weight: .heavy)).foregroundColor(Color(red: 1, green: 0.88, blue: 0.6))
            .frame(width: 26 * k, height: 96 * k)
            .background(RoundedRectangle(cornerRadius: 8 * k).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8 * k).stroke(Color(red: 1, green: 0.84, blue: 0.5).opacity(0.3), lineWidth: 1))
    }

    private func card(_ card: Card, _ width: CGFloat) -> some View {
        let w = game.city
        let on: Bool, name: String, key: String?, costs: [(IceGood, Double)], blocked: String?, run: () -> Void
        switch card {
        case .build(let kind):
            on = game.placing == kind
            name = kind.name
            key = nil
            costs = [IceGood.wood, .stone, .iron].compactMap { g in kind.cost[g.rawValue] > 0 ? (g, kind.cost[g.rawValue]) : nil }
            blocked = !game.me ? "观战中：右上角换成「我」才能盖" : kind == .greenhouse && w.level < 2 ? "温室要熔炉 2 级才暖得起来" : nil
            run = { game.placing = game.placing == kind ? nil : kind }
        case .tool(let tool):
            on = game.tool == tool
            name = tool == .road ? "道路" : tool == .wall ? "城墙" : "拆除"
            key = tool == .road ? "R" : tool == .wall ? "W" : "X"
            costs = tool == .wall ? [(.stone, 3), (.wood, 1)] : []
            blocked = !game.me ? "观战中：右上角换成「我」才能用" : nil
            run = { game.tool = game.tool == tool ? nil : tool }
        }
        let short = costs.contains { w.stored($0.0) < $0.1 }
        let tip: String = {
            if let blocked { return blocked }
            switch card {
            case .build(let kind): return "\(kind.name)：\(Self.purpose(kind))" + (short ? "\n材料不够：先放下，等材料运到再盖" : "")
            case .tool(let tool): return tool == .road ? "拖动铺路（R）：路上走得快" : tool == .wall ? "拖动筑墙（W）：每格 3 石 1 木，挡北风、防突袭" : "拆除（X）：点建筑、城墙或路，材料回来一半"
            }
        }()
        return Button(action: run) {
            VStack(spacing: 2 * k) {
                ZStack(alignment: .topTrailing) {
                    switch card {
                    case .build(let kind): IceBuildingIcon(kind: kind, tool: nil).equatable().frame(width: width - 10 * k, height: 46 * k)
                    case .tool(let tool): IceBuildingIcon(kind: nil, tool: tool).equatable().frame(width: width - 10 * k, height: 46 * k)
                    }
                    if let key { IceKey(text: key, k: k * 0.85).offset(x: 3 * k, y: -3 * k) }
                }
                Text(name).font(.system(size: 12.5 * k, weight: .heavy)).foregroundColor(on ? Color(red: 0.24, green: 0.14, blue: 0.04) : .white).lineLimit(1)
                costRow(costs, w, on)
            }
            .padding(.horizontal, 4 * k).padding(.vertical, 5 * k)
            .frame(width: width, height: 106 * k, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(on ? LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), Color(red: 1, green: 0.74, blue: 0.34)], startPoint: .top, endPoint: .bottom)
                                                                     : LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(on ? Color(red: 1, green: 0.95, blue: 0.8) : Color.white.opacity(0.2), lineWidth: on ? 2 * k : 1))
            .shadow(color: on ? Color(red: 1, green: 0.7, blue: 0.3).opacity(0.6) : .clear, radius: 8 * k)
            .opacity(blocked != nil ? 0.42 : short ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked != nil)
        .help(tip)
    }

    private func costRow(_ costs: [(IceGood, Double)], _ w: IceCity, _ on: Bool) -> some View {
        let rows = costs.isEmpty ? [] : stride(from: 0, to: costs.count, by: 2).map { Array(costs[$0..<min($0 + 2, costs.count)]) }
        return VStack(spacing: 1 * k) {
            if costs.isEmpty {
                Text("免费").font(.system(size: 10.5 * k, weight: .bold)).foregroundColor(on ? Color(red: 0.36, green: 0.24, blue: 0.1) : .white.opacity(0.6))
            }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4 * k) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        let (good, amount) = rows[r][i]
                        let have = w.stored(good) >= amount
                        HStack(spacing: 1 * k) {
                            IceGoodIcon(good: good).equatable().frame(width: 11 * k, height: 11 * k)
                            Text("\(Int(amount))").font(.system(size: 10.5 * k, weight: .heavy, design: .rounded)).monospacedDigit().fixedSize()
                                .foregroundColor(have ? (on ? Color(red: 0.3, green: 0.2, blue: 0.08) : .white.opacity(0.92)) : Color(red: 1, green: 0.42, blue: 0.38))
                        }
                    }
                }
            }
        }
    }

    static func purpose(_ kind: IceBuildKind) -> String {
        switch kind {
        case .house: return "住 5 人；在热圈里才暖和"
        case .storage: return "存放东西，工人就近搬运"
        case .clinic: return "治病人，6 张病床"
        case .lumber: return "砍附近的松树，出木头"
        case .coalMine: return "要挨着黑色的煤层，出煤"
        case .ironMine: return "要挨着带红斑的铁矿石，出铁"
        case .quarry: return "要挨着岩石，出石头"
        case .hunter: return "在附近树林里打猎，出粮"
        case .fishery: return "要整个放在冰面上，凿冰钓鱼"
        case .greenhouse: return "放在热圈里，一年四季长粮"
        case .barracks: return "练兵，每座多住 20 个兵"
        case .tavern: return "招募武将，民心每天 +0.3"
        case .furnace: return "城的心"
        }
    }
}

// MARK: - The mouse: clicks, drags for roads and walls, where it hovers

struct IceMouse: NSViewRepresentable {
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {}

    final class Catcher: NSView {
        private var start: IceTile?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
        @MainActor private func tileAt(_ e: NSEvent) -> IceTile { IceGame.shared.tile(at: point(e)) }

        override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { IceGame.shared.hover = tileAt(event) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { IceGame.shared.hover = nil } }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
            MainActor.assumeIsolated {
                let game = IceGame.shared
                start = tileAt(event)
                if game.tool == .road || game.tool == .wall, let start { game.drag = (start, start) }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = IceGame.shared
                let t = tileAt(event)
                game.hover = t
                if game.tool == .road || game.tool == .wall, let start { game.drag = (start, t) }
                else if game.placing == nil { game.pan(event.deltaX, event.deltaY) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = IceGame.shared
                let t = tileAt(event)
                if game.tool == .road, let start { game.road(start, t); game.drag = nil }
                else if game.tool == .wall, let start { game.wall(start, t); game.drag = nil }
                else if start == t || game.placing != nil || game.tool != nil { game.click(t) }
            }
            start = nil
        }
        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = IceGame.shared
                game.placing = nil; game.tool = nil; game.drag = nil; game.selected = nil; game.assigning = nil
            }
        }
        override func scrollWheel(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = IceGame.shared
                if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                    game.zoom(by: pow(1.02, event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 3)), at: point(event))
                } else {
                    game.pan(event.scrollingDeltaX, event.scrollingDeltaY)
                }
            }
        }
        override func magnify(with event: NSEvent) {
            MainActor.assumeIsolated { IceGame.shared.zoom(by: 1 + event.magnification, at: point(event)) }
        }
    }
}

/// The keyboard while the city is showing: Esc lets go, space pauses, 1–4 set the speed, arrows move, = and - zoom, R roads, W walls, X demolishes, M the map.
@MainActor
enum IceKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let game = IceGame.shared
            switch event.keyCode {
            case 53: game.placing = nil; game.tool = nil; game.selected = nil; game.drag = nil; game.assigning = nil; game.showMap = false; return nil
            case 49: game.speed = game.speed == 0 ? 1 : 0; return nil
            case 15: if game.me { game.tool = game.tool == .road ? nil : .road }; return nil
            case 13: if game.me { game.tool = game.tool == .wall ? nil : .wall }; return nil
            case 7: if game.me { game.tool = game.tool == .bulldoze ? nil : .bulldoze }; return nil
            case 46: game.showMap.toggle(); return nil
            case 18, 19, 20, 21: game.speed = [1, 2, 4, 8][Int(event.keyCode) - 18]; return nil
            case 123: game.pan(120, 0); return nil
            case 124: game.pan(-120, 0); return nil
            case 125: game.pan(0, -120); return nil
            case 126: game.pan(0, 120); return nil
            case 24: game.zoom(by: 1.25); return nil
            case 27: game.zoom(by: 0.8); return nil
            default: return event
            }
        }
    }
    static func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

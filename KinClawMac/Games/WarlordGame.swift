import AppKit
import SwiftUI

/// Who plays a faction.
enum WarlordSeat: String, CaseIterable, Identifiable {
    case me, computer, jev, tev1, nimble, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "tev1", "nimble", "大模型"][Self.allCases.firstIndex(of: self)!] }
    /// tev1 or nimble: an open decision model on the box's Ollama, asked Jev's own question.
    var open: String? { self == .tev1 || self == .nimble ? rawValue : nil }
    /// Jev, or an open model of its kind.
    var decides: Bool { self == .jev || open != nil }
    /// Does somebody other than the script choose what comes first?
    var commands: Bool { decides || self == .llm }
}

/// An army being made ready to march: from where, at what, with whom, how many.
struct WarlordDraft {
    var from: Int, to: Int
    var team: [Int]
    var troops: Int
}

/// Soldiers, gold and grain being sent to a neighbouring city of one's own.
struct WarlordShipment {
    var from: Int, to: Int
    var officer: Int
    var troops = 0, gold = 0, grain = 0
    /// 移动: the general goes too. 运输: the goods go, the general stays.
    var stay: Bool
}

/// 三国争霸（大地图版）, played with the mouse: whose turn it is, what the
/// person has chosen on the map, the orders a click becomes, and the months
/// going by — the script's, Jev's and the chat models' turns quickly, the
/// person's for as long as they like.
@MainActor
final class WarlordGame: ObservableObject {
    static let shared = WarlordGame()

    enum Phase: Equatable {
        /// The faction at this place in the month's order is moving.
        case turn(Int)
        /// Every army on the road goes forward.
        case marching
        /// The month's battles are being told.
        case telling
    }

    @Published private(set) var beat = 0
    /// Paused until somebody presses 开始; the person's own turn waits for them at any speed.
    @Published var speed = 0.0 { didSet { if speed > 0 { started = true; if loop == nil { start() } } } }
    @Published private(set) var started = false
    private(set) var world: WarlordWorld
    private(set) var seed: UInt64
    @Published var seats: [WarlordSeat] { didSet { UserDefaults.standard.set(seats.map(\.rawValue), forKey: "kinclaw.warlord.seats") } }
    /// For a chat model: "host|model", or "" for the app's own pick.
    @Published var model = "" { didSet { UserDefaults.standard.set(model, forKey: "kinclaw.warlord.model") } }

    @Published private(set) var phase: Phase = .turn(0)
    private var acted = false, asking = false
    private var hold = 0.0
    /// How far this month's march has gone.
    private(set) var marchT = 0.0
    /// The month's battles, while they are told.
    @Published private(set) var told: [WarlordBattle] = []
    private var tellHold = 0.0
    /// The person was in one of these battles: the reports wait for them.
    @Published private(set) var tellWaits = false
    /// What Jev or a chat model last chose for each faction.
    @Published private(set) var words: [Int: String] = [:]

    // What the person has picked.
    @Published var selected: Int? { didSet { if selected != oldValue { picked = nil } } }
    @Published var picked: Int?
    /// Picking a city on the map: enemy ones to march on, or our own to move or send to.
    enum Targeting: Equatable { case march(Int), move(Int, Int), send(Int, Int) }
    @Published var targeting: Targeting?
    @Published var draft: WarlordDraft?
    @Published var shipment: WarlordShipment?
    @Published var showDiplomacy = false
    @Published var showSeats = false
    @Published var showFactions = true
    @Published var showChronicle = false
    var hover: Int?

    @Published var camera = GameCamera(map: CGSize(width: WarlordMap.width, height: WarlordMap.height), focus: CGPoint(x: WarlordMap.width / 2, y: WarlordMap.height / 2), zoom: 1)
    var viewSize = CGSize(width: 1200, height: 760)
    var scale: CGFloat = 1

    @Published private(set) var message: String?
    private var said = Date.distantPast
    private var loop: Task<Void, Never>?
    private var frames = 0

    init() {
        seed = UInt64.random(in: 1...9999)
        world = WarlordWorld(seed: seed)
        let kept = UserDefaults.standard.stringArray(forKey: "kinclaw.warlord.seats")?.compactMap(WarlordSeat.init(rawValue:)) ?? []
        seats = kept.count == warlordBanners.count ? kept : warlordBanners.indices.map { $0 == 0 ? .me : .computer }
        model = UserDefaults.standard.string(forKey: "kinclaw.warlord.model") ?? ""
        selected = seats.firstIndex(of: .me).map { warlordBanners[$0].cities[0] }
    }

    // MARK: Who is who

    /// The faction moving now.
    var current: Int? {
        guard case .turn(let i) = phase, world.order.indices.contains(i) else { return nil }
        return world.order[i]
    }
    /// The person's faction whose turn it is now.
    var myTurn: Int? { current.flatMap { seats[$0] == .me && world.factions[$0].alive ? $0 : nil } }
    /// The faction the person plays (the one moving now if several), or nil when only watching.
    var mine: Int? { myTurn ?? seats.indices.first { seats[$0] == .me && world.factions[$0].alive } }
    /// The faction the bar shows: the person's, or the one watched.
    var shown: Int {
        if let mine { return mine }
        if let s = selected, world.cities[s].owner >= 0 { return world.cities[s].owner }
        return world.factions.indices.filter { world.factions[$0].alive }.max { world.strength($0) < world.strength($1) } ?? 0
    }

    func setSeat(_ f: Int, _ seat: WarlordSeat) {
        guard seats.indices.contains(f) else { return }
        seats[f] = seat
        words[f] = nil
        if seat != .me, targeting != nil || draft != nil || shipment != nil { cancel() }
        beat += 1
    }
    /// A faction by its lord's name or its banner's character.
    func faction(named name: String) -> Int? {
        warlordBanners.firstIndex { $0.lord == name || $0.mark == name } ?? world.factions.indices.first { world.lordName($0) == name }
    }

    func say(_ text: String) { message = text; said = Date() }
    var saying: String? { Date().timeIntervalSince(said) < 3.5 ? message : nil }

    // MARK: The clock

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                tick(1.0 / 60)
                frames += 1
                if frames % 8 == 0 { beat += 1 }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }

    func restart(seed chosen: UInt64? = nil) {
        seed = chosen ?? UInt64.random(in: 1...9999)
        world = WarlordWorld(seed: seed)
        phase = .turn(0); acted = false; asking = false; hold = 0; marchT = 0
        told = []; tellWaits = false; words = [:]
        cancel(); showDiplomacy = false
        selected = mine.map { warlordBanners[$0].cities[0] }
        started = false; speed = 0
        camera = GameCamera(map: CGSize(width: WarlordMap.width, height: WarlordMap.height), focus: CGPoint(x: WarlordMap.width / 2, y: WarlordMap.height / 2), zoom: 1)
        camera.settle(viewSize)
        beat += 1
    }

    /// One frame of the game's time: the script's turns, the march, the battle reports.
    func tick(_ dt: Double) {
        guard !world.over else { return }
        switch phase {
        case .turn(let i):
            guard i < world.order.count else { phase = .marching; marchT = 0; return }
            let f = world.order[i]
            guard world.factions[f].alive else { next(); return }
            if seats[f] == .me { return }
            guard speed > 0 else { return }
            if !acted {
                if seats[f] == .computer {
                    let before = world.armies.count
                    WarlordBrain.play(&world, f)
                    acted = true
                    hold = world.armies.count > before ? 0.6 : 0.12
                    beat += 1
                } else if !asking { consult(f) }
                return
            }
            hold -= dt * speed
            if hold <= 0 { next() }
        case .marching:
            guard speed > 0 else { return }
            marchT += world.armies.isEmpty ? 1 : dt * speed / 1.1
            if marchT >= 1 { finishMonth() }
        case .telling:
            guard !tellWaits, speed > 0 else { return }
            tellHold -= dt * speed
            if tellHold <= 0 { endTelling() }
        }
    }

    private func next() {
        guard case .turn(let i) = phase else { return }
        phase = .turn(i + 1); acted = false
        beat += 1
    }

    private func finishMonth() {
        world.endMonth()
        marchT = 0
        if let s = selected, draft?.from == s || shipment?.from == s { cancel() }
        let fights = world.battles
        if fights.isEmpty { phase = .turn(0); acted = false; beat += 1; return }
        let me = Set(seats.indices.filter { seats[$0] == .me })
        // The person's own battles first.
        told = fights.filter { me.contains($0.attacker) || me.contains($0.defender) } + fights.filter { !(me.contains($0.attacker) || me.contains($0.defender)) }
        tellWaits = fights.contains { me.contains($0.attacker) || me.contains($0.defender) }
        tellHold = 1.3 + 0.55 * Double(min(fights.count, 8))
        phase = .telling
        beat += 1
    }

    /// The reports put away: the next month begins.
    func endTelling() {
        guard phase == .telling else { return }
        told = []; tellWaits = false
        phase = .turn(0); acted = false
        beat += 1
    }

    /// Play on at once without drawing, every faction as its seat says (the script standing in for Jev and chat models), for a number of months: for tests and panel tools.
    func fastForward(months: Int) {
        for _ in 0..<months where !world.over {
            for f in world.order where world.factions[f].alive { WarlordBrain.play(&world, f) }
            world.endMonth()
        }
        phase = .turn(0); acted = false; told = []; tellWaits = false
        beat += 1
    }

    // MARK: Jev and chat models

    private func consult(_ f: Int) {
        let options = WarlordCommander.options(world, f)
        guard options.count > 1 else {
            WarlordBrain.play(&world, f, attacks: false); acted = true; hold = 0.12
            return
        }
        asking = true
        let who = seats[f], stamp = (seed, world.turns)
        let situation = WarlordCommander.situation(world, f), question = WarlordCommander.question(world.lordName(f))
        Task { @MainActor in
            defer { asking = false }
            do {
                let (index, chance, name) = who.decides ? try await askJev(options, situation, question, via: who.open) : try await askChat(options, situation, question)
                guard (seed, world.turns) == stamp, seats[f] == who, current == f, !acted else { return }
                let before = world.armies.count
                WarlordCommander.execute(options[index].plan, &world, f)
                words[f] = "\(name)（\(world.lordName(f))）：\(options[index].title)" + (chance.map { " · \(Int(($0 * 100).rounded()))%" } ?? "")
                acted = true; hold = world.armies.count > before ? 1.0 : 0.6
                beat += 1
            } catch {
                guard (seed, world.turns) == stamp, current == f, !acted else { return }
                words[f] = "\(who.title)没答上：\(error.localizedDescription.prefix(50))；这个月由电脑代管"
                WarlordBrain.play(&world, f)
                acted = true; hold = 0.3
                beat += 1
            }
        }
    }

    private func askJev(_ options: [WarlordOption], _ situation: String, _ question: String, via: String? = nil) async throws -> (Int, Double?, String) {
        let q = JevClient.Question(id: "q", question: question, howToJudge: WarlordCommander.howToJudge,
                                   options: options.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.words) })
        let reply = try await JevClient.ask(state: [("game", WarlordCommander.rules), ("position_before_move", situation)], [q], via: via)
        guard let answer = reply.answers["q"], let n = Int(answer.choice.dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("\(via ?? "Jev") 的回答读不出来")
        }
        return (n - 1, answer.chances[answer.choice], via ?? "Jev")
    }

    private func askChat(_ options: [WarlordOption], _ situation: String, _ question: String) async throws -> (Int, Double?, String) {
        var chosen: (host: String, model: String)?
        if model.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = model.firstIndex(of: "|") { chosen = (String(model[..<bar]), String(model[model.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(model) { chosen = (entry.host, model); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = """
            \(WarlordCommander.rules)
            The situation: \(situation)
            \(question) \(WarlordCommander.howToJudge)
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

    // MARK: The camera

    func zoom(by factor: CGFloat, at p: CGPoint? = nil) { camera.zoom(by: factor, at: p ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize) }
    func pan(_ dx: CGFloat, _ dy: CGFloat) { camera.pan(dx, dy, viewSize) }
    func city(at p: CGPoint) -> Int? { WarlordScene.hit(p, S: camera.tile(viewSize), origin: camera.origin(viewSize)) }
    /// Bring a city into the middle of the view.
    func look(at c: Int) {
        camera.focus = WarlordMap.at(c)
        camera.settle(viewSize)
    }

    // MARK: What a click means

    func click(_ c: Int?) {
        guard let c else {
            if targeting == nil { selected = nil }
            return
        }
        switch targeting {
        case .march(let from):
            if world.foes(of: from).contains(c) { openDraft(from, c) } else if c != from { say("只能出征相邻的敌城或空城") }
        case .move(let from, let o):
            if cities(from).contains(c) { shipment = WarlordShipment(from: from, to: c, officer: o, troops: 0, gold: 0, grain: 0, stay: true); targeting = nil }
            else if c != from { say("只能移动到相邻的自己的城") }
        case .send(let from, let o):
            if cities(from).contains(c) { shipment = WarlordShipment(from: from, to: c, officer: o, troops: world.cities[from].troops / 2, gold: world.cities[from].gold / 2, grain: world.cities[from].grain / 2, stay: false); targeting = nil }
            else if c != from { say("只能运输到相邻的自己的城") }
        case nil:
            selected = c
        }
        beat += 1
    }

    /// Neighbouring cities of one's own.
    func cities(_ from: Int) -> [Int] { warlordLinks[from].map(\.city).filter { world.cities[$0].owner == world.cities[from].owner } }

    var targets: Set<Int> {
        switch targeting {
        case .march(let from): return Set(world.foes(of: from))
        case .move(let from, _), .send(let from, _): return Set(cities(from))
        case nil: return []
        }
    }

    func cancel() { targeting = nil; draft = nil; shipment = nil }

    /// Can the person give orders in this city now?
    func mayCommand(_ c: Int) -> Bool { myTurn != nil && world.cities[c].owner == myTurn }

    /// The general for a command: the one picked, or the best one free for it.
    func officer(for job: WarlordWork?, in c: Int) -> Int? {
        let idle = world.idle(c)
        if let picked, idle.contains(picked) { return picked }
        switch job {
        case .farm?, .trade?: return idle.max { world.pol($0) < world.pol($1) }
        case .wall?, .draft?, .drill?: return idle.max { world.lead($0) < world.lead($1) }
        case .search?: return idle.max { world.wit($0) < world.wit($1) }
        case nil: return idle.max { WarlordBrain.fighting(world, $0) < WarlordBrain.fighting(world, $1) }
        }
    }

    func work(_ job: WarlordWork, in c: Int) {
        guard mayCommand(c) else { return }
        guard let o = officer(for: job, in: c) else { say("这座城里没有空闲的武将了"); return }
        if let text = world.work(o, job) { say(text) } else {
            let x = world.cities[c]
            say(job == .draft ? "征不了兵：金或人口不够" : x.gold < job.cost ? "金不够：\(job.name)要 \(job.cost) 金" : "\(job.name)已经到顶了")
        }
        picked = nil
        beat += 1
    }

    func beginMarch(from c: Int) {
        guard mayCommand(c) else { return }
        guard !world.idle(c).filter({ world.officers[$0].rest == 0 }).isEmpty else { say("没有能出征的武将（刚打过仗的要休整一个月）"); return }
        guard !world.foes(of: c).isEmpty else { say("\(warlordSites[c].name)不和敌城或空城相邻"); return }
        targeting = .march(c); draft = nil; shipment = nil
        say("点一座红圈里的城：出征目标")
    }

    func openDraft(_ from: Int, _ to: Int) {
        let ready = world.idle(from).filter { world.officers[$0].rest == 0 }
        guard let lead = (picked.flatMap { ready.contains($0) ? $0 : nil }) ?? ready.max(by: { WarlordBrain.fighting(world, $0) < WarlordBrain.fighting(world, $1) }) else { return }
        // Enough for about four chances in five, or most of what the city has.
        let most = world.cities[from].troops * 9 / 10
        let n = world.needed([lead], from: from, to: to, want: 0.8, spare: most) ?? world.cities[from].troops * 3 / 4
        draft = WarlordDraft(from: from, to: to, team: [lead], troops: max(300, min(world.cities[from].troops, n)) / 100 * 100)
        targeting = nil
    }

    func chance(_ d: WarlordDraft) -> Double { world.chance(d.team, troops: d.troops, train: world.cities[d.from].train, from: d.from, to: d.to) }

    func confirmDraft() {
        guard let d = draft, mayCommand(d.from) else { return }
        let rations = d.troops / 10 * (warlordRoad(d.from, d.to)?.months ?? 1)
        if world.cities[d.from].grain < rations { say("粮不够：\(d.troops) 兵行军要 \(rations) 粮"); return }
        if world.march(d.team, from: d.from, to: d.to, troops: d.troops) != nil {
            say("\(d.team.map { world.name($0) }.joined(separator: "、"))率 \(d.troops) 兵出征\(warlordSites[d.to].name)")
            draft = nil
        } else { say("出征不成：检查兵力和武将") }
        beat += 1
    }

    func beginMove(from c: Int, send: Bool) {
        guard mayCommand(c) else { return }
        guard let o = officer(for: nil, in: c) else { say("这座城里没有空闲的武将了"); return }
        guard !cities(c).isEmpty else { say("\(warlordSites[c].name)旁边没有自己的城") ; return }
        targeting = send ? .send(c, o) : .move(c, o); draft = nil
        say(send ? "点一座绿圈里的城：运输去哪里" : "点一座绿圈里的城：\(world.name(o))移动去哪里")
    }

    func confirmShipment() {
        guard let s = shipment, mayCommand(s.from) else { return }
        if world.move(s.officer, to: s.to, troops: s.troops, gold: s.gold, grain: s.grain, stay: s.stay) {
            say(s.stay ? "\(world.name(s.officer))移动到\(warlordSites[s.to].name)" : "运往\(warlordSites[s.to].name)：兵 \(s.troops) 金 \(s.gold) 粮 \(s.grain)")
            shipment = nil
        } else { say("做不到") }
        beat += 1
    }

    func recruit(_ t: Int, in c: Int) {
        guard mayCommand(c) else { return }
        let idle = world.idle(c)
        guard let o = (picked.flatMap { idle.contains($0) ? $0 : nil }) ?? idle.max(by: { world.recruitChance($0, t) < world.recruitChance($1, t) }) else { say("没有空闲的武将去登用"); return }
        let p = world.recruitChance(o, t)
        if let ok = world.recruit(o, t) { say(ok ? "🎉 \(world.name(t))答应了！（\(Int(p * 100))%）" : "\(world.name(t))拒绝了\(world.name(o))（\(Int(p * 100))%）") }
        picked = nil
        beat += 1
    }

    func release(_ t: Int) { guard let f = myTurn, world.officers[t].faction == f else { return }; world.release(t); say("放走了\(world.name(t))"); beat += 1 }
    func execute(_ t: Int) { guard let f = myTurn, world.officers[t].faction == f else { return }; world.execute(t); say("斩了\(world.name(t))"); beat += 1 }

    func ally(with g: Int, from c: Int) {
        guard mayCommand(c), let o = world.idle(c).max(by: { world.allyChance($0, with: g) < world.allyChance($1, with: g) }) else { return }
        guard world.cities[c].gold >= WarlordWorld.allyCost else { say("结盟要备礼 \(WarlordWorld.allyCost) 金"); return }
        if let ok = world.ally(o, with: g) { say(ok ? "🤝 \(world.lordName(g))答应结盟，三年为期" : "\(world.lordName(g))拒绝了结盟") }
        beat += 1
    }
    func breakAlliance(with g: Int) { guard let f = myTurn else { return }; world.breakAlliance(f, g); say("与\(world.lordName(g))断盟"); beat += 1 }
    func sow(_ t: Int, from c: Int) {
        guard mayCommand(c), let o = world.idle(c).max(by: { world.sowChance($0, t) < world.sowChance($1, t) }) else { return }
        if let drop = world.sow(o, t) { say(drop > 0 ? "离间成功：\(world.name(t))忠诚 −\(drop)" : "\(world.name(t))没有上当") }
        beat += 1
    }
    func persuade(_ t: Int, from c: Int) {
        guard mayCommand(c), let o = world.idle(c).max(by: { world.persuadeChance($0, t) < world.persuadeChance($1, t) }) else { return }
        if let ok = world.persuade(o, t) { say(ok ? "🎉 \(world.name(t))被说动了！" : "\(world.name(t))不为所动") }
        beat += 1
    }

    /// The person's turn is over.
    func endTurn() {
        guard myTurn != nil else { return }
        cancel(); showDiplomacy = false
        next()
        if speed == 0 { speed = 1 }
    }

    /// Select the next city of the person's.
    func nextCity() {
        guard let f = mine else { return }
        let mine = world.cities(of: f)
        guard !mine.isEmpty else { return }
        let i = selected.flatMap { mine.firstIndex(of: $0) } ?? -1
        selected = mine[(i + 1) % mine.count]
        look(at: selected!)
    }

    // MARK: For the panel tools

    var report: String {
        let w = world
        var lines = ["三国争霸：\(w.date)（\(w.season)）· 第 \(w.turns + 1) 个月 · \(speed == 0 ? "暂停" : "\(Int(speed))×")" + (w.winner.map { " · \(w.lordName($0))统一天下" } ?? "")]
        switch phase {
        case .turn: if let f = current { lines.append("正在行动：\(w.lordName(f))（\(seats[f].title)）" + (myTurn != nil ? " · 等你下令，按「结束回合」" : "")) }
        case .marching: lines.append("大军行进中")
        case .telling: lines.append("战报：" + told.map { "\(warlordSites[$0.city].name)\($0.won ? "陷落" : "守住")" }.joined(separator: "、") + (tellWaits ? "（等你看完）" : ""))
        }
        let alive = w.factions.indices.filter { w.factions[$0].alive }.sorted { w.held($0) > w.held($1) }
        lines.append("势力 \(alive.count) 家 · 空城 \(w.cities(of: -1).count)")
        for f in alive {
            lines.append("  \(w.lordName(f))（\(seats[f].title)）：\(w.held(f)) 城 · 兵 \(w.troops(of: f)) · 将 \(w.staff(of: f).count) · 金 \(w.gold(of: f)) · 粮 \(w.grain(of: f))"
                         + (w.factions[f].allies.isEmpty ? "" : " · 盟 " + w.factions[f].allies.keys.sorted().map { w.lordName($0) }.joined(separator: "、"))
                         + (words[f].map { " · \($0)" } ?? ""))
        }
        if let s = selected {
            let x = w.cities[s]
            lines.append("选中：\(warlordSites[s].name)（\(w.banner(x.owner))）兵 \(x.troops) 训练 \(x.train) · 金 \(x.gold) 粮 \(x.grain) · 人口 \(x.people) · 农 \(x.farm) 商 \(x.trade) 城防 \(x.wall) 民忠 \(x.loyalty) · 武将 " + w.present(s).map { w.name($0) + (w.officers[$0].done ? "✓" : "") }.joined(separator: "、"))
        }
        let recent = w.chronicle.suffix(6).map { "\($0.year).\($0.month) \($0.text)" }
        if !recent.isEmpty { lines.append("近事：" + recent.joined(separator: "；")) }
        return lines.joined(separator: "\n")
    }
}

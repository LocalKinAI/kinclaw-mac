import AppKit
import SwiftUI

/// Who runs 放逐之城.
enum CitySeat: String, CaseIterable, Identifiable {
    case me, computer, jev, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "大模型"][Self.allCases.firstIndex(of: self)!] }
    /// Does somebody other than the script decide what comes first?
    var commands: Bool { self == .jev || self == .llm }
}

/// 放逐之城, played with the mouse: the town's clock, who is mayor, what is
/// selected and what is being placed, and the orders a click becomes.
@MainActor
final class CityGame: ObservableObject {
    static let shared = CityGame()

    @Published private(set) var beat = 0
    /// Paused until somebody presses 开始 ("默认所有游戏都不要开始").
    @Published var speed = 0.0 { didSet { if speed > 0, loop == nil { start() } } }
    private(set) var world: CityWorld
    private var brain = CityBrain()
    private(set) var seed: UInt64

    @Published var seat: CitySeat = .me { didSet { seated() } }
    /// For a chat model as mayor: "host|model", or "" for the app's own pick.
    @Published var model = "" { didSet { UserDefaults.standard.set(model, forKey: "kinclaw.city.model") } }
    /// The person's town: the computer decides how many work where, unless the person does.
    @Published var autoStaff = true { didSet { UserDefaults.standard.set(autoStaff, forKey: "kinclaw.city.autostaff") } }
    @Published var jevAdvises = false { didSet { advice = nil; lastAdvised = -99 } }
    @Published private(set) var advice: (option: CityOption, chance: Double)?
    /// What the mayor who is not the person last decided, or why a question failed.
    @Published private(set) var note: String?

    /// The camera: zoom and where it looks. The view's size is kept here for the mouse and the keys.
    @Published var camera = GameCamera(map: CGSize(width: CityWorld.width, height: CityWorld.height), focus: CGPoint(x: 32, y: 20))
    var viewSize = CGSize(width: 1200, height: 800)

    @Published var selected: Int?
    @Published var placing: CityKind? { didSet { if placing != nil { tool = nil; selected = nil } } }
    @Published var tool: CityTool? { didSet { if tool != nil { placing = nil; selected = nil } } }
    var hover: CityTile?
    var drag: (CityTile, CityTile)?

    @Published private(set) var message: String?
    private var said = Date.distantPast
    private var loop: Task<Void, Never>?
    private var frames = 0
    private var asking = false, lastAsked = -99.0
    private var advising = false, lastAdvised = -99.0
    private var told = Set<String>()

    init() {
        seed = UInt64.random(in: 1...9999)
        world = CityWorld(seed: seed)
        lookAtHall()
        if let kept = UserDefaults.standard.string(forKey: "kinclaw.city.seat").flatMap(CitySeat.init(rawValue:)) { seat = kept }
        model = UserDefaults.standard.string(forKey: "kinclaw.city.model") ?? ""
        if UserDefaults.standard.object(forKey: "kinclaw.city.autostaff") != nil { autoStaff = UserDefaults.standard.bool(forKey: "kinclaw.city.autostaff") }
    }

    var me: Bool { seat == .me }

    private func seated() {
        UserDefaults.standard.set(seat.rawValue, forKey: "kinclaw.city.seat")
        brain.focus = nil; note = nil; advice = nil; lastAsked = -99
        if !me { placing = nil; tool = nil }
    }

    func say(_ text: String) { message = text; said = Date() }
    var saying: String? { Date().timeIntervalSince(said) < 4 ? message : nil }

    // MARK: The clock

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                if speed > 0, !world.over {
                    let dt = 1.0 / 30
                    for _ in 0..<max(1, Int(speed)) {
                        if !me { brain.think(&world, dt) } else if autoStaff { brain.staffOnly(&world, dt) }
                        world.step(dt)
                    }
                    watch()
                    if seat.commands, !asking, world.time - lastAsked >= (seat == .jev ? 10 : 20) { consult() }
                    if me, jevAdvises, !advising, world.time - lastAdvised >= 12 { advise() }
                }
                frames += 1
                if frames % 6 == 0 { beat += 1 }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    func restart() {
        seed = UInt64.random(in: 1...9999)
        world = CityWorld(seed: seed)
        brain = CityBrain()
        selected = nil; placing = nil; tool = nil; message = nil; note = nil; advice = nil
        lastAsked = -99; lastAdvised = -99; told = []
        speed = 0; beat += 1
        lookAtHall()
    }

    func lookAtHall() {
        if let hall = world.hall { let c = world.centre(hall); camera.focus = CGPoint(x: c.x, y: c.y) }
        camera.zoom = 2
    }

    func zoom(by factor: CGFloat, at p: CGPoint? = nil) { camera.zoom(by: factor, at: p ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize) }
    func pan(_ dx: CGFloat, _ dy: CGFloat) { camera.pan(dx, dy, viewSize) }
    /// The tile under a point of the map view.
    func tile(at p: CGPoint) -> CityTile { let t = camera.at(p, viewSize); return CityTile(x: Int(floor(t.x)), y: Int(floor(t.y))) }

    /// How the town stands, in a few lines — for city_status.
    var report: String {
        let w = world, l = CityLedger(w)
        var lines = ["放逐之城：第 \(w.year) 年 \(CityWorld.monthNames[w.monthOfYear]) · 市长 \(seat.title) · \(speed == 0 ? "暂停" : "\(Int(speed))×")" + (w.over ? " · 城镇消亡了" : "")]
        lines.append("\(l.people) 人（童 \(l.children) · 老 \(l.retired) · 无家 \(l.homeless)）· 房 \(l.houses) 座，住得下 \(l.room) 人 · 在盖 \(l.sites) 处")
        lines.append("食物 \(Int(l.food)) · 木 \(Int(l.logs)) · 石 \(Int(l.stone)) · 铁 \(Int(l.iron)) · 柴火 \(Int(l.firewood)) · 工具 \(Int(l.tools))")
        lines.append("这一年产粮 \(Int(w.madeLastYear(.food)))、吃掉 \(Int(w.usedLastYear(.food))) · 出生 \(w.births) · 新来 \(w.arrivals) · 饿死 \(w.deaths["hunger"] ?? 0) · 冻死 \(w.deaths["cold"] ?? 0) · 老死 \(w.deaths["age"] ?? 0)")
        let kinds = CityKind.allCases.compactMap { k -> String? in
            let n = w.buildings.filter { $0.kind == k && $0.done }.count
            return n > 0 ? "\(CityWorld.kindNames[k.rawValue]) \(n)" : nil
        }
        lines.append("建筑：" + kinds.joined(separator: " · "))
        if let note { lines.append(note) }
        return lines.joined(separator: "\n")
    }

    // MARK: What the town says of its own accord

    private func watch() {
        let l = CityLedger(world)
        for e in world.events where world.time - e.time < 0.1 {
            switch e.kind {
            case .newYear(let y): say("第 \(y) 年开春")
            case .arrived(let n): say("新来了 \(n) 个人")
            case .died(.hunger): once("饿\(world.monthNumber)", "有人饿死了——粮食不够")
            case .died(.cold): once("冻\(world.monthNumber)", "有人冻死了——" + (l.homeless > 0 ? "有人没房子" : "柴火不够"))
            default: break
            }
        }
        if l.monthsToWinter == 1, l.firewood < l.firewoodNeed { once("柴\(world.year)", "⚠️ 下个月入冬，柴火只有 \(Int(l.firewood))，要 \(Int(l.firewoodNeed))") }
        if l.monthsToWinter == 2, l.homeless > 0 { once("房\(world.year)", "⚠️ 还有两个月入冬，\(l.homeless) 人没房子") }
        if l.people > 0, l.monthsOfFood < 3, world.year > 1 { once("粮\(world.year)-\(world.monthOfYear / 4)", "⚠️ 粮食只够 \(Int(l.monthsOfFood)) 个月了") }
        for goal in [50, 100, 150, 200] where l.people >= goal { once("人\(goal)", "🎉 城里有 \(goal) 人了") }
        if let id = selected, world.building(id) == nil { selected = nil }
    }

    private func once(_ key: String, _ text: String) {
        guard !told.contains(key) else { return }
        told.insert(key); say(text)
    }

    // MARK: Asking Jev or a chat model

    /// The mayor's question: which need first. The answer is carried out by the computer's hands.
    private func consult() {
        let options = CityCommander.needs(world)
        asking = true; lastAsked = world.time
        let situation = CityCommander.situation(world), who = seat
        Task { @MainActor in
            defer { asking = false }
            do {
                let (index, chance, name) = who == .jev
                    ? try await askJev(options, situation, CityCommander.question, CityCommander.howToJudge)
                    : try await askChat(options, situation, CityCommander.question, CityCommander.howToJudge)
                guard seat == who, !world.over else { return }
                CityCommander.execute(options[index].plan, &world, &brain)
                note = "\(name)（市长）：先顾\(options[index].title)" + (chance.map { " · \(Int($0 * 100))%" } ?? "")
            } catch {
                note = "\(who.title)没答上：\(error.localizedDescription.prefix(60))"
            }
        }
    }

    /// Jev's advice for the person: what to build next and where, with a 照做 button.
    private func advise() {
        let options = CityCommander.advice(world)
        guard options.count > 1 else { return }
        advising = true; lastAdvised = world.time
        let situation = CityCommander.situation(world)
        Task { @MainActor in
            defer { advising = false }
            if let (index, chance, _) = try? await askJev(options, situation, CityCommander.adviceQuestion, CityCommander.adviceJudge), me {
                advice = (options[index], chance ?? 0)
            }
        }
    }

    func follow() {
        guard let advice, me else { return }
        CityCommander.execute(advice.option.plan, &world, &brain)
        if case .build(let kind, _) = advice.option.plan, !autoStaff, let b = world.buildings.last, b.kind == kind { world.buildings[world.buildings.count - 1].wanted = CityWorld.slots(kind) }
        say("照做了：\(advice.option.title)")
        self.advice = nil; lastAdvised = world.time - 6
    }

    private func askJev(_ options: [CityOption], _ situation: String, _ question: String, _ judge: String) async throws -> (Int, Double?, String) {
        let q = JevClient.Question(id: "order", question: question, howToJudge: judge,
                                   options: options.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.words) })
        let reply = try await JevClient.ask(state: [("game", CityCommander.rules), ("situation", situation)], [q])
        guard let answer = reply.answers["order"], let n = Int(answer.choice.dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("Jev 的回答读不出来")
        }
        return (n - 1, answer.chances[answer.choice], "Jev")
    }

    private func askChat(_ options: [CityOption], _ situation: String, _ question: String, _ judge: String) async throws -> (Int, Double?, String) {
        var chosen: (host: String, model: String)?
        if model.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = model.firstIndex(of: "|") { chosen = (String(model[..<bar]), String(model[model.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(model) { chosen = (entry.host, model); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = """
            \(CityCommander.rules)
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

    func click(_ t: CityTile) {
        guard CityWorld.inside(t) else { return }
        if let kind = placing { put(kind, at: t); return }
        if tool == .bulldoze {
            guard me else { return }
            if let id = world.occupant[CityWorld.index(t)], let b = world.building(id) {
                if b.kind == .townHall { say("市政厅不能拆"); return }
                world.remove(id); say("拆了\(CityWorld.kindNames[b.kind.rawValue])，材料回来一半")
            } else if world.road[CityWorld.index(t)] { world.unlay(road: t) }
            beat += 1
            return
        }
        if tool == .road { return }
        selected = world.occupant[CityWorld.index(t)]
    }

    func put(_ kind: CityKind, at t: CityTile) {
        guard me else { placing = nil; return }
        let n = CityWorld.size(kind), origin = CityTile(x: t.x - (n - 1) / 2, y: t.y - (n - 1) / 2)
        guard world.fits(kind, at: origin) else {
            say(kind == .quarry ? "采石场要挨着石头" : kind == .mine ? "铁矿要挨着矿石" : kind == .fishery ? "渔屋要挨着水" : "这里放不下")
            return
        }
        guard let id = world.place(kind, at: origin) else { return }
        if !autoStaff, let i = world.buildingIndex(id) { world.buildings[i].wanted = CityWorld.slots(kind) }
        let cost = CityWorld.cost(kind)
        if world.stored(.logs) < cost[1] || world.stored(.stone) < cost[2] { say("先放下了，等材料送到才能盖") }
        if !NSEvent.modifierFlags.contains(.shift) { placing = nil }
        beat += 1
    }

    /// A road dragged from one tile to another.
    func road(_ a: CityTile, _ b: CityTile) {
        guard me else { return }
        var laid = 0
        for t in CityScene.line(a, b) where world.lay(road: t) { laid += 1 }
        if laid == 0 { say("路只能铺在空草地上") }
        beat += 1
    }

    /// More or fewer workers at the selected building — the person's own choice from now on.
    func workers(_ delta: Int) {
        guard me, let id = selected, let i = world.buildingIndex(id) else { return }
        if autoStaff { autoStaff = false; say("改成你自己安排工人了") }
        let kind = world.buildings[i].kind
        world.buildings[i].wanted = max(0, min(CityWorld.slots(kind), world.buildings[i].wanted + delta))
        beat += 1
    }

    func demolish() {
        guard me, let id = selected, let b = world.building(id), b.kind != .townHall else { return }
        world.remove(id); selected = nil
        say("拆了\(CityWorld.kindNames[b.kind.rawValue])")
    }
}

// MARK: - The view

struct CityView: View {
    @ObservedObject private var game = CityGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    static let icons = ["🍞", "🪵", "🪨", "⚙️", "🔥", "🔨"]
    static func price(_ kind: CityKind) -> String {
        let c = CityWorld.cost(kind)
        let parts = [c[1] > 0 ? "\(Int(c[1]))木" : nil, c[2] > 0 ? "\(Int(c[2]))石" : nil].compactMap { $0 }
        return parts.isEmpty ? "免费" : parts.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            top
            GeometryReader { space in
                let size = space.size
                let S = game.camera.tile(size), origin = game.camera.origin(size), view = game.camera.visible(size)
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: game.speed == 0 && game.placing == nil && game.tool == nil)) { timeline in
                        let scene = CityScene(world: game.world, selected: game.selected, placing: game.placing, tool: game.tool,
                                              hover: game.hover, drag: game.drag, now: timeline.date.timeIntervalSinceReferenceDate)
                        Canvas(rendersAsynchronously: true) { context, canvas in
                            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Color(red: 0.12, green: 0.2, blue: 0.13)))
                            context.translateBy(x: -origin.x * S, y: -origin.y * S)
                            scene.paint(&context, tile: S, view: view)
                        }
                    }
                    CityMouse().frame(width: size.width, height: size.height)
                    if game.speed == 0, !game.world.over, game.placing == nil, game.tool == nil {
                        Button { game.speed = 1 } label: {
                            Label(game.world.time == 0 ? "开始" : "继续", systemImage: "play.fill")
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                                .padding(.horizontal, 24).padding(.vertical, 11)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                        .frame(width: size.width, height: size.height)
                    }
                    if let text = game.saying {
                        Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .frame(width: size.width).padding(.top, 10).allowsHitTesting(false)
                    }
                    zoomButtons.frame(width: size.width, height: size.height, alignment: .bottomTrailing).padding(-10)
                    if game.world.over {
                        VStack(spacing: 10) {
                            Text("城镇消亡了").font(.system(size: 40, weight: .heavy, design: .rounded))
                            Text("撑到第 \(game.world.year) 年 · 出生 \(game.world.births) · 新来 \(game.world.arrivals) · 饿死 \(game.world.deaths["hunger"] ?? 0) · 冻死 \(game.world.deaths["cold"] ?? 0) · 老死 \(game.world.deaths["age"] ?? 0)")
                                .font(.system(size: 14, weight: .semibold))
                            Button("再来一局") { game.restart() }.controlSize(.large)
                        }
                        .foregroundColor(.white).padding(30)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.7)))
                        .frame(width: size.width, height: size.height)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear { game.viewSize = size }
                .onChange(of: size) { _, new in game.viewSize = new }
            }
            .padding(.horizontal, 8)
            bottom
        }
        .onAppear { game.start(); CityKeys.install() }
        .onDisappear { game.stop(); CityKeys.remove() }
        .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }

    private var zoomButtons: some View {
        VStack(spacing: 6) {
            Button { game.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 28, height: 28) }
            Button { game.zoom(by: 0.8) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 28, height: 28) }
            Button { game.lookAtHall() } label: { Image(systemName: "house").frame(width: 28, height: 28) }
        }
        .buttonStyle(.plain).foregroundColor(.white)
        .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
        .padding(20)
    }

    // MARK: Along the top: the calendar, the people, the stores, the mayor, the speed

    private var top: some View {
        _ = game.beat
        let w = game.world, l = CityLedger(w)
        let season = ["🌱", "☀️", "🍂", "❄️"][w.season]
        return HStack(spacing: 12) {
            Text("\(season) 第 \(w.year) 年 · \(CityWorld.monthNames[w.monthOfYear])").font(.system(size: 13, weight: .bold)).monospacedDigit()
            Text("👥 \(l.people)（童 \(l.children) · 老 \(l.retired)）").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            if l.homeless > 0 { Text("无家 \(l.homeless)").font(.system(size: 12, weight: .semibold)).foregroundColor(.orange) }
            ForEach(0..<6, id: \.self) { k in
                let amount = k == 0 ? l.food : k == 4 ? l.firewood : w.stored(CityGood(rawValue: k)!)
                Text("\(Self.icons[k]) \(Int(amount))").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .help(CityWorld.goodNames[k] + (k == 0 || k == 4 ? "（仓库加家里）" : ""))
            }
            if let warning = warning(l) { Text(warning).font(.system(size: 12, weight: .semibold)).foregroundColor(.orange).lineLimit(1) }
            Spacer()
            HStack(spacing: 4) {
                Text("市长").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Picker("", selection: $game.seat) { ForEach(CitySeat.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().controlSize(.small).fixedSize()
                if game.seat == .llm {
                    Picker("", selection: $game.model) {
                        Text("自动").tag("")
                        ForEach(chatModels, id: \.host) { entry in
                            Section(BoxServices.place(of: entry.host)) {
                                ForEach(entry.models, id: \.self) { name in Text(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")).tag("\(entry.host)|\(name)") }
                            }
                        }
                    }
                    .labelsHidden().controlSize(.small).fixedSize()
                }
            }
            if game.me {
                Toggle("自动安排工人", isOn: $game.autoStaff).toggleStyle(.checkbox).controlSize(.small)
                Toggle("Jev 参谋", isOn: $game.jevAdvises).toggleStyle(.checkbox).controlSize(.small)
            }
            Picker("", selection: $game.speed) {
                Text("暂停").tag(0.0); Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0); Text("8×").tag(8.0)
            }
            .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            Button("重新开始") { game.restart() }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func warning(_ l: CityLedger) -> String? {
        if l.people > 0, l.monthsOfFood < 4 { return "粮食只够 \(Int(l.monthsOfFood)) 个月" }
        if l.monthsToWinter <= 3, l.firewood < l.firewoodNeed { return "柴火不够过冬" }
        if l.homeless > 0, l.monthsToWinter <= 4 { return "入冬前要给 \(l.homeless) 人盖房" }
        if l.workers >= 8, l.tools < 1 { return "没工具了：干活慢四成" }
        return nil
    }

    // MARK: Along the bottom: what is selected, what can be built, what the mayor said

    private var bottom: some View {
        _ = game.beat
        return HStack(alignment: .center, spacing: 12) {
            info.frame(width: 300, alignment: .leading)
            Divider().frame(height: 50)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    toolButton("道路", "拖动铺路", on: game.tool == .road) { game.tool = game.tool == .road ? nil : .road }
                    toolButton("拆除", "点建筑或路", on: game.tool == .bulldoze) { game.tool = game.tool == .bulldoze ? nil : .bulldoze }
                    ForEach(CityKind.allCases.filter { $0 != .townHall }, id: \.self) { kind in
                        toolButton(CityWorld.kindNames[kind.rawValue], Self.price(kind), on: game.placing == kind) { game.placing = game.placing == kind ? nil : kind }
                    }
                }
            }
            if game.jevAdvises || game.seat.commands {
                Divider().frame(height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    if let advice = game.advice {
                        HStack(spacing: 6) {
                            Text("Jev 建议：\(advice.option.title)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\(Int(advice.chance * 100))%").font(.system(size: 10)).foregroundColor(.secondary)
                            Button("照做") { game.follow() }.controlSize(.small)
                        }
                    } else if game.jevAdvises, game.me { Text("Jev 在想…").font(.system(size: 11)).foregroundColor(.secondary) }
                    if let note = game.note { Text(note).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2) }
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(height: 70)
    }

    @ViewBuilder private var info: some View {
        let w = game.world
        if let id = game.selected, let b = w.building(id) {
            let name = CityWorld.kindNames[b.kind.rawValue]
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 13, weight: .bold))
                    if b.kind != .townHall, game.me { Button("拆") { game.demolish() }.controlSize(.mini) }
                }
                Text(detail(b, w)).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                if b.done, CityWorld.slots(b.kind) > 0 {
                    HStack(spacing: 6) {
                        Text("工人 \(w.workers(b.id))/\(b.wanted)（最多 \(CityWorld.slots(b.kind))）").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        if game.me {
                            Button("−") { game.workers(-1) }.controlSize(.mini)
                            Button("+") { game.workers(1) }.controlSize(.mini)
                        }
                    }
                }
            }
        } else if !game.me {
            VStack(alignment: .leading, spacing: 3) {
                Text("观战：\(game.seat.title)当市长").font(.system(size: 12, weight: .semibold))
                Text("右上角换成「我」就能自己当市长").font(.system(size: 11)).foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("点下面的建筑，再点地图放下；按住 ⇧ 连续放").font(.system(size: 12, weight: .semibold))
                Text("拖动或双指滑动看别处，捏合或 ⌘ 滚轮缩放；右键或 Esc 取消，空格暂停，1–4 调速").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private func detail(_ b: CityBuilding, _ w: CityWorld) -> String {
        if !b.done {
            let c = CityWorld.cost(b.kind)
            var parts: [String] = []
            if c[1] > 0 { parts.append("木 \(Int(b.delivered[1]))/\(Int(c[1]))") }
            if c[2] > 0 { parts.append("石 \(Int(b.delivered[2]))/\(Int(c[2]))") }
            return "在盖：" + (parts.isEmpty ? "" : "材料 " + parts.joined(separator: " · ") + " · ") + "进度 \(Int(b.progress * 100))%"
        }
        switch b.kind {
        case .townHall, .storage:
            let held = b.stock.reduce(0, +)
            return "存着 \(Int(held))/\(Int(CityWorld.capacity(b.kind)))：" + (0..<6).filter { b.stock[$0] >= 1 }.map { "\(CityWorld.goodNames[$0]) \(Int(b.stock[$0]))" }.joined(separator: " · ")
        case .house:
            return "住 \(w.residents(b.id)) 人 · 家里存 食物 \(Int(b.stock[0])) · 柴火 \(Int(b.stock[4]))"
        case .field:
            return "种了 \(Int(b.planted * 100))% · 长了 \(Int(b.grown * 100))% · 收了 \(Int(b.harvested * 100))% · 土 \(Int(w.fieldFertility(b) / 1.3 * 100))% · 今年收 \(Int(b.output))"
        case .quarry, .mine:
            return "还能挖 \(Int(b.reserve)) · 今年 \(Int(b.output)) · 去年 \(Int(b.lastOutput))"
        case .woodcutter:
            return "木头 \(Int(b.stock[1])) → 柴火 · 今年劈了 \(Int(b.output)) · 去年 \(Int(b.lastOutput))"
        case .blacksmith:
            return "铁 \(Int(b.stock[3])) · 木 \(Int(b.stock[1])) · 今年打了 \(Int(b.output)) 件工具"
        default:
            return "今年 \(Int(b.output)) · 去年 \(Int(b.lastOutput))" + (b.kind == .forester ? " 木头" : " 食物")
        }
    }

    private func toolButton(_ title: String, _ sub: String, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(sub).font(.system(size: 9)).foregroundColor(.secondary)
            }
            .frame(minWidth: 58).padding(.vertical, 4).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .disabled(!game.me)
        .opacity(game.me ? 1 : 0.45)
    }
}

// MARK: - The mouse: clicks, drags for roads, where it hovers

struct CityMouse: NSViewRepresentable {
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {}

    final class Catcher: NSView {
        private var start: CityTile?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
        @MainActor private func tileAt(_ e: NSEvent) -> CityTile { CityGame.shared.tile(at: point(e)) }

        override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { CityGame.shared.hover = tileAt(event) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { CityGame.shared.hover = nil } }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
            MainActor.assumeIsolated {
                let game = CityGame.shared
                start = tileAt(event)
                if game.tool == .road, let start { game.drag = (start, start) }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = CityGame.shared
                let t = tileAt(event)
                game.hover = t
                if game.tool == .road, let start { game.drag = (start, t) }
                else if game.placing == nil { game.pan(event.deltaX, event.deltaY) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = CityGame.shared
                let t = tileAt(event)
                if game.tool == .road, let start { game.road(start, t); game.drag = nil }
                else if start == t || game.placing != nil || game.tool != nil { game.click(t) }
            }
            start = nil
        }
        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = CityGame.shared
                game.placing = nil; game.tool = nil; game.drag = nil; game.selected = nil
            }
        }
        override func scrollWheel(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = CityGame.shared
                if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                    game.zoom(by: pow(1.02, event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 3)), at: point(event))
                } else {
                    game.pan(event.scrollingDeltaX, event.scrollingDeltaY)
                }
            }
        }
        override func magnify(with event: NSEvent) {
            MainActor.assumeIsolated { CityGame.shared.zoom(by: 1 + event.magnification, at: point(event)) }
        }
    }
}

/// The keyboard while the town is showing: Esc lets go, space pauses, 1–4 set the speed, arrows move, = and - zoom, R roads, X demolishes.
@MainActor
enum CityKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let game = CityGame.shared
            switch event.keyCode {
            case 53: game.placing = nil; game.tool = nil; game.selected = nil; game.drag = nil; return nil
            case 49: game.speed = game.speed == 0 ? 1 : 0; return nil
            case 15: if game.me { game.tool = game.tool == .road ? nil : .road }; return nil
            case 7: if game.me { game.tool = game.tool == .bulldoze ? nil : .bulldoze }; return nil
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

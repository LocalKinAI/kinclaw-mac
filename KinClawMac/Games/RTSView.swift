import AppKit
import SwiftUI

/// Who sits on a side of 帝国时代.
enum RTSSeat: String, CaseIterable, Identifiable {
    case me, computer, jev, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "大模型"][Self.allCases.firstIndex(of: self)!] }
    /// Does somebody other than the script decide this side's big moves?
    var commands: Bool { self == .jev || self == .llm }
}

/// 帝国时代, played with the mouse: the game's clock, who sits on each side,
/// what is selected, what is being placed, and the commands a click becomes.
@MainActor
final class RTSGame: ObservableObject {
    static let shared = RTSGame()

    /// Bumped a few times a second, for the panels; the map redraws on its own clock.
    @Published private(set) var beat = 0
    /// Paused until somebody presses 开始: a game that was already playing
    /// when its tab came up was a game nobody had started ("默认所有游戏都不要开始").
    @Published var speed = 0.0 { didSet { if speed > 0, loop == nil { start() } } }
    private(set) var world = RTSWorld(seed: 7)
    private var brains = [RTSBrain(owner: 0), RTSBrain(owner: 1)]
    private(set) var seed: UInt64 = 7

    /// Who plays Blue and Red: a person, the script, Jev, a chat model. At most one person.
    @Published var seats: [RTSSeat] = [.me, .computer] { didSet { seated(was: oldValue) } }
    /// For a chat-model seat: "host|model", or "" for the app's own pick.
    @Published var models: [String] = ["", ""] { didSet { UserDefaults.standard.set(models, forKey: "kinclaw.rts.models") } }
    /// The side the person plays; nil when they are watching.
    var me: Int? { seats.firstIndex(of: .me) }

    @Published var selected: Set<Int> = []
    @Published var building: Int?
    @Published var placing: RTSBuildingKind?
    var hover: RTSTile?
    /// The box being dragged, in tiles.
    var box: (CGPoint, CGPoint)?
    /// The camera: zoom and where it looks, and the size of the view it looks through.
    @Published var camera = GameCamera(map: CGSize(width: RTSWorld.width, height: RTSWorld.height), focus: CGPoint(x: 24, y: 15), zoom: 1.6)
    var viewSize = CGSize(width: 1200, height: 800)

    func zoom(by factor: CGFloat, at p: CGPoint? = nil) { camera.zoom(by: factor, at: p ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize) }
    func pan(_ dx: CGFloat, _ dy: CGFloat) { camera.pan(dx, dy, viewSize) }
    /// A point of the view in tiles, and the tile it falls on.
    func spot(at p: CGPoint) -> CGPoint { camera.at(p, viewSize) }
    func tile(at p: CGPoint) -> RTSTile { let t = spot(at: p); return RTSTile(x: Int(floor(t.x)), y: Int(floor(t.y))) }
    /// Look at the person's town centre — or, watching, the middle of the map.
    func lookHome() {
        if let side = me, let tc = world.buildings.first(where: { $0.owner == side && $0.kind == .townCenter }) { camera.focus = CGPoint(x: Double(tc.x) + 1.5, y: Double(tc.y) + 1.5); camera.zoom = 1.8 }
        else { camera.focus = CGPoint(x: 24, y: 15); camera.zoom = 1 }
    }
    @Published private(set) var message: String?
    private var said = Date.distantPast
    private var loop: Task<Void, Never>?
    private var frames = 0
    private var warned = 0.0

    /// Jev's advice for the person's side.
    @Published var jevAdvises = false { didSet { advice = nil; lastAdvised = -99 } }
    @Published private(set) var advice: (option: RTSOption, chance: Double)?
    /// What each side that is not the script last decided, and why a question failed.
    @Published private(set) var notes: [String?] = [nil, nil]
    private var asking = [false, false], lastAsked = [-99.0, -99.0]
    private var advising = false, lastAdvised = -99.0

    init() {
        if let kept = UserDefaults.standard.stringArray(forKey: "kinclaw.rts.seats")?.compactMap(RTSSeat.init(rawValue:)), kept.count == 2 { seats = kept }
        if let kept = UserDefaults.standard.stringArray(forKey: "kinclaw.rts.models"), kept.count == 2 { models = kept }
        for s in 0..<2 { brains[s].commanded = seats[s].commands }
    }

    /// A seat changed: one person at most — the other side falls to the computer — and each brain told how much to decide.
    private func seated(was: [RTSSeat]) {
        if seats[0] == .me, seats[1] == .me {
            let changed = was[0] != .me ? 0 : 1
            seats[1 - changed] = .computer
            return
        }
        for s in 0..<2 { brains[s].commanded = seats[s].commands }
        if seats != was { selected = []; building = nil; placing = nil; notes = [nil, nil]; lastAsked = [-99, -99] }
        UserDefaults.standard.set(seats.map(\.rawValue), forKey: "kinclaw.rts.seats")
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                if speed > 0, world.winner == nil {
                    let dt = 1.0 / 30
                    for _ in 0..<max(1, Int(speed)) {
                        for s in 0..<2 { if seats[s] == .me { brains[s].fulfil(&world) } else { brains[s].think(&world, dt) } }
                        world.step(dt)
                    }
                    watch()
                    for s in 0..<2 where seats[s].commands && !asking[s] && world.time - lastAsked[s] >= (seats[s] == .jev ? 5 : 10) { consult(s) }
                    if jevAdvises, let me, !advising, world.time - lastAdvised >= 8 { advise(me) }
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
        world = RTSWorld(seed: seed)
        brains = [RTSBrain(owner: 0), RTSBrain(owner: 1)]
        for s in 0..<2 { brains[s].commanded = seats[s].commands }
        selected = []; building = nil; placing = nil; message = nil
        advice = nil; notes = [nil, nil]; lastAsked = [-99, -99]; lastAdvised = -99
        speed = 0; beat += 1                      // laid out, waiting for 开始
        lookHome()
    }

    func say(_ text: String) { message = text; said = Date() }
    var saying: String? { Date().timeIntervalSince(said) < 4 ? message : nil }

    // MARK: Asking Jev or a chat model

    /// One question: what side `s` should do next. The answer is carried out by that side's hands.
    private func consult(_ s: Int) {
        let options = RTSCommander.postures(world, s, current: brains[s].posture)
        guard options.count > 1 else { return }
        asking[s] = true; lastAsked[s] = world.time
        let situation = RTSCommander.situation(world, s), seat = seats[s]
        Task { @MainActor in
            defer { asking[s] = false }
            do {
                let (index, chance, who) = seat == .jev ? try await askJev(options, situation, strategy: true) : try await askChat(options, situation, model: models[s])
                guard seats[s] == seat, world.winner == nil else { return }
                RTSCommander.execute(options[index].plan, &world, s, &brains[s])
                notes[s] = "\(who)（\(RTSWorld.names[s])）：\(options[index].title)" + (chance.map { " · \(Int($0 * 100))%" } ?? "")
            } catch {
                notes[s] = "\(seat.title)（\(RTSWorld.names[s])）没答上：\(error.localizedDescription.prefix(60))"
            }
        }
    }

    /// Jev's advice for the person, shown with a 照做 button.
    private func advise(_ s: Int) {
        let options = RTSCommander.options(world, s, goal: brains[s].goal)
        guard options.count > 1 else { return }
        advising = true; lastAdvised = world.time
        let situation = RTSCommander.situation(world, s)
        Task { @MainActor in
            defer { advising = false }
            if let (index, chance, _) = try? await askJev(options, situation), me == s { advice = (options[index], chance ?? 0) }
        }
    }

    private func askJev(_ options: [RTSOption], _ situation: String, strategy: Bool = false) async throws -> (Int, Double?, String) {
        let question = JevClient.Question(id: "order", question: strategy ? RTSCommander.postureQuestion : RTSCommander.question,
                                          howToJudge: strategy ? RTSCommander.postureJudge : RTSCommander.howToJudge,
                                          options: options.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.words) })
        let reply = try await JevClient.ask(state: [("game", RTSCommander.rules), ("situation", situation)], [question])
        guard let answer = reply.answers["order"], let n = Int(answer.choice.dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("Jev 的回答读不出来")
        }
        return (n - 1, answer.chances[answer.choice], "Jev")
    }

    /// The same question to a chat model on an Ollama, told to answer with the option's key.
    private func askChat(_ options: [RTSOption], _ situation: String, model named: String) async throws -> (Int, Double?, String) {
        var chosen: (host: String, model: String)?
        if named.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = named.firstIndex(of: "|") { chosen = (String(named[..<bar]), String(named[named.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(named) { chosen = (entry.host, named); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = """
            \(RTSCommander.rules)
            The situation: \(situation)
            \(RTSCommander.postureQuestion) \(RTSCommander.postureJudge)
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

    /// Do what Jev advised.
    func follow() {
        guard let advice, let me else { return }
        RTSCommander.execute(advice.option.plan, &world, me, &brains[me])
        say("照做了：\(advice.option.title)" + (brains[me].goal != nil ? "，钱够了就自动盖" : ""))
        self.advice = nil; lastAdvised = world.time - 5
    }

    // MARK: What the game says of its own accord

    private func watch() {
        let side = me ?? -1
        if side >= 0, world.events.contains(where: { $0.owner == side && $0.kind == .attacked && world.time - $0.time < 0.2 }), world.time - warned > 20 {
            warned = world.time; say("⚔️ 你的建筑正在被攻击！")
        }
        for e in world.events where world.time - e.time < 0.1 {
            if case .age(let n) = e.kind, side < 0 || e.owner == side { say("🎉 \(side < 0 ? RTSWorld.names[e.owner] : "")进入了\(RTSWorld.ageNames[n])") }
        }
        if side >= 0, let done = world.events.first(where: { if case .finished = $0.kind, $0.owner == side, world.time - $0.time < 0.05 { return true }; return false }),
           case .finished(let kind) = done.kind { say("\(RTSView.names[kind.rawValue])盖好了") }
        selected = selected.filter { id in world.units.contains { $0.id == id } }
        if let b = building, world.building(b) == nil { building = nil }
    }

    // MARK: What a click means

    /// A left click on tile `t`, at `spot` in tiles.
    func click(_ t: RTSTile, at spot: CGPoint, adding: Bool) {
        if let kind = placing { put(kind, at: t); return }
        let px = Double(spot.x), py = Double(spot.y)
        if let unit = world.units.filter({ hypot($0.x - px, $0.y - py) < 0.7 }).min(by: { hypot($0.x - px, $0.y - py) < hypot($1.x - px, $1.y - py) }) {
            if unit.owner == me {
                if adding { if selected.contains(unit.id) { selected.remove(unit.id) } else { selected.insert(unit.id) } }
                else { selected = [unit.id] }
                building = nil
            } else { selected = []; building = nil; say("那是\(RTSWorld.names[unit.owner])的\(RTSView.unitNames[unit.kind.rawValue])") }
            return
        }
        if RTSWorld.inside(t), let id = world.occupant[RTSWorld.index(t)], let b = world.building(id) {
            if b.owner == me { building = id; selected = [] } else { building = nil; selected = []; say("\(RTSWorld.names[b.owner])的\(RTSView.names[b.kind.rawValue])") }
            return
        }
        if !adding { selected = []; building = nil }
    }

    /// Everybody of the person's inside a box, in tiles — the soldiers only, if there are any.
    func select(from a: CGPoint, to b: CGPoint) {
        guard let me else { return }
        let x0 = Double(min(a.x, b.x)), x1 = Double(max(a.x, b.x)), y0 = Double(min(a.y, b.y)), y1 = Double(max(a.y, b.y))
        let inside = world.units.filter { $0.owner == me && $0.x >= x0 && $0.x <= x1 && $0.y >= y0 && $0.y <= y1 }
        let soldiers = inside.filter { $0.kind != .villager }
        selected = Set((soldiers.isEmpty ? inside : soldiers).map(\.id))
        building = nil
    }

    /// Right click: tell what is selected to go there and do what the place calls for.
    func order(_ t: RTSTile) {
        guard RTSWorld.inside(t), let me else { return }
        if let id = building {
            if let i = world.buildingIndex(id) { world.buildings[i].rally = t; say("集结点设好了") }
            return
        }
        guard !selected.isEmpty else { return }
        let px = Double(t.x) + 0.5, py = Double(t.y) + 0.5
        let foe = world.units.filter { $0.owner != me && hypot($0.x - px, $0.y - py) < 1 }.first
        let place = world.occupant[RTSWorld.index(t)].flatMap { world.building($0) }
        let terrain = world.terrain[RTSWorld.index(t)]
        for id in selected {
            guard let u = world.units.first(where: { $0.id == id }) else { continue }
            if let foe { world.command(id, .attack(foe.id)); continue }
            if let place, place.owner != me { world.command(id, .raze(place.id)); continue }
            if u.kind == .villager {
                if let place, place.owner == me {
                    if !place.done { world.command(id, .build(place.id)); continue }
                    if place.kind == .farm { world.command(id, .farm(place.id)); continue }
                }
                if RTSWorld.resource(of: terrain) != nil { world.command(id, .gather(t)); continue }
            }
            world.command(id, .move(t))
        }
    }

    /// Put down the building being placed, with the selected villagers — or the nearest one — as builders.
    func put(_ kind: RTSBuildingKind, at t: RTSTile) {
        guard let me else { placing = nil; return }
        let n = RTSWorld.size(kind), origin = RTSTile(x: t.x - (n - 1) / 2, y: t.y - (n - 1) / 2)
        guard world.fits(kind, at: origin) else { say("这里放不下"); return }
        guard world.afford(RTSWorld.cost(kind), me) else { say("资源不够"); return }
        var builders = selected.filter { id in world.units.first { $0.id == id }?.kind == .villager }
        if builders.isEmpty, let nearest = world.units.filter({ $0.owner == me && $0.kind == .villager })
            .min(by: { hypot($0.x - Double(t.x), $0.y - Double(t.y)) < hypot($1.x - Double(t.x), $1.y - Double(t.y)) }) {
            builders = [nearest.id]
        }
        guard world.order(kind, at: origin, owner: me, builders: Array(builders)) != nil else { say("放不下"); return }
        if !NSEvent.modifierFlags.contains(.shift) { placing = nil }
    }

    func train(_ kind: RTSUnitKind) {
        guard let me, let yard = building.flatMap(world.building) ?? world.buildings.first(where: { $0.owner == me && $0.kind == RTSWorld.trainer(kind) && $0.done }) else { return }
        if kind == .knight, world.players[me].age < 2 { say("骑士要城堡时代"); return }
        if !world.afford(RTSWorld.cost(kind), me) { say("资源不够"); return }
        if !world.train(kind, at: yard.id) { say("排满了") }
        beat += 1
    }

    func advance() {
        guard let me else { return }
        if world.players[me].researching > 0 { say("正在升级"); return }
        if !world.advance(me) { say("资源不够：\(RTSView.price(RTSWorld.ageCost[min(world.players[me].age, 1)]))") }
        beat += 1
    }

    func charge() {
        guard let me, let tc = world.buildings.first(where: { $0.owner != me && $0.kind == .townCenter }) else { return }
        let army = world.units.filter { $0.owner == me && $0.kind != .villager }
        for u in army { world.command(u.id, .attackMove(RTSTile(x: tc.x + 1, y: tc.y + 1))) }
        say(army.isEmpty ? "还没有兵" : "全军出击：\(army.count) 人")
    }

    func stopSelected() { for id in selected { world.command(id, .idle) } }

    func idleVillager() {
        guard let me else { return }
        let idle = world.units.filter { $0.owner == me && $0.kind == .villager && $0.task == .idle }
        guard !idle.isEmpty else { say("没有闲着的村民"); return }
        let current = selected.first.flatMap { id in idle.firstIndex { $0.id == id } } ?? -1
        selected = [idle[(current + 1) % idle.count].id]; building = nil
    }
}

// MARK: - The view

struct RTSView: View {
    @ObservedObject private var game = RTSGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    static let names = ["城镇中心", "房屋", "磨坊", "农田", "伐木场", "采矿场", "兵营", "靶场", "马厩", "箭塔"]
    static let unitNames = ["村民", "长枪兵", "弓箭手", "骑士"]
    static func price(_ p: [Double]) -> String {
        zip(p, ["食", "木", "金", "石"]).filter { $0.0 > 0 }.map { "\(Int($0.0))\($0.1)" }.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            top
            GeometryReader { space in
                let size = space.size
                let S = game.camera.tile(size), origin = game.camera.origin(size), view = game.camera.visible(size)
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: game.speed == 0 && game.placing == nil)) { timeline in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        let scene = RTSScene(world: game.world, viewer: game.me ?? 0, selected: game.selected, building: game.building, placing: game.placing,
                                             hover: game.hover, box: game.box, now: now)
                        Canvas(rendersAsynchronously: true) { context, canvas in
                            context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Color(red: 0.12, green: 0.2, blue: 0.13)))
                            context.translateBy(x: -origin.x * S, y: -origin.y * S)
                            scene.paint(&context, tile: S, view: view)
                        }
                    }
                    RTSMouse().frame(width: size.width, height: size.height)
                    if game.speed == 0, game.world.winner == nil, game.placing == nil {
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
                    VStack(spacing: 6) {
                        Button { game.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 28, height: 28) }
                        Button { game.zoom(by: 0.8) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 28, height: 28) }
                        Button { game.lookHome() } label: { Image(systemName: "house").frame(width: 28, height: 28) }
                    }
                    .buttonStyle(.plain).foregroundColor(.white)
                    .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                    .padding(10)
                    .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
                    if let winner = game.world.winner {
                        VStack(spacing: 10) {
                            Text(game.me == nil ? "\(RTSWorld.names[winner])赢了" : winner == game.me ? "胜利！" : "失败…").font(.system(size: 44, weight: .heavy, design: .rounded))
                            Text(game.me == nil ? "\(game.seats[winner].title)攻破了\(RTSWorld.names[1 - winner])的城镇中心"
                                 : winner == game.me ? "你攻破了\(RTSWorld.names[1 - winner])的城镇中心" : "你的城镇中心被攻破了").font(.system(size: 16, weight: .semibold))
                            Button("再来一局") { game.restart() }.controlSize(.large)
                        }
                        .foregroundColor(.white).padding(30)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.7)))
                        .frame(width: size.width, height: size.height)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear { game.viewSize = size; game.lookHome() }
                .onChange(of: size) { _, new in game.viewSize = new }
            }
            .padding(.horizontal, 8)
            bottom
        }
        .onAppear { game.start(); RTSKeys.install() }
        .onDisappear { game.stop(); RTSKeys.remove() }
    }

    // MARK: Along the top: stock, people, age, time, speed

    private var top: some View {
        _ = game.beat
        return HStack(spacing: 14) {
            if let side = game.me {
                stock(side, full: true)
            } else {
                // Watching: both sides, briefly.
                ForEach(0..<2, id: \.self) { s in stock(s, full: false) }
            }
            Spacer()
            ForEach(0..<2, id: \.self) { s in seatPicker(s) }
            if game.me != nil { Toggle("Jev 参谋", isOn: $game.jevAdvises).toggleStyle(.checkbox).controlSize(.small) }
            Text(String(format: "%02d:%02d", Int(game.world.time) / 60, Int(game.world.time) % 60)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Picker("", selection: $game.speed) {
                Text("暂停").tag(0.0); Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0)
            }
            .pickerStyle(.segmented).frame(width: 190).labelsHidden()
            Button("重新开始") { game.restart() }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }

    /// A side's stock, people and age.
    private func stock(_ s: Int, full: Bool) -> some View {
        let side = game.world.players[s]
        return HStack(spacing: full ? 14 : 8) {
            if !full { Circle().fill(RTSScene.team[s]).frame(width: 9, height: 9) }
            ForEach(0..<4, id: \.self) { k in
                Text("\(["🍖", "🪵", "🪙", "🪨"][k]) \(Int(side.stock[k]))").font(.system(size: full ? 13 : 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Text("👥 \(game.world.population(s))/\(game.world.room(s))").font(.system(size: full ? 13 : 11, weight: .semibold)).monospacedDigit()
                .foregroundColor(game.world.population(s) >= game.world.room(s) ? .orange : .primary)
            Text(RTSWorld.ageNames[side.age] + (side.researching > 0 ? " → 升级中 \(Int(side.researching)) 秒" : ""))
                .font(.system(size: full ? 12 : 10, weight: .semibold)).foregroundColor(.secondary)
        }
    }

    /// Who sits on a side — and, for a chat model, which one.
    private func seatPicker(_ s: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(RTSScene.team[s]).frame(width: 9, height: 9)
            Text(RTSWorld.names[s]).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Picker("", selection: $game.seats[s]) {
                ForEach(RTSSeat.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().controlSize(.small).fixedSize()
            if game.seats[s] == .llm {
                Picker("", selection: $game.models[s]) {
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
    }

    // MARK: Along the bottom: what is selected and what it can do

    private var bottom: some View {
        _ = game.beat
        let w = game.world
        let chosen = w.units.filter { game.selected.contains($0.id) }
        let place = game.building.flatMap(w.building)
        let side = game.me ?? 0, age = w.players[side].age
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let place {
                    Text(Self.names[place.kind.rawValue]).font(.system(size: 13, weight: .bold))
                    Text(place.done ? "生命 \(Int(place.hp))/\(Int(RTSWorld.health(place.kind)))" : "在盖：\(Int(place.progress * 100))%")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if !place.queue.isEmpty {
                        Text("在训练：" + place.queue.map { Self.unitNames[$0.rawValue] }.joined(separator: "、") + " · \(Int(place.trained / RTSWorld.trainTime(place.queue[0]) * 100))%")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                } else if !chosen.isEmpty {
                    let groups = Dictionary(grouping: chosen, by: \.kind).sorted { $0.key.rawValue < $1.key.rawValue }
                    Text(groups.map { "\(Self.unitNames[$0.key.rawValue]) ×\($0.value.count)" }.joined(separator: "  ")).font(.system(size: 13, weight: .bold))
                    Text("右键：去那里 / 采集 / 盖 / 攻击").font(.system(size: 11)).foregroundColor(.secondary)
                } else if game.me == nil {
                    Text("观战：\(game.seats[0].title)（蓝）对 \(game.seats[1].title)（红）").font(.system(size: 12, weight: .semibold))
                    Text("右上角把一边换成「我」就能自己上").font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Text("左键选人（可以拖框），右键下命令").font(.system(size: 12, weight: .semibold))
                    Text("选中村民后点下面的建筑，再点地图放下；按住 ⇧ 连续放").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .frame(width: 260, alignment: .leading)
            Divider().frame(height: 44)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let place, place.done, place.owner == game.me {
                        switch place.kind {
                        case .townCenter:
                            action("村民", RTSWorld.cost(.villager)) { game.train(.villager) }
                            if age < 2 { action("升级到\(RTSWorld.ageNames[age + 1])", RTSWorld.ageCost[age]) { game.advance() } }
                        case .barracks: action("长枪兵", RTSWorld.cost(.spearman)) { game.train(.spearman) }
                        case .range: action("弓箭手", RTSWorld.cost(.archer)) { game.train(.archer) }
                        case .stable: action("骑士", RTSWorld.cost(.knight), locked: age < 2) { game.train(.knight) }
                        default: EmptyView()
                        }
                    } else if chosen.contains(where: { $0.kind == .villager }) {
                        ForEach(RTSBuildingKind.allCases.filter { $0 != .townCenter }, id: \.self) { kind in
                            action(Self.names[kind.rawValue], RTSWorld.cost(kind), locked: age < RTSWorld.age(kind), on: game.placing == kind) {
                                game.placing = game.placing == kind ? nil : kind
                            }
                        }
                    } else if !chosen.isEmpty {
                        Button("停下") { game.stopSelected() }.controlSize(.regular)
                    }
                }
            }
            if game.jevAdvises || game.seats.contains(where: \.commands) {
                Divider().frame(height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    if let advice = game.advice {
                        HStack(spacing: 6) {
                            Text("Jev 建议：\(advice.option.title)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\(Int(advice.chance * 100))%").font(.system(size: 10)).foregroundColor(.secondary)
                            Button("照做") { game.follow() }.controlSize(.small)
                        }
                    } else if game.jevAdvises, game.me != nil { Text("Jev 在想…").font(.system(size: 11)).foregroundColor(.secondary) }
                    ForEach(0..<2, id: \.self) { s in
                        if let note = game.notes[s] { Text(note).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1) }
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            Divider().frame(height: 44)
            let idle = w.units.filter { $0.owner == side && $0.kind == .villager && $0.task == .idle }.count
            Button("闲置村民 \(idle)") { game.idleVillager() }.controlSize(.regular).disabled(idle == 0 || game.me == nil)
            Button("全军出击") { game.charge() }.controlSize(.regular).disabled(game.me == nil)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(height: 64)
    }

    private func action(_ title: String, _ cost: [Double], locked: Bool = false, on: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(locked ? "🔒 下个时代" : Self.price(cost)).font(.system(size: 9)).foregroundColor(.secondary)
            }
            .frame(minWidth: 64).padding(.vertical, 4).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .disabled(locked || game.me == nil || !game.world.afford(cost, game.me ?? 0))
        .opacity(locked || game.me == nil || !game.world.afford(cost, game.me ?? 0) ? 0.45 : 1)
    }
}

// MARK: - The mouse, straight from AppKit: left and right buttons, drags, where it hovers

struct RTSMouse: NSViewRepresentable {
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {}

    final class Catcher: NSView {
        private var start: CGPoint?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

        override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { RTSGame.shared.hover = RTSGame.shared.tile(at: point(event)) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { RTSGame.shared.hover = nil } }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
            start = point(event)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let p = point(event)
            MainActor.assumeIsolated {
                let game = RTSGame.shared
                game.hover = game.tile(at: p)
                if game.placing == nil { game.box = (game.spot(at: start), game.spot(at: p)) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            guard let from = start else { return }
            start = nil
            let p = point(event), adding = event.modifierFlags.contains(.shift)
            MainActor.assumeIsolated {
                let game = RTSGame.shared
                game.box = nil
                if game.placing == nil, hypot(p.x - from.x, p.y - from.y) > 6 { game.select(from: game.spot(at: from), to: game.spot(at: p)) }
                else { game.click(game.tile(at: p), at: game.spot(at: p), adding: adding) }
            }
        }
        override func rightMouseDown(with event: NSEvent) {
            let p = point(event)
            MainActor.assumeIsolated {
                let game = RTSGame.shared
                if game.placing != nil { game.placing = nil; return }
                game.order(game.tile(at: p))
            }
        }
        override func scrollWheel(with event: NSEvent) {
            let p = point(event)
            MainActor.assumeIsolated {
                let game = RTSGame.shared
                if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                    game.zoom(by: pow(1.02, event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 3)), at: p)
                } else {
                    game.pan(event.scrollingDeltaX, event.scrollingDeltaY)
                }
            }
        }
        override func magnify(with event: NSEvent) {
            let p = point(event)
            MainActor.assumeIsolated { RTSGame.shared.zoom(by: 1 + event.magnification, at: p) }
        }
    }
}

/// The keyboard while the map is showing: Esc lets go, space pauses, arrows move, = and - zoom.
@MainActor
enum RTSKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let game = RTSGame.shared
            switch event.keyCode {
            case 53: game.placing = nil; game.selected = []; game.building = nil; return nil
            case 49: game.speed = game.speed == 0 ? 1 : 0; return nil
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

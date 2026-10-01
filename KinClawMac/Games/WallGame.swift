import AppKit
import SwiftUI

/// Who holds the pass.
enum WallSeat: String, CaseIterable, Identifiable {
    case me, computer, jev, tev1, nimble, llm
    var id: String { rawValue }
    var title: String { ["我", "电脑", "Jev", "tev1", "nimble", "大模型"][Self.allCases.firstIndex(of: self)!] }
    /// tev1 or nimble: an open decision model on the box's Ollama, asked Jev's own question.
    var open: String? { self == .tev1 || self == .nimble ? rawValue : nil }
    /// Jev, or an open model of its kind.
    var decides: Bool { self == .jev || open != nil }
    /// Does somebody other than the script decide?
    var commands: Bool { decides || self == .llm }
}

/// What placing a tower on the tile under the mouse would do: refused and why, or the ways it would make.
struct WallPreview {
    var tile: WallTile
    var kind: WallKind
    var refusal: WallField.Refusal?
    var routes: [[WallTile]]?
    var after: Double
}

/// 长城守卫（建造）, played with the mouse: the war's clock, who holds the pass, what is selected and being
/// placed, the orders a click becomes, and the questions put to Jev or a chat model.
@MainActor
final class WallGame: ObservableObject {
    static let shared = WallGame()

    @Published private(set) var beat = 0
    /// Paused until somebody presses 开始, like every game in the app.
    @Published var speed = 0.0 { didSet { if speed > 0, loop == nil { start() } } }
    private(set) var field: WallField
    private var brain = WallBrain()
    private(set) var seed: UInt64

    @Published var seat: WallSeat = .me { didSet { seated() } }
    /// For a chat model: "host|model", or "" for the app's own pick.
    @Published var model = "" { didSet { UserDefaults.standard.set(model, forKey: "kinclaw.wall.model") } }
    /// The furthest wave ever reached.
    @Published private(set) var best = UserDefaults.standard.integer(forKey: "kinclaw.wall.bestWave") { didSet { UserDefaults.standard.set(best, forKey: "kinclaw.wall.bestWave") } }
    /// What the defender who is not the person last chose, or why a question failed.
    @Published private(set) var note: String?
    /// The options last put to Jev or the chat model, and which was chosen: shown while watching.
    @Published private(set) var ballot: (options: [WallOption], chosen: Int, chance: Double?)?

    @Published var camera = GameCamera(map: WallGame.mapSize, focus: CGPoint(x: 15, y: WallGame.mapSize.height / 2), zoom: 1)
    /// The map's part of the view: below the glass strip along the top.
    var viewSize = CGSize(width: 1200, height: 700)
    var scale: CGFloat = 1
    /// Points at the top of the view the glass strip covers; the map is drawn below them.
    var inset: CGFloat = 76

    @Published var selected: Int?
    @Published var placing: WallKind? { didSet { if placing != nil { selected = nil }; kept = nil } }
    var hover: WallTile? { didSet { if hover != oldValue { kept = nil } } }
    /// The tower under the mouse, for its reach.
    var hoverTower: Int? { hover.flatMap { field.tower(at: $0)?.id } }

    @Published private(set) var message: String?
    private var said = Date.distantPast
    private var loop: Task<Void, Never>?
    private var frames = 0
    private var asking = false, lastAsked = -99.0
    private var told = Set<String>()
    private var kept: WallPreview?

    /// The drawn world in tiles: the field, with a band of hills above it and the Wall's face below.
    nonisolated static let top: CGFloat = 1.7, bottom: CGFloat = 1.4
    nonisolated static let mapSize = CGSize(width: CGFloat(WallField.width) + 1, height: CGFloat(WallField.height) + top + bottom)

    init() {
        seed = UInt64.random(in: 1...9999)
        field = WallField(seed: seed)
        if let kept = UserDefaults.standard.string(forKey: "kinclaw.wall.seat").flatMap(WallSeat.init(rawValue:)) { seat = kept }
        model = UserDefaults.standard.string(forKey: "kinclaw.wall.model") ?? ""
    }

    var me: Bool { seat == .me }

    private func seated() {
        UserDefaults.standard.set(seat.rawValue, forKey: "kinclaw.wall.seat")
        brain = WallBrain(); note = nil; ballot = nil; lastAsked = -99
        if !me { placing = nil }
    }

    func say(_ text: String) { message = text; said = Date() }
    var saying: String? { Date().timeIntervalSince(said) < 3.5 ? message : nil }

    // MARK: The clock

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                if speed > 0, !field.over {
                    let dt = 1.0 / 60
                    for _ in 0..<max(1, Int(speed)) {
                        if seat == .computer { brain.think(&field) }
                        field.step(dt)
                    }
                    watch()
                    if seat.commands, !asking, field.time - lastAsked >= (seat.decides ? 5 : 10) { consult() }
                }
                frames += 1
                if frames % 6 == 0 { beat += 1 }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil }

    /// A fresh frontier — from a seed when given, for a game to replay or a test.
    func restart(seed chosen: UInt64? = nil) {
        seed = chosen ?? UInt64.random(in: 1...9999)
        field = WallField(seed: seed)
        brain = WallBrain()
        selected = nil; placing = nil; message = nil; note = nil; ballot = nil; kept = nil
        lastAsked = -99; told = []
        speed = 0; beat += 1
        camera = GameCamera(map: Self.mapSize, focus: CGPoint(x: 15, y: Self.mapSize.height / 2), zoom: 1)
    }

    /// Play on at once without drawing, the script's hands at work (unless `script` is false), to a wave:
    /// for tests, pictures, and a panel tool that skips ahead.
    func fastForward(toWave n: Int, script: Bool = true) {
        var b = WallBrain()
        let dt = 1.0 / 30
        while field.wave < n, !field.over {
            if script { b.think(&field) }
            field.step(dt)
        }
        beat += 1
    }

    /// Step the war a little without anybody's hands: for pictures of a moment.
    func advance(seconds: Double, script: Bool = false) {
        var b = WallBrain()
        let dt = 1.0 / 30
        var t = 0.0
        while t < seconds, !field.over {
            if script { b.think(&field) }
            field.step(dt); t += dt
        }
        beat += 1
    }

    /// For tests and pictures: change the field directly.
    func edit(_ change: (inout WallField) -> Void) { change(&field); kept = nil; beat += 1 }

    func zoom(by factor: CGFloat, at p: CGPoint? = nil) {
        camera.zoom(by: factor, at: p.map { CGPoint(x: $0.x, y: $0.y - inset) } ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), viewSize)
        if camera.zoom < 1.01 { camera.zoom = 1; camera.settle(viewSize) }
    }
    func pan(_ dx: CGFloat, _ dy: CGFloat) { camera.pan(dx, dy, viewSize) }
    func frame() { camera = GameCamera(map: Self.mapSize, focus: CGPoint(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2), zoom: 1); camera.settle(viewSize) }

    /// The field's tile under a point of the map view.
    func tile(at p: CGPoint) -> WallTile {
        let t = camera.at(CGPoint(x: p.x, y: p.y - inset), viewSize)
        return WallTile(x: Int(floor(t.x - 0.5)), y: Int(floor(t.y - Self.top)))
    }

    /// What placing the chosen tower under the mouse would do.
    var preview: WallPreview? {
        guard let kind = placing, let t = hover, WallField.inside(t) else { return nil }
        if let kept, kept.tile == t, kept.kind == kind { return kept }
        let refusal = field.refusal(kind, at: t)
        var routes: [[WallTile]]?
        var after = field.pathLength
        if refusal == nil || refusal == .gold(kind.cost - field.gold) {
            if field.routes.contains(where: { $0.contains(t) }), let r = field.routes(blocking: t) {
                routes = r
                after = r.map { WallField.length($0) }.reduce(0, +) / Double(r.count)
            }
        }
        let p = WallPreview(tile: t, kind: kind, refusal: refusal, routes: routes, after: after)
        kept = p
        return p
    }

    /// How the war stands, in a few lines — for wall_status.
    var report: String {
        let f = field
        var lines = ["长城守卫：第 \(f.wave) 波（最高 \(max(best, f.wave)) 波）· 命 \(f.lives)/\(WallField.startLives) · 金 \(f.gold) · 守关 \(seat.title) · \(speed == 0 ? "暂停" : "\(Int(speed))×")" + (f.over ? " · 关口失守" : "")]
        let w = f.coming
        lines.append("下一波：第 \(w.number) 波「\(w.theme)」\(w.chinese)" + (f.spawned ? "，\(Int(max(0, f.clock).rounded())) 秒后来（现在叫多得 \(f.earlyBonus) 金）" : "（这一波还在出）"))
        lines.append(String(format: "场上敌人 %d · 敌人走到关口平均 %.0f 格 · 杀敌 %d · 放过 %d · 单于被斩 %d", f.enemies.count, f.pathLength, f.kills, f.leaked, f.bossesKilled))
        let kinds = WallKind.allCases.compactMap { k -> String? in
            let ts = f.towers.filter { $0.kind == k }
            guard !ts.isEmpty else { return nil }
            return "\(k.name) \(ts.count)" + (ts.contains { $0.level > 0 } ? "（升级 \(ts.filter { $0.level > 0 }.count)）" : "")
        }
        lines.append("塔：" + (kinds.isEmpty ? "还没有" : kinds.joined(separator: " · ")))
        if let note { lines.append(note) }
        return lines.joined(separator: "\n")
    }

    // MARK: What the war says of its own accord

    private func watch() {
        for m in field.moments where field.time - m.time < 0.05 * max(1, speed) {
            switch m.kind {
            case .wave(let n): let w = WallWave.make(n, seed: field.seed); say("第 \(n) 波：\(w.theme)（\(w.chinese)）")
            case .boss(let n): say("⚠️ 第 \(n) 波：单于亲征！")
            case .leak(let foe, let n): once("漏\(Int(field.time * 2))", "\(foe.name)冲过了关口！−\(n) 命")
            case .destroyed(let kind, let foe): say("\(foe.name)毁了一座\(kind.name)")
            case .lost: say("关口失守")
            }
        }
        if field.wave > best { best = field.wave }
        if let id = selected, field.tower(id) == nil { selected = nil }
    }

    private func once(_ key: String, _ text: String) {
        guard !told.contains(key) else { return }
        told.insert(key); say(text)
    }

    // MARK: Asking Jev or a chat model

    private func consult() {
        let options = WallCommander.options(field, best: best)
        lastAsked = field.time
        // Nothing to choose but keeping the gold: no question.
        guard options.count > 1 else { return }
        asking = true
        let situation = WallCommander.situation(field, best: best), who = seat
        Task { @MainActor in
            defer { asking = false }
            do {
                let (index, chance, name) = who.decides ? try await askJev(options, situation, via: who.open) : try await askChat(options, situation)
                guard seat == who, !field.over else { return }
                let done = WallCommander.execute(options[index].order, &field)
                ballot = (options, index, chance)
                note = "\(name)：\(done)" + (chance.map { " · \(Int($0 * 100))%" } ?? "")
                beat += 1
            } catch {
                note = "\(who.title)没答上：\(error.localizedDescription.prefix(60))"
            }
        }
    }

    private func askJev(_ options: [WallOption], _ situation: String, via: String? = nil) async throws -> (Int, Double?, String) {
        let q = JevClient.Question(id: "order", question: WallCommander.question, howToJudge: WallCommander.howToJudge,
                                   options: options.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.words) })
        let reply = try await JevClient.ask(state: [("game", WallCommander.rules), ("position_before_move", situation)], [q], via: via)
        guard let answer = reply.answers["order"], let n = Int(answer.choice.dropFirst()), options.indices.contains(n - 1) else {
            throw JevArcade.Failure.message("\(via ?? "Jev") 的回答读不出来")
        }
        return (n - 1, answer.chances[answer.choice], via ?? "Jev")
    }

    private func askChat(_ options: [WallOption], _ situation: String) async throws -> (Int, Double?, String) {
        var chosen: (host: String, model: String)?
        if model.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = model.firstIndex(of: "|") { chosen = (String(model[..<bar]), String(model[model.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(model) { chosen = (entry.host, model); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = """
            \(WallCommander.rules)
            The situation: \(situation)
            \(WallCommander.question) \(WallCommander.howToJudge)
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

    func click(_ t: WallTile) {
        if let kind = placing { put(kind, at: t); return }
        guard WallField.inside(t) else { selected = nil; return }
        selected = field.tower(at: t)?.id
        beat += 1
    }

    static func why(_ r: WallField.Refusal, _ kind: WallKind) -> String {
        switch r {
        case .outside: return "只能造在关前的草地上"
        case .taken: return "这里已经有塔了"
        case .land: return "这里造不了：河水、岩石、山脊和长城上都不行"
        case .blocks: return "不能造：这一格一堵，敌人就没有路走到关口了——总要给他们留一条路"
        case .enemy: return "有敌人正站在这里"
        case .gold(let short): return "\(kind.name)要 \(kind.cost) 金，还差 \(short)"
        }
    }

    func put(_ kind: WallKind, at t: WallTile) {
        guard me else { placing = nil; return }
        if let r = field.refusal(kind, at: t) { say(Self.why(r, kind)); return }
        let before = field.pathLength
        field.build(kind, at: t)
        let after = field.pathLength
        if after > before + 0.4 { say(String(format: "%@：敌人的路从 %.0f 格变成 %.0f 格", kind.name, before, after)) }
        if !NSEvent.modifierFlags.contains(.shift) { placing = nil }
        kept = nil
        beat += 1
    }

    func upgrade() {
        guard me, let id = selected, let t = field.tower(id) else { return }
        guard let c = field.upgradeCost(t) else { say("已经是最高级了"); return }
        if field.upgrade(id) { say("\(t.kind.name)升到 \(t.level + 2) 级") } else { say("升级要 \(c) 金，还差 \(c - field.gold)") }
        beat += 1
    }

    func sell() {
        guard me, let id = selected, let t = field.tower(id) else { return }
        let back = field.sell(id)
        selected = nil
        say("卖了\(t.kind.name)，拿回 \(back) 金")
        beat += 1
    }

    func aim(_ a: WallAim) {
        guard me, let id = selected else { return }
        field.aim(id, a)
        beat += 1
    }

    func cycleAim() {
        guard let id = selected, let t = field.tower(id), t.kind.shoots else { return }
        aim(WallAim(rawValue: (t.aim.rawValue + 1) % WallAim.allCases.count)!)
    }

    /// 下一波: call it now, for gold.
    func callNext() {
        guard me else { return }
        guard field.spawned else { say("这一波还没出完"); return }
        let bonus = field.earlyBonus
        field.call()
        if speed == 0 { speed = 1 }
        say("第 \(field.wave) 波提前来了 · +\(WallField.waveBonus(field.wave) + bonus) 金")
        beat += 1
    }
}

// MARK: - The mouse: hover, clicks, drags to look around when zoomed in

struct WallMouse: NSViewRepresentable {
    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {}

    final class Catcher: NSView {
        private var start: CGPoint?
        private var dragged = false
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

        override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { WallGame.shared.hover = WallGame.shared.tile(at: point(event)) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { WallGame.shared.hover = nil } }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
            start = point(event); dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = WallGame.shared
                game.hover = game.tile(at: point(event))
                if let s = start, hypot(point(event).x - s.x, point(event).y - s.y) > 4 { dragged = true }
                if dragged, game.placing == nil, game.camera.zoom > 1.01 { game.pan(event.deltaX, event.deltaY) }
            }
        }
        override func mouseUp(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = WallGame.shared
                if !dragged || game.placing != nil { game.click(game.tile(at: point(event))) }
            }
            start = nil
        }
        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated { let game = WallGame.shared; game.placing = nil; game.selected = nil }
        }
        override func scrollWheel(with event: NSEvent) {
            MainActor.assumeIsolated {
                let game = WallGame.shared
                if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
                    game.zoom(by: pow(1.02, event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 3)), at: point(event))
                } else if game.camera.zoom > 1.01 {
                    game.pan(event.scrollingDeltaX, event.scrollingDeltaY)
                }
            }
        }
        override func magnify(with event: NSEvent) {
            MainActor.assumeIsolated { WallGame.shared.zoom(by: 1 + event.magnification, at: point(event)) }
        }
    }
}

/// The keyboard while the pass is showing: Esc lets go, space pauses, 1–4 set the speed, Q W E R T F pick a tower,
/// N calls the next wave, U raises the selected tower, S (or Delete) sells it, Tab changes whom it aims at, = and - zoom.
@MainActor
enum WallKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let game = WallGame.shared
            let towers: [UInt16: WallKind] = [12: .arrow, 13: .ballista, 14: .trebuchet, 15: .fire, 17: .beacon, 3: .barricade]
            if let kind = towers[event.keyCode] {
                if game.me { game.placing = game.placing == kind ? nil : kind }
                return nil
            }
            switch event.keyCode {
            case 53: game.placing = nil; game.selected = nil; return nil
            case 49: game.speed = game.speed == 0 ? 1 : 0; return nil
            case 18, 19, 20, 21: game.speed = [1, 2, 4, 8][Int(event.keyCode) - 18]; return nil
            case 45: if game.me { game.callNext() }; return nil
            case 32: game.upgrade(); return nil
            case 1, 51: game.sell(); return nil
            case 48: game.cycleAim(); return nil
            case 24: game.zoom(by: 1.25); return nil
            case 27: game.zoom(by: 0.8); return nil
            case 123: game.pan(120, 0); return nil
            case 124: game.pan(-120, 0); return nil
            case 125: game.pan(0, -120); return nil
            case 126: game.pan(0, 120); return nil
            default: return event
            }
        }
    }
    static func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

import AppKit
import SceneKit
import SwiftUI

/// 沙盒搭建, played with the mouse: a world of blocks to build in, a chat model
/// that builds what it is asked from a plan, and Jev, who looks at a build —
/// measured into words — and says what it thinks it is.
@MainActor
final class SandboxGame: ObservableObject {
    static let shared = SandboxGame()

    @Published private(set) var beat = 0
    @Published var selected: Block = .planks
    @Published var request = ""
    /// For the chat model that builds: "host|model", or "" for the app's own pick.
    @Published var model = "" { didSet { UserDefaults.standard.set(model, forKey: "kinclaw.sandbox.model") } }
    @Published private(set) var status: String?
    @Published private(set) var building = false
    @Published private(set) var judging = false
    /// What Jev made of the last build it was shown.
    @Published private(set) var verdict: (title: String, lines: [String])?

    private(set) var world: SandboxWorld
    let stage = SandboxStage()
    weak var view: SCNView?
    /// Where a plan goes up: the empty cell above the last block clicked, or the middle of the map.
    private(set) var spot: BlockPos
    /// What was asked for last, for Jev to judge the build against, and where it went up.
    private(set) var asked: String?
    private var askedAt: BlockPos?
    /// The last plan a model wrote: who wrote it, its commands, the ones not understood, the blocks it puts down.
    private(set) var lastPlan: (by: String, steps: Int, unread: Int, blocks: Int)?
    private var queue: [(BlockPos, Block)] = []
    private var saving: Task<Void, Never>?
    private var placing: Task<Void, Never>?

    init() {
        world = SandboxWorld.load() ?? SandboxWorld(seed: UInt64.random(in: 1...99_999))
        let x = SandboxWorld.sx / 2, z = SandboxWorld.sz / 2
        spot = BlockPos(x: x, y: world.top(x, z) + 1, z: z)
        model = UserDefaults.standard.string(forKey: "kinclaw.sandbox.model") ?? ""
        stage.refresh(&world)
    }

    /// A line over the world; one that is not about work still going on fades after a few seconds.
    func say(_ text: String?) {
        status = text
        beat += 1
        guard let text else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if status == text, !building, !judging { status = nil; beat += 1 }
        }
    }

    // MARK: Building by hand

    /// A click on the map: put the chosen block in front of the face clicked.
    func place(at before: BlockPos) {
        guard SandboxWorld.inside(before), world[before] == .air || world[before] == .water else { return }
        if world.set(before, selected) {
            spot = before
            changed()
        }
    }

    /// A right click: take the block away.
    func remove(_ p: BlockPos) {
        guard p.y > 0 else { say("最底下一层拿不掉"); return }
        guard world[p] != .water else { return }
        if world.set(p, .air) { changed() }
    }

    func pick(_ b: Block) { selected = b; beat += 1 }

    func block(at p: BlockPos) -> Block { world[p] }

    /// Keys walk the view: across the ground the way the camera faces, or up and down.
    func walk(right: CGFloat, forward: CGFloat, up: CGFloat) {
        stage.walk(right: right, forward: forward, up: up)
        view?.defaultCameraController.target = stage.focus
    }

    private func look(at place: SCNVector3) {
        stage.go(to: place)
        view?.defaultCameraController.target = stage.focus
    }

    func newWorld() {
        placing?.cancel(); queue = []; building = false
        world = SandboxWorld(seed: UInt64.random(in: 1...99_999))
        let x = SandboxWorld.sx / 2, z = SandboxWorld.sz / 2
        spot = BlockPos(x: x, y: world.top(x, z) + 1, z: z)
        verdict = nil; asked = nil; askedAt = nil
        changed()
        say("新的世界")
    }

    private func changed() {
        stage.refresh(&world)
        beat += 1
        saving?.cancel()
        saving = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            world.save()
        }
    }

    func saveNow() { world.save() }

    // MARK: A chat model builds

    /// Ask the chat model for a plan in the building language, then put it up block by block where the last block went.
    func buildFromRequest() {
        let words = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !building else { return }
        building = true
        asked = words
        let base = spot
        askedAt = base
        say("大模型在画图纸：\(words)")
        Task { @MainActor in
            do {
                let (plan, name) = try await askChat(words)
                let (steps, unread) = SandboxPlan.parse(plan)
                guard !steps.isEmpty else { throw JevArcade.Failure.message("\(name) 的图纸一行都读不懂") }
                let blocks = SandboxPlan.blocks(steps)
                lastPlan = (name, steps.count, unread, blocks.count)
                queue = blocks.map { (BlockPos(x: base.x + $0.0.x, y: base.y + $0.0.y, z: base.z + $0.0.z), $0.1) }
                // The trees standing where it goes come down first.
                let xs = queue.map(\.0.x), ys = queue.map(\.0.y), zs = queue.map(\.0.z)
                if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), let z0 = zs.min(), let z1 = zs.max() {
                    world.clearTrees(from: BlockPos(x: x0, y: y0, z: z0), to: BlockPos(x: x1, y: y1, z: z1))
                    look(at: SCNVector3(Float(x0 + x1 + 1) / 2, Float(y0 + y1) / 2 + 1, Float(z0 + z1 + 1) / 2))
                }
                say("\(name) 画好了图纸：\(steps.count) 步、\(blocks.count) 块" + (unread > 0 ? "（\(unread) 行没看懂，跳过了）" : "") + "，开始盖")
                raise()
            } catch {
                building = false
                say("没盖成：\(error.localizedDescription.prefix(80))")
            }
        }
    }

    /// Put the queued blocks down a handful at a time, so the build can be seen going up.
    private func raise() {
        placing?.cancel()
        placing = Task { @MainActor in
            var done = 0
            // A handful a frame, more for a big build: none takes much over ten seconds to go up.
            let each = max(18, queue.count / 330)
            while !queue.isEmpty, !Task.isCancelled {
                let batch = queue.prefix(each)
                queue.removeFirst(batch.count)
                for (p, b) in batch where SandboxWorld.inside(p) && p.y > 0 { world.set(p, b) }
                done += batch.count
                stage.refresh(&world)
                beat += 1
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            building = false
            changed()
            say("盖好了：\(done) 块。点「Jev 看看」让它说说这是什么")
        }
    }

    private func askChat(_ words: String) async throws -> (String, String) {
        var chosen: (host: String, model: String)?
        if model.isEmpty { chosen = await FilmStudio.writer() }
        else if let bar = model.firstIndex(of: "|") { chosen = (String(model[..<bar]), String(model[model.index(after: bar)...])) }
        else { for entry in await FilmStudio.candidates() where entry.models.contains(model) { chosen = (entry.host, model); break } }
        guard let writer = chosen, let url = URL(string: writer.host + "/api/chat") else { throw JevArcade.Failure.message("没找到能用的对话模型") }
        let prompt = SandboxPlan.grammar + "\n\nBuild this, with care for how it looks: \(words)\nCommands only."
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": writer.model, "stream": false, "think": false,
                                                                        "messages": [["role": "user", "content": prompt]]] as [String: Any])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let reply = (try JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = (reply["message"] as? [String: Any])?["content"] as? String else { throw JevArcade.Failure.message("\(writer.model) 没回话") }
        // A model that thinks aloud: only what comes after its thinking.
        let plan = text.components(separatedBy: "</think>").last ?? text
        return (plan, writer.model)
    }

    // MARK: Jev looks

    /// Measure the build nearest the last block placed, and ask Jev what it is — and, if it was asked for, how well it matches.
    func judge() {
        guard !judging else { return }
        guard let survey = BuildSurvey(world, near: spot) else { say("附近没有你盖的东西：先盖点什么"); return }
        judging = true
        say("Jev 在看…")
        let what = JevClient.Question(id: "what", question: "What is this build most likely meant to be?",
                                      howToJudge: "Read the measurements literally: size and shape, whether it closes in a room, doorways, windows, roof, what it stands on.",
                                      options: BuildSurvey.kinds.enumerated().map { (String(format: "p%02d", $0.offset + 1), $0.element.1) })
        var questions = [what]
        // The request only counts for a build near where it went up.
        let asked = askedAt.map { abs(spot.x - $0.x) + abs(spot.z - $0.z) <= 24 } == true ? self.asked : nil
        if let asked {
            questions.append(JevClient.Question(id: "match", question: "How well does this build match what was asked for: \"\(asked)\"?",
                                                howToJudge: "Compare the measurements with what the request calls for — its parts, its size, its materials.",
                                                options: [("p01", "it does not match at all"), ("p02", "it matches a little"), ("p03", "it matches about half of it"),
                                                          ("p04", "it matches most of it"), ("p05", "it matches it well in every part")]))
        }
        Task { @MainActor in
            defer { judging = false }
            do {
                let reply = try await JevClient.ask(state: [("world", "A world of one-metre blocks; somebody built something in it."), ("build", survey.words)], questions)
                guard let answer = reply.answers["what"] else { throw JevArcade.Failure.message("Jev 的回答读不出来") }
                let ranked = answer.chances.sorted { $0.value > $1.value }.prefix(3).compactMap { key, chance -> String? in
                    guard let n = Int(key.dropFirst()), BuildSurvey.kinds.indices.contains(n - 1) else { return nil }
                    return "\(BuildSurvey.kinds[n - 1].0) \(Int((chance * 100).rounded()))%"
                }
                var lines = ["它猜：" + ranked.joined(separator: " · ")]
                if let match = reply.answers["match"], let n = Int(match.choice.dropFirst()) {
                    lines.append("和「\(asked ?? "")」对得上：" + String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n))
                }
                lines.append("量出来的：\(survey.width)×\(survey.depth)，高 \(survey.height)，\(survey.blocks) 块，" + (survey.rooms > 0 ? "\(survey.rooms) 个房间" : "没有房间") + (survey.doors > 0 ? "，有门" : "") + (survey.windows > 0 ? "，\(survey.windows) 块玻璃" : ""))
                verdict = (ranked.first.map { "Jev 看这像：\($0)" } ?? "Jev 看不出来", lines)
                say(nil)
            } catch {
                say("Jev 没答上：\(error.localizedDescription.prefix(80))")
            }
        }
    }

    func dismissVerdict() { verdict = nil }

    /// How the sandbox stands, for the panel's tools.
    var report: String {
        var lines = ["沙盒搭建：世界 \(SandboxWorld.sx)×\(SandboxWorld.sz)、高 \(SandboxWorld.sy)；盖上去的方块 \(world.placed.lazy.filter { $0 }.count) 块；手里拿的是\(selected.name)"]
        if building { lines.append("正在盖，还剩 \(queue.count) 块") }
        if judging { lines.append("Jev 正在看") }
        if let status { lines.append("状态：\(status)") }
        if let asked { lines.append("上次要盖的：\(asked)") }
        if let plan = lastPlan { lines.append("\(plan.by) 的图纸：\(plan.steps) 步、\(plan.blocks) 块" + (plan.unread > 0 ? "，\(plan.unread) 行没看懂" : "")) }
        if let survey = BuildSurvey(world, near: spot) { lines.append("最后点的地方旁边那座，量出来：" + survey.words) }
        if let verdict { lines.append(verdict.title); lines.append(contentsOf: verdict.lines.map { "  " + $0 }) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - The view

struct SandboxView: View {
    @ObservedObject private var game = SandboxGame.shared
    @State private var chatModels: [(host: String, models: [String])] = []
    private static let icons: [Block: NSImage] = {
        let atlas = SandboxArt.atlas()
        var out: [Block: NSImage] = [:]
        for b in Block.palette {
            let index = SandboxArt.picture(b, .side)
            let rect = CGRect(x: (index % SandboxArt.cols) * SandboxArt.tile, y: (index / SandboxArt.cols) * SandboxArt.tile, width: SandboxArt.tile, height: SandboxArt.tile)
            if let piece = atlas.cropping(to: rect) { out[b] = NSImage(cgImage: piece, size: NSSize(width: 32, height: 32)) }
        }
        return out
    }()

    var body: some View {
        VStack(spacing: 0) {
            top
            ZStack(alignment: .top) {
                SandboxSceneView()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let status = game.status {
                    Text(status).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(.top, 10).allowsHitTesting(false)
                }
                if let verdict = game.verdict {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(verdict.title).font(.system(size: 16, weight: .bold))
                            Spacer()
                            Button { game.dismissVerdict() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }
                        ForEach(verdict.lines, id: \.self) { Text($0).font(.system(size: 12)) }
                    }
                    .foregroundColor(.white).padding(14).frame(width: 420)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.72)))
                    .padding(.top, 54)
                }
            }
            .padding(.horizontal, 8)
            hotbar
        }
        .onAppear { SandboxKeys.install() }
        .onDisappear { SandboxKeys.remove(); game.saveNow() }
        .task { if chatModels.isEmpty { chatModels = await FilmStudio.candidates() } }
    }

    private var top: some View {
        HStack(spacing: 10) {
            Text("沙盒搭建").font(.system(size: 13, weight: .bold))
            Text("左键放 · 右键拆 · 拖动转视角 · 滚轮缩放 · WASD 走、QE 升降 · 1–9 选方块").font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            TextField("让大模型盖：比如 一座带塔楼的石头小城堡", text: $game.request)
                .textFieldStyle(.roundedBorder).frame(width: 280)
                .onSubmit { game.buildFromRequest() }
            Picker("", selection: $game.model) {
                Text("自动").tag("")
                ForEach(chatModels, id: \.host) { entry in
                    Section(BoxServices.place(of: entry.host)) {
                        ForEach(entry.models, id: \.self) { name in Text(name + (name.hasSuffix(":cloud") ? " ☁︎" : "")).tag("\(entry.host)|\(name)") }
                    }
                }
            }
            .labelsHidden().controlSize(.small).fixedSize()
            Button(game.building ? "在盖…" : "盖") { game.buildFromRequest() }.disabled(game.building || game.request.isEmpty).controlSize(.small)
            Button(game.judging ? "Jev 在看…" : "Jev 看看") { game.judge() }.disabled(game.judging).controlSize(.small)
            Button("新世界") { game.newWorld() }.controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var hotbar: some View {
        _ = game.beat
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(Block.palette.enumerated()), id: \.offset) { k, b in
                    Button { game.pick(b) } label: {
                        VStack(spacing: 2) {
                            if let icon = Self.icons[b] { Image(nsImage: icon).interpolation(.none).resizable().frame(width: 30, height: 30) }
                            Text((k < 10 ? "\((k + 1) % 10) " : "") + b.name).font(.system(size: 10, weight: .semibold))
                        }
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(game.selected == b ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(game.selected == b ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(height: 70)
    }
}

// MARK: - The 3D view: SceneKit's camera for turning and zooming, clicks for building

struct SandboxSceneView: NSViewRepresentable {
    func makeNSView(context: Context) -> Canvas3D {
        let game = SandboxGame.shared
        let view = Canvas3D(frame: .zero)
        view.scene = game.stage.scene
        view.pointOfView = game.stage.camera
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = game.stage.focus
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.maximumVerticalAngle = 85
        view.defaultCameraController.minimumVerticalAngle = 5
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(red: 0.56, green: 0.74, blue: 0.95, alpha: 1)
        view.preferredFramesPerSecond = 60
        game.view = view
        return view
    }
    func updateNSView(_ view: Canvas3D, context: Context) {}

    final class Canvas3D: SCNView {
        private var downAt: NSPoint?, rightAt: NSPoint?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        override var acceptsFirstResponder: Bool { true }

        private func hit(_ event: NSEvent) -> (block: BlockPos, before: BlockPos)? {
            let p = convert(event.locationInWindow, from: nil)
            let stage = MainActor.assumeIsolated { SandboxGame.shared.stage }
            let results = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
            guard let first = results.first(where: { $0.node !== stage.cursor && $0.node !== stage.ghost }) else { return nil }
            let target = SandboxStage.target(first)
            // Water gives way: a block put onto it goes into it, level with the surface.
            if MainActor.assumeIsolated({ SandboxGame.shared.block(at: target.block) }) == .water { return (target.block, target.block) }
            return target
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let target = hit(event)
            MainActor.assumeIsolated {
                let stage = SandboxGame.shared.stage
                guard let target else { stage.cursor.isHidden = true; stage.ghost.isHidden = true; return }
                stage.cursor.position = SCNVector3(Float(target.block.x), Float(target.block.y), Float(target.block.z))
                stage.cursor.isHidden = false
                stage.ghost.position = SCNVector3(Float(target.before.x) + 0.5, Float(target.before.y) + 0.5, Float(target.before.z) + 0.5)
                stage.ghost.isHidden = !SandboxWorld.inside(target.before)
            }
        }
        override func mouseExited(with event: NSEvent) {
            MainActor.assumeIsolated { SandboxGame.shared.stage.cursor.isHidden = true; SandboxGame.shared.stage.ghost.isHidden = true }
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            // Control-click is a right click: it takes a block away when it comes up.
            if event.modifierFlags.contains(.control) { rightAt = event.locationInWindow; return }
            downAt = event.locationInWindow
            super.mouseDown(with: event)
        }
        override func mouseUp(with event: NSEvent) {
            if rightAt != nil { rightMouseUp(with: event); return }
            super.mouseUp(with: event)
            defer { downAt = nil }
            guard let downAt, hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y) < 4, let target = hit(event) else { return }
            MainActor.assumeIsolated { SandboxGame.shared.place(at: target.before) }
            mouseMoved(with: event)
        }
        override func rightMouseDown(with event: NSEvent) { rightAt = event.locationInWindow; super.rightMouseDown(with: event) }
        override func rightMouseUp(with event: NSEvent) {
            if event.type == .rightMouseUp { super.rightMouseUp(with: event) }
            defer { rightAt = nil }
            guard let rightAt, hypot(event.locationInWindow.x - rightAt.x, event.locationInWindow.y - rightAt.y) < 4, let target = hit(event) else { return }
            MainActor.assumeIsolated { SandboxGame.shared.remove(target.block) }
            mouseMoved(with: event)
        }
    }
}

/// The keyboard while the world is showing: 1–9 and 0 choose a block; WASD or the arrows walk, Q and E go down and up.
@MainActor
enum SandboxKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !(event.window?.firstResponder is NSText) else { return event }
            let digits: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8, 29: 9]
            // ⌘1 and the like belong to the app.
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if let k = digits[event.keyCode], Block.palette.indices.contains(k) { SandboxGame.shared.pick(Block.palette[k]); return nil }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 3 : 1
            let walks: [UInt16: (CGFloat, CGFloat, CGFloat)] = [13: (0, 1, 0), 126: (0, 1, 0), 1: (0, -1, 0), 125: (0, -1, 0),
                                                                0: (-1, 0, 0), 123: (-1, 0, 0), 2: (1, 0, 0), 124: (1, 0, 0), 12: (0, 0, -1), 14: (0, 0, 1)]
            if let (r, f, u) = walks[event.keyCode] { SandboxGame.shared.walk(right: r * step, forward: f * step, up: u * step); return nil }
            return event
        }
    }
    static func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}

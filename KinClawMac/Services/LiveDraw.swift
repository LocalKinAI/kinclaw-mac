import AppKit
import Foundation

/// 画给我看: an answer drawn as a live picture (「继续，做画给我看」, 2026-10-08). The answer comes in words, as
/// always; 「画给我看」 under it has Claude — this Mac's subscription, Claude Code — draw it in
/// huashu-art-motion's way: one idea made visible, 8–15 seconds of scenes drawn in code on huashu's
/// engine, with knobs to explore the idea, played right there in the conversation and kept in 活画.
///
/// Claude works in the drawing's own folder (<art>/live/<id>/engine), reads huashu's skill from the
/// shared copy (<art>/live/_huashu, fetched from the box once) and looks at its own drawing through
/// live_check — the same WebKit the person will watch it in — until it is right. OpenAI's Intelligent UI
/// (the same day) assembles answers from a component library; this one paints them.
@MainActor
final class LiveDraw: ObservableObject {
    static let shared = LiveDraw()

    /// huashu-art-motion's skill on this Mac, and its engine.
    static var skill: URL { LiveFilm.folder.appendingPathComponent("_huashu") }
    static var engine: URL { skill.appendingPathComponent("scripts/engine") }
    /// Where it lives on the box: one of OpenMontage's skills.
    static let boxSkill = "~/OpenMontage/.agents/skills/huashu-art-motion"

    struct Job: Identifiable {
        let id: String
        var message: UUID?
        let question: String
        let answer: String
        var state = State.drawing
        var step = "开始"
        var started = Date()
        var finished: Date?
        var session: String?
        var title: String?
        var poster: URL?
        var error: String?
        /// What the last check said.
        var report: String?
        /// Said out loud as soon as it is drawn (陪伴模式: she explains it while it moves).
        var narrate = false
        /// What its music is doing ("在作配乐"), nil when there is nothing to wait for.
        var scoring: String?

        enum State { case drawing, ready, failed }
    }

    @Published private(set) var jobs: [String: Job] = [:]
    @Published private(set) var byMessage: [UUID: String] = [:]
    /// The drawing that plays in a conversation now — one at a time; the others show a still.
    @Published private(set) var playing: String?
    let inline = LivePlayer()
    /// The player the check draws in, off screen.
    private let checker = LivePlayer()
    private var processes: [String: Process] = [:]

    private init() {}

    // MARK: - Drawing

    /// A drawing of an answer; its id at once, the picture in two to four minutes.
    @discardableResult
    func start(question: String, answer: String, message: UUID?, narrate: Bool = false) -> String {
        let id = "d\(Int(Date().timeIntervalSince1970))\(Int.random(in: 10...99))"
        var job = Job(id: id, message: message, question: question, answer: answer)
        job.narrate = narrate
        jobs[id] = job
        if let message { byMessage[message] = id }
        Task { await run(id, note: nil) }
        return id
    }

    /// 「改一下」: the same Claude conversation, told what to change.
    func revise(_ id: String, note: String) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, jobs[id] != nil, jobs[id]?.state != .drawing else { return }
        if playing == id { inline.pause() }
        Task { await run(id, note: note) }
    }

    /// 「再画一次」 after a failure: from the start, in a new folder of its own.
    func retry(_ id: String) {
        guard let job = jobs[id], job.state == .failed else { return }
        let fresh = start(question: job.question, answer: job.answer, message: job.message, narrate: job.narrate)
        if job.message == nil { jobs[fresh]?.message = nil }
    }

    func stop(_ id: String) {
        processes[id]?.terminate()
    }

    private func update(_ id: String, _ change: (inout Job) -> Void) {
        guard var job = jobs[id] else { return }
        change(&job)
        jobs[id] = job
    }

    private func run(_ id: String, note: String?) async {
        guard let job = jobs[id] else { return }
        func fail(_ text: String) { update(id) { $0.state = .failed; $0.error = text; $0.finished = Date() } }
        update(id) { $0.state = .drawing; $0.error = nil; $0.finished = nil; $0.started = Date(); $0.step = note == nil ? "想怎么画" : "照你说的改" }
        guard let binary = AgentHarness.claude.binary else { fail("这台 Mac 上没有 Claude Code"); return }
        if !FileManager.default.fileExists(atPath: Self.engine.appendingPathComponent("engine.js").path) {
            update(id) { $0.step = "从盒子拿 huashu 的画法（只这一次，25 MB）" }
            do { try await LiveFilm.fetch(Self.boxSkill, into: Self.skill, excluding: [".git", "tests", "reference_films"]) } catch {
                fail(error.localizedDescription)
                return
            }
        }
        let folder = LiveFilm.folder.appendingPathComponent(id).appendingPathComponent("engine")
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("scenes"), withIntermediateDirectories: true)
        let words = note.map { "改一下：\($0)\n\n改完照样用 live_check 看一遍，再答一行标题。" } ?? Self.ask(job)
        if let trouble = await claude(binary, id: id, folder: folder, words: words, resume: note == nil ? nil : job.session) {
            fail(trouble)
            return
        }
        update(id) { $0.step = "看一遍" }
        let (report, _) = await check(id, times: nil)
        guard checker.ready else { fail("画好了但跑不起来：\(report.prefix(600))"); return }
        let poster = LiveFilm.folder.appendingPathComponent(id).appendingPathComponent("poster.png")
        if let shot = try? await checker.frame(at: checker.total * 0.62, width: 960) { try? shot.png.write(to: poster) }
        let written = (try? String(contentsOf: folder.appendingPathComponent("title.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = written.isEmpty ? String(job.question.prefix(24)) : String(written.prefix(40))
        try? LiveFilm.write(LiveFilm.Film(id: id, title: title, film: id, fetched: Date(), base: Self.engine.path,
                                          kind: "drawing", question: job.question))
        LiveFilm.shared.reload()
        update(id) {
            $0.state = .ready; $0.title = title; $0.poster = poster; $0.finished = Date(); $0.report = report
        }
        if jobs[id]?.message != nil { activate(id) } else { await LiveFilm.shared.show(id) }
        // Its music, written on the box to its length while it already plays; then, in companion
        // mode, her voice over it.
        await score(id, folder: folder, seconds: checker.total)
        if jobs[id]?.narrate == true, note == nil {
            update(id) { $0.scoring = "写解说、念出来" }
            _ = try? await LiveOut.shared.narrate(id)
            update(id) { $0.scoring = nil }
        }
    }

    /// The music Claude asked for (music.txt), as long as the drawing, by ACE-Step on the box; the
    /// drawing then plays over it wherever it plays.
    private func score(_ id: String, folder: URL, seconds: Double) async {
        let brief = ((try? String(contentsOf: folder.appendingPathComponent("music.txt"), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty, var film = LiveFilm.shared.film(named: id), film.id == id else { return }
        update(id) { $0.scoring = "在盒子上作配乐（约一分钟）" }
        defer { update(id) { $0.scoring = nil } }
        guard await FilmStudio.aceOnBox() else { return }
        let music = LiveFilm.folder.appendingPathComponent(id).appendingPathComponent("music.wav")
        do {
            try await FilmStudio.composeACE(brief, seconds: seconds + 0.5, for: "live-\(id)", to: music)
        } catch {
            update(id) { $0.error = "配乐没作成：\(error.localizedDescription)" }
            return
        }
        film.music = "music.wav"
        if film.lines == nil { film.song = "music.wav" }
        try? LiveFilm.write(film)
        LiveFilm.shared.reload()
        LiveOut.shared.reloadPlayers(film)
    }

    /// The drawing plays in its card; the one that played before goes back to its still.
    func activate(_ id: String) {
        guard let film = LiveFilm.shared.film(named: id), film.kind == "drawing" else { return }
        playing = id
        LiveFilm.load(film, into: inline)
        Task { [inline] in
            await inline.untilReady()
            inline.play()
        }
    }

    // MARK: - Claude

    /// One `claude -p` in the drawing's folder, its steps shown as it goes; nil when it finished well,
    /// else what went wrong.
    private func claude(_ binary: String, id: String, folder: URL, words: String, resume: String?) async -> String? {
        let panel: [String: Any] = ["type": "stdio", "command": Bundle.main.executablePath ?? "",
                                    "args": ["--mcp-stdio", "--tools", "live_check", "--timeout", "300", "--images"]]
        let config = (try? JSONSerialization.data(withJSONObject: ["mcpServers": ["panel": panel]], options: .withoutEscapingSlashes))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var args = ["-p", "--output-format", "stream-json", "--verbose",
                    "--mcp-config", config, "--strict-mcp-config", "--setting-sources", "",
                    "--add-dir", Self.skill.path,
                    "--allowedTools", "Read,Glob,Grep,Write,Edit,mcp__panel__live_check",
                    "--disallowedTools", "Bash,WebFetch,WebSearch,Task,NotebookEdit",
                    "--append-system-prompt", Self.brief(id: id, skill: Self.skill.path)]
        if let resume { args += ["--resume", resume] }
        args.append(words)
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE") && !$0.key.hasPrefix("ANTHROPIC") }
        env["PATH"] = AgentLauncher.childPath(for: binary)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.currentDirectoryURL = folder
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return "Claude Code 起不来：\(error.localizedDescription)" }
        processes[id] = process
        // Fifteen minutes at most.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 900, execute: deadline)
        defer { deadline.cancel(); processes[id] = nil }

        let handle = out.fileHandleForReading
        var outcome: String? = "Claude 没说完就停了"
        for await event in Self.events(handle) {
            switch event["type"] as? String {
            case "system":
                if let session = event["session_id"] as? String { update(id) { $0.session = session } }
            case "assistant":
                let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                for item in content where item["type"] as? String == "tool_use" {
                    let step = Self.step(item["name"] as? String ?? "", item["input"] as? [String: Any] ?? [:])
                    update(id) { $0.step = step }
                }
            case "result":
                let said = event["result"] as? String ?? ""
                if event["is_error"] as? Bool == true || (event["subtype"] as? String ?? "success") != "success" {
                    outcome = "Claude：" + (said.isEmpty ? (event["subtype"] as? String ?? "出错了") : String(said.prefix(300)))
                } else {
                    outcome = nil
                }
            default:
                break
            }
        }
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal, outcome != nil { return "停了" }
        return outcome
    }

    /// Claude Code's stream-json, one event a line, read off the main thread.
    nonisolated private static func events(_ handle: FileHandle) -> AsyncStream<[String: Any]> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { continuation.yield(event) }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// What it is doing, in a few words.
    nonisolated private static func step(_ tool: String, _ input: [String: Any]) -> String {
        let path = (input["file_path"] as? String) ?? (input["path"] as? String) ?? (input["pattern"] as? String) ?? ""
        let name = (path as NSString).lastPathComponent
        switch tool {
        case "Read": return "在读 \(name)"
        case "Glob", "Grep": return "在找 \(name.isEmpty ? "文件" : name)"
        case "Write": return "在写 \(name)"
        case "Edit": return "在改 \(name)"
        case "mcp__panel__live_check": return "在看自己画的"
        case "ToolSearch": return "准备工具"
        default: return tool
        }
    }

    nonisolated private static func ask(_ job: Job) -> String {
        """
        他们问：\(job.question)

        回答（他们刚读到的）：
        \(job.answer.prefix(4000))

        画给他们看：把这个回答里最要紧的那个道理，画成一幅会动、能拧旋钮去试的画——是画，不是图表。
        """
    }

    nonisolated private static func brief(id: String, skill: String) -> String {
        """
        You draw a live, moving answer to a person's question — 画给我看 — with huashu-art-motion's engine: code that \
        draws every frame of a 1920×1080 canvas, played in their app in real time (60 fps, no sound) right under the \
        answer they read, with knobs they can turn. Not a film: one idea made visible, 8–15 seconds, one to three \
        shots, made in a few minutes. One direction — no options, no questions back.

        Where things are
        - The working directory is this drawing, id "\(id)". Write only here.
        - huashu's skill, to read and never to change: \(skill). Its engine is \(skill)/scripts/engine: lib/*.js — U \
        (util: clamp, lerp, ss, ease, rng, hash), MO (motion: smooth, seg, lagged, springs), CAM (a world canvas and a \
        camera), DG (diagrams: draw-on, Write, Transform, neurons, braces, the manim palette), TY (type: word pops, \
        counting, highlights), CH (charts, axes first), UI (keynote cards, glass, sheen), CL (collage), TOON (flat \
        cartoon), PAINT (noise, textures, cached layers, brushes, renderers, post) — and transitions.js (crossfade, \
        fadeShift, push, slidePush, zoomThrough, expandRect, blurPush, matchCut, whip, …). The explainer grammars: \
        references/09-视频动画语法.md, and one card each in references/动画语法/ — t1_3b1b (a concept or some maths, \
        one thing turning into the next), y3_whiteboard (steps, a process), y1_kurzgesagt (science, nature, scale), \
        t3_finance_chart (numbers that change), y5_kinetic_type (words, a quote, a list), t2_keynote_ui (a product, an \
        interface), y2_vox (history, causes), y4_storytime (a little story), y6_presenter_explainer — each with a worked \
        film in scripts/engine/demos/<grammar>/. For a picture in an art style: references/风格配方/INDEX.md and \
        scripts/engine/scenes/. Pick the one grammar that fits; read its card and its demo, and only the lib files you call.

        What to write
        - eras_\(id).js: window.PUNCH = 0; window.FILM_DURATION = <seconds>; window.ERAS = [{ id: '\(id)_1', dur: 5 }, \
        { id: '\(id)_2', dur: 5, transition: { type: 'fadeShift', dur: 0.6 } }]; and no SCENE_DIR.
        - scenes/\(id)_1.js and so on: (() => { SCENES['\(id)_1'] = { draw(c, lt, t) { … } }; })(); — lt is seconds into \
        the shot, t into the whole drawing. A frame is a pure function of t: no Math.random, no Date, nothing carried \
        from one frame to the next — seeded U.rng / U.hash; draw everything every frame and cache what never changes \
        with PAINT.cached.
        - live_\(id).js: one to three knobs that let them explore the idea — window.LIVE_KNOBS = [{ id, label, min, max, \
        value, step, apply(v) }], apply setting a global your scenes read every frame (window.K = { rate: 0.05 } …), so \
        that turning it changes the picture at once: the interest rate, the pendulum's length, how many planets. Labels \
        in their language, two to four characters. It is loaded after the scenes.
        - title.txt: one short line naming the drawing, in their language.
        - music.txt: one line for the music the box writes to its length (ACE-Step): genre, instruments, mood, tempo, \
        in English, made for the style — "guqin and bamboo flute, slow, misty, 70 bpm, instrumental" for ink; "gentle \
        piano and strings, warm, 90 bpm, instrumental" for Ghibli.

        How it should look: a painting, not a chart. Pick one of huashu's painting styles for it — references/风格配方/ \
        INDEX.md: ink 水墨, Ghibli, Monet, Van Gogh, ukiyo-e, Dunhuang, shadow puppets, Bauhaus, Kurzgesagt's flat \
        colour… — the one the subject asks for, and paint it as its card says (its scene in scripts/engine/scenes/ is a \
        worked example). Make the idea something seen: compound interest as a snowball gathering snow down an ink \
        mountain, not a line going up; a chart only when they asked for data. The grammar card still says how things \
        move and are shown. Words on screen in the language they wrote in, few and short; Chinese in "PingFang SC" (it \
        has every character) or the engine's NotoSansSC-700 / LXGWWenKai-500. Every movement has a purpose; one idea a \
        shot; nothing cut off by the frame or hidden under something else; the last shot holds the answer on screen.

        Check, then fix: after writing, call live_check with id "\(id)". It loads your drawing in the same WebKit they \
        will watch it in and answers with its errors, its speed and the frames at the times you give (default: four \
        across it), as pictures. Fix every error. Look at every frame as they will: is anything cut off, overlapping, \
        unreadable, empty, ugly or wrong? Fix it and check again — three rounds at most. Then answer with one line: the title.
        """
    }

    // MARK: - The check

    /// The drawing loaded off screen in the WebKit the person watches it in: what went wrong, how fast it
    /// draws, whether its knobs work, and the frames at `times` (default: four across it) as image:// lines.
    func check(_ id: String, times: [Double]?, knobs: [String: Double] = [:], script: String? = nil) async -> (String, Bool) {
        let folder = LiveFilm.folder.appendingPathComponent(id).appendingPathComponent("engine")
        guard id.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil,
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("eras_\(id).js").path) else {
            return ("没有这幅画：\(folder.path)/eras_\(id).js 不在", true)
        }
        checker.shelve()
        checker.load(folder, base: Self.engine, film: id)
        await checker.untilReady(seconds: 40)
        guard checker.ready else {
            let said = checker.errors.isEmpty ? "四十秒里没有画出第一帧" : checker.errors.prefix(12).joined(separator: "\n")
            return ("没画起来：\n\(said)", true)
        }
        let total = checker.total
        var lines = [String(format: "画起来了：%.1f 秒，%d 幕（%@）", total, checker.eras.count,
                            checker.eras.map { String(format: "%@ %.1f–%.1f 秒", $0.id, $0.t0, $0.t1) }.joined(separator: "，"))]
        // The knobs, each at its ends, mid-way through.
        if checker.knobs.isEmpty {
            lines.append("没有旋钮：live_\(id).js 里写 window.LIVE_KNOBS")
        } else {
            lines.append("旋钮：" + checker.knobs.map { "\($0.label)（\($0.id)）\($0.min)–\($0.max)，现在 \($0.value)" }.joined(separator: "；"))
            let before = checker.errors.count
            for knob in checker.knobs {
                for value in [knob.max, knob.min] {
                    checker.setKnob(knob.id, value)
                    _ = try? await checker.frame(at: total / 2, width: 320)
                }
                checker.setKnob(knob.id, knob.value)
            }
            if checker.errors.count > before { lines.append("拧到两头时出错了（见下面的错误）") }
        }
        // As asked: knobs set, then the film's own code called, before the frames are taken.
        for (knob, value) in knobs { checker.setKnob(knob, value) }
        if let script, !script.isEmpty {
            _ = try? await checker.view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        }
        if !knobs.isEmpty || script?.isEmpty == false {
            lines.append("先设了：\(knobs.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) \(script?.prefix(120) ?? "")")
        }
        let shots = LiveFilm.folder.appendingPathComponent(id).appendingPathComponent("check")
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let at = (times?.isEmpty == false ? times! : [0.12, 0.38, 0.64, 0.92].map { ($0 * total * 100).rounded() / 100 })
        var pictures: [String] = []
        for t in at {
            let t = min(max(0, t), total)
            guard let shot = try? await checker.frame(at: t, width: 960) else { lines.append(String(format: "%.2f 秒那一帧拿不到", t)); continue }
            let file = shots.appendingPathComponent(String(format: "t%06.2f.png", t))
            try? shot.png.write(to: file)
            if shot.spread < 4 { lines.append(String(format: "%.2f 秒那一帧几乎是一片纯色（亮度起伏 %.1f）", t, shot.spread)) }
            pictures.append("image://" + file.path)
        }
        if let speed = await checker.bench(Array(stride(from: 0.0, to: total, by: max(0.05, total / 40)))) {
            lines.append(String(format: "每帧：中位 %.1f ms，最慢 %.1f ms", speed.median, speed.worst)
                         + (speed.median > 16 ? "——超过 16 ms，实时会掉帧：不变的图层用 PAINT.cached，少用大半径的模糊" : ""))
        }
        let errors = checker.errors
        if !errors.isEmpty { lines.append("错误（\(errors.count)）：\n" + errors.prefix(15).joined(separator: "\n")) }
        return ((lines + pictures).joined(separator: "\n"), !errors.isEmpty)
    }

    /// The line for the tools.
    func report() -> String {
        guard !jobs.isEmpty else { return "还没有画给我看的画" }
        return jobs.values.sorted { $0.started > $1.started }.prefix(8).map { job in
            switch job.state {
            case .drawing: return "「\(job.question.prefix(30))」（\(job.id)）：在画，\(job.step)"
            case .ready: return "「\(job.title ?? job.id)」（\(job.id)）：画好了，在活画里"
            case .failed: return "「\(job.question.prefix(30))」（\(job.id)）：没画成，\(job.error ?? "")"
            }
        }.joined(separator: "\n")
    }
}

import AppKit
import Foundation

/// Pixelle-Video on the box, as a tab.
///
/// Pixelle-Video (AIDC-AI, Apache-2.0) makes a narrated short video from a
/// script: a scene a paragraph, one picture per scene from the box's ComfyUI
/// (Qwen Image 2.1 with the 8-step LoRA), each line read by the box's own
/// voices (:8102 makes a voice from a description, :8101 has presets), each
/// scene laid out on an HTML card with its subtitle, music under it, the
/// whole finished to −14 LUFS in one MP4. It runs on the box as an API on the
/// box's loopback only, and was worked from a terminal with a script of ours,
/// pv.py (ssh, curl over ssh, rsync back) — "Pixelle-Video这个太酷了，接近来独立
/// tab吧，agent可以操作那种". So the app carries that script and runs it: the
/// service's state, the job in progress as it goes, every video made with its
/// storyboard sheet, and the tab's own agent with the same steps as tools
/// (pixelle_*). The results land where the script always put them, the art
/// folder's pixelle/.
@MainActor
final class PixelleStudio: ObservableObject {
    static let shared = PixelleStudio()

    static var root: URL { CompanionArt.folder.appendingPathComponent("pixelle") }
    /// Pixelle's bundled music is an OC ReMix arrangement of Final Fantasy
    /// IX's "Melodies of Life": never under anything shown outside.
    static let forbiddenMusic = "default.mp3"
    static let defaultTemplate = "1080x1920/image_default.html"

    // MARK: State

    enum Service: Equatable { case unknown, up, down(String), starting, stopping }

    struct BoxJob: Equatable {
        let id: String
        let status: String
        let progress: String?
        let percent: Double?
    }

    /// The job this Mac is following: made here, or found running on the box.
    struct Job: Equatable {
        enum State: Equatable { case running, done, failed(String) }
        let id: String
        var title: String
        let started: Date
        var progress: String
        var percent: Double?
        /// pv.py's progress lines, as they came: "[  52s] frame_step 2/5 media 40%".
        var lines: [String] = []
        var state: State = .running
        /// ComfyUI busy with other tabs' work, when this job is waiting behind it.
        var waiting: String?
        var folder: URL?
        var sheet: URL?
        /// What the finished job said, for pixelle_wait.
        var summary: String?
    }

    struct Run: Identifiable, Equatable {
        struct Scene: Equatable {
            let narration: String
            let prompt: String?
            let seconds: Double?
        }
        let id: String
        let folder: URL
        let title: String
        let date: Date
        let seconds: Double?
        let template: String?
        let scenes: [Scene]
        let sheet: URL?
        /// The first scene's card, for a run without a sheet.
        let cover: URL?
        /// Read in one take (one narrator for the whole video), rather than line by line.
        var oneVoice = false
        /// How many scenes move (pan or LTX), and how.
        var moving = 0
        var motion: String?
        /// The output folder on the box this one was remade from (pixelle_rework).
        var remadeFrom: String?
        var video: URL { folder.appendingPathComponent("final.mp4") }
        /// The folder's name on the box: "20260928_093131_db14".
        var boxFolder: String { String(id.prefix { $0 != "-" }) }
        /// "一人配音 · 会动 5/5（ltx） · 重做自 …", or nil for a plain run.
        var remark: String? {
            var marks: [String] = []
            if oneVoice { marks.append("一人配音") }
            if moving > 0 { marks.append("会动 \(moving)/\(scenes.count)" + (motion.map { "（\($0)）" } ?? "")) }
            if let remadeFrom { marks.append("重做自 \(remadeFrom)") }
            return marks.isEmpty ? nil : marks.joined(separator: " · ")
        }
        /// Width over height, from the template's name ("1080x1920/…"); 9:16 when unknown.
        var aspect: CGFloat {
            guard let size = template?.split(separator: "/").first?.split(separator: "x"), size.count == 2,
                  let w = Double(size[0]), let h = Double(size[1]), h > 0 else { return 9.0 / 16.0 }
            return CGFloat(w / h)
        }
    }

    @Published private(set) var service: Service = .unknown
    @Published private(set) var checking = false
    /// ComfyUI's queue and the voices, as status last found them.
    @Published private(set) var comfy: String?
    @Published private(set) var voices: String?
    @Published private(set) var boxJobs: [BoxJob] = []
    @Published private(set) var checked: Date?
    @Published private(set) var runs: [Run] = []
    @Published private(set) var job: Job?
    @Published private(set) var note: String?
    /// The run the tab shows.
    @Published var selected: String?

    private var follower: Task<Void, Never>?
    private var following: String?

    private init() {}

    // MARK: pv.py

    struct Output: Sendable {
        let code: Int32
        let out: String
        let err: String
        var ok: Bool { code == 0 }
    }

    /// pv.py from the app's bundle, with this Mac's box and art folder: what
    /// it printed, its complaints and its exit code. Off the main thread;
    /// `line` hears each line it prints as it prints it (wait's progress).
    func pv(_ arguments: [String], input: Data? = nil, timeout: TimeInterval,
            line: (@Sendable (String) -> Void)? = nil) async -> Output {
        let box = BoxServices.ssh
        guard !box.isEmpty else { return Output(code: 2, out: "", err: "先在 设置 → Backend 里填盒子的 SSH（user@地址）") }
        guard let script = Bundle.main.url(forResource: "pv", withExtension: "py") else {
            return Output(code: 2, out: "", err: "这个版本的 app 里没有 pv.py")
        }
        var env = ProcessInfo.processInfo.environment
        // Homebrew's ffmpeg and ffprobe (the sheet, the duration) are not on
        // an app's PATH.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PIXELLE_BOX"] = box
        env["PIXELLE_OUT"] = Self.root.path
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        return await PixelleScript.run(script: script, arguments, environment: env, input: input, timeout: timeout, line: line)
    }

    /// What went wrong, in pv.py's words.
    nonisolated static func complaint(_ output: Output) -> String {
        var text = output.err.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("error: ") { text = String(text.dropFirst(7)) }
        if text.isEmpty { text = output.out.trimmingCharacters(in: .whitespacesAndNewlines) }
        if text.isEmpty { text = "pv.py 退出码 \(output.code)" }
        return String(text.suffix(1500))
    }

    /// The JSON pv.py printed last, after any progress lines: from the last
    /// line that opens a top-level object or list.
    nonisolated static func lastJSON(_ text: String) -> Any? {
        let lines = text.components(separatedBy: "\n")
        for start in lines.indices.reversed() where lines[start] == "{" || lines[start] == "[" {
            let candidate = lines[start...].joined(separator: "\n")
            if let value = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) { return value }
        }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: The service

    /// Is the API up, is ComfyUI busy, are the voices there, what is running.
    func refresh() async {
        // One look at a time; a second asker waits for the one under way.
        guard !checking else {
            for _ in 0..<800 where checking { try? await Task.sleep(nanoseconds: 200_000_000) }
            return
        }
        checking = true
        defer { checking = false }
        let result = await pv(["status"], timeout: 150)
        checked = Date()
        guard let report = Self.lastJSON(result.out) as? [String: Any] else {
            service = .down(Self.complaint(result))
            return
        }
        let api = (report["pixelle_api"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        service = api.hasPrefix("running") ? .up
            : .down(api.hasPrefix("not running") ? "没在跑" : String(api.split(separator: "\n").first ?? "没应答"))
        if let queue = report["comfyui"] as? [String: Any] {
            let running = queue["running"] as? Int ?? 0, pending = queue["pending"] as? Int ?? 0
            comfy = running + pending == 0 ? "空闲" : "在跑 \(running)，排队 \(pending)"
        } else {
            comfy = "没应答"
        }
        voices = ["8101", "8102"].map { port -> String in
            let health = report["tts_" + port] as? [String: Any]
            return port + ((health?["status"] as? String) == "healthy" ? " ✓" : " ✗")
        }.joined(separator: " · ")
        boxJobs = (report["jobs"] as? [[String: Any]] ?? []).map {
            BoxJob(id: $0["task_id"] as? String ?? "", status: $0["status"] as? String ?? "",
                   progress: $0["progress"] as? String, percent: FilmTools.number($0["percent"]))
        }
        // A job on the box that nobody here follows — the app restarted in the
        // middle of one, or a terminal started it: followed from now on.
        if let live = boxJobs.first(where: { $0.status == "running" || $0.status == "pending" }),
           !(job?.id == live.id && job?.state == .running && following == live.id) {
            follow(live.id)
        }
    }

    func start() async -> (String, Bool) {
        service = .starting
        let result = await pv(["start"], timeout: 150)
        await refresh()
        return result.ok ? (result.out.trimmingCharacters(in: .whitespacesAndNewlines), false) : (Self.complaint(result), true)
    }

    /// Refused while a job runs (it would be lost), unless `force`.
    func stop(force: Bool) async -> (String, Bool) {
        service = .stopping
        let result = await pv(["stop"] + (force ? ["--force"] : []), timeout: 90)
        await refresh()
        return result.ok ? (result.out.trimmingCharacters(in: .whitespacesAndNewlines), false) : (Self.complaint(result), true)
    }

    // MARK: Making one

    /// Send a job; it runs on the box, and this Mac follows it.
    func make(_ spec: [String: Any]) async -> Result<[String: Any], Failure> {
        guard let data = try? JSONSerialization.data(withJSONObject: spec) else { return .failure(Failure("写不成 JSON")) }
        let result = await pv(["make"], input: data, timeout: 120)
        guard result.ok, let answer = Self.lastJSON(result.out) as? [String: Any], let task = answer["task_id"] as? String else {
            return .failure(Failure(Self.complaint(result)))
        }
        job = Job(id: task, title: spec["title"] as? String ?? "", started: Date(), progress: "排队", percent: 0)
        follow(task)
        return .success(answer)
    }

    /// Remake a finished video from its own pictures (pv.py rework): the
    /// narration read again in one take, and/or scenes that move. The source
    /// stays; the result is a new run.
    func rework(_ spec: [String: Any]) async -> Result<[String: Any], Failure> {
        guard let data = try? JSONSerialization.data(withJSONObject: spec) else { return .failure(Failure("写不成 JSON")) }
        let result = await pv(["rework"], input: data, timeout: 120)
        guard result.ok, let answer = Self.lastJSON(result.out) as? [String: Any], let task = answer["task_id"] as? String else {
            return .failure(Failure(Self.complaint(result)))
        }
        job = Job(id: task, title: answer["title"] as? String ?? spec["title"] as? String ?? "", started: Date(),
                  progress: "排队", percent: 0)
        follow(task)
        return .success(answer)
    }

    /// LTX (the box's video service, :8001) up for moving scenes — started if
    /// it is not. Nil when it answers, else why not.
    func readyForMotion() async -> String? {
        await BoxServices.shared.ensure(.film) ? nil
            : "LTX（盒子上的出片服务 :8001）没起来：在 Settings → Backend → 盒子上的服务 里看看，或者先用 motion pan"
    }

    struct Failure: Error, LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    /// Follow a job until it is done: pv.py's wait, nine minutes at a time,
    /// its progress lines onto the tab as they come; done, its files copied
    /// here and the run shown.
    func follow(_ task: String) {
        if following == task, follower != nil { return }
        follower?.cancel()
        following = task
        if job?.id != task {
            job = Job(id: task, title: Self.title(ofJob: task) ?? "", started: Date(), progress: "在盒子上做", percent: nil)
        } else {
            job?.state = .running
        }
        follower = Task { [weak self] in
            await self?.followLoop(task)
        }
    }

    func isFollowing(_ task: String) -> Bool { following == task && follower != nil }

    private func followLoop(_ task: String) async {
        defer {
            if following == task { following = nil; follower = nil }
        }
        while !Task.isCancelled {
            let result = await pv(["wait", task, "--timeout", "540", "--every", "6"], timeout: 720) { [weak self] line in
                Task { @MainActor in self?.heard(line, from: task) }
            }
            guard !Task.isCancelled, following == task else { return }
            if result.ok, let answer = Self.lastJSON(result.out) as? [String: Any], answer["folder"] != nil {
                finished(task, answer)
                return
            }
            // Nine minutes up and the job still going: wait again.
            if result.ok, result.out.contains("still ") { continue }
            let why = Self.complaint(result)
            let settled = why.contains(" failed") || why.contains(" cancelled") || why.contains("job \(task)")
            job?.state = .failed(settled ? why : "跟丢了：\(why)（盒子上的任务可能还在跑：pixelle_wait 或刷新会接着跟）")
            job?.waiting = nil
            return
        }
    }

    private func heard(_ line: String, from task: String) {
        guard job?.id == task, job?.state == .running else { return }
        let text = line.trimmingCharacters(in: .whitespaces)
        // Progress lines only: "[  52s] frame_step 2/5 media 40%". The JSON at
        // the end is read whole when pv.py is done.
        guard text.hasPrefix("["), let close = text.firstIndex(of: "]") else { return }
        job?.lines.append(text)
        if (job?.lines.count ?? 0) > 300 { job?.lines.removeFirst(100) }
        var rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("still on") {
            job?.waiting = rest
            return
        }
        if let at = rest.range(of: #"\s\d+%$"#, options: .regularExpression) {
            job?.percent = Double(rest[at].trimmingCharacters(in: CharacterSet(charactersIn: " %")))
            rest = String(rest[..<at.lowerBound])
        }
        job?.progress = rest
        job?.waiting = nil
    }

    private func finished(_ task: String, _ answer: [String: Any]) {
        let folder = (answer["folder"] as? String).map { URL(fileURLWithPath: $0) }
        job?.state = .done
        job?.progress = "好了"
        job?.percent = 100
        job?.waiting = nil
        job?.folder = folder
        job?.sheet = (answer["sheet"] as? String).map { URL(fileURLWithPath: $0) }
        job?.summary = Self.describe(answer)
        if let title = answer["title"] as? String, !title.isEmpty { job?.title = title }
        reload(select: folder?.lastPathComponent)
    }

    /// A finished job, in lines: the video, its length, loudness, and each
    /// scene's narration and the picture prompt used.
    nonisolated static func describe(_ answer: [String: Any]) -> String {
        var lines: [String] = []
        let seconds = FilmTools.number(answer["duration_s"])
        lines.append("做好了：「\(answer["title"] as? String ?? "")」" + (seconds.map { String(format: "，%.1f 秒", $0) } ?? ""))
        if let video = answer["video"] as? String { lines.append("视频：\(video)") }
        if let folder = answer["folder"] as? String { lines.append("文件夹：\(folder)（frames/ 里每个场景的图、声音、卡片）") }
        if let loudness = answer["loudness"] as? String { lines.append("响度：\(loudness)") }
        for scene in answer["scenes"] as? [[String: Any]] ?? [] {
            let n = FilmTools.int(scene["scene"]).map(String.init) ?? "?"
            let s = FilmTools.number(scene["seconds"]).map { String(format: "%.1f 秒", $0) } ?? ""
            lines.append("\(n) · \(s) · \(scene["narration"] as? String ?? "")")
            if let prompt = scene["image_prompt"] as? String { lines.append("    画面：\(prompt)") }
        }
        return lines.joined(separator: "\n")
    }

    /// The title pv.py kept with a job it sent (jobs/<task>.json).
    private static func title(ofJob task: String) -> String? {
        let file = root.appendingPathComponent("jobs/\(task).json")
        guard let data = try? Data(contentsOf: file),
              let spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return spec["title"] as? String
    }

    func cancel(_ task: String) async -> (String, Bool) {
        let result = await pv(["cancel", task], timeout: 60)
        guard result.ok else { return (Self.complaint(result), true) }
        return ("取消了 \(task)。已经交给 ComfyUI 的那张图还会在那边画完（pixelle_status 看队列）", false)
    }

    /// Stop following, as the app quits: the job goes on on the box.
    func shutdown() {
        follower?.cancel()
        follower = nil
        following = nil
        PixelleScript.terminateAll()
    }

    // MARK: The runs

    func reload(select: String? = nil) {
        let root = Self.root
        Task {
            let found = await Task.detached(priority: .utility) { Self.scan(root) }.value
            runs = found
            if let select, found.contains(where: { $0.id == select }) {
                selected = select
            } else if selected == nil || !found.contains(where: { $0.id == selected }) {
                selected = found.first?.id
            }
        }
    }

    /// The folders under pixelle/ with a finished video in them, newest first.
    nonisolated static func scan(_ root: URL) -> [Run] {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }
            .map { root.appendingPathComponent($0) }
            .filter { files.fileExists(atPath: $0.appendingPathComponent("final.mp4").path) }
            .map(read)
            .sorted { $0.date > $1.date }
    }

    nonisolated static func read(_ folder: URL) -> Run {
        let files = FileManager.default
        func json(_ name: String) -> [String: Any]? {
            (try? Data(contentsOf: folder.appendingPathComponent(name)))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        let saved = json("result.json")
        let result = saved?["result"] as? [String: Any]
        let request = saved?["request"] as? [String: Any]
        let meta = json("metadata.json")
        let input = meta?["input"] as? [String: Any]
        let board = json("storyboard.json")
        let title = [result?["title"], board?["title"], input?["title"]].compactMap { $0 as? String }.first { !$0.isEmpty }
            ?? folder.lastPathComponent
        let frames = (result?["frames"] as? [[String: Any]]) ?? (board?["frames"] as? [[String: Any]]) ?? []
        let scenes = frames.map {
            Run.Scene(narration: $0["narration"] as? String ?? "", prompt: $0["image_prompt"] as? String,
                      seconds: FilmTools.number($0["duration"]))
        }
        let template = [input?["frame_template"], request?["frame_template"], (board?["config"] as? [String: Any])?["frame_template"]]
            .compactMap { $0 as? String }.first
        // When: the folder's own name (20260928_093131_…), else when it finished, else the folder's date.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        let named = stamp.date(from: String(folder.lastPathComponent.prefix(15)))
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let completed = (meta?["completed_at"] as? String).flatMap { iso.date(from: String($0.prefix(19))) }
        let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let sheet = folder.appendingPathComponent("sheet.png")
        let firstCard = folder.appendingPathComponent("frames/01_composed.png")
        var run = Run(id: folder.lastPathComponent, folder: folder, title: title, date: named ?? completed ?? modified,
                      seconds: FilmTools.number(result?["duration"]), template: template, scenes: scenes,
                      sheet: files.fileExists(atPath: sheet.path) ? sheet : nil,
                      cover: files.fileExists(atPath: firstCard.path) ? firstCard : nil)
        // What pixelle's LocalKin additions say they did: the voice, the motion, the source.
        let voice = (result?["voice"] as? [String: Any]) ?? (board?["voice"] as? [String: Any])
        let kept = (voice?["was"] as? [String: Any])?["mode"] as? String
        run.oneVoice = voice?["mode"] as? String == "one take" || kept == "one take"
        let moved = frames.compactMap { $0["motion"] as? String }.filter { !$0.hasPrefix("still") }
        run.moving = moved.count
        run.motion = moved.first.map { String($0.prefix { $0 != " " }) }
        run.remadeFrom = (result?["reworked_from"] as? String) ?? (board?["reworked_from"] as? String)
        return run
    }

    func run(named wanted: String) -> Run? {
        let w = wanted.trimmingCharacters(in: .whitespaces)
        return runs.first { $0.id == w || $0.folder.path == w || $0.title == w || $0.id.hasPrefix(w) }
    }

    // MARK: For the panel's tools

    var serviceLine: String {
        switch service {
        case .unknown: return "Pixelle API：还没看过"
        case .up: return "Pixelle API：在跑（盒子的 127.0.0.1:8190）"
        case .down(let why): return "Pixelle API：没在跑 —— \(why)"
        case .starting: return "Pixelle API：在起"
        case .stopping: return "Pixelle API：在停"
        }
    }

    var jobLines: [String] {
        guard let job else { return ["没有在跟的任务"] }
        let minutes = Int(Date().timeIntervalSince(job.started) / 60)
        switch job.state {
        case .running:
            return ["正在做：「\(job.title)」task \(job.id) —— \(job.progress)" + (job.percent.map { " \(Int($0))%" } ?? "")
                    + "（跟了 \(minutes) 分钟）"] + (job.waiting.map { ["  在排队：\($0)"] } ?? [])
        case .done:
            return ["上一个做好了：「\(job.title)」task \(job.id)" + (job.folder.map { " → \($0.path)" } ?? "")]
        case .failed(let why):
            return ["上一个没做成：「\(job.title)」task \(job.id) —— \(why)"]
        }
    }
}

/// pv.py as a process: its lines as they come, a time limit, and a register
/// of the ones running, so that the app's quitting takes them with it.
enum PixelleScript {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: [ObjectIdentifier: Process] = [:]

    static func terminateAll() {
        lock.lock()
        let all = Array(running.values)
        lock.unlock()
        all.forEach { if $0.isRunning { $0.terminate() } }
    }

    static func run(script: URL, _ arguments: [String], environment: [String: String], input: Data?,
                    timeout: TimeInterval, line: (@Sendable (String) -> Void)?) async -> PixelleStudio.Output {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", script.path] + arguments
                process.environment = environment
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                let feed = input == nil ? nil : Pipe()
                if let feed { process.standardInput = feed } else { process.standardInput = FileHandle.nullDevice }
                do { try process.run() } catch {
                    done.resume(returning: .init(code: 127, out: "", err: "python3 起不来：\(error.localizedDescription)"))
                    return
                }
                let id = ObjectIdentifier(process)
                lock.lock(); running[id] = process; lock.unlock()
                if let input, let feed {
                    feed.fileHandleForWriting.write(input)
                    try? feed.fileHandleForWriting.close()
                }
                let collected = Collected()
                let clock = DispatchWorkItem {
                    if process.isRunning { collected.timedOut = true; process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: clock)
                // Both pipes read to their end at once: one left full stops the other.
                let reading = DispatchGroup()
                reading.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let handle = out.fileHandleForReading
                    var pending = Data()
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        collected.printed.append(chunk)
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 0x0A) {
                            let text = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                            pending.removeSubrange(pending.startIndex...newline)
                            line?(text)
                        }
                    }
                    if !pending.isEmpty { line?(String(decoding: pending, as: UTF8.self)) }
                    reading.leave()
                }
                reading.enter()
                DispatchQueue.global(qos: .utility).async {
                    collected.complained = err.fileHandleForReading.readDataToEndOfFile()
                    reading.leave()
                }
                process.waitUntilExit()
                reading.wait()
                clock.cancel()
                lock.lock(); running[id] = nil; lock.unlock()
                var said = String(decoding: collected.complained, as: UTF8.self)
                if collected.timedOut { said += "\n（pv.py 超过 \(Int(timeout)) 秒，停了它；盒子上的事可能还在做）" }
                done.resume(returning: .init(code: collected.timedOut ? 124 : process.terminationStatus,
                                             out: String(decoding: collected.printed, as: UTF8.self), err: said))
            }
        }
    }

    /// What one run printed, filled from the threads that read it; read once
    /// they have finished.
    private final class Collected: @unchecked Sendable {
        var printed = Data()
        var complained = Data()
        var timedOut = false
    }
}

/// The Pixelle tab's tools, for its agent and the kernel.
@MainActor
enum PixelleTools {
    static func call(_ name: String, _ args: [String: Any]) async -> (String, Bool) {
        let studio = PixelleStudio.shared
        switch name {
        case "pixelle_status":
            await studio.refresh()
            studio.reload()
            let found = PixelleStudio.scan(PixelleStudio.root)
            var lines = [studio.serviceLine]
            if let comfy = studio.comfy { lines.append("ComfyUI（和 Film、Comfy、Montage 标签共用）：\(comfy)") }
            if let voices = studio.voices { lines.append("配音：\(voices)（8102 按描述造声音，8101 预设声音）") }
            lines += studio.jobLines
            let others = studio.boxJobs.filter { $0.status == "running" || $0.status == "pending" }
            if !others.isEmpty {
                lines.append("盒子上在做的：" + others.map { "\($0.id) \($0.status) \($0.progress ?? "")" }.joined(separator: "；"))
            }
            lines.append("做好的视频（\(PixelleStudio.root.path)）：")
            lines += found.prefix(5).map(runLine)
            if found.isEmpty { lines.append("  还没有") }
            return (lines.joined(separator: "\n"), false)

        case "pixelle_service":
            switch (args["action"] as? String ?? "").lowercased() {
            case "start": return await studio.start()
            case "stop": return await studio.stop(force: args["force"] as? Bool == true)
            case "restart":
                let stopped = await studio.stop(force: args["force"] as? Bool == true)
                if stopped.1 { return stopped }
                return await studio.start()
            default: return ("action 是 start、stop 或 restart", true)
            }

        case "pixelle_make":
            let spec: [String: Any]
            let notes: [String]
            switch makeSpec(args) {
            case .failure(let failure): return (failure.text, true)
            case .success(let made): spec = made.0; notes = made.1
            }
            if studio.job?.state == .running, let busy = studio.job {
                return ("已经有一个在做：「\(busy.title)」task \(busy.id)（\(busy.progress)）。等它做完（pixelle_wait），或者 pixelle_cancel", true)
            }
            if spec["scene_motion"] as? String == "ltx", let why = await studio.readyForMotion() { return (why, true) }
            switch await studio.make(spec) {
            case .failure(let failure): return ("没发出去：\(failure.text)", true)
            case .success(let answer):
                if PanelTools.place == nil || PanelTools.place == "pixelle" {
                    NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "pixelle", "raise": false])
                }
                var lines = ["开始做了：task \(answer["task_id"] as? String ?? "")，\(FilmTools.int(answer["scenes"]).map { "\($0) 个场景" } ?? "")。"
                             + "\(answer["estimate"] as? String ?? "")"]
                lines += notes + (answer["notes"] as? [String] ?? [])
                lines.append("跟着看：pixelle_wait（一次最多等 9 分钟，没好就再调；任务在盒子上接着做）。Pixelle 标签上有进度。")
                return (lines.joined(separator: "\n"), false)
            }

        case "pixelle_rework":
            studio.reload()
            let found = PixelleStudio.scan(PixelleStudio.root)
            let wanted = (args["run"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let run = wanted.isEmpty ? found.first
                    : found.first(where: { $0.id == wanted || $0.boxFolder == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) }) else {
                return (wanted.isEmpty ? "还没有做好的视频可以重做" : "没有这一个：\(wanted)（pixelle_runs 看有哪些）", true)
            }
            var spec: [String: Any] = ["source": run.boxFolder, "title": run.title]
            let revoice = args["revoice"] as? Bool == true
            spec["revoice"] = revoice
            for key in ["tts_instruct", "tts_voice", "tts_language"] {
                if let value = args[key] as? String { spec[key] = value }
            }
            if let url = args["tts_url"] { spec["tts_url"] = FilmTools.text(url) }
            if let speed = FilmTools.number(args["tts_speed"]) { spec["tts_speed"] = speed }
            let motion = (args["motion"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) ?? "none"
            guard ["none", "pan", "ltx"].contains(motion) else { return ("motion 是 none、pan（慢推慢移，几秒一个场景）或 ltx（真的动，约 3 分钟一个场景）", true) }
            spec["scene_motion"] = motion
            if let prompts = args["motion_prompts"] as? [Any] { spec["motion_prompts"] = prompts.map(FilmTools.text) }
            if let scenes = args["scenes"] as? [Any] { spec["scenes"] = scenes.compactMap(FilmTools.int) }
            if let bgm = args["bgm_path"] as? String {
                if (bgm as NSString).lastPathComponent == PixelleStudio.forbiddenMusic {
                    return ("default.mp3 不能用：它是 OC ReMix 改编的《最终幻想 IX》Melodies of Life，有版权", true)
                }
                spec["bgm_path"] = bgm
            }
            if let volume = FilmTools.number(args["bgm_volume"]) { spec["bgm_volume"] = volume }
            guard revoice || motion != "none" else { return ("没什么可重做的：revoice true（整篇一次念完、一个人）和／或 motion pan|ltx", true) }
            if studio.job?.state == .running, let busy = studio.job {
                return ("已经有一个在做：「\(busy.title)」task \(busy.id)（\(busy.progress)）。等它做完（pixelle_wait），或者 pixelle_cancel", true)
            }
            if motion == "ltx", let why = await studio.readyForMotion() { return (why, true) }
            switch await studio.rework(spec) {
            case .failure(let failure): return ("没发出去：\(failure.text)", true)
            case .success(let answer):
                if PanelTools.place == nil || PanelTools.place == "pixelle" {
                    NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "pixelle", "raise": false])
                }
                let moving = (answer["moving"] as? [Any] ?? []).compactMap(FilmTools.int)
                var lines = ["开始重做「\(run.title)」（\(run.boxFolder)）：task \(answer["task_id"] as? String ?? "")，"
                             + (revoice ? "整篇重新一次念完（一个人）" : "旁白不变")
                             + (moving.isEmpty ? "" : "，第 \(moving.map(String.init).joined(separator: "、")) 场会动（\(motion)）")
                             + "。\(answer["estimate"] as? String ?? "")"]
                lines.append("原来那支不动，做好的是一支新的。跟着看：pixelle_wait。")
                return (lines.joined(separator: "\n"), false)
            }

        case "pixelle_wait":
            let wanted = (args["task"] as? String)?.trimmingCharacters(in: .whitespaces)
            guard let task = (wanted?.isEmpty == false ? wanted : nil) ?? studio.job?.id else {
                return ("没有在做的视频", false)
            }
            // Done already: said at once. Otherwise followed, if nobody is.
            if !(studio.job?.id == task && studio.job?.state == .done), !studio.isFollowing(task) { studio.follow(task) }
            let seen = studio.job?.state == .running ? (studio.job?.lines.count ?? 0) : 0
            let limit = min(540, max(20, PanelTools.patience - 20))
            let started = Date()
            while studio.job?.id == task, studio.job?.state == .running, Date().timeIntervalSince(started) < limit {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard let job = studio.job, job.id == task else { return ("跟丢了 \(task)：pixelle_status 看看", true) }
            let progress = job.lines.count > seen ? Array(job.lines[seen...].suffix(12)) : []
            switch job.state {
            case .running:
                return ((progress + ["还在做：\(job.progress)" + (job.percent.map { " \(Int($0))%" } ?? "")
                                     + (job.waiting.map { "（\($0)）" } ?? "")
                                     + "。再调 pixelle_wait 接着等；任务在盒子上接着做"]).joined(separator: "\n"), false)
            case .failed(let why):
                return ((progress + ["没做成：\(why)"]).joined(separator: "\n"), true)
            case .done:
                var lines = progress + [job.summary ?? "做好了"]
                lines.append("先看 sheet（所有场景并排）再说好不好；给对方看视频：在 Pixelle 标签里已经选中了。")
                if let sheet = job.sheet { lines.append("image://\(sheet.path)") }
                return (lines.joined(separator: "\n"), false)
            }

        case "pixelle_cancel":
            let wanted = (args["task"] as? String)?.trimmingCharacters(in: .whitespaces)
            guard let task = (wanted?.isEmpty == false ? wanted : nil) ?? studio.job?.id else { return ("没有在做的任务", false) }
            return await studio.cancel(task)

        case "pixelle_image":
            guard let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
                return ("pixelle_image 要 prompt（英文，写画面里实际有的东西）", true)
            }
            var arguments = ["image", guarded(prompt)]
            if let prefix = (args["prefix"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty {
                arguments += ["--prefix", guarded(prefix)]
            }
            if let size = (args["size"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !size.isEmpty {
                guard size.range(of: #"^\d{3,4}x\d{3,4}$"#, options: .regularExpression) != nil else { return ("size 写成 1024x1024 这样", true) }
                arguments += ["--size", size]
            }
            if args["full"] as? Bool == true { arguments.append("--full") }
            let result = await studio.pv(arguments, timeout: max(30, PanelTools.patience - 15))
            guard result.ok, let answer = PixelleStudio.lastJSON(result.out) as? [String: Any], let picture = answer["picture"] as? String else {
                return ("没画成：\(PixelleStudio.complaint(result))。ComfyUI 被别的标签占着时要排队：pixelle_status 看队列", true)
            }
            return (["图：\(picture)（\(FilmTools.number(answer["seconds"]).map { String(format: "%.0f 秒", $0) } ?? "")，\(answer["workflow"] as? String ?? "")）",
                     "用的 prompt：\(answer["prompt_used"] as? String ?? prompt)",
                     "image://\(picture)"].joined(separator: "\n"), false)

        case "pixelle_voice":
            guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return ("pixelle_voice 要 text（一句要读的话）", true)
            }
            var arguments = ["voice", guarded(text)]
            if let instruct = args["instruct"] as? String { arguments += ["--instruct", guarded(instruct)] }
            if let speaker = (args["speaker"] as? String)?.trimmingCharacters(in: .whitespaces), !speaker.isEmpty { arguments += ["--speaker", speaker] }
            if let url = args["tts_url"] { arguments += ["--url", FilmTools.text(url)] }
            if let speed = FilmTools.number(args["speed"]) { arguments += ["--speed", String(speed)] }
            if args["check"] as? Bool != false { arguments.append("--check") }
            let result = await studio.pv(arguments, timeout: max(30, PanelTools.patience - 15))
            guard result.ok, let answer = PixelleStudio.lastJSON(result.out) as? [String: Any], let audio = answer["audio"] as? String else {
                return ("没读成：\(PixelleStudio.complaint(result))", true)
            }
            var lines = ["声音：\(audio)，\(FilmTools.number(answer["duration"]).map { String(format: "%.1f 秒", $0) } ?? "时长不明")"
                         + "（\(FilmTools.number(answer["seconds"]).map { String(format: "%.0f 秒", $0) } ?? "")做完）"]
            if let heard = answer["heard"] { lines.append("盒子的语音识别听到的：\(FilmTools.text(heard))（和原文不一样的地方就是读错的：改字或写成要读的样子）") }
            return (lines.joined(separator: "\n"), false)

        case "pixelle_templates":
            let result = await studio.pv(["templates"], timeout: 120)
            guard result.ok, let answer = PixelleStudio.lastJSON(result.out) as? [String: Any] else { return (PixelleStudio.complaint(result), true) }
            var lines = ["模板（frame_template）：视频尺寸 · 类型 · 可改的字段（template_params）。盒子上只能用 image_（每个场景一张 AI 图）和 static_（纯文字，不用 ComfyUI）。"]
            for t in answer["templates"] as? [[String: Any]] ?? [] {
                let params = (t["params"] as? [String] ?? []).joined(separator: ", ")
                lines.append("· \(t["template"] as? String ?? "") · \(t["kind"] as? String ?? "")" + (params.isEmpty ? "" : " · \(params)"))
            }
            lines.append("音乐（bgm_path）：" + (answer["bgm"] as? [String] ?? []).map { $0 == PixelleStudio.forbiddenMusic ? "\($0)（有版权，不能用）" : $0 }.joined(separator: "、"))
            lines.append("出图流程（media_workflow）：fast = 8 步（默认，约 45 秒一张）、full = 25 步（约 2 分钟一张）")
            return (lines.joined(separator: "\n"), false)

        case "pixelle_voices":
            let result = await studio.pv(["voices"], timeout: 60)
            guard result.ok, let answer = PixelleStudio.lastJSON(result.out) as? [String: Any] else { return (PixelleStudio.complaint(result), true) }
            var lines = ["默认 8102（tts_url 8102）：按 tts_instruct 的描述造声音，例如「中年男性科普纪录片旁白，嗓音沉稳温暖，吐字清晰，语速适中」。它每次调用都会造一个新声音，所以整篇稿子一次念完、再在句与句之间的停顿处切开（one_take，默认开）：全片是同一个人。one_take false 就逐句念，每句像换了个人。"]
            let presets = (answer["presets_8101"] as? [String: Any])?["voices"] as? [[String: Any]] ?? []
            lines.append("8101 预设声音（tts_url 8101，tts_voice = id，tts_instruct 留空或写语气）：" + presets.map { "\($0["id"] as? String ?? "")（\($0["name"] as? String ?? "")）" }.joined(separator: "、"))
            return (lines.joined(separator: "\n"), false)

        case "pixelle_runs":
            studio.reload()
            let found = PixelleStudio.scan(PixelleStudio.root)
            if found.isEmpty { return ("还没有做好的视频（\(PixelleStudio.root.path)）", false) }
            let wanted = (args["run"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let chosen = wanted.isEmpty ? found.first : found.first { $0.id == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) || $0.folder.path == wanted }
            guard let chosen else { return ("没有这一个：\(wanted)", true) }
            let limit = max(1, FilmTools.int(args["limit"]) ?? 10)
            var lines = ["做好的视频（新的在前）："] + found.prefix(limit).map(runLine)
            lines.append("")
            lines.append("「\(chosen.title)」\(chosen.folder.path)" + (chosen.remark.map { "（\($0)）" } ?? ""))
            lines += chosen.scenes.enumerated().map { i, s in
                "\(i + 1) · \(s.seconds.map { String(format: "%.1f 秒", $0) } ?? "") · \(s.narration)"
            }
            if let sheet = chosen.sheet { lines.append("image://\(sheet.path)") }
            return (lines.joined(separator: "\n"), false)

        default:
            return ("没有叫 \(name) 的 Pixelle 工具", true)
        }
    }

    private static func runLine(_ run: PixelleStudio.Run) -> String {
        let when = DateFormatter()
        when.dateFormat = "MM-dd HH:mm"
        return "· \(when.string(from: run.date)) 「\(run.title)」" + (run.seconds.map { String(format: " %.1f 秒", $0) } ?? "")
            + " · \(run.scenes.count) 个场景" + (run.remark.map { " · \($0)" } ?? "") + " · \(run.video.path)"
    }

    /// argparse takes a word that starts with "-" for an option.
    private static func guarded(_ text: String) -> String { text.hasPrefix("-") ? " " + text : text }

    /// The job, from the tool's arguments: Pixelle's own field names, checked
    /// before anything goes to the box.
    static func makeSpec(_ args: [String: Any]) -> Result<([String: Any], [String]), PixelleStudio.Failure> {
        typealias Failure = PixelleStudio.Failure
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .failure(Failure("pixelle_make 要 text：稿子，一段一个场景，段与段之间空一行"))
        }
        var spec: [String: Any] = ["text": text]
        var notes: [String] = []
        let mode = (args["mode"] as? String)?.lowercased() ?? "fixed"
        guard mode == "fixed" || mode == "generate" else { return .failure(Failure("mode 是 fixed（稿子照写）或 generate（text 是题目，盒子上的模型写稿）")) }
        spec["mode"] = mode
        for key in ["title", "split_mode", "prompt_prefix", "tts_instruct", "tts_voice", "tts_language", "bgm_mode"] {
            if let value = args[key] as? String { spec[key] = value }
        }
        if let prompts = args["image_prompts"] as? [Any] {
            spec["image_prompts"] = prompts.map(FilmTools.text)
        } else if mode == "fixed" {
            notes.append("没给 image_prompts：盒子上的模型会照稿子自己写画面描述（又长又花哨，比喻会被照字面画出来）。最好自己写")
        }
        if let n = FilmTools.int(args["n_scenes"]) { spec["n_scenes"] = n }
        if let workflow = (args["media_workflow"] as? String)?.trimmingCharacters(in: .whitespaces), !workflow.isEmpty {
            switch workflow.lowercased() {
            case "fast": spec["media_workflow"] = "selfhost/image_qwen21_box.json"
            case "full": spec["media_workflow"] = "selfhost/image_qwen21_box_full.json"
            default: spec["media_workflow"] = workflow
            }
        }
        let template = (args["frame_template"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        spec["frame_template"] = template.isEmpty ? PixelleStudio.defaultTemplate : template
        let kind = ((spec["frame_template"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? ""
        guard kind.hasPrefix("image_") || kind.hasPrefix("static_") else {
            return .failure(Failure("盒子上只能用 image_ 和 static_ 模板：video_ 要视频工作流（盒子上没有），asset_ 要你自己的素材。pixelle_templates 看全部"))
        }
        if let params = args["template_params"] as? [String: Any] {
            spec["template_params"] = params.mapValues(FilmTools.text)
        } else {
            notes.append("没给 template_params：模板页脚会是 Pixelle 自己的署名（@Pixelle.AI 之类）。用 author/brand/describe/signature 改掉（\"\" 隐藏），pixelle_templates 看这个模板有哪些字段")
        }
        if let url = args["tts_url"] { spec["tts_url"] = FilmTools.text(url) }
        if let bgm = (args["bgm_path"] as? String)?.trimmingCharacters(in: .whitespaces), !bgm.isEmpty {
            if (bgm as NSString).lastPathComponent == PixelleStudio.forbiddenMusic {
                return .failure(Failure("default.mp3 不能用：它是 OC ReMix 改编的《最终幻想 IX》Melodies of Life，有版权。用 localkin-wonder-33s.wav，或者不要音乐（不给 bgm_path）"))
            }
            spec["bgm_path"] = bgm
        }
        for key in ["tts_speed", "bgm_volume", "loudness_lufs"] {
            if let value = FilmTools.number(args[key]) { spec[key] = value }
        }
        if let fps = FilmTools.int(args["video_fps"]) { spec["video_fps"] = fps }
        if let master = args["master_audio"] as? Bool { spec["master_audio"] = master }
        if let oneTake = args["one_take"] as? Bool { spec["tts_one_take"] = oneTake }
        if let motion = (args["motion"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !motion.isEmpty {
            guard ["none", "pan", "ltx"].contains(motion) else {
                return .failure(Failure("motion 是 none（静止，默认）、pan（慢推慢移，几秒一个场景）或 ltx（真的动，约 3 分钟一个场景）"))
            }
            spec["scene_motion"] = motion
        }
        if let prompts = args["motion_prompts"] as? [Any] { spec["motion_prompts"] = prompts.map(FilmTools.text) }
        return .success((spec, notes))
    }
}

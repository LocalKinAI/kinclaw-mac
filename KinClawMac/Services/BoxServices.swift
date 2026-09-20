import Foundation

/// The model servers on the box, as things that can be started and stopped.
///
/// They used to be started by hand in an ssh session and lost at the next
/// reboot, which is how a film gets four minutes in before anybody finds out
/// the edit server is not there. They also do not all need to be running:
/// measured, the three diffusion servers cost five to eight gigabytes idle
/// between them and come up in three to six seconds, while a language model
/// left resident in kinfer costs thirty-five and has no way to be unloaded —
/// which is the difference between the high-quality video model fitting on
/// the box and not. So: started when something needs them, stopped when
/// asked, and visible either way.
///
/// Over ssh with the key the user already has — `BatchMode`, so it either
/// works silently or fails at once, never prompts — and the same way they
/// were started by hand: no launchd jobs, nothing installed on the box.
@MainActor
final class BoxServices: ObservableObject {
    static let shared = BoxServices()

    static let sshKey = "kinclaw.box.ssh"
    static let autoStartKey = "kinclaw.box.autostart"
    static let binaryKey = "kinclaw.box.diffuser"
    static let defaultBinary = "~/.ollamadiffuser/venv/bin/ollamadiffuser"

    enum Kind: String, CaseIterable { case draw, edit, film, filmHQ, brain, laya }

    struct Service: Identifiable, Equatable {
        let kind: Kind
        let title: String
        /// What it costs to have running, measured on the box it was built on.
        let cost: String
        var id: String { kind.rawValue }
    }

    static let all: [Service] = [
        Service(kind: .draw, title: "画图", cost: "空闲约 2 GB"),
        Service(kind: .edit, title: "改图 / 换装 / 空镜", cost: "用过之后约 8 GB"),
        Service(kind: .film, title: "出片", cost: "空闲不占，拍的时候约 25 GB"),
        Service(kind: .filmHQ, title: "出片 · 精修 (q8)", cost: "拍的时候约 45 GB，一个镜头 9 分钟"),
        Service(kind: .brain, title: "kinfer 大模型", cost: "模型常驻，35B 约 35 GB，不会自己卸载"),
        Service(kind: .laya, title: "Laya（打分 / 下棋）", cost: "约 2 GB；第一道题加载 5 秒，之后一道 23 ms"),
    ]

    enum State: Equatable { case unknown, up, down, starting, stopping }

    @Published private(set) var states: [Kind: State] = [:]
    @Published private(set) var memoryFree: Int?
    @Published private(set) var note: String?

    // MARK: - Where things are

    /// `user@host`. Empty means there is no box to control, and everything
    /// here is a no-op — the app works exactly as it did.
    static var ssh: String { (UserDefaults.standard.string(forKey: sshKey) ?? "").trimmingCharacters(in: .whitespaces) }
    static var autoStart: Bool { UserDefaults.standard.object(forKey: autoStartKey) as? Bool ?? true }

    /// The model each server runs. Overridable, because these are one
    /// person's choices and not the only ones that work.
    static func model(_ kind: Kind) -> String {
        let chosen = safe(UserDefaults.standard.string(forKey: "kinclaw.box.model.\(kind.rawValue)") ?? "")
        if !chosen.isEmpty { return chosen }
        switch kind {
        case .draw:   return "boogu-image-turbo-mlx"
        case .edit:   return "flux.2-klein-4b-edit-mlx"
        case .film:   return "ltx-2.3-mlx-q4"
        case .filmHQ: return "ltx-2.3-mlx-q8"
        case .brain:  return "ai.localkin.kinfer"          // a launchd label, not a model
        case .laya:   return "laya_judge.py"               // a script, not a model
        }
    }

    /// Where each one answers. The diffusion servers' addresses are the ones
    /// already in Settings; the high-quality one sits beside the video server.
    static func base(_ kind: Kind) -> String {
        switch kind {
        case .draw:   return DiffuserClient.host
        case .edit:   return DiffuserClient.editHost
        case .film:   return DiffuserClient.videoHost
        case .filmHQ: return replacingPort(of: DiffuserClient.videoHost, with: 8003)
        case .brain:
            let configured = OllamaCatalog.baseURL
            return configured == OllamaCatalog.defaultBaseURL
                ? replacingPort(of: DiffuserClient.videoHost, with: 11590) : configured
        case .laya:   return replacingPort(of: DiffuserClient.videoHost, with: 8005)
        }
    }

    /// The box's own Ollama, when there is a box: the same machine as the
    /// video server, on Ollama's port. Its local models (a 35B that this Mac
    /// would not want to hold) run on the box's memory and cost no cloud quota.
    static var ollama: String? {
        guard !ssh.isEmpty || !DiffuserClient.videoHost.contains("localhost") && !DiffuserClient.videoHost.contains("127.0.0.1") else { return nil }
        let address = replacingPort(of: DiffuserClient.videoHost, with: 11434)
        return address == OllamaCatalog.defaultBaseURL ? nil : address
    }

    /// "本机", "盒子", or the address: what to call an Ollama in a menu.
    static func place(of host: String) -> String {
        if host == OllamaCatalog.defaultBaseURL { return "本机" }
        if let box = ollama, host == box { return "盒子" }
        return host.replacingOccurrences(of: "http://", with: "")
    }

    private static func replacingPort(of address: String, with port: Int) -> String {
        guard var parts = URLComponents(string: address) else { return address }
        parts.port = port
        return parts.string ?? address
    }

    private static func port(_ kind: Kind) -> Int { URLComponents(string: base(kind))?.port ?? 0 }

    // MARK: - Looking

    /// Ask each one whether it is there. Plain HTTP, no ssh: this is what
    /// runs on a timer while Settings is open.
    func refresh() async {
        await withTaskGroup(of: (Kind, Bool).self) { group in
            for service in Self.all {
                let kind = service.kind
                group.addTask { (kind, await Self.answers(kind)) }
            }
            for await (kind, up) in group {
                let now = states[kind] ?? .unknown
                if now == .starting && !up { continue }        // still coming up
                if now == .stopping && up { continue }         // still going down
                states[kind] = up ? .up : .down
            }
        }
    }

    nonisolated private static func answers(_ kind: Kind) async -> Bool {
        let path = kind == .brain ? "/api/tags" : kind == .laya ? "/health" : "/api/health"
        guard let url = await URL(string: base(kind) + path) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// How much of the box's memory is free, which is the number that decides
    /// whether the big video model will fit.
    func refreshMemory() async {
        guard !Self.ssh.isEmpty else { memoryFree = nil; return }
        let (code, output) = await Self.run("memory_pressure | grep -i 'free percentage'")
        guard code == 0, let digits = output.split(separator: ":").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: " %\n")), let value = Int(digits) else { return }
        memoryFree = value
    }

    // MARK: - Doing

    func start(_ kind: Kind) async {
        guard !Self.ssh.isEmpty else { note = "先填盒子的 SSH（user@地址）"; return }
        states[kind] = .starting
        note = nil
        let command: String
        if kind == .brain {
            command = "launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/\(Self.model(.brain)).plist 2>&1; true"
        } else if kind == .laya {
            // Its own virtualenv under ~/.kinclaw/laya — not the diffusion
            // servers', whose torch and transformers it has no business moving.
            // On the box because it is a quarter of the time there (23 ms a
            // question on its GPU, against 150–490 on this Mac's CPU) and
            // because two resident checkpoints are this Mac's gigabyte and a half.
            command = """
                pgrep -f laya_judge.py >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH LAYA_JUDGE_HOST=0.0.0.0 LAYA_JUDGE_PORT=\(Self.port(.laya)) \
                USE_TF=0 HF_HUB_OFFLINE=1 TOKENIZERS_PARALLELISM=false \
                nohup ~/.kinclaw/laya/venv/bin/python ~/.kinclaw/laya/laya_judge.py > ~/Library/Logs/kinclaw/laya.log 2>&1 & echo started; }
                """
        } else {
            let model = Self.model(kind), binary = Self.binary
            // The way they were always started by hand, with the two things
            // that went wrong doing it over ssh put right: Homebrew is not on
            // a non-interactive PATH (and the video model refuses to load
            // without ffmpeg), and a server with no log leaves no evidence.
            command = """
                pgrep -f "ollamadiffuser run \(model) " >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH nohup \(binary) run \(model) --host 0.0.0.0 --port \(Self.port(kind)) \
                > ~/Library/Logs/kinclaw/\(kind.rawValue).log 2>&1 & echo started; }
                """
        }
        let (code, output) = await Self.run(command)
        guard code == 0 else {
            states[kind] = .down
            note = "起不来：\(output.trimmingCharacters(in: .whitespacesAndNewlines).suffix(160))"
            return
        }
        // Up when it answers, not when the shell came back.
        for _ in 0..<45 {
            if await Self.answers(kind) { states[kind] = .up; await refreshMemory(); return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        states[kind] = .down
        note = "\(Self.all.first { $0.kind == kind }?.title ?? kind.rawValue) 启动了但 90 秒内没应答，看盒子上的 ~/Library/Logs/kinclaw/\(kind.rawValue).log"
    }

    func stop(_ kind: Kind) async {
        guard !Self.ssh.isEmpty else { note = "先填盒子的 SSH（user@地址）"; return }
        states[kind] = .stopping
        note = nil
        let command = kind == .brain
            ? "launchctl bootout gui/$(id -u)/\(Self.model(.brain)) 2>&1; true"
            : kind == .laya ? "pkill -f laya_judge.py; true"
            : "pkill -f \"ollamadiffuser run \(Self.model(kind)) \"; true"
        _ = await Self.run(command)
        for _ in 0..<10 {
            if !(await Self.answers(kind)) { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        states[kind] = await Self.answers(kind) ? .up : .down
        await refreshMemory()
    }

    /// Bring a service up if it is not, for something about to use it.
    /// True when it is answering afterwards. Without an ssh target, or with
    /// auto-start off, this only looks.
    func ensure(_ kind: Kind) async -> Bool {
        if await Self.answers(kind) { states[kind] = .up; return true }
        guard Self.autoStart, !Self.ssh.isEmpty else { return false }
        await start(kind)
        return states[kind] == .up
    }

    /// The high-quality video model needs the memory a resident language
    /// model is sitting on. Nil when there is room, or no way of telling.
    func roomForHQ() async -> String? {
        if await Self.answers(.brain) {
            return "kinfer 开着（模型常驻约 35 GB），q8 要 45 GB 放不下。先在 Settings → Backend → 盒子上的服务 里把它停掉"
        }
        await refreshMemory()
        if let free = memoryFree, free < 55 { return "盒子内存只剩 \(free)% 空闲，q8 要一半左右。先停掉点别的" }
        return nil
    }

    private static var binary: String {
        let chosen = safe(UserDefaults.standard.string(forKey: binaryKey) ?? "")
        return chosen.isEmpty ? defaultBinary : chosen
    }

    /// These end up inside a shell command on another machine. A model name
    /// or a path has no business containing anything a shell would act on.
    private static func safe(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/~-")
        return String(text.unicodeScalars.filter { allowed.contains($0) })
    }

    /// One command on the box. `BatchMode`: a key that works, or a failure —
    /// never a password prompt from inside an app.
    nonisolated static func run(_ command: String) async -> (Int32, String) {
        let target = await ssh
        guard !target.isEmpty else { return (255, "no ssh target") }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                // No accept-new: a box this Mac has never spoken to is refused,
                // with ssh's own words, rather than trusted by an app on the
                // user's behalf. Connecting once by hand is how it gets known.
                process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=6", target, command]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() } catch {
                    continuation.resume(returning: (255, error.localizedDescription)); return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}

import Foundation
import Network

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

    enum Kind: String, CaseIterable { case draw, edit, flux, film, filmHQ, brain, laya, comfy, narrator, clone, turn, omni, face }

    struct Service: Identifiable, Equatable {
        let kind: Kind
        let title: String
        /// What it costs to have running, measured on the box it was built on.
        let cost: String
        var id: String { kind.rawValue }
    }

    static let all: [Service] = [
        Service(kind: .draw, title: "画图（Qwen-Image-2.1-Turbo）", cost: "画过一张后约 29 GB；和改图、FLUX 3 轮流，起一个先停另一个；闲 10 分钟盒子控制台会停掉它"),
        Service(kind: .edit, title: "改图 / 换装 / 空镜（Qwen-Image-2.1-Turbo）", cost: "改过一张后约 30 GB；和画图、FLUX 3 轮流，换一次约 10 秒；闲 10 分钟盒子控制台会停掉它"),
        Service(kind: .flux, title: "画图 + 改图（FLUX 3 Image Klein）", cost: "画或改的时候约 37 GB，闲 10 分钟自己放掉模型（进程留着，几乎不占）；和 Qwen 的画图、改图轮流。短的要求先由盒子 Ollama 的 ornith 写成整段画面描述（约 23 GB，用完 2 分钟放掉）"),
        Service(kind: .film, title: "出片", cost: "空闲不占，拍的时候约 25 GB"),
        Service(kind: .filmHQ, title: "出片 · 精修 (q8)", cost: "拍的时候约 45 GB，一个镜头 9 分钟"),
        Service(kind: .brain, title: "kinfer 大模型", cost: "模型常驻，35B 约 35 GB，不会自己卸载"),
        Service(kind: .laya, title: "Laya（打分 / 下棋）", cost: "约 2 GB；第一道题加载 5 秒，之后一道 23 ms"),
        Service(kind: .comfy, title: "ComfyUI", cost: "空闲不占；跑工作流时装着那个工作流的模型，跑完留在内存里直到被让出来"),
        Service(kind: .narrator, title: "电影旁白（Qwen3-TTS 1.7B VoiceDesign）", cost: "约 3 GB；一段 100 字的旁白 9 秒读完。和对话用的快速语音（8101）分开"),
        Service(kind: .clone, title: "克隆声音（Qwen3-TTS 1.7B Base）", cost: "约 3 GB；几秒录音，就用那个人的声音说任何一种语言。视频翻译、用某段录音的声音做说话视频都靠它"),
        Service(kind: .turn, title: "陪伴小回合（Smart Turn + MaAI）", cost: "约 1 GB，只用 CPU；起来要一分钟。判断你说完没有、什么时候该嗯一声"),
        Service(kind: .face, title: "实时口型（Ditto 身体 + QuickTalk 嘴）", cost: "约 10 GB；起来要半分钟多。陪伴里「真人 · 实时口型」，每秒 20 帧"),
        Service(kind: .omni, title: "MiniCPM-o 全双工（陪伴的另一个大脑）", cost: "通话时约 14 GB，开摄像头约 23 GB，挂断后仍占着；不用就在这里停掉。只听盒子本机，经 ssh 隧道连"),
    ]

    enum State: Equatable { case unknown, up, down, starting, stopping }

    @Published private(set) var states: [Kind: State] = [:]
    @Published private(set) var memoryFree: Int?
    @Published private(set) var note: String?
    /// The last look at the box failed as "offline" while this Mac is online: the app is kept
    /// off the local network, and the services may be up. See `localNetworkBlocked`.
    @Published private(set) var blocked = false

    private init() { _ = Self.path }

    // MARK: - Kept off the local network

    /// This Mac's own network, watched from launch.
    nonisolated private static let path: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "kinclaw.box.path"))
        return monitor
    }()

    /// Whether a failed request to the box is macOS's Local Network permission rather than the
    /// box: "offline" (or no route to the host) while this Mac is online. Then curl and the
    /// system's python reach every service and the app reaches none — and the app said they were
    /// all down (Motion's notebook, 2026-09-29).
    nonisolated static func localNetworkBlocked(_ error: Error) -> Bool {
        let error = error as NSError
        let offline = error.domain == NSURLErrorDomain && error.code == NSURLErrorNotConnectedToInternet
        let noRoute = error.domain == NSPOSIXErrorDomain && error.code == Int(EHOSTUNREACH)
        return (offline || noRoute) && path.currentPath.status == .satisfied
    }

    static let blockedAdvice = "这台 Mac 上的 KinClaw 被挡在局域网外了：系统说「离线」，可这台 Mac 的网络是通的——是 macOS 的本地网络权限。"
        + "系统设置 → 隐私与安全性 → 本地网络，打开 KinClaw（盒子上的服务本身多半好好的）"

    private func setBlocked(_ value: Bool) { if blocked != value { blocked = value } }

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
        case .draw:   return "qwen-image-2.1-turbo-mlx"       // the same weights twice: its own 8-step
        case .edit:   return "qwen-image-2.1-turbo-edit-mlx"  // schedule to draw, its editor to change
        case .flux:   return "flux3_server.py"                // a script: FLUX 3 Image Klein on mflux, both 画 and 改
        case .film:   return "ltx-2.3-mlx-q4"
        case .filmHQ: return "ltx-2.3-mlx-q8"
        case .brain:  return "ai.localkin.kinfer"          // a launchd label, not a model
        case .laya:   return "laya_judge.py"               // a script, not a model
        case .comfy:  return "ComfyUI"                     // a program with its own models
        case .narrator: return "qwen3-tts:1.7b-voicedesign" // a kin audio model
        case .clone:  return "qwen3-tts:1.7b-base"         // a kin audio model that clones a voice
        case .turn:   return "kin-avatar/turn/server.py"   // a script, not a model
        case .omni:   return "llama-omni-server"           // llama.cpp-omni with MiniCPM-o 4.5 Q8_0
        case .face:   return "kin-avatar/face/server.py"   // QuickTalk (MuseTalk before) over a Ditto body
        }
    }

    /// Where each one answers. The diffusion servers' addresses are the ones
    /// already in Settings; the high-quality one sits beside the video server.
    static func base(_ kind: Kind) -> String {
        switch kind {
        case .draw:   return DiffuserClient.host
        case .edit:   return DiffuserClient.editHost
        case .flux:   return DiffuserClient.fluxHost
        case .film:   return DiffuserClient.videoHost
        case .filmHQ: return replacingPort(of: DiffuserClient.videoHost, with: 8003)
        case .brain:
            let configured = OllamaCatalog.baseURL
            return configured == OllamaCatalog.defaultBaseURL
                ? replacingPort(of: DiffuserClient.videoHost, with: 11590) : configured
        case .laya:   return replacingPort(of: DiffuserClient.videoHost, with: 8005)
        case .comfy:
            let set = (UserDefaults.standard.string(forKey: "kinclaw.comfy.url") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            return set.isEmpty ? replacingPort(of: DiffuserClient.videoHost, with: 8188) : set
        case .narrator:
            let set = (UserDefaults.standard.string(forKey: "kinclaw.film.narrator.url") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            return set.isEmpty ? replacingPort(of: DiffuserClient.videoHost, with: 8102) : set
        case .clone:  return replacingPort(of: DiffuserClient.videoHost, with: 8103)
        case .turn:   return replacingPort(of: DiffuserClient.videoHost, with: 8104)
        // Loopback on the box only (its firewall admits nothing else): reached
        // through OmniCall's ssh tunnel, and looked at over ssh.
        case .omni:   return replacingPort(of: DiffuserClient.videoHost, with: OmniCall.port)
        case .face:   return replacingPort(of: DiffuserClient.videoHost, with: LiveFace.port)
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
        if kind == .omni {
            let (code, _) = await run("curl -sf -m 2 http://127.0.0.1:\(OmniCall.port)/health >/dev/null")
            return code == 0
        }
        let path = kind == .brain ? "/api/tags" : (kind == .laya || kind == .narrator || kind == .clone || kind == .turn || kind == .face) ? "/health" : kind == .comfy ? "/system_stats" : "/api/health"
        guard let url = await URL(string: base(kind) + path) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            await shared.setBlocked(false)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            if localNetworkBlocked(error) { await shared.setBlocked(true); return false }
            // No answer within three seconds is not "off" when something is listening there: a
            // server busy generating or loading a model. Read as off, the next `ensure` would start
            // a second copy of it beside the first.
            if (error as? URLError)?.code == .timedOut, let host = url.host, let port = url.port {
                return await listening(host: host, port: port)
            }
            return false
        }
    }

    /// Whether anything takes a TCP connection at host:port within `seconds`.
    nonisolated static func listening(host: String, port: Int, seconds: Double = 2) async -> Bool {
        guard let endpoint = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpoint, using: .tcp)
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let lock = NSLock()
            var answered = false
            func finish(_ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !answered else { return }
                answered = true
                connection.cancel()
                done.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { finish(false) }
        }
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

    /// The other picture servers. Each of Qwen's holds all of
    /// Qwen-Image-2.1-Turbo, 29–30 GB once it has made a picture, FLUX 3 about
    /// 37 GB while it works, and the box cannot keep two beside ComfyUI and a
    /// language model (it went down once on memory, 2026-10-09) — so they take
    /// turns.
    private static func partners(_ kind: Kind) -> [Kind] {
        switch kind {
        case .draw: return [.edit, .flux]
        case .edit: return [.draw, .flux]
        case .flux: return [.draw, .edit]
        default:    return []
        }
    }

    func start(_ kind: Kind) async {
        guard !Self.ssh.isEmpty else { note = "先填盒子的 SSH（user@地址）"; return }
        // The ones not wanted are let go first: about 3 s to stop, and the next
        // picture spends about 8 s loading. DiffuserClient makes one picture at a
        // time, so the one let go is not in the middle of one of ours.
        for other in Self.partners(kind) where await Self.answers(other) { await stop(other) }
        states[kind] = .starting
        note = nil
        let command: String
        if kind == .brain {
            command = "launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/\(Self.model(.brain)).plist 2>&1; true"
        } else if kind == .comfy {
            // AIOHTTP_NOSENDFILE=1 is not a preference. With aiohttp's sendfile
            // on this Mac, every file ComfyUI sends over the network — its own
            // editor page, the templates, the pictures it made — arrives with
            // no HTTP headers in front of it (on the loopback it happens to be
            // fine, so it works on the box and fails everywhere else). Measured:
            // the same picture, sendfile on, "000 0 bytes"; off, 200 and 2.3 MB.
            command = """
                lsof -nP -iTCP:\(Self.port(.comfy)) -sTCP:LISTEN -t >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~/ComfyUI; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH AIOHTTP_NOSENDFILE=1 \
                nohup venv/bin/python main.py --listen 0.0.0.0 --port \(Self.port(.comfy)) > ~/Library/Logs/kinclaw/comfy.log 2>&1 & echo started; }
                """
        } else if kind == .narrator || kind == .clone {
            // The film narrator: kin audio serving a voice-design model — a
            // voice made from a description, for films; the companion's quick
            // conversational voice stays on its own server. The clone: the
            // same server with a model that speaks in a recording's voice.
            command = """
                pgrep -f "kin audio serve \(Self.model(kind)) " >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~/localkin-service-audio; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH nohup .venv/bin/kin audio serve \(Self.model(kind)) \
                --host 0.0.0.0 --port \(Self.port(kind)) > ~/Library/Logs/kinclaw/\(kind.rawValue).log 2>&1 & echo started; }
                """
        } else if kind == .omni {
            command = OmniCall.serveCommand
        } else if kind == .face {
            // Started with MuseTalk's python; it re-execs itself in its mouth's own
            // virtualenv (QuickTalk's is OpenTalking's) and keeps its path, so pgrep
            // can tell it from other server.py. The body clips are under looks/.
            command = """
                pgrep -f "\(Self.model(.face))" >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~/kin-avatar/face; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH PORT=\(Self.port(.face)) \
                nohup ~/kin-avatar/musetalk/.venv/bin/python ~/\(Self.model(.face)) > ~/Library/Logs/kinclaw/face.log 2>&1 & echo started; }
                """
        } else if kind == .turn {
            // The companion's mini-turns: its own virtualenv under ~/kin-avatar/turn
            // (Smart Turn's ONNX and MaAI's torch on the CPU), started by its full
            // path so that pgrep can tell it from any other server.py.
            command = """
                pgrep -f "\(Self.model(.turn))" >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~/kin-avatar/turn; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH PORT=\(Self.port(.turn)) \
                nohup .venv/bin/python ~/\(Self.model(.turn)) > ~/Library/Logs/kinclaw/turn.log 2>&1 & echo started; }
                """
        } else if kind == .flux {
            // FLUX 3 Image Klein in its own virtualenv under ~/.kinclaw/flux3
            // (mflux 0.23, set up by scripts/flux3) — not OllamaDiffuser's, whose
            // mflux the Qwen servers run on. One process does 画 and 改.
            command = """
                pgrep -f "\(Self.model(.flux))" >/dev/null && echo already || { \
                mkdir -p ~/Library/Logs/kinclaw; cd ~/.kinclaw/flux3; \
                PATH=/opt/homebrew/bin:/usr/local/bin:$PATH \
                nohup venv/bin/python \(Self.model(.flux)) --port \(Self.port(.flux)) > ~/Library/Logs/kinclaw/flux.log 2>&1 & echo started; }
                """
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
            : kind == .flux ? "pkill -f \"\(Self.model(.flux))\"; true"
            : kind == .comfy ? "lsof -nP -iTCP:\(Self.port(.comfy)) -sTCP:LISTEN -t | xargs kill 2>/dev/null; true"
            : kind == .narrator || kind == .clone ? "pkill -f \"kin audio serve \(Self.model(kind)) \"; true"
            : kind == .turn ? "pkill -f \"\(Self.model(.turn))\"; true"
            : kind == .face ? "pkill -f \"\(Self.model(.face))\"; true"
            : kind == .omni ? "lsof -nP -iTCP:\(OmniCall.port) -sTCP:LISTEN -t | xargs kill 2>/dev/null; true"
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

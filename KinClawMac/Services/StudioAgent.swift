import AppKit
import CryptoKit
import Foundation
import SwiftTerm

/// Which coding agent does the work: Claude Code, or Codex.
enum AgentHarness: String, Codable, CaseIterable {
    case claude, codex

    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var integration: AgentLauncher.Integration { self == .claude ? AgentLauncher.claudeCode : AgentLauncher.codex }
    /// The binary on this Mac, if it is installed.
    var binary: String? { AgentLauncher.available.first { $0.integration.id == integration.id }?.binary }
}

/// What the agent thinks with: where the model is served, and which one.
struct AgentBrain: Hashable, Codable {
    enum Source: String, Codable, CaseIterable {
        /// The harness's own account on this Mac: Claude Code's Claude
        /// subscription, Codex's ChatGPT sign-in.
        case account
        /// This Mac's Ollama.
        case macOllama
        /// The box's Ollama.
        case boxOllama
        /// The box's kinfer: its own local models, resident in the box's
        /// memory — the memory H3 and Qwen want when they run.
        case boxKinfer
    }

    var source: Source
    /// Empty for the account: its own default model.
    var model: String

    static let account = AgentBrain(source: .account, model: "")

    /// The base URL of the server for this brain; nil for the account.
    /// Ollama (0.34+) and kinfer serve both Anthropic's Messages API (for
    /// Claude Code) and OpenAI's Responses API (for Codex).
    @MainActor var endpoint: String? {
        let box = BrainCatalog.boxHost ?? "127.0.0.1"
        switch source {
        case .account: return nil
        case .macOllama: return OllamaCatalog.defaultBaseURL
        case .boxOllama: return "http://\(box):11434"
        case .boxKinfer: return "http://\(box):11590"
        }
    }

    @MainActor func title(for harness: AgentHarness) -> String {
        guard source == .account else { return model }
        let signed = BrainCatalog.shared.signedIn[harness]
        switch harness {
        case .claude:
            if signed == false { return "Claude（这台 Mac 没登录）" }
            return BrainCatalog.shared.claudeUsage ? "Claude（这台 Mac 的账号，按用量计费）" : "Claude（这台 Mac 的订阅）"
        case .codex:
            return signed == false ? "ChatGPT（Codex 没登录）" : "ChatGPT（Codex 的登录）"
        }
    }

    static func section(_ source: Source, for harness: AgentHarness) -> String {
        switch source {
        case .account: return harness == .claude ? "Claude Code 登录的账号" : "Codex 登录的账号"
        case .macOllama: return "这台 Mac 的 Ollama"
        case .boxOllama: return "盒子上的 Ollama"
        case .boxKinfer: return "盒子上的 kinfer（本地模型，常驻盒子内存；拍 H3 时会抢）"
        }
    }
}

/// Which models each source has, and how each harness is signed in — one
/// list for the agent's menus.
@MainActor
final class BrainCatalog: ObservableObject {
    static let shared = BrainCatalog()

    @Published private(set) var models: [AgentBrain.Source: [String]] = [:]
    /// Whether each harness is signed in on this Mac (nil: not known yet).
    @Published private(set) var signedIn: [AgentHarness: Bool] = [:]
    /// Claude Code's account here is billed by use rather than a subscription.
    @Published private(set) var claudeUsage = false
    private var loaded: Date?

    /// The box's address, from the ssh target the app already has.
    static var boxHost: String? {
        let target = BoxServices.ssh
        guard !target.isEmpty, let host = target.split(separator: "@").last else { return nil }
        return String(host)
    }

    /// Ask each place what it serves. At most once a minute.
    func refresh() async {
        if let loaded, Date().timeIntervalSince(loaded) < 60 { return }
        loaded = Date()
        var found: [AgentBrain.Source: [String]] = [:]
        found[.macOllama] = await OllamaCatalog.loadPresets(baseURL: OllamaCatalog.defaultBaseURL).map(\.model)
        if let box = Self.boxHost {
            found[.boxOllama] = await OllamaCatalog.loadPresets(baseURL: "http://\(box):11434").map(\.model)
            found[.boxKinfer] = await Self.kinfer("http://\(box):11590")
        }
        models = found
        // Only the kind of sign-in — never who, never a key.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claude = (try? JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".claude.json")))) as? [String: Any]
        let account = claude?["oauthAccount"] as? [String: Any]
        let billing = account?["billingType"] as? String ?? ""
        claudeUsage = account != nil && !(billing.hasPrefix("stripe_subscription") && !billing.contains("contracted"))
        let codex = (try? JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".codex/auth.json")))) as? [String: Any]
        signedIn = [.claude: account != nil, .codex: codex?["tokens"] != nil || codex?["OPENAI_API_KEY"] != nil]
    }

    /// kinfer's own models: its list also carries the Ollama models it can
    /// pass through, which are already under Ollama.
    private static func kinfer(_ host: String) async -> [String] {
        guard let url = URL(string: host + "/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]] else { return [] }
        return list.filter { ($0["owned_by"] as? String) == "kinfer" }.compactMap { $0["id"] as? String }
    }
}

/// The agents of the Studio's tabs — one for each, working that tab while you
/// watch: Claude Code or Codex in a terminal on this Mac, standing along the
/// tab's left, holding that tab's tools and nothing else.
///
/// The Montage tab showed the shape ("这个真的很酷啊……就是通过 agent 来操作"):
/// say what you want in a sentence, watch the agent work in its terminal and
/// the result land on the board beside it, answer when it asks. Film, Motion
/// and Comfy were boards already, and every step they take is a panel tool —
/// film_make, film_frames, film_reshoot, motion_make, comfy_run. Tried as one
/// agent for all of them, and taken back ("我后悔了……他们是独立分开的"): each tab
/// keeps its own, with its own conversation, its own brain, and its own folder,
/// so that "接着上一次" goes back to that tab's conversation and no other.
/// Each can be Claude Code or Codex ("应该也可以用 codex"), thinking with its own
/// sign-in or a model from this Mac's or the box's Ollama or the box's kinfer.
/// Montage's works OpenMontage on the box through a bridge started over ssh
/// (Resources/om_bridge.py) — here, so that it too can think on this Mac's
/// subscription.
@MainActor
final class StudioAgent: ObservableObject {
    enum Place: String, CaseIterable { case film, motion, comfy, montage }

    static let film = StudioAgent(.film)
    static let motion = StudioAgent(.motion)
    static let comfy = StudioAgent(.comfy)
    static let montage = StudioAgent(.montage)
    static let all = [film, motion, comfy, montage]

    static func of(_ place: Place) -> StudioAgent {
        switch place {
        case .film: return film
        case .motion: return motion
        case .comfy: return comfy
        case .montage: return montage
        }
    }

    let place: Place

    @Published var harness: AgentHarness {
        didSet {
            UserDefaults.standard.set(harness.rawValue, forKey: "kinclaw.agent.\(place.rawValue).harness")
            checkResumable()
        }
    }
    @Published var brain: AgentBrain {
        didSet {
            if let data = try? JSONEncoder().encode(brain) { UserDefaults.standard.set(data, forKey: "kinclaw.agent.\(place.rawValue).brain") }
        }
    }
    @Published private(set) var running = false
    @Published private(set) var note: String?
    /// The column is showing. Put away, a running agent keeps running.
    @Published var shown: Bool
    /// Its harness keeps a conversation of this tab's to go back to: what
    /// "接着上一次" and 重启 return to.
    @Published private(set) var resumable = false

    private(set) var terminal: LocalProcessTerminalView?
    private var relay: StudioAgentExitRelay?
    private var watcher: Task<Void, Never>?

    private init(_ place: Place) {
        self.place = place
        // Out on every tab, as on Montage's ("film, motion, comfy 可以打开就有
        // 一样和 montage 的 agent 打开着吗").
        shown = true
        let key = "kinclaw.agent.\(place.rawValue)"
        harness = AgentHarness(rawValue: UserDefaults.standard.string(forKey: key + ".harness") ?? "") ?? .claude
        if let data = UserDefaults.standard.data(forKey: key + ".brain"), let saved = try? JSONDecoder().decode(AgentBrain.self, from: data) {
            brain = saved
        } else {
            brain = .account
        }
        checkResumable()
    }

    var brainTitle: String { brain.title(for: harness) }
    var whereTitle: String { "\(harness.title) · 在这台 Mac 上" }

    /// Its own folder: where it works, what it opens, and where its harness
    /// keeps the conversations "接着上一次" goes back to.
    var folder: URL {
        switch place {
        case .film: return FilmStudio.root
        case .motion: return MotionStudio.root
        case .comfy: return ComfyStudio.root
        case .montage: return CompanionArt.folder.appendingPathComponent("montage")
        }
    }

    // MARK: Running it

    /// Start the agent, with the first thing to say to it — or, `continuing`,
    /// back in its last conversation (both harnesses keep them, by folder),
    /// waiting for the next word: an agent cut off by the app quitting picks
    /// up there. With none to go back to, it starts a new one and says so —
    /// not a terminal that only says "No conversation found to continue".
    func start(saying words: String? = nil, continuing: Bool = false) {
        stop()
        guard let binary = harness.binary else {
            note = "这台 Mac 上没装 \(harness.title)"
            shown = true
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        let relay = StudioAgentExitRelay { [weak self] code in
            Task { @MainActor in self?.exited(code) }
        }
        view.processDelegate = relay
        self.relay = relay
        terminal = view
        running = true
        shown = true
        note = nil
        let harness = self.harness, brain = self.brain, folder = self.folder
        Task { @MainActor in
            // Montage's bridge on the box first, so OpenMontage is there when it looks.
            if self.place == .montage { await OpenMontageBridge.ensure() }
            let session = continuing ? await Task.detached { Self.lastConversation(harness, in: folder) }.value : nil
            guard self.terminal === view else { return }           // stopped meanwhile
            if continuing && session == nil { self.note = "这个标签还没有可以接着的对话：开了一个新的" }
            let args = harness == .claude ? self.claudeArgs(binary, brain, words, session)
                                          : self.codexArgs(binary, brain, words, session)
            var env = Terminal.getEnvironmentVariables(termName: "xterm-256color").filter { !$0.hasPrefix("PATH=") }
            env.append("PATH=" + AgentLauncher.childPath(for: binary))
            if harness == .claude {
                // Aimed at a host as the Term tab aims it.
                if let endpoint = brain.endpoint {
                    for (key, value) in AgentLauncher.claudeCode.env(endpoint, brain.model).sorted(by: { $0.key < $1.key }) {
                        env.append("\(key)=\(value)")
                    }
                }
                // An H3 shot is ten minutes: a tool may take that long.
                env.append("MCP_TOOL_TIMEOUT=960000")
                env.append("MCP_TIMEOUT=30000")
            }
            // Through the login shell, as the Term tab starts an agent: our PATH
            // first, and whatever .zshrc sets for its children.
            view.startProcess(executable: AgentLauncher.loginShell,
                              args: ["-l", "-i", "-c", "exec " + args.map(AgentLauncher.shellQuoted).joined(separator: " ")],
                              environment: env,
                              currentDirectory: folder.path)
            if self.place == .montage { MontageStudio.shared.follow() }
            self.watchScreen()
        }
        if place == .montage { Task { await MontageStudio.shared.openBoard() } }
    }

    /// The MCP servers it is given: the panel's tools for this tab, served by
    /// this very binary and cut down to them; for Montage, the bridge. A panel
    /// call may take as long as its work does (a download, a render: fifteen
    /// minutes), and Claude Code is handed the pictures a tool names.
    private func servers(for harness: AgentHarness) -> [(name: String, command: String, args: [String])] {
        var list: [(String, String, [String])] = []
        if !panelTools.isEmpty {
            list.append(("panel", Bundle.main.executablePath ?? "",
                         ["--mcp-stdio", "--tools", panelTools.joined(separator: ","), "--timeout", "900"]
                            + (harness == .claude ? ["--images"] : [])))
        }
        if place == .montage, let bridge = OpenMontageBridge.server {
            list.append(("openmontage", bridge.command, bridge.args))
        }
        return list
    }

    private func claudeArgs(_ binary: String, _ brain: AgentBrain, _ words: String?, _ session: String?) -> [String] {
        var config: [String: Any] = [:]
        for server in servers(for: .claude) { config[server.name] = ["type": "stdio", "command": server.command, "args": server.args] }
        let json = (try? JSONSerialization.data(withJSONObject: ["mcpServers": config], options: .withoutEscapingSlashes))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var allowed = panelTools.map { "mcp__panel__" + $0 }
        if place == .montage { allowed += OpenMontageBridge.looking.map { "mcp__openmontage__" + $0 } }
        // The options that take several values go first, each ended by the
        // next option; the first words, if any, come last, after one that
        // takes exactly one — else they would be read as one more tool name.
        var args = [binary, "--mcp-config", json, "--strict-mcp-config"]
        if !allowed.isEmpty { args += ["--allowedTools", allowed.joined(separator: ",")] }
        args += ["--disallowedTools", "Edit,Write,NotebookEdit", "--append-system-prompt", briefing]
        if brain.source != .account { args += ["--model", brain.model] }
        if let session { args += ["--resume", session] }
        if let words, !words.isEmpty { args.append(words) }
        return args
    }

    /// Codex takes its servers, its provider and the briefing as config
    /// overrides; each value is TOML, and a JSON string or array is TOML.
    private func codexArgs(_ binary: String, _ brain: AgentBrain, _ words: String?, _ session: String?) -> [String] {
        func toml(_ value: Any) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
        var args = [binary]
        if let session { args += ["resume", session] }
        args += ["-C", folder.path, "-c", "developer_instructions=" + toml(briefing)]
        for server in servers(for: .codex) {
            args += ["-c", "mcp_servers.\(server.name).command=" + toml(server.command),
                     "-c", "mcp_servers.\(server.name).args=" + toml(server.args),
                     "-c", "mcp_servers.\(server.name).startup_timeout_sec=30",
                     "-c", "mcp_servers.\(server.name).tool_timeout_sec=960"]
        }
        if let endpoint = brain.endpoint {
            // As the Term tab points Codex at a host: a provider of our own,
            // on its Responses API.
            args += ["-c", "model_provider=kinhost",
                     "-c", "model_providers.kinhost.name=\"KinClaw host\"",
                     "-c", "model_providers.kinhost.base_url=" + toml(endpoint + "/v1"),
                     "-c", "model_providers.kinhost.wire_api=\"responses\"",
                     "--model", brain.model]
        }
        if let words, !words.isEmpty { args.append(words) }
        return args
    }

    /// Words for it: typed into its terminal if it is running, else the first
    /// thing it hears.
    func say(_ words: String) {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        shown = true
        guard running, let terminal else {
            // After it has stopped, what is said goes on in the conversation
            // still on its screen.
            start(saying: text, continuing: self.terminal != nil)
            return
        }
        // A question on its screen — whether to trust the folder, the first
        // time — takes the return below as its answer, and its default is
        // "No, exit". Nothing is typed over a question.
        if let question = Self.asking(terminal) {
            note = question
            return
        }
        note = nil
        terminal.send(txt: text)
        // The TUI takes a pasted line and a separate return as "send it".
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { terminal.send([13]) }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        if let terminal {
            terminal.processDelegate = nil     // an exit we caused is not news
            terminal.terminate()
        }
        terminal = nil
        relay = nil
        running = false
        if place == .montage { MontageStudio.shared.unfollow() }
        checkResumable()
    }

    /// `status` as waitpid gives it, which SwiftTerm hands on unchanged: the
    /// exit code in its second byte, or the signal that ended it in its first
    /// — "退出码 256" was an exit code of 1.
    private func exited(_ status: Int32?) {
        running = false
        watcher?.cancel()
        if place == .montage { MontageStudio.shared.unfollow() }
        let why = status.map { $0 & 0x7f == 0 ? "退出码 \(($0 >> 8) & 0xff)" : "被信号 \($0 & 0x7f) 结束" }
        note = "agent 停了" + (why.map { "（\($0)）" } ?? "")
        checkResumable()
    }

    // MARK: Its conversations

    /// Look again, off the main thread, whether there is a conversation to go back to.
    func checkResumable() {
        let harness = harness, folder = folder
        Task {
            let found = await Task.detached(priority: .utility) { Self.lastConversation(harness, in: folder) }.value
            if self.harness == harness { resumable = found != nil }
        }
    }

    /// The id of the latest conversation a harness keeps for a folder. Claude
    /// Code keeps each folder's in ~/.claude/projects, under the folder's path
    /// with every character but a letter or a digit made a dash; Codex keeps
    /// everyone's in ~/.codex/sessions, by day, each file starting with a line
    /// that names its folder. Codex's is resumed by that id: after `--last`,
    /// the words to say would be taken for one.
    nonisolated static func lastConversation(_ harness: AgentHarness, in folder: URL) -> String? {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let real = realPath(folder.path)
        switch harness {
        case .claude:
            let name = String(real.utf16.map { unit -> Character in
                switch unit {
                case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return Character(Unicode.Scalar(UInt8(unit)))
                default: return "-"
                }
            })
            let dir = home.appendingPathComponent(".claude/projects").appendingPathComponent(name)
            func modified(_ url: URL) -> Date {
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }
            let kept = (try? files.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return kept.filter { $0.pathExtension == "jsonl" }.max { modified($0) < modified($1) }?
                .deletingPathExtension().lastPathComponent
        case .codex:
            guard let walk = files.enumerator(at: home.appendingPathComponent(".codex/sessions"), includingPropertiesForKeys: nil) else { return nil }
            // Named by the time they began: sorted, the newest first.
            let rollouts = walk.compactMap { $0 as? URL }
                .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for file in rollouts.prefix(300) {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                // {"timestamp":…,"type":"session_meta","payload":{"session_id":…,"id":"…","timestamp":…,"cwd":"…"
                let head = String(decoding: (try? handle.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
                try? handle.close()
                guard let cwd = field("cwd", in: head), cwd == folder.path || cwd == real else { continue }
                return field("id", in: head)
            }
            return nil
        }
    }

    nonisolated private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// A string's value in a line of compact JSON, by its key.
    nonisolated private static func field(_ key: String, in json: String) -> String? {
        guard let start = json.range(of: "\"\(key)\":\"") else { return nil }
        let rest = json[start.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    /// For the first half minute, what the screen says that needs a person:
    /// a sign-in that has run out, a folder to trust.
    private func watchScreen() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, let terminal = self.terminal else { return }
                if let problem = Self.problem(terminal) ?? Self.asking(terminal) {
                    self.note = problem
                    return
                }
            }
        }
    }

    /// What an agent's terminal is asking, if it is asking something a
    /// return would answer: the folder-trust question, first of all.
    static func asking(_ terminal: LocalProcessTerminalView) -> String? {
        let screen = AgentTerminalSessions.visibleLines(terminal.getTerminal()).joined(separator: "\n")
        if screen.contains("trust this folder") || screen.contains("trust the contents") || screen.contains("Do you trust") {
            return "它在问信不信任这个文件夹（第一次都会问）：在终端里选信任"
        }
        if screen.contains("Enter to confirm") || screen.contains("Do you want to proceed?") {
            return "它在等你回答一个问题：先在终端里选好，再说"
        }
        return nil
    }

    /// What has gone wrong that only the person can put right.
    static func problem(_ terminal: LocalProcessTerminalView) -> String? {
        let screen = AgentTerminalSessions.visibleLines(terminal.getTerminal()).joined(separator: "\n")
        let signs = ["session expired", "Please run /login", "Invalid API key", "Not logged in", "Failed to authenticate",
                     "Sign in with ChatGPT", "codex login"]
        if signs.contains(where: screen.contains) {
            return "要登录：Claude Code 在终端里输入 /login；Codex 按它屏幕上说的登 ChatGPT（都会打开浏览器）。或者换一个脑子"
        }
        return nil
    }

    // MARK: What it is given

    /// The tab's panel tools, and what they lean on. The panel's others — the
    /// browser the person is signed into, their terminals, her body, the
    /// games — never reach it: the relay serves only these
    /// (`--mcp-stdio --tools`). Montage's has none: its tools are the bridge's.
    var panelTools: [String] {
        let studio = ["panel_show", "box_services", "image_generate", "video_generate", "video_status"]
        let comfy = ["comfy_templates", "comfy_run", "comfy_import", "comfy_status", "comfy_stop"]
        let film = ["film_guide", "film_make", "film_status", "film_shot", "film_edit", "film_cast", "film_continue",
                    "film_frames", "film_count", "film_fix_picture", "film_grade", "film_reshoot", "film_recut",
                    "film_rescore", "film_review", "film_stop"]
        switch place {
        case .film: return film + comfy + studio
        case .motion: return ["motion_find", "motion_make", "motion_status", "motion_stop", "motion_continue", "video_frames"] + studio
        case .comfy: return comfy + ["video_frames"] + studio
        case .montage: return []
        }
    }

    private static let seeing = """
        Tools that show you something hand you the picture itself (a line `image://<path>` names it; if a picture \
        did not come with it, open that file). Look before you say anything about it — every frame you are \
        shown — and count what the story counts. A reviewer's score is not proof.
        """

    var briefing: String {
        switch place {
        case .film:
            return """
                You direct short films in the KinClaw app's Film tab, on the person's Mac. They watch the tab beside \
                this terminal: the storyboard, every still and clip as it lands, and the cut appear there by \
                themselves. You work through the panel's film tools (mcp__panel__film_*). Call film_guide once before \
                anything else and follow it: it is the method this studio's films are made by, learned the hard way. \
                \(Self.seeing) The work runs on the box and is slow — a still about 2 minutes, an H3 shot 10–12, music \
                several — so before you shoot a film, give them the plan in a few lines (the shots, engine, shape, \
                length, roughly how long it takes) and wait for a yes; say what a fix will cost before starting it. \
                You decide as much as you want to: what you give film_make (the cast, each shot's `who`, its \
                `picture`, its `h3` words) is used as written, and the studio writes only the rest. On H3, make it with \
                stop_after "frames", look at every shot with film_shot — its set, its first frame, the words each \
                model was given — fix what is wrong (film_edit, film_cast, film_fix_picture), then film_continue: a \
                wrong first frame costs ten minutes of filming. One job at a time; follow it with film_status (wait: \
                true) instead of asking again and again. A film they have open is the one they mean by "this film"; \
                film_status lists them all. Speak the language they write in, and keep it short.
                """
        case .motion:
            return """
                You make motion takes in the KinClaw app's Motion tab, on the person's Mac: a movement taken from a \
                real video (a reference) is performed by her — the companion, from her portrait — in a place and \
                clothes they describe. They watch the tab beside this terminal, where every take appears. motion_find \
                searches for Creative Commons reference videos by topic; motion_make makes a take from a reference (a \
                file, or a `url` whose licence it checks — anything not Creative Commons needs the person to say it is \
                theirs, `rights`; always pass `credit`), a start second, a length and the scene. A reference should be \
                one person, whole body, a steady camera. `camera`: skeleton (default, filmed from where the reference \
                was) or the 3D route — static, orbit, push, on a `place` set (park or open). Give `until: "still"` to \
                stop once her first picture is drawn: look at it with motion_status(take) — you see it, with the pose \
                it copies and the words the model got — then motion_continue. Your own English for the scene \
                (`scene_as_written`) or for the filming (`words`) is used as written. motion_status(wait: true) follows \
                a take; motion_stop stops one; video_frames shows any finished video. \(Self.seeing) Ten seconds take \
                about five minutes on the box: say so, and wait for a yes before a long one. Speak the language they \
                write in, and keep it short.
                """
        case .comfy:
            return """
                You work ComfyUI on the box for the person, through the KinClaw app's Comfy tab, which they watch \
                beside this terminal: the workflow you open shows there as a form, and its results appear there. \
                comfy_templates finds a ready-made workflow by what it does (about 300 run locally); comfy_run opens \
                one — by name, or from their words with `ask` (if that fails nothing runs, and you are told why) — sets \
                its values with `changes` (node, name, value, as comfy_status lists them; one that matches nothing \
                stops the run and is named), gives it input files with `files`, and runs it, bringing back that run's \
                files — you see the pictures; video_frames shows a video. A seed you set is kept; keep_seed keeps the \
                form's. A run that fails is an error with ComfyUI's reason. comfy_status says what is open, what it \
                lacks and the latest results (wait: true waits for a run); comfy_stop stops one; comfy_import brings \
                in a workflow from a file or a link. \(Self.seeing) A missing model is a download of many gigabytes \
                that only the person can start, in the Comfy tab: tell them which and how big. Speak the language \
                they write in, and keep it short.
                """
        case .montage:
            return """
                You make videos with OpenMontage for the person, in the KinClaw app's Montage tab on their Mac. \
                OpenMontage lives on "the box", an M3 Ultra Mac on the network, in ~/OpenMontage, and you reach it \
                through the openmontage tools: list, read, look (pictures and clips, to see them), write, run (a shell \
                command there with its venv active, up to 15 minutes) and start + job (anything longer: renders, H3, \
                music). Before producing, read CLAUDE.md and AGENT_GUIDE.md there and follow them — its pipelines, \
                checkpoints and approval gates. The person watches OpenMontage's Backlot board beside this terminal: \
                create the project workspace as the guide says and the board finds it by itself (never run \
                `backlot open`). Generate on the box with its local tools qwen_image, h3_video and minimax_music — read \
                .agents/skills/minimax-h3-local/SKILL.md first — instead of paid APIs. A project already under \
                projects/ can be carried on from its checkpoints. \(Self.seeing) The box is slow — about 2 minutes a \
                still, 10 minutes a 5-second H3 shot, 70 seconds of work per second of music — and does one heavy job \
                at a time: say what a plan will cost in time, wait for a yes, and start the music early. Speak the \
                language they write in, and keep it short.
                """
        }
    }

    // MARK: For the panel's tools

    var report: String {
        var lines = ["\(place.rawValue) 的 agent（\(whereTitle)）：" + (running ? "在跑，\(brainTitle)" : "没在跑，\(brainTitle)")]
        if let note { lines.append(note) }
        if let terminal {
            // Whether the wheel goes to the program (TerminalWheel) or scrolls
            // the scrollback.
            let t = terminal.getTerminal()
            lines.append("终端：" + (t.isCurrentBufferAlternate ? "备用屏幕" : "普通屏幕")
                         + (t.mouseMode != .off ? "，程序要了鼠标（滚轮给它）" : "，滚轮滚历史"))
            var rows = AgentTerminalSessions.visibleLines(t)
            while let last = rows.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
            if rows.count > 20 { rows.removeFirst(rows.count - 20) }
            if !rows.isEmpty { lines.append("终端最后几行：\n" + rows.joined(separator: "\n")) }
        }
        return lines.joined(separator: "\n")
    }
}

/// OpenMontage's bridge on the box: installed from the app's copy when the box
/// has none or an older one, and started by the agent over ssh.
@MainActor
enum OpenMontageBridge {
    /// The tools that only look, allowed without asking; running, starting
    /// and writing ask first (unless the person has said otherwise).
    static let looking = ["list", "read", "look", "job"]
    private static var checked: String?

    /// How the agent starts it; nil without a box.
    static var server: (command: String, args: [String])? {
        guard !BoxServices.ssh.isEmpty else { return nil }
        return ("/usr/bin/ssh", ["-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=30", "-o", "ConnectTimeout=8",
                                 BoxServices.ssh, "python3 ~/.kinclaw/om_bridge.py"])
    }

    /// Put this build's bridge on the box if what is there is not it.
    static func ensure() async {
        guard !BoxServices.ssh.isEmpty,
              let url = Bundle.main.url(forResource: "om_bridge", withExtension: "py"),
              let data = try? Data(contentsOf: url) else { return }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if checked == hash { return }
        let (_, out) = await BoxServices.run("shasum -a 256 ~/.kinclaw/om_bridge.py 2>/dev/null | cut -d' ' -f1")
        if out.trimmingCharacters(in: .whitespacesAndNewlines) != hash {
            let (code, _) = await BoxServices.run("mkdir -p ~/.kinclaw && echo '\(data.base64EncodedString())' | base64 -D > ~/.kinclaw/om_bridge.py.new && mv ~/.kinclaw/om_bridge.py.new ~/.kinclaw/om_bridge.py")
            guard code == 0 else { return }
        }
        checked = hash
    }
}

/// `processDelegate` is weak; the agent holds this.
private final class StudioAgentExitRelay: NSObject, LocalProcessTerminalViewDelegate {
    let onExit: (Int32?) -> Void
    init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { onExit(exitCode) }
}

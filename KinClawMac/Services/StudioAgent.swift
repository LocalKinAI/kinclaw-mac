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

/// Claude's Remote Control for the Claude Code sessions this app starts —
/// the Studio agents and the Code tab's — so the Claude app on a phone and
/// claude.ai/code show them by name and can follow and steer them. Jacky,
/// 2026-09-28: remote control of everything, "包括你自己", "第一层现在就开".
/// It needs the Claude account; a session on another brain is left as it was.
enum RemoteControl {
    static let key = "kinclaw.agents.remoteControl"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// `--remote-control <name>` for a Claude Code session on the account, else nothing.
    static func args(_ name: String, brain: AgentBrain) -> [String] {
        on && brain.source == .account ? ["--remote-control", name] : []
    }
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
    enum Place: String, CaseIterable { case film, motion, comfy, montage, pixelle, social }

    static let film = StudioAgent(.film)
    static let motion = StudioAgent(.motion)
    static let comfy = StudioAgent(.comfy)
    static let montage = StudioAgent(.montage)
    static let pixelle = StudioAgent(.pixelle)
    static let social = StudioAgent(.social)
    static let all = [film, motion, comfy, montage, pixelle, social]

    static func of(_ place: Place) -> StudioAgent {
        switch place {
        case .film: return film
        case .motion: return motion
        case .comfy: return comfy
        case .montage: return montage
        case .pixelle: return pixelle
        case .social: return social
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
    /// Its Remote Control session on claude.ai (the Claude app opens the same),
    /// read off its screen when it starts: the phone view links to it.
    @Published private(set) var remoteURL: String?

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
        case .pixelle: return PixelleStudio.root
        case .social: return SocialStudio.root
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
        StudioNotebook.ensure(place)
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
                         ["--mcp-stdio", "--tools", panelTools.joined(separator: ","), "--timeout", "900", "--place", place.rawValue]
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
        // Named, always: a bare --remote-control would take the first words as its name.
        args += RemoteControl.args("LocalKin · " + (ChatMode(rawValue: place.rawValue)?.title ?? place.rawValue), brain: brain)
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
        // Lines go in as one paste: typed bare, every newline is a return, and
        // a prompt of several lines was sent off at its first.
        let paste = text.contains("\n") && terminal.getTerminal().bracketedPasteMode
        terminal.send(txt: paste ? "\u{1b}[200~" + text + "\u{1b}[201~" : text)
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
    /// a sign-in that has run out, a folder to trust. And, for up to a minute,
    /// its Remote Control link, which scrolls away once it starts working.
    private func watchScreen() {
        watcher?.cancel()
        remoteURL = nil
        watcher = Task { [weak self] in
            for tick in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, let terminal = self.terminal else { return }
                if self.remoteURL == nil { self.remoteURL = Self.remoteLink(terminal) }
                if tick < 15, let problem = Self.problem(terminal) ?? Self.asking(terminal) {
                    self.note = problem
                    return
                }
                if tick >= 14, self.remoteURL != nil || !RemoteControl.on || self.harness != .claude { return }
            }
        }
    }

    /// The claude.ai/code session Remote Control shows for this terminal.
    static func remoteLink(_ terminal: LocalProcessTerminalView) -> String? {
        let screen = AgentTerminalSessions.visibleLines(terminal.getTerminal()).joined(separator: "\n")
        guard let range = screen.range(of: #"https://claude\.ai/code/session_[A-Za-z0-9_-]+"#, options: .regularExpression) else { return nil }
        return String(screen[range])
    }

    /// What the tab itself is making now, whoever asked for it — the agent,
    /// the person in the tab, or the phone. The remote view shows a tab's
    /// stop button only while this says something.
    var busy: String? {
        switch place {
        case .film:
            guard let id = FilmStudio.shared.shooting else { return nil }
            return "在拍「\(FilmStudio.shared.films.first { $0.id == id }?.title ?? id)」"
        case .motion:
            let studio = MotionStudio.shared
            guard let id = studio.working else { return nil }
            let title = studio.takes.first { $0.id == id }?.title ?? id
            return "在拍「\(title)」" + (studio.progress.map { "：\($0)" } ?? "")
        case .pixelle:
            guard let job = PixelleStudio.shared.job, job.state == .running else { return nil }
            return "在做「\(job.title)」：\(job.progress)"
        case .comfy:
            return ComfyStudio.shared.working
        case .montage, .social:
            return nil
        }
    }

    /// For the remote view (the LocalKin console's phone page): what it needs
    /// to show this agent — running, working or waiting, what needs the
    /// person, the last lines of its terminal, its Remote Control link, and
    /// what its tab is busy making.
    func snapshot(lines keep: Int) -> [String: Any] {
        var rows: [String] = []
        if let terminal {
            rows = AgentTerminalSessions.visibleLines(terminal.getTerminal())
            while let last = rows.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
            if remoteURL == nil { remoteURL = Self.remoteLink(terminal) }
        }
        let screen = rows.joined(separator: "\n").lowercased()
        var out: [String: Any] = [
            "tab": place.rawValue, "title": ChatMode(rawValue: place.rawValue)?.title ?? place.rawValue,
            "running": running, "harness": harness.title, "brain": brainTitle,
            "working": running && screen.contains("esc to interrupt"),
            "lines": Array(rows.suffix(keep)),
        ]
        if let note { out["note"] = note }
        if let remoteURL { out["remote"] = remoteURL }
        if let terminal, let needs = Self.problem(terminal) ?? Self.asking(terminal) { out["needs"] = needs }
        // Always there, "" when idle: its absence tells the console an older app is answering.
        out["busy"] = busy ?? ""
        return out
    }

    // MARK: One another

    /// The tab's name as the person sees it: Film, Motion, Easel…
    var title: String { ChatMode(rawValue: place.rawValue)?.title ?? place.rawValue }

    /// Its agent's state in a few words, for another tab's agent.
    var stateWords: String {
        guard running, let terminal else { return "agent 没在跑" }
        if let needs = Self.problem(terminal) ?? Self.asking(terminal) { return "agent 在等人处理（\(needs)）" }
        let screen = AgentTerminalSessions.visibleLines(terminal.getTerminal()).joined(separator: "\n").lowercased()
        return screen.contains("esc to interrupt") ? "agent 在干活" : "agent 在等人说话"
    }

    /// What the tab finished last, newest first, each with its file: what
    /// another tab's agent can pick up ("用 Comfy 刚写的那首歌").
    func latest(_ count: Int) -> [String] {
        func modified(_ url: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        var found: [(when: Date, what: String)] = []
        switch place {
        case .film:
            for film in FilmStudio.shared.films where film.state == .done {
                if let when = modified(film.file) { found.append((when, "「\(film.title)」 → \(film.file.path)")) }
            }
        case .motion:
            for take in MotionStudio.shared.takes where take.state == .done {
                if let when = modified(take.file) {
                    found.append((when, "「\(take.title)」\(Int(take.seconds.rounded())) 秒 → \(take.file.path)"))
                }
            }
        case .pixelle:
            // Read from disk: the tab's own list fills when the tab is first shown.
            for run in PixelleStudio.scan(PixelleStudio.root) {
                found.append((run.date, "「\(run.title)」 → \(run.video.path)"))
            }
        case .comfy:
            if ComfyStudio.shared.runs.isEmpty { ComfyStudio.shared.loadRuns() }
            for run in ComfyStudio.shared.runs {
                found.append((run.when, "\(run.title) → " + run.outputs.prefix(3).map(\.path).joined(separator: "，")))
            }
        case .social:
            for draft in SocialStudio.scan(SocialStudio.draftsFolder, legacy: false) {
                found.append((draft.created, "\(draft.platform)「\(draft.title)」 → \(draft.folder.path)"))
            }
        case .montage:
            break // its work is OpenMontage's, on the box: its agent knows it
        }
        let clock = DateFormatter()
        clock.dateFormat = "MM-dd HH:mm"
        return found.sorted { $0.when > $1.when }.prefix(count).map { clock.string(from: $0.when) + " " + $0.what }
    }

    /// A request one tab's agent handed another's, the person having said yes.
    struct Handoff {
        let from: Place
        let to: Place
        let when: Date
        let request: String
    }
    /// The last few, for studio_team: who passed what to whom.
    private(set) static var handoffs: [Handoff] = []
    /// Where the request it was last handed came from, and when: a request is
    /// not handed straight back.
    private var handedBy: (place: Place, when: Date)?

    /// Take the person's request from another tab's agent: typed in marked as
    /// handed over, so this one knows they already said yes and that it has
    /// not seen the conversation it came from. nil when taken, else why not.
    func handOver(_ request: String, from giver: StudioAgent) -> String? {
        if let back = giver.handedBy, back.place == place, Date().timeIntervalSince(back.when) < 600 {
            return "这件事是 \(title) 刚转给你的，别再转回去：问人要怎么办"
        }
        if let terminal, running, let question = Self.asking(terminal) {
            return "\(title) 的终端里有个问题在等人回答（\(question)），现在打不进去：请人先在 \(title) 标签里答了，再转"
        }
        handedBy = (giver.place, Date())
        Self.handoffs.append(Handoff(from: giver.place, to: place, when: Date(), request: request))
        if Self.handoffs.count > 12 { Self.handoffs.removeFirst(Self.handoffs.count - 12) }
        say("【从 \(giver.title) 转来 · 人已同意】" + request)
        return nil
    }

    /// The other tabs at once, for an agent (or anyone): each one's agent,
    /// what the tab is making now, and what it finished last; and what the
    /// box's ComfyUI is running, whoever started it.
    static func team(for me: Place?) async -> String {
        var lines = [me.map { "你是 \(of($0).title) 标签的 agent。其他标签此刻：" } ?? "Studio 各标签此刻："]
        for agent in all where agent.place != me {
            let doing = agent.place == .montage ? "它的活在盒子上的 OpenMontage 里（问它的 agent）"
                : agent.busy.map { "标签在做：\($0)" } ?? "标签空闲"
            lines.append("· \(agent.title)：\(agent.stateWords)；\(doing)")
            lines += agent.latest(2).map { "  最近做好：" + $0 }
        }
        if !handoffs.isEmpty {
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm"
            lines.append("最近的转交：" + handoffs.suffix(4).map {
                "\(clock.string(from: $0.when)) \(of($0.from).title)→\(of($0.to).title)「\($0.request.prefix(30))」"
            }.joined(separator: "；"))
        }
        lines.append(await comfyQueue())
        lines.append("看某个标签的 agent 在跟人说什么：studio_team 带 tab。把人的请求交给别的标签：先问人，人说好再 studio_handoff。")
        return lines.joined(separator: "\n")
    }

    /// The box's ComfyUI queue in a line. A job an agent put on the box
    /// itself shows in no tab's `busy` — Motion's hand-built H3 take did not —
    /// but it holds the box all the same.
    static func comfyQueue() async -> String {
        guard let url = URL(string: ComfyStudio.base + "/queue") else { return "盒子的 ComfyUI：地址不对" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let queue = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "盒子的 ComfyUI：连不上"
        }
        let running = queue["queue_running"] as? [[Any]] ?? []
        let pending = queue["queue_pending"] as? [[Any]] ?? []
        // What a job is, from its nodes: [number, id, graph, extra, outputs].
        let kinds = [("MiniMaxH3", "H3 视频"), ("MiniMaxMusic", "MiniMax 配乐"), ("YuE", "YuE2 歌"), ("LTX", "LTX 视频"),
                     ("FrameInterpolat", "补帧"), ("SeedVR", "放大"), ("Hunyuan3D", "3D"), ("Trellis", "3D"), ("Qwen", "出图")]
        func kind(_ job: [Any]) -> String {
            let graph = job.count > 2 ? job[2] as? [String: Any] ?? [:] : [:]
            let nodes = graph.values.compactMap { ($0 as? [String: Any])?["class_type"] as? String }.joined(separator: " ")
            return kinds.first { nodes.localizedCaseInsensitiveContains($0.0) }?.1 ?? "别的工作流"
        }
        let what = running.isEmpty ? "" : "（" + running.map(kind).joined(separator: "、") + "）"
        return "盒子的 ComfyUI（几个标签共用）：在跑 \(running.count)\(what)，排队 \(pending.count)"
    }

    /// One tab closer: its agent, what it makes now and made last, and the
    /// last lines of its terminal — what it and the person are saying.
    func closer(lines keep: Int) -> String {
        var out = ["\(title)：\(stateWords)" + (busy.map { "；标签在做：\($0)" } ?? "")]
        out += latest(3).map { "最近做好：" + $0 }
        if let terminal {
            var rows: [String] = []
            for row in AgentTerminalSessions.visibleLines(terminal.getTerminal()) where !Self.chrome(row) {
                let blank = row.trimmingCharacters(in: .whitespaces).isEmpty
                if blank, rows.last.map({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? true { continue }
                rows.append(row)
            }
            while let last = rows.last, last.trimmingCharacters(in: .whitespaces).isEmpty { rows.removeLast() }
            if !rows.isEmpty { out.append("它的终端最后几行：\n" + rows.suffix(keep).joined(separator: "\n")) }
        }
        return out.joined(separator: "\n")
    }

    /// The frame Claude Code draws around a conversation — rules, the empty
    /// prompt, the mode line, the Remote Control notice — which says nothing.
    static func chrome(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return t.allSatisfy { "─━".contains($0) } || t == "❯" || t.hasPrefix("⏵⏵") || t.contains("shift+tab to cycle")
            || t.contains("/remote-control is active") || t.hasPrefix("https://claude.ai/code/session_")
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
    /// (`--mcp-stdio --tools`). Montage's work is the bridge's; the Comfy
    /// tools are there for YuE2 songs, as they are for Pixelle's and Easel's.
    var panelTools: [String] {
        let studio = ["panel_show", "box_services", "image_generate", "video_generate", "video_status"]
        let comfy = ["comfy_templates", "comfy_run", "comfy_import", "comfy_status", "comfy_stop"]
        let film = ["film_guide", "film_make", "film_status", "film_shot", "film_edit", "film_cast", "film_continue",
                    "film_frames", "film_count", "film_fix_picture", "film_grade", "film_reshoot", "film_recut",
                    "film_rescore", "film_review", "film_stop"]
        let pixelle = ["pixelle_status", "pixelle_service", "pixelle_make", "pixelle_rework", "pixelle_wait", "pixelle_cancel",
                       "pixelle_image", "pixelle_voice", "pixelle_templates", "pixelle_voices", "pixelle_runs"]
        let social = ["social_status", "social_profile", "social_trends", "social_page", "social_card", "social_draft", "social_drafts"]
        // Each other: what the other tabs are doing and have made, and
        // handing the person's request to one of them.
        let team = ["studio_team", "studio_handoff"]
        switch place {
        case .film: return film + comfy + studio + team + ["studio_note"]
        case .motion: return ["motion_find", "motion_make", "motion_status", "motion_stop", "motion_continue", "video_frames"] + studio + team + ["studio_note"]
        case .comfy: return comfy + ["video_frames"] + studio + team + ["studio_note"]
        case .montage: return comfy + team + ["studio_note"]
        case .pixelle: return pixelle + comfy + ["video_frames"] + studio + team + ["studio_note"]
        // A post may carry a video: Pixelle's, made or found, from here too.
        case .social: return social + pixelle + comfy + ["video_frames"] + studio + team + ["studio_note"]
        }
    }

    private static let seeing = """
        Tools that show you something hand you the picture itself (a line `image://<path>` names it; if a picture \
        did not come with it, open that file). Look before you say anything about it — every frame you are \
        shown — and count what the story counts. A reviewer's score is not proof.
        """

    /// Said to every one of them: the notebook they keep, and who reads it.
    private static let notebook = """
        Your notebook is CLAUDE.md in your folder; you have read it already, and you keep it with studio_note. \
        When you learn something the next session should know, note a lesson; what the person likes, a \
        preference; and whenever the studio's own tools or pipeline get in your way — something wrong, missing, \
        slow or confusing — note a problem, saying what happened, where and what would fix it: the developer \
        reads those and fixes the studio. Briefly, when it happens.
        """

    /// Montage's agent may change OpenMontage itself, on the box.
    private static let openMontageCode = """
        You may change OpenMontage's own code and skills on the box (through the bridge's write and run) when \
        they are wrong or missing something; note each change as a lesson, with the file.
        """

    /// Said to every one of them: which tab makes what best — the Studio
    /// guide the person opens from the top bar, from the same list — so a
    /// request that belongs to another tab is sent there instead of forced.
    private static var routing: String {
        let map = StudioGuide.routes.map { "\($0.want) → \($0.mode.title)" }.joined(separator: "; ")
        return "What each Studio tab makes best (the person's Studio guide says the same): \(map). " + handing
    }

    /// And how the tabs work with one another: handing a request over, with
    /// the person's yes, and looking across at what the others are doing.
    private static let handing = """
        When what they ask for is another tab's work, say which tab and why rather than forcing it here, and ask \
        whether to hand it over; only on their yes, studio_handoff it, written out in full — what they want, what \
        is already decided, the files by path — since that agent has seen none of this conversation. A request \
        that begins 【从 … 转来 · 人已同意】 was handed to you that way: it is the person's, go on with it as if they \
        had said it here. studio_team shows the other tabs — whose agent is working, what each tab is making on the \
        box right now, and what each finished last, with its file: look there when they mention another tab's work \
        ("用 Comfy 刚写的那首歌"), and before starting something long while the box is busy.
        """

    var briefing: String {
        brief + " " + Self.notebook + " " + Self.routing + (place == .montage ? " " + Self.openMontageCode : "")
    }

    private var brief: String {
        switch place {
        case .film:
            return """
                You direct short films in the KinClaw app's Film tab, on the person's Mac. They watch the tab beside \
                this terminal: the storyboard, every still and clip as it lands, and the cut appear there by \
                themselves. You work through the panel's film tools (mcp__panel__film_*). Call film_guide once before \
                anything else and follow it: it is the method this studio's films are made by, learned the hard way. \
                \(Self.seeing) The work runs on the box and is slow — a still about 2 minutes, an H3 shot 10–12, music about 6 \
                seconds of work per second of music (3 minutes for 30 s; a minute a second when the box lacks its GPU \
                text encoder; film_status gives the estimate), showing no progress while it works: \
                film_status says when it began and how long it takes, and it is not stuck — so before you shoot a film, give them the plan in a few lines (the shots, engine, shape, \
                length, roughly how long it takes) and wait for a yes; say what a fix will cost before starting it. \
                The studio no longer reviews or retakes shots by itself unless the person turns 把关 back on: you \
                are the reviewer. Look at each finished take (film_frames) and reshoot only what is wrong. Every shot \
                of an H3 film is filmed on LTX first (animate, about a minute and a half against H3's 5–6), a \
                person's shot from its composed first frame with the cast in it; when a face drifts or a movement \
                LTX cannot do comes out wrong, film_reshoot that shot with method "h3". \
                You decide as much as you want to: what you give film_make (the cast, each shot's `who`, its \
                `picture`, its `h3` words) is used as written, and the studio writes only the rest. On H3, make it with \
                stop_after "frames", look at every shot with film_shot — its set, its first frame, the words each \
                model was given — fix what is wrong (film_edit, film_cast, film_fix_picture), then film_continue: a \
                wrong first frame costs ten minutes of filming. One job at a time; follow it with film_status (wait: \
                true) instead of asking again and again. A film they have open is the one they mean by "this film"; \
                film_status lists them all. For craft, guides/higgsfield/ in this folder is a reference library (MIT, \
                docs only) written for Higgsfield's cloud models: skip their model settings, take the craft — the MCSLA \
                order for a shot's words (INDEX.md routes to every heading), skills/higgsfield-acting/SKILL.md for a \
                performance (what the character wants, what stands in the way, the beats, the eyes), \
                skills/higgsfield-seedance/HELL-GRIND.md for keeping people and places the same across a film, and \
                skills/higgsfield-seedance/FAILURE-MODES.md for naming what went wrong in a shot. A song with a voice \
                and words — a theme, a closing song — is YuE2: comfy_run, template audio_yue2_text2music (open it with \
                run: false and read comfy_status for its fields: the style in English, the lyrics in [Verse]/[Chorus] \
                sections, max_duration in seconds, the format), or audio_yue2_music_cover for a cover of a song given \
                in `files`. About 17 seconds of work per second of music, and ComfyUI is busy all that time. Then \
                film_rescore with music_file (the file comfy_run brought back) and voice: false keeps the narration. \
                Background music without words stays the film's own. Speak the language they write in, and keep it short.
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
                about five minutes on the box: say so, and wait for a yes before a long one. \
                The third route, 提示词白模, needs no reference: when they describe a place and a camera move ("雨夜的老街，\
                镜头沿街往前推"), YOU write the set as a spec of plain shapes and a camera path (motion_make's description \
                has the format and the looks) — a few hundred boxes, cylinders and balls make a street or a room; measure \
                in metres and keep the camera inside the set. Pass `looks` (what each shape becomes, the light) and `words` \
                (the English H3 films from: the place, the light, how the camera moves, the sound). Use until: "plan" \
                first and look at the plan and the set's first frame yourself before anything is filmed; people stand \
                still on this route. Speak the language they write in, and keep it short.
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
                in a workflow from a file or a link. guides/comfy-templates.md in your folder says, for all 566 \
                templates, which run on this Mac now (21), which need a download, which are paid cloud, what each is best \
                at and what to avoid here (the 3D bake nodes, int8 patches, 30–90 GB models); comfy_templates shows the \
                same notes. Recommend from it. \(Self.seeing) A missing model is a download of many gigabytes \
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
                still, 10 minutes a 5-second H3 shot, about 6 seconds of work per second of music (minimax_music's text \
                stage runs on the box's GPU now: 3 minutes for 30 s) — and does one heavy job \
                at a time: say what a plan will cost in time, wait for a yes, and start the music early. A song with a \
                voice and words is YuE2, through the Comfy tools (comfy_run, template audio_yue2_text2music — open it \
                with run: false and read comfy_status for its fields — or audio_yue2_music_cover for a cover of a song \
                in `files`): about 17 seconds of work per second of music — slower than minimax_music now, but it \
                sings the words. The \
                file comfy_run brings back is also on the box at ~/ComfyUI/output/audio/ under the same name, for \
                OpenMontage to use. Speak the language they write in, and keep it short.
                """
        case .pixelle:
            return """
                你在 KinClaw app 的 Pixelle 标签里给对方做解说短视频，在对方的 Mac 上。Pixelle-Video（AIDC-AI 开源）装在「盒子」上\
                （局域网里一台 M3 Ultra Mac）：一篇稿子，一段一个场景；每个场景用盒子 ComfyUI 上的 Qwen Image 2.1 画一张图，用盒子上的 TTS 读一句\
                （8102 按描述造声音，8101 是预设声音；整篇稿子一次念完再在句间停顿处切开，全片是同一个人），套进 HTML 卡片模板、配上字幕，\
                可以让画面动起来（motion：pan 慢推慢移，几秒一个场景；ltx 用盒子上的 LTX 把每张图真的动起来，约 3 分钟一个场景），垫音乐，\
                合成一支 MP4，响度拉到 −14 LUFS。对方就在这个终端\
                旁边看着 Pixelle 标签：进度、做好的视频、每个场景并排的 sheet 都会自己出现。你用 pixelle_* 工具做事（它们包着盒子上的 Pixelle API；\
                pixelle_status 说它没在跑就用 pixelle_service 起，盒子重启后它不会自己起来）。\
                稿子和每个场景的画面描述都由你来写，照写的用：mode fixed，一段一个场景，段与段之间空一行；每段 20–35 个汉字（中文大约每秒 4 个字，\
                每句前后各停 0.2 / 0.6 秒，一段约 5–9 秒；30 秒左右的视频约 130–140 字、5 个场景）；数字写成要读出来的样子（一九九五年）。\
                image_prompts 每个场景一条英文，只写画面里真有的东西，不写比喻（比喻会被照字面画出来）；共同的风格放进 prompt_prefix。\
                别让盒子上的模型替你写稿（它不管字数，写得虚）。先试后做：pixelle_image 试一张图（约 45 秒），pixelle_voice 试一句声音\
                （它告诉你盒子的语音识别听到了什么：听错的地方就是读错的，改字）。做整支之前，把稿子、每个场景的画面、声音、模板、音乐和大概\
                要多久给对方看，等对方点头：五个场景约 5–6 分钟，ComfyUI 被别的标签占着时（一段 MiniMax 配乐几分钟，一首 YuE2 歌二十分钟上下）要等更久，pixelle_status \
                看得到队列。pixelle_make 立刻给你一个 task id；pixelle_wait 跟着（一次最多等 9 分钟，没好就再调）。做好之后先看 sheet，再说好不好。\
                画面默认是静止的卡片。要动：先做静止版给对方看（快），对方满意了再用 pixelle_rework 做会动的版本（不重画图，原片不动，出一支新的）；\
                开做前说清要多久（ltx 约 3 分钟一个场景）。ltx 的动法可以用 motion_prompts 每个场景写一句英文（镜头怎么走、画面里什么在动），\
                不写就按画面描述轻轻地动；图表、文字类的画面用 pan 更稳（LTX 可能把线条和字弄变形）。ltx 的片段会先用 RIFE 补成两倍帧\
                （几秒一个场景），场景比片段长、要放慢时也不卡；ComfyUI 被别的标签占着时那几场不补，结果里的 motion 会写明。以前逐句配音的片子每句像换了个人：\
                pixelle_rework revoice true 重配成一个人。模板只有 image_*（每个场景一张 AI 图）\
                和 static_*（纯文字，不用 ComfyUI）能在盒子上跑；大多数模板的页脚默认是 Pixelle 自己的署名（@Pixelle.AI），用 template_params\
                （author / brand / describe / signature，"" 隐藏）换成对方的。音乐：盒子上的 localkin-wonder-33s.wav 可以用（bgm_volume 约 0.45，\
                对方要听得清音乐）；绝不用 Pixelle 自带的 default.mp3——它是《最终幻想 IX》Melodies of Life 的 OC ReMix 改编，有版权，不能出现在\
                任何公开的东西里。也可以专门写一首带人声的歌：comfy_run 跑 YuE2（template audio_yue2_text2music，先 run: false 再用 \
                comfy_status 看字段：风格用英文写，歌词分 [Verse]/[Chorus] 段，max_duration 秒数，格式；翻唱用 audio_yue2_music_cover，\
                参考歌给 files），每秒音乐约 17 秒计算，那段时间 ComfyUI 被占着；做好把 comfy_run 带回来的文件路径直接给 pixelle_make 或 \
                pixelle_rework 的 bgm_path（会先传到盒子上；只换歌也能 rework）。人声会和旁白抢字：bgm_volume 放低到 0.15–0.25，或者用在旁白\
                少的片子里。单个场景没法单独重做：改那一段的字或画面描述，整支再做一遍（没改的场景种子不变，画面一样）。\
                \(Self.seeing) 用对方写的语言说话，简短。
                """
        case .social:
            return """
                你在 KinClaw app 的「Easel」标签（以前叫「社媒」）里帮对方做社交媒体的草稿，在对方的 Mac 上。这个标签照 ZJU-REAL/Easel\
                （Apache-2.0）的做法做，名字也是借它的。平台：小红书（图文为主）、抖音、B站、微博、知乎、快手，微信的公众号文章、视频号视频、\
                朋友圈，还有 TikTok、X、YouTube Shorts。对方就在这个终端旁边看着这个标签：每份草稿像手机上的帖子一样显示（卡片轮播、标题、\
                正文、话题）。你用 social_* 工具做事。\
                开工前读你文件夹里 guides/easel/ 的指南（Easel，Apache-2.0），照它们的方法做：skills/openclaw/ 下的 xhs-note-creator、card-design\
                （先读它 references/ 里的 styles.md、layout-laws.md、typography.md、anti-ai-slop.md）、card-xiaohongshu、text-polisher\
                （references/zh-ai-markers.md）、skill-quality-gate（references/platform-xiaohongshu.md）、skill-topic-evaluator、\
                skill-publish-checklist；账号画像的格式在 profiles/_template。指南里提到的脚本、OpenClaw、Playwright 和各种付费 API 这里都没有，\
                用这里的工具：画卡片 social_card，读网页 social_page，热榜 social_trends，账号 social_profile，存草稿 social_draft；要视频可以用 \
                pixelle_*（解说短视频）。流程：账号画像（social_profile；没有就建一个，和对方一起填，别替对方编）→ 需要时看热榜 → 选题（按 Easel \
                的七维打分，给两三个方向，等对方挑）→ 文案（按平台写标题备选、正文、话题）→ 卡片（先和对方定一种风格，整组只用这一套；一张一张画，\
                每张都看回来的图和审查）→ 自检（合规、去 AI 味、每个数字对一遍原文）→ social_draft。事实：从对方自己的看板（例如宇宙看板 \
                https://space.localkin.ai，用 social_page 读）或任何来源拿来的数字和说法，必须和原文一字不差，带日期和出处，每一条都写进 \
                social_draft 的 sources；拿不准的就不用。不夸大，不写末日论，不制造焦虑，不做标题党；照账号画像的语气写，去 AI 味。\
                各平台：social_draft 的 platform 写平台名（中文、英文、别名都认），它按各平台自己公布的规则查（数字在工具说明里）。要视频的：\
                抖音、B站、快手、视频号、YouTube Shorts（≤3 分钟，竖的或方的）；TikTok 要一支视频或一组图（photo mode，最多 35 张）。视频用 \
                pixelle_* 做（1080×1920，9:16），做好把 final.mp4 给 social_draft 的 video；要一首专门的歌，用 comfy_run 跑 YuE2\
                （audio_yue2_text2music，风格英文、歌词分段；每秒音乐约 17 秒计算），做好的文件给 pixelle 的 bgm_path。X 的 280 是加权的（汉字、emoji 算 2，链接算 23），\
                最多 4 张图，话题不超过 2 个，链接放第一条回复；TikTok 话题最多 5 个；Shorts 标题 ≤100，描述里的链接点不开；公众号是一篇文章：\
                标题（≤64，32 以内最稳）、摘要（summary，≤120）、封面 900×383，结构和排版看 skill-wechat-publisher 的 references（它的脚本、\
                登录和发布这里都不用）；视频号描述 ≤1000 字；朋友圈没有标题也没有话题，最多 9 张图，只能在手机（或新版 Mac 微信）上发。\
                TikTok、X、YouTube Shorts 的读者多半说英文，文案可以写英文：一样去 AI 味（delve、game-changer、in today's fast-paced world \
                这类不要），数字一样要出处；热榜用 social_trends 的 google_trends 和 x（geo 选国家），tiktok、youtube、wechat 没有公开榜，\
                它会说该怎么办。别的平台怎么写，读 skills/openclaw/ 下 social-content/references/platform-specs.md、\
                image-editing/references/platform-sizes.md，一个内容改写到几个平台看 skill-cross-platform-diff。卡片：小红书 1080×1440\
                （3:4），朋友圈 1080×1080，公众号封面 900×383（后台还会从里面裁一块 1:1，要紧的字放中间），X 1600×900（16:9）或 \
                1080×1080、1080×1350，TikTok 图集 1080×1920；HTML/CSS 你来写。这台 Mac 上的中文字体有 PingFang SC（100–600，大标题用细的）、\
                Songti SC（衬线，Light / Regular / Bold / Black）、Kaiti SC、Lantinghei SC，等宽用 Menlo；没有 Noto CJK，指南里写 Noto 的地方\
                换成这些。英文用 -apple-system（SF Pro）、Helvetica Neue、Avenir Next、Georgia、ui-serif（New York），英文卡片把英文字体放在\
                最前面（或整页写 <html lang="en">）。本机的图\
                （盒子出的图、截图）用 file:// 全路径，要在素材文件夹下。正文不小于 28px，任何字不小于 20px；social_card 审查出问题就改到通过。\
                永远不发布、不登录任何平台，也不替对方去平台上操作：你只做草稿，发布是对方自己在平台上点。\(Self.seeing) 用对方写的语言说话，\
                简短。
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

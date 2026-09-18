import AppKit
import SwiftTerm
import SwiftUI

// MARK: - Asking for an agent

/// How the model menus in Cowork and Code ask for an agent. The session is
/// opened straight away; the request is what SpotlightContentView watches to
/// switch the panel to the Term tab.
@MainActor
final class AgentTerminalStore: ObservableObject {
    static let shared = AgentTerminalStore()

    struct Request: Equatable {
        let agent: String
        let host: String
        let model: String
        /// The folder to start in, when the asker has one — Code passes its
        /// repo. nil leaves the choice to the tab.
        let directory: String?
        /// Bumped on every ask, so asking twice is two requests.
        let serial: Int
    }

    @Published private(set) var request: Request?
    private var serial = 0

    func run(_ item: AgentLauncher.Installed, host: String, model: String, directory: String? = nil) {
        AgentTerminalSessions.shared.open(agent: item.integration.id, host: host, model: model, folder: directory)
        serial += 1
        request = Request(agent: item.integration.id, host: host, model: model,
                          directory: directory, serial: serial)
    }
}

// MARK: - Sessions

/// The Term tab's sessions, and the terminals running them.
///
/// The terminals live here rather than in the view tree, on purpose. SwiftUI
/// tears a view down whenever it leaves the hierarchy — another tab selected,
/// the panel switched to Cowork — and a terminal torn down is an agent killed
/// in the middle of whatever it was doing. That was true of the single-tab
/// version too: leaving Term ended the agent. Held here, a session keeps
/// running out of sight, and only closing its tab ends it.
@MainActor
final class AgentTerminalSessions: ObservableObject {
    static let shared = AgentTerminalSessions()

    struct Session: Identifiable, Codable, Equatable {
        var id = UUID()
        var agent: String
        /// "" = whatever source the panes are using.
        var host: String
        var model: String
        /// "" = the folder Code is pointed at, else home.
        var folder: String
    }

    @Published private(set) var sessions: [Session] = []
    @Published var selectedID: UUID? { didSet { save() } }
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var notes: [UUID: String] = [:]

    private var terminals: [UUID: LocalProcessTerminalView] = [:]
    private var relays: [UUID: ExitRelay] = [:]

    private static let sessionsKey = "kinclaw.term.sessions"
    private static let selectedKey = "kinclaw.term.selected"

    private init() { load() }

    var selected: Session? {
        sessions.first { $0.id == selectedID } ?? sessions.first
    }

    static func host(of s: Session) -> String {
        s.host.isEmpty ? OllamaCatalog.baseURL : s.host
    }

    static func folder(of s: Session) -> String {
        if !s.folder.isEmpty, FileManager.default.fileExists(atPath: s.folder) { return s.folder }
        return AgentLauncher.defaultDirectory
    }

    static func installed(_ s: Session) -> AgentLauncher.Installed? {
        AgentLauncher.available.first { $0.integration.id == s.agent } ?? AgentLauncher.available.first
    }

    // MARK: Tabs

    /// A new tab set up like `template` — the tab you were on — so "+" gives
    /// you the same agent on the same machine without choosing it all again.
    @discardableResult
    func newTab(like template: Session? = nil) -> Session {
        let s = Session(agent: template?.agent
                            ?? AgentLauncher.availableAgents.first?.integration.id
                            ?? AgentLauncher.available.first?.integration.id ?? "",
                        host: template?.host ?? "",
                        model: template?.model ?? "",
                        folder: template?.folder ?? "")
        sessions.append(s)
        selectedID = s.id
        save()
        return s
    }

    /// What a model menu asked for: the tab already set up exactly that way if
    /// there is one, a new tab otherwise — never by replacing an agent that is
    /// mid-conversation in whichever tab happened to be selected.
    func open(agent: String, host: String, model: String, folder: String?) {
        if let existing = sessions.first(where: {
            $0.agent == agent && Self.host(of: $0) == host && $0.model == model
                && (folder == nil || Self.folder(of: $0) == folder)
        }) {
            selectedID = existing.id
            if terminals[existing.id] != nil, !running.contains(existing.id) {
                restart(existing.id)
            }
            return
        }
        let s = Session(agent: agent, host: host, model: model, folder: folder ?? "")
        sessions.append(s)
        selectedID = s.id
        save()
    }

    /// A tab running your own shell, in the folder the selected tab is in —
    /// which is the folder you were just looking at.
    @discardableResult
    func newShell() -> Session {
        let s = Session(agent: AgentLauncher.shell.id, host: "", model: "",
                        folder: selected?.folder ?? "")
        sessions.append(s)
        selectedID = s.id
        save()
        return s
    }

    func close(_ id: UUID) {
        stop(id)
        terminals[id] = nil
        notes[id] = nil
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: i)
        if selectedID == id {
            selectedID = sessions.isEmpty ? nil : sessions[min(i, sessions.count - 1)].id
        }
        save()
    }

    /// Change a tab's settings. Its agent restarts: agent, machine, model and
    /// folder are all fixed when a process starts.
    func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        var s = sessions[i]
        change(&s)
        guard s != sessions[i] else { return }
        sessions[i] = s
        save()
        restart(id)
    }

    /// A fresh terminal, not the old one reused: the old screen belonged to
    /// the old process.
    func restart(_ id: UUID) {
        stop(id)
        terminals[id] = nil
        notes[id] = nil
        objectWillChange.send()
    }

    func setNote(_ id: UUID, _ text: String?) { notes[id] = text }

    // MARK: Terminals

    /// The terminal for a session, started the first time it is asked for —
    /// which is when its tab is first shown, so tabs restored at launch do not
    /// all start agents at once.
    func terminal(for s: Session) -> LocalProcessTerminalView? {
        if let view = terminals[s.id] { return view }
        guard let item = Self.installed(s),
              !item.integration.needsModel || !s.model.isEmpty else { return nil }

        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        let id = s.id
        let relay = ExitRelay { [weak self] code in
            Task { @MainActor in self?.exited(id, code: code) }
        }
        view.processDelegate = relay
        relays[id] = relay
        terminals[id] = view

        let host = Self.host(of: s)
        // Our PATH has to win, and two PATH= entries in one environment array
        // is anybody's guess, so drop the inherited one first.
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            .filter { !$0.hasPrefix("PATH=") }
        env.append("PATH=" + AgentLauncher.childPath(for: item.binary))
        for (key, value) in item.integration.env(host).sorted(by: { $0.key < $1.key }) {
            env.append("\(key)=\(value)")
        }
        // Through the login shell, interactive: agents start children of their
        // own (MCP servers, hooks) that want node, and this Mac keeps PATH and
        // nvm in .zshrc — which `zsh -l -c` does not read. Measured: `env node`
        // fails under launchd's PATH and resolves under `zsh -l -i -c`. `exec`
        // hands the PTY straight to the agent, so ^C and the exit code are its
        // own.
        var args = ["-l", "-i"]
        if item.integration.needsModel {
            let command = ([item.binary] + item.integration.args(host, s.model))
                .map(AgentLauncher.shellQuoted).joined(separator: " ")
            args += ["-c", "exec " + command]
        }
        view.startProcess(executable: AgentLauncher.loginShell,
                          args: args,
                          environment: env,
                          currentDirectory: Self.folder(of: s))
        // Not published from here: this runs while a view is being built.
        DispatchQueue.main.async { self.running.insert(id) }
        return view
    }

    private func stop(_ id: UUID) {
        if let view = terminals[id] {
            view.processDelegate = nil // an exit we caused is not news
            view.terminate()
        }
        relays[id] = nil
        running.remove(id)
    }

    private func exited(_ id: UUID, code: Int32?) {
        running.remove(id)
        notes[id] = code.map { "进程结束（退出码 \($0)）" } ?? "进程结束了"
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.sessionsKey),
           let saved = try? JSONDecoder().decode([Session].self, from: data) {
            sessions = saved
        } else if let model = defaults.string(forKey: "kinclaw.term.model"), !model.isEmpty {
            // The tab from before there were tabs: one session in four keys.
            sessions = [Session(agent: defaults.string(forKey: "kinclaw.term.agent") ?? "",
                                host: defaults.string(forKey: "kinclaw.term.host") ?? "",
                                model: model,
                                folder: defaults.string(forKey: "kinclaw.term.folder") ?? "")]
        }
        if let raw = defaults.string(forKey: Self.selectedKey), let id = UUID(uuidString: raw),
           sessions.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = sessions.first?.id
        }
    }
}

/// Receives a terminal's process events and passes on the one that matters.
/// `processDelegate` is weak, so the sessions hold these.
private final class ExitRelay: NSObject, LocalProcessTerminalViewDelegate {
    let onExit: (Int32?) -> Void

    init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { onExit(exitCode) }
}

// MARK: - The tab

/// The Term tab: agents running in terminals inside the panel, one per tab.
///
/// Why a terminal rather than our own transcript with our own cards: Claude
/// Code and its kind are interactive TUIs — their own approval prompts, their
/// own scrollback, their own ^C — and `claude -p`'s JSON mode has no approval
/// callback to hang cards on, so a pane that swallowed one would be strictly
/// worse than the real thing. What the tab adds is the environment: the
/// machine, the model and the folder you picked.
///
/// One caveat worth knowing: an agent is spawned by this app, so a file or
/// network prompt it triggers is attributed to KinClawMac. 「在外部终端打开」
/// is there for when that matters.
struct AgentTerminalPane: View {
    @ObservedObject private var sessions = AgentTerminalSessions.shared

    @AppStorage("kinclaw.term.recents") private var termRecentsRaw: String = ""
    /// Code's recent repos, offered here too: they are the folders a person
    /// actually works in.
    @AppStorage("kinclaw.kincode.recents") private var codeRecentsRaw: String = ""

    @State private var presets: [BrainPreset] = []
    @State private var scanning = false
    @State private var healthTick = 0

    private typealias Session = AgentTerminalSessions.Session

    private var installed: [AgentLauncher.Installed] { AgentLauncher.available }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.15)
            if let s = sessions.selected {
                header(s)
                Divider().opacity(0.15)
                if let terminal = sessions.terminal(for: s) {
                    TerminalSlot(terminal: terminal)
                        .id(s.id)
                } else {
                    emptySession
                }
            } else {
                noTabs
            }
        }
        .background(Color.black.opacity(0.28))
        .task(id: presetKey) { await reloadPresets() }
    }

    /// Changes when the models on offer could: another tab, another machine.
    private var presetKey: String {
        guard let s = sessions.selected else { return "" }
        return "\(s.id)|\(AgentTerminalSessions.host(of: s))"
    }

    // MARK: Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sessions.sessions) { s in tab(s) }
                }
                .padding(.horizontal, 8)
            }
            Button {
                sessions.newShell()
            } label: {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.leading, 6)
            .help("新开一个 shell 标签（就是你的登录 shell，在当前文件夹里）")
            Button {
                sessions.newTab(like: sessions.selected)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .help("新开一个 agent 标签（沿用当前标签的设置）")
        }
        .padding(.vertical, 5)
    }

    private func tab(_ s: Session) -> some View {
        let active = s.id == sessions.selected?.id
        let label = AgentTerminalSessions.installed(s)?.integration.label ?? "Agent"
        let folder = AgentTerminalSessions.folder(of: s)
        return HStack(spacing: 5) {
            Circle()
                .fill(sessions.running.contains(s.id) ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text("\(label) · \((folder as NSString).lastPathComponent)")
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .primary : .secondary)
                .lineLimit(1)
            Button {
                sessions.close(s.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("关掉这个标签（会结束里面的 agent）")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(active ? Color.white.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { sessions.selectedID = s.id }
        .help("\(label) · \(s.model.isEmpty ? "未选模型" : s.model) · "
              + "\(OllamaCatalog.hostLabel(AgentTerminalSessions.host(of: s))) · \(folder)")
    }

    // MARK: Header

    private func header(_ s: Session) -> some View {
        let agent = AgentTerminalSessions.installed(s)
        return HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let agent {
                agentMenu(s, current: agent)
                if agent.integration.needsModel {
                    machineMenu(s)
                    modelMenu(s)
                }
                folderMenu(s)
            } else {
                Text("没有可跑的 agent")
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            if let message = sessions.notes[s.id] ?? dialectWarning(s) {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(message)
            }
            if let agent, !agent.integration.needsModel || !s.model.isEmpty {
                Button("重启") { sessions.restart(s.id) }
                    .controlSize(.small)
                Button("在外部终端打开") { openOutside(s) }
                    .controlSize(.small)
                    .help("同样的环境，但窗口归终端 app —— 它的权限提示也就不算在 KinClaw 头上")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Which agent. A picker only when there is something to pick between.
    @ViewBuilder
    private func agentMenu(_ s: Session, current: AgentLauncher.Installed) -> some View {
        if installed.count > 1 {
            Menu(current.integration.label) {
                ForEach(installed) { item in
                    Button {
                        sessions.update(s.id) { $0.agent = item.integration.id }
                    } label: {
                        HStack {
                            if item.id == current.id { Image(systemName: "checkmark") }
                            Text(item.integration.label)
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            Text(current.integration.label)
                .font(.system(size: 12, weight: .medium))
        }
    }

    /// Whether the machine speaks the agent's dialect — asked of the host,
    /// since a kinfer box can be running a build from before it learned
    /// /v1/messages and /v1/responses.
    private func dialectWarning(_ s: Session) -> String? {
        guard let agent = AgentTerminalSessions.installed(s),
              agent.integration.needsModel else { return nil }
        let host = AgentTerminalSessions.host(of: s)
        guard let health = OllamaCatalog.cachedHealth(host), health.reachable else { return nil }
        let (served, path) = agent.integration.dialect == .openAIResponses
            ? (health.openAIResponses, "/v1/responses")
            : (health.anthropicMessages, "/v1/messages")
        guard !served else { return nil }
        return "\(OllamaCatalog.hostLabel(host)) 没有 \(path)，\(agent.integration.label) 用不了这台 —— 更新那台的 kinfer"
    }

    /// Which machine's models the agent talks to — the same catalog as both
    /// brain menus, but the choice is this tab's.
    private func machineMenu(_ s: Session) -> some View {
        let host = AgentTerminalSessions.host(of: s)
        return Menu {
            let _ = healthTick
            ForEach(OllamaCatalog.knownHosts, id: \.self) { candidate in
                Button {
                    switchMachine(s, to: candidate)
                } label: {
                    HStack {
                        if candidate == host {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: candidate == OllamaCatalog.defaultBaseURL
                                  ? "laptopcomputer" : "network")
                        }
                        Text(OllamaCatalog.hostLabel(candidate) + OllamaCatalog.healthNote(candidate))
                    }
                }
            }
            Divider()
            Button(scanning ? "扫描中…" : "扫描局域网找 Ollama / kinfer…") { scanLAN(s) }
                .disabled(scanning)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: host == OllamaCatalog.defaultBaseURL ? "laptopcomputer" : "network")
                    .font(.system(size: 9))
                Text(OllamaCatalog.hostLabel(host))
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { refreshHealth() }
    }

    private func modelMenu(_ s: Session) -> some View {
        Menu(s.model.isEmpty ? "选个模型" : s.model) {
            if presets.isEmpty {
                Text("\(OllamaCatalog.hostLabel(AgentTerminalSessions.host(of: s))) 上没读到模型")
                    .foregroundColor(.secondary)
            }
            ForEach(presets) { preset in
                Button(preset.label) {
                    // The machine the list came from is the machine the model is
                    // on; a tab that was following the panes keeps it from here.
                    let host = AgentTerminalSessions.host(of: s)
                    sessions.update(s.id) { $0.model = preset.model; $0.host = host }
                }
            }
            Divider()
            Button("重新读取模型列表") { Task { await reloadPresets() } }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Where the agent works. Changing it restarts the agent: a working
    /// directory is fixed when a process starts.
    private func folderMenu(_ s: Session) -> some View {
        let folder = AgentTerminalSessions.folder(of: s)
        return Menu {
            ForEach(recentFolders(current: folder), id: \.self) { path in
                Button {
                    switchFolder(s, to: path)
                } label: {
                    HStack {
                        if path == folder { Image(systemName: "checkmark") }
                        Text(displayPath(path))
                    }
                }
            }
            Divider()
            Button("选择文件夹…") { pickFolder(s, from: folder) }
            if !s.folder.isEmpty {
                Button("跟随 Code 的仓库") { switchFolder(s, to: "") }
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text((folder as NSString).lastPathComponent)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(folder)
    }

    private var emptySession: some View {
        let agents = AgentLauncher.availableAgents
        return VStack(spacing: 8) {
            Text(agents.isEmpty ? "这台机器上没找到可以跑的 agent" : "先在上面挑一个模型")
                .font(.system(size: 13))
            if agents.isEmpty {
                Text("装好 Claude Code 或 Codex 再重开 app —— 或者开一个 shell 标签。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("开一个 shell") { sessions.newShell() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noTabs: some View {
        VStack(spacing: 10) {
            Text("没有打开的标签")
                .font(.system(size: 13))
            HStack(spacing: 8) {
                Button("开一个 agent") { sessions.newTab() }
                    .controlSize(.small)
                Button("开一个 shell") { sessions.newShell() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Doing things

    /// Point a tab at another machine. The model has to exist there — a name
    /// the new host has never heard of just fails later, in the terminal.
    private func switchMachine(_ s: Session, to candidate: String) {
        let id = s.id
        let model = s.model
        sessions.setNote(id, nil)
        Task {
            await OllamaCatalog.probe(candidate)
            let fresh = await OllamaCatalog.loadPresets(baseURL: candidate)
            await MainActor.run {
                presets = fresh
                healthTick += 1
                if fresh.isEmpty {
                    sessions.update(id) { $0.host = candidate }
                    sessions.setNote(id, "\(OllamaCatalog.hostLabel(candidate)) 连不上或没有模型")
                } else if fresh.contains(where: { $0.model == model }) {
                    sessions.update(id) { $0.host = candidate }
                } else if let family = model.split(separator: ":").first,
                          let near = fresh.first(where: { $0.model.hasPrefix(family) }) {
                    sessions.update(id) { $0.host = candidate; $0.model = near.model }
                } else {
                    sessions.update(id) { $0.host = candidate; $0.model = "" }
                    if !model.isEmpty {
                        sessions.setNote(id, "\(OllamaCatalog.hostLabel(candidate)) 上没有 \(model)，挑一个")
                    }
                }
            }
        }
    }

    private func switchFolder(_ s: Session, to path: String) {
        if !path.isEmpty {
            var recents = termRecentsRaw.split(separator: ",").map(String.init).filter { $0 != path }
            recents.insert(path, at: 0)
            termRecentsRaw = recents.prefix(10).joined(separator: ",")
        }
        sessions.update(s.id) { $0.folder = path }
    }

    private func pickFolder(_ s: Session, from folder: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folder)
        panel.message = "Agent 在哪个文件夹里工作？"
        if panel.runModal() == .OK, let url = panel.url {
            switchFolder(s, to: url.path)
        }
    }

    /// The current folder, then the tab's recent ones, then Code's —
    /// deduplicated, with folders that no longer exist left out.
    private func recentFolders(current: String) -> [String] {
        let candidates = [current]
            + termRecentsRaw.split(separator: ",").map(String.init)
            + codeRecentsRaw.split(separator: ",").map(String.init)
        var out: [String] = []
        for path in candidates where !path.isEmpty && !out.contains(path)
            && FileManager.default.fileExists(atPath: path) {
            out.append(path)
            if out.count == 8 { break }
        }
        return out
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func openOutside(_ s: Session) {
        guard let agent = AgentTerminalSessions.installed(s) else { return }
        sessions.setNote(s.id, AgentLauncher.launch(agent,
                                                     host: AgentTerminalSessions.host(of: s),
                                                     model: s.model,
                                                     directory: AgentTerminalSessions.folder(of: s)))
    }

    private func scanLAN(_ s: Session) {
        guard !scanning else { return }
        scanning = true
        let id = s.id
        Task {
            let found = await OllamaCatalog.discover()
            await MainActor.run {
                let before = Set(OllamaCatalog.knownHosts)
                for h in found { OllamaCatalog.remember(h) }
                let added = found.filter { !before.contains($0) }
                scanning = false
                sessions.setNote(id, added.isEmpty
                    ? (found.isEmpty ? "这个网段上没找到别的 Ollama 或 kinfer" : "找到的都已经在列表里了")
                    : "找到 " + added.map { OllamaCatalog.hostLabel($0) }.joined(separator: "、"))
                healthTick += 1
            }
            await OllamaCatalog.probeAll()
            await MainActor.run { healthTick += 1 }
        }
    }

    private func refreshHealth() {
        Task {
            await OllamaCatalog.probeAll()
            await MainActor.run { healthTick += 1 }
        }
    }

    private func reloadPresets() async {
        guard let s = sessions.selected else { return }
        let fresh = await OllamaCatalog.loadPresets(baseURL: AgentTerminalSessions.host(of: s))
        await MainActor.run { presets = fresh }
    }
}

/// Shows a terminal the sessions own. The container is SwiftUI's to create
/// and destroy; the terminal inside it is not, which is what lets an agent
/// outlive its tab being out of sight.
private struct TerminalSlot: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        mount(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if terminal.superview !== container { mount(in: container) }
    }

    private func mount(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Typing should land in the terminal the moment its tab is shown.
        let terminal = self.terminal
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
    }
}

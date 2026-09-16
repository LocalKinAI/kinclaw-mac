import AppKit
import SwiftTerm
import SwiftUI

/// What the Term tab should run. The model menus in Cowork and Code drop
/// a request in here; SpotlightContentView notices, switches to the tab,
/// and the tab takes it from there.
@MainActor
final class AgentTerminalStore: ObservableObject {
    static let shared = AgentTerminalStore()

    struct Request: Equatable {
        let agent: String
        let host: String
        let model: String
        /// The folder to start in, when the asker has one — Code passes its
        /// repo. nil keeps whatever folder the tab already has.
        let directory: String?
        /// Bumped on every ask, so the same agent on the same model is a
        /// fresh request rather than a no-op.
        let serial: Int
    }

    @Published private(set) var request: Request?
    private var serial = 0

    func run(_ item: AgentLauncher.Installed, host: String, model: String, directory: String? = nil) {
        serial += 1
        request = Request(agent: item.integration.id, host: host, model: model,
                          directory: directory, serial: serial)
    }
}

/// The Term tab: the agent itself, running in a terminal inside the panel.
///
/// Why a terminal rather than our own transcript with our own cards:
/// Claude Code and its kind are interactive TUIs — their own approval
/// prompts, their own scrollback, their own ^C — and `claude -p`'s JSON
/// mode has no approval callback to hang cards on, so a pane that
/// swallowed one would be strictly worse than the real thing. What this
/// tab adds is the environment: the machine and the model you picked.
///
/// The tab keeps its own machine and model, rather than following the
/// panes': a terminal session you started against the LAN box should not
/// move when Cowork switches its brain back to this Mac.
struct AgentTerminalPane: View {
    @ObservedObject private var store = AgentTerminalStore.shared

    /// The tab's own agent, machine and model. Empty host = follow
    /// whatever source the panes are using.
    @AppStorage("kinclaw.term.agent") private var termAgent: String = ""
    @AppStorage("kinclaw.term.host") private var termHost: String = ""
    @AppStorage("kinclaw.term.model") private var termModel: String = ""
    /// Empty = the folder Code is pointed at, else home.
    @AppStorage("kinclaw.term.folder") private var termFolder: String = ""
    @AppStorage("kinclaw.term.recents") private var termRecentsRaw: String = ""
    /// Code's recent repos, offered here too: they are the folders a person
    /// actually works in.
    @AppStorage("kinclaw.kincode.recents") private var codeRecentsRaw: String = ""

    @State private var presets: [BrainPreset] = []
    @State private var serial: Int = 0
    @State private var note: String?
    @State private var scanning = false
    @State private var healthTick = 0

    private var installed: [AgentLauncher.Installed] { AgentLauncher.available }

    /// The agent asked for, else the tab's own, else whatever is here.
    private var agent: AgentLauncher.Installed? {
        let wanted = store.request?.agent ?? termAgent
        return installed.first { $0.integration.id == wanted } ?? installed.first
    }

    private var host: String { termHost.isEmpty ? OllamaCatalog.baseURL : termHost }

    /// Where the agent works: the tab's own choice while it still exists,
    /// else the folder Code is pointed at, else home.
    private var folder: String {
        if !termFolder.isEmpty, FileManager.default.fileExists(atPath: termFolder) { return termFolder }
        return AgentLauncher.defaultDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            if let agent, !termModel.isEmpty {
                TerminalHost(binary: agent.binary,
                             args: agent.integration.args(host, termModel),
                             environment: agent.integration.env(host),
                             directory: folder,
                             serial: serial,
                             onExit: { code in
                                 note = code.map { "进程结束（退出码 \($0)）" } ?? "进程结束了"
                             })
                    .id("\(agent.id)|\(host)")
            } else {
                empty
            }
        }
        .background(Color.black.opacity(0.28))
        .task { await reloadPresets() }
        .onChange(of: store.request) { _, request in adopt(request) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let agent {
                agentMenu(current: agent)
                machineMenu
                modelMenu
                folderMenu
            } else {
                Text("没有可跑的 agent")
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            if let message = note ?? dialectWarning {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(message)
            }
            if agent != nil, !termModel.isEmpty {
                Button("重启") { note = nil; serial += 1 }
                    .controlSize(.small)
                Button("在外部终端打开") { openOutside() }
                    .controlSize(.small)
                    .help("同样的环境，但窗口归终端 app —— 它的权限提示也就不算在 KinClaw 头上")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Which agent. A picker only when there is something to pick
    /// between — one installed agent does not need a menu.
    @ViewBuilder
    private func agentMenu(current: AgentLauncher.Installed) -> some View {
        if installed.count > 1 {
            Menu(current.integration.label) {
                ForEach(installed) { item in
                    Button {
                        note = nil
                        termAgent = item.integration.id
                        serial += 1
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

    /// Whether the chosen machine speaks the chosen agent's dialect — asked
    /// of the host, since a kinfer box can be running a build from before
    /// it learned /v1/messages and /v1/responses. Better said in the header
    /// than discovered as a dead connection in the terminal.
    private var dialectWarning: String? {
        guard let agent, let health = OllamaCatalog.cachedHealth(host), health.reachable else { return nil }
        let (served, path) = agent.integration.dialect == .openAIResponses
            ? (health.openAIResponses, "/v1/responses")
            : (health.anthropicMessages, "/v1/messages")
        guard !served else { return nil }
        return "\(OllamaCatalog.hostLabel(host)) 没有 \(path)，\(agent.integration.label) 用不了这台 —— 更新那台的 kinfer"
    }

    /// Which machine's models the agent talks to. Same catalog as both
    /// brain menus — this Mac, every remembered box, and a LAN scan —
    /// but the choice is the tab's own.
    private var machineMenu: some View {
        Menu {
            let _ = healthTick
            ForEach(OllamaCatalog.knownHosts, id: \.self) { candidate in
                Button {
                    switchMachine(to: candidate)
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
            Button(scanning ? "扫描中…" : "扫描局域网找 Ollama / kinfer…") { scanLAN() }
                .disabled(scanning)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: OllamaCatalog.isRemote || !termHost.isEmpty
                      ? "network" : "laptopcomputer")
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

    private var modelMenu: some View {
        Menu(termModel.isEmpty ? "选个模型" : termModel) {
            if presets.isEmpty {
                Text("\(OllamaCatalog.hostLabel(host)) 上没读到模型")
                    .foregroundColor(.secondary)
            }
            ForEach(presets) { preset in
                Button(preset.label) {
                    note = nil
                    termModel = preset.model
                    serial += 1
                }
            }
            Divider()
            Button("重新读取模型列表") { Task { await reloadPresets() } }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text(installed.isEmpty ? "这台机器上没找到可以跑的 agent" : "先在上面挑一个模型")
                .font(.system(size: 13))
            if installed.isEmpty {
                Text("装好 Claude Code 再重开 app，这一行就会出现。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Where the agent works. Changing it restarts the agent: a process's
    /// working directory is fixed when it starts, and an agent still running
    /// in the old folder while the header names the new one is worse than one
    /// that restarted.
    private var folderMenu: some View {
        Menu {
            ForEach(recentFolders, id: \.self) { path in
                Button {
                    switchFolder(to: path)
                } label: {
                    HStack {
                        if path == folder { Image(systemName: "checkmark") }
                        Text(displayPath(path))
                    }
                }
            }
            Divider()
            Button("选择文件夹…") { pickFolder() }
            if !termFolder.isEmpty {
                Button("跟随 Code 的仓库") { switchFolder(to: "") }
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

    /// The current folder, then the tab's recent ones, then Code's —
    /// deduplicated, with folders that no longer exist left out.
    private var recentFolders: [String] {
        let candidates = [folder]
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

    // MARK: - Doing things

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folder)
        panel.message = "Agent 在哪个文件夹里工作？"
        if panel.runModal() == .OK, let url = panel.url {
            switchFolder(to: url.path)
        }
    }

    /// Make `path` the tab's folder and put it at the front of its recents.
    /// "" goes back to following Code.
    private func rememberFolder(_ path: String) {
        termFolder = path
        guard !path.isEmpty else { return }
        var recents = termRecentsRaw.split(separator: ",").map(String.init).filter { $0 != path }
        recents.insert(path, at: 0)
        termRecentsRaw = recents.prefix(10).joined(separator: ",")
    }

    private func switchFolder(to path: String) {
        rememberFolder(path)
        note = nil
        if !termModel.isEmpty { serial += 1 }
    }

    /// A model menu in Cowork or Code asked for this agent: take its
    /// machine and model as the tab's own and start.
    private func adopt(_ request: AgentTerminalStore.Request?) {
        guard let request else { return }
        note = nil
        termAgent = request.agent
        termHost = request.host
        termModel = request.model
        if let directory = request.directory, !directory.isEmpty {
            rememberFolder(directory)
        }
        serial += 1
        Task { await reloadPresets() }
    }

    /// Point the tab at another machine. The model has to exist there —
    /// carrying a name the new host has never heard of just fails later,
    /// in the terminal, as a 404 nobody asked for.
    private func switchMachine(to candidate: String) {
        termHost = candidate
        note = nil
        Task {
            await OllamaCatalog.probe(candidate)
            let fresh = await OllamaCatalog.loadPresets(baseURL: candidate)
            await MainActor.run {
                presets = fresh
                healthTick += 1
                if fresh.isEmpty {
                    note = "\(OllamaCatalog.hostLabel(candidate)) 连不上或没有模型"
                } else if fresh.contains(where: { $0.model == termModel }) {
                    serial += 1
                } else if let family = termModel.split(separator: ":").first,
                          let near = fresh.first(where: { $0.model.hasPrefix(family) }) {
                    termModel = near.model
                    serial += 1
                } else {
                    let wanted = termModel
                    termModel = ""
                    note = wanted.isEmpty
                        ? nil
                        : "\(OllamaCatalog.hostLabel(candidate)) 上没有 \(wanted)，挑一个"
                }
            }
        }
    }

    private func openOutside() {
        guard let agent else { return }
        note = AgentLauncher.launch(agent, host: host, model: termModel, directory: folder)
    }

    private func scanLAN() {
        guard !scanning else { return }
        scanning = true
        Task {
            let found = await OllamaCatalog.discover()
            await MainActor.run {
                let before = Set(OllamaCatalog.knownHosts)
                for h in found { OllamaCatalog.remember(h) }
                let added = found.filter { !before.contains($0) }
                scanning = false
                note = added.isEmpty
                    ? (found.isEmpty ? "这个网段上没找到别的 Ollama 或 kinfer" : "找到的都已经在列表里了")
                    : "找到 " + added.map { OllamaCatalog.hostLabel($0) }.joined(separator: "、")
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
        let fresh = await OllamaCatalog.loadPresets(baseURL: host)
        await MainActor.run { presets = fresh }
    }
}

/// A `LocalProcessTerminalView` — SwiftTerm's PTY-backed terminal — with
/// the agent running inside it. Restarts when `serial` changes.
private struct TerminalHost: NSViewRepresentable {
    let binary: String
    let args: [String]
    let environment: [String: String]
    let directory: String
    let serial: Int
    let onExit: (Int32?) -> Void

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var started: Int?
        var onExit: ((Int32?) -> Void)?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onExit?(exitCode)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onExit = onExit
        return coordinator
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        start(view, context: context)
        // Typing should land in the terminal the moment the tab opens.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        guard context.coordinator.started != serial else { return }
        view.terminate()
        start(view, context: context)
    }

    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        // Leaving an agent running behind a tab nobody is looking at is
        // how you end up with three of them.
        view.terminate()
    }

    private func start(_ view: LocalProcessTerminalView, context: Context) {
        context.coordinator.started = serial
        // Our PATH has to win, and two PATH= entries in one environment
        // array is anybody's guess, so drop the inherited one first.
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
            .filter { !$0.hasPrefix("PATH=") }
        env.append("PATH=" + AgentLauncher.childPath(for: binary))
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            env.append("\(key)=\(value)")
        }
        // Through the login shell, interactive: the agent starts children
        // of its own (MCP servers, hooks) that want node, and this Mac
        // keeps PATH and nvm in .zshrc — which `zsh -l -c` does not read.
        // Measured: `env node` fails under launchd's PATH and resolves to
        // /opt/homebrew/bin/node under `zsh -l -i -c`. `exec` hands the
        // PTY straight to the agent, so ^C and the exit code are its own.
        let command = ([binary] + args).map(AgentLauncher.shellQuoted).joined(separator: " ")
        view.startProcess(executable: AgentLauncher.loginShell,
                          args: ["-l", "-i", "-c", "exec " + command],
                          environment: env,
                          currentDirectory: directory)
    }
}

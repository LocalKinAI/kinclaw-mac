import AppKit
import SwiftTerm
import SwiftUI

/// What the Term tab should be running. The model menus in Cowork and
/// Code drop a request in here; SpotlightContentView notices, switches to
/// the tab, and the tab starts the process.
@MainActor
final class AgentTerminalStore: ObservableObject {
    static let shared = AgentTerminalStore()

    struct Request: Equatable {
        let agent: String
        let host: String
        let model: String
        /// Bumped on every ask, so running the same agent on the same
        /// model again is a restart rather than a no-op.
        let serial: Int
    }

    @Published private(set) var request: Request?
    private var serial = 0

    func run(_ item: AgentLauncher.Installed, host: String, model: String) {
        serial += 1
        request = Request(agent: item.integration.id, host: host, model: model, serial: serial)
    }
}

/// The Term tab: the agent itself, running in a terminal inside the panel.
///
/// Why a terminal rather than our own transcript with our own cards:
/// Claude Code and its kind are interactive TUIs — their own approval
/// prompts, their own scrollback, their own ^C — and `claude -p`'s JSON
/// mode has no approval callback to hang cards on, so a pane that
/// swallowed one would be strictly worse than the real thing. A PTY runs
/// the real thing; what this tab adds is the environment, which is the
/// whole point: the host and the model you picked in the model menu.
///
/// One caveat worth knowing: the child is spawned by this app, so a file
/// or network prompt it triggers is attributed to KinClawMac. 「在外部终端
/// 打开」 is there for when that matters.
struct AgentTerminalPane: View {
    @ObservedObject private var store = AgentTerminalStore.shared
    /// Last model run here, so the tab can start on its own next time.
    @AppStorage("kinclaw.term.model") private var lastModel: String = ""
    @State private var presets: [BrainPreset] = []
    @State private var note: String?

    private var installed: [AgentLauncher.Installed] { AgentLauncher.available }

    /// The agent asked for, else the only one installed.
    private var agent: AgentLauncher.Installed? {
        if let id = store.request?.agent,
           let match = installed.first(where: { $0.integration.id == id }) {
            return match
        }
        return installed.first
    }

    private var host: String { store.request?.host ?? OllamaCatalog.baseURL }
    private var model: String { store.request?.model ?? lastModel }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            if let agent, !model.isEmpty {
                TerminalHost(binary: agent.binary,
                             args: agent.integration.modelArgs(model),
                             environment: agent.integration.env(host),
                             directory: AgentLauncher.defaultDirectory,
                             serial: store.request?.serial ?? 0,
                             onExit: { code in
                                 note = code.map { "进程结束（退出码 \($0)）" } ?? "进程结束了"
                             })
                    .id(agent.id)
            } else {
                empty
            }
        }
        .background(Color.black.opacity(0.28))
        .task { await loadPresets() }
        .onChange(of: model) { _, m in if !m.isEmpty { lastModel = m } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(agent?.integration.label ?? "没有可跑的 agent")
                .font(.system(size: 12, weight: .medium))
            if agent != nil {
                Text(OllamaCatalog.hostLabel(host))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                modelMenu
            }
            Spacer()
            if let note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if agent != nil, !model.isEmpty {
                Button("重启") { restart() }
                    .controlSize(.small)
                Button("在外部终端打开") {
                    if let agent {
                        note = AgentLauncher.launch(agent, host: host, model: model)
                    }
                }
                .controlSize(.small)
                .help("同样的环境，但窗口归终端 app —— 它的权限提示也就不算在 KinClaw 头上")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// The models on whichever host the source picker is pointing at —
    /// the same list the brain menus show, read from the same catalog.
    private var modelMenu: some View {
        Menu(model.isEmpty ? "选个模型" : model) {
            if presets.isEmpty {
                Text("\(OllamaCatalog.hostLabel(host)) 上没读到模型")
                    .foregroundColor(.secondary)
            }
            ForEach(presets) { preset in
                Button(preset.label) {
                    lastModel = preset.model
                    if let agent {
                        store.run(agent, host: OllamaCatalog.baseURL, model: preset.model)
                    }
                }
            }
            Divider()
            Button("重新读取模型列表") { Task { await loadPresets() } }
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

    private func restart() {
        guard let agent else { return }
        note = nil
        store.run(agent, host: host, model: model)
    }

    private func loadPresets() async {
        let fresh = await OllamaCatalog.loadPresets()
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

import SwiftUI
import WebKit

/// The Montage tab: OpenMontage on the box, where it can be seen and used.
///
/// On the left, standing, the agent that makes the films — the same column as
/// on every Studio tab, but running on the box — with the box to say the first
/// words in until it runs. On the right, OpenMontage's own Backlot board: the
/// production as it happens, and every earlier one in its library, with back,
/// home and reload above it — a board that had been clicked into a project had
/// no way back to the library ("openmontage 应该可以回到首页啊").
/// See `MontageStudio`, `StudioAgent`.
struct MontageView: View {
    @ObservedObject private var studio = MontageStudio.shared
    @ObservedObject private var agent = StudioAgent.montage
    @State private var words = ""
    /// The board shows the library of every project instead of following the
    /// one the agent is working in.
    @State private var library = false

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                AgentDock(agent: agent, examples: ["一分钟的五饼二鱼，H3 拍，配乐", "三十秒讲清楚复利，配数据动画"],
                          widest: space.size.width - 520, onExample: { agent.say($0) }) {
                    // Running, the agent's own prompt is where to type: this
                    // box is only for the first words ("为什么有两个输入框呢").
                    starter
                }
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    board.frame(maxHeight: .infinity)
                }
            }
        }
        .tint(Theme.accent)
        // The agent is how this tab is used: its column is out when the tab is.
        .onAppear { if !agent.running { agent.shown = true } }
        .task { await studio.openBoard() }
    }

    // MARK: Header: where the board is, and the way home

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if !agent.shown {
                Button { agent.shown = true } label: { Label("agent", systemImage: "sidebar.left") }
                    .buttonStyle(.quietFilled)
                    .help("把 agent 那一栏拿出来")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenMontage").font(.kinTitle)
                Text("在盒子上 · 写稿、出图、拍片、配乐、剪辑，用盒子上的 Qwen-Image、H3 和 MiniMax Music")
                    .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if studio.board == .up {
                HStack(spacing: 2) {
                    Button { studio.web?.goBack() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.quiet).disabled(!studio.canGoBack)
                        .help("后退")
                    Button { goHome() } label: { Image(systemName: "house") }
                        .buttonStyle(.quiet)
                        .help("回到看板首页：全部项目")
                    Button { studio.web?.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.quiet)
                        .help("刷新看板")
                }
                if studio.project != nil {
                    Button { library.toggle() } label: {
                        ChipLabel(title: library ? "看全部项目" : "跟着当前项目", symbol: library ? "square.grid.2x2" : "scope", on: !library)
                    }
                    .buttonStyle(.plain)
                    .help(library ? "看板在显示全部项目；点一下回到 agent 正在做的那个" : "看板跟着 agent 正在做的项目；点一下看全部")
                }
                Button { NSWorkspace.shared.open(boardURL) } label: { Image(systemName: "safari") }
                    .buttonStyle(.quiet)
                    .help("在浏览器里打开看板（经过到盒子的 ssh 隧道，app 开着的时候都能看）")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// The library, whatever the board was showing — a project the agent
    /// opened, or one clicked into on the board itself.
    private func goHome() {
        library = true
        studio.web?.load(URLRequest(url: MontageStudio.boardURL))
    }

    // MARK: The board

    private var boardURL: URL {
        guard !library, let project = studio.project else { return MontageStudio.boardURL }
        return MontageStudio.boardURL.appendingPathComponent("p").appendingPathComponent(project)
    }

    @ViewBuilder
    private var board: some View {
        switch studio.board {
        case .up:
            BoardWeb(url: boardURL)
        case .idle, .starting:
            placeholder {
                ProgressView().controlSize(.small)
                Text("在盒子上起 OpenMontage 的看板…").font(.kinLabel).foregroundStyle(.secondary)
            }
        case .down(let why):
            placeholder {
                Label(why, systemImage: "exclamationmark.triangle").font(.kinLabel).foregroundStyle(Theme.notice)
                    .multilineTextAlignment(.center)
                Button("再试一次") { Task { await studio.openBoard() } }.buttonStyle(.quietFilled)
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
    }

    // MARK: The first words

    private var starter: some View {
        // With a stopped agent's screen still up, what is typed here goes on
        // in that conversation.
        let after = agent.terminal != nil
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(after ? "接着跟它说：回到上面这段对话" : "想拍什么？比如：一分钟的五饼二鱼，H3 拍，配乐。它先写方案和剧本给你批，再出图、拍片、配乐、剪辑",
                      text: $words, axis: .vertical)
                .textFieldStyle(.plain).font(.kinBody).lineLimit(3...8)
                .onSubmit(send)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            Button(after ? "接着说" : "开拍", action: send)
                .buttonStyle(.primary)
                .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("开一个 agent（\(agent.whereTitle)，\(agent.brainTitle)，经桥操作盒子上的 OpenMontage），第一句就是这个")
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func send() {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        words = ""
        agent.say(text)
    }
}

/// Backlot, in a web view. Loaded once per address — SwiftUI's updates that
/// change nothing do not reload it — and handed to the studio for back, home
/// and reload.
private struct BoardWeb: NSViewRepresentable {
    let url: URL

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { MontageStudio.shared.canGoBack = webView.canGoBack }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            MainActor.assumeIsolated { MontageStudio.shared.canGoBack = webView.canGoBack }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        context.coordinator.loaded = url
        MontageStudio.shared.web = view
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        MontageStudio.shared.web = view
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        view.load(URLRequest(url: url))
    }
}

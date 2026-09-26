import SwiftUI

/// The agent of a Studio tab, standing along its left side — the same on
/// every one: what it thinks with and where it runs, its terminal, and a way
/// to put it away while it keeps working. See `StudioAgent`.
///
/// A column, not a strip along the bottom ("对话 agent 应该在左侧竖立着"): a
/// conversation grows downwards and reads better tall, and what the tab shows —
/// a film, a board made for a wide screen — keeps the width. Chat on the left,
/// the work on the right, as in the Claude app. It starts about 85 columns
/// wide, what Claude Code's tables and diffs want before they wrap, and its
/// edge can be dragged.
struct AgentDock<Starter: View>: View {
    @ObservedObject var agent: StudioAgent
    @ObservedObject private var catalog = BrainCatalog.shared
    /// Things to try, for the dock with nothing running in it.
    var examples: [String]
    /// The most of the tab it may take.
    var widest: CGFloat
    /// What a click on an example does — say it, with whatever the tab adds.
    var onExample: (String) -> Void
    /// Where to type the first words, for a tab with no box of its own.
    var starter: Starter

    @AppStorage private var width: Double
    @State private var from: Double?
    @State private var restarting = false

    init(agent: StudioAgent, examples: [String], widest: CGFloat = .infinity,
         onExample: @escaping (String) -> Void, @ViewBuilder starter: () -> Starter) {
        self.agent = agent
        self.examples = examples
        self.widest = widest
        self.onExample = onExample
        self.starter = starter()
        _width = AppStorage(wrappedValue: 600, "kinclaw.agent.width")
    }

    private var shownWidth: CGFloat { min(max(CGFloat(width), 360), max(widest, 360)) }

    var body: some View {
        Group {
            if agent.shown {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        content.frame(maxHeight: .infinity)
                        // Not running — never started, or stopped with its
                        // screen still up — the first words go in here.
                        if !agent.running { starter }
                    }
                    .frame(width: shownWidth)
                    .background(Theme.sidebar)
                    edge
                }
            } else if agent.running {
                // Put away and still working: a strip that says so.
                Button { agent.shown = true } label: {
                    VStack(spacing: 10) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 14)
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
                    .background(Theme.sidebar)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("agent 在干活（\(agent.whereTitle) · \(agent.brainTitle)）：展开")
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 0.5) }
            }
        }
        .task { await catalog.refresh() }
        .onAppear { agent.checkResumable() }
    }

    /// Its right edge: drag it for a wider terminal or a wider tab.
    private var edge: some View {
        Rectangle().fill(Theme.hairline).frame(width: 0.5)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(coordinateSpace: .global)
                        .onChanged { drag in
                            if from == nil { from = Double(shownWidth) }
                            width = min(1100, max(360, (from ?? width) + drag.translation.width))
                        }
                        .onEnded { _ in from = nil })
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("agent").font(.kinHeadline)
                Text(agent.whereTitle).font(.kinCaption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.well))
                Spacer(minLength: 6)
                if agent.terminal != nil {
                    Button("重启") { if agent.running { restarting = true } else { agent.start(continuing: true) } }
                        .buttonStyle(.quiet)
                        .help("重开 agent，回到它这段对话接着说。卡住了、或者换了 agent 或脑子之后，用这个")
                        .confirmationDialog("重启 agent？", isPresented: $restarting) {
                            Button("重启") { agent.start(continuing: true) }
                        } message: {
                            Text("它手上这一步会被打断；已经交给盒子跑的任务会接着跑完。重启后回到这段对话，接着说就行。")
                        }
                }
                if agent.running {
                    Button("停") { agent.stop() }
                        .buttonStyle(.quiet)
                        .help("结束这个 agent。已经在拍、在跑的会自己跑完；它做过的都还在页面上")
                }
                Button { agent.shown = false } label: { Image(systemName: "sidebar.left").font(.system(size: 12)) }
                    .buttonStyle(.quiet)
                    .help(agent.running ? "收起来，它接着干" : "收起来")
            }
            HStack(spacing: 6) {
                harnessMenu
                brainMenu
                Spacer(minLength: 0)
            }
            if let note = agent.note {
                Label(note, systemImage: "hand.raised").font(.kinCaption).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal: false, vertical: true)
            } else if agent.running {
                Text("在下面它的终端里说话；要批准的，它会在那里问").font(.kinCaption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Which agent: Claude Code or Codex. The next one started is this one.
    private var harnessMenu: some View {
        Menu {
            ForEach(AgentHarness.allCases, id: \.self) { harness in
                Button { agent.harness = harness } label: {
                    Label(harness.title + (harness.binary == nil ? "（这台 Mac 没装）" : ""),
                          systemImage: agent.harness == harness ? "checkmark" : "")
                }
                .disabled(harness.binary == nil)
            }
        } label: {
            ChipLabel(title: agent.harness.title, symbol: "terminal", menu: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("用哪个 agent：Claude Code 或 Codex。换了之后下一次开的用新的，正在跑的不变")
    }

    /// Every place a brain can come from, grouped.
    private var brainMenu: some View {
        Menu {
            ForEach(AgentBrain.Source.allCases, id: \.self) { source in
                Section(AgentBrain.section(source, for: agent.harness)) {
                    if source == .account {
                        choice(.account)
                    } else if let models = catalog.models[source], !models.isEmpty {
                        ForEach(models, id: \.self) { model in choice(AgentBrain(source: source, model: model)) }
                    } else {
                        Text(catalog.models[source] == nil ? "在问…" : "没连上，或者没有模型")
                    }
                }
            }
        } label: {
            ChipLabel(title: agent.brainTitle, symbol: "brain", menu: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("agent 用哪个模型想事情：它自己登录的账号（Claude 订阅 / ChatGPT）、这台 Mac 的 Ollama、盒子上的 Ollama 或 kinfer。换了之后下一次开的 agent 用新的，正在跑的不变")
    }

    private func choice(_ brain: AgentBrain) -> some View {
        Button { agent.brain = brain } label: {
            Label(brain.title(for: agent.harness), systemImage: agent.brain == brain ? "checkmark" : "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let terminal = agent.terminal {
            VStack(spacing: 0) {
                TerminalSlot(terminal: terminal)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(nsColor: NSColor(calibratedWhite: 0.06, alpha: 1)))
                if !agent.running { again }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("用大白话说，它来操作这一页。它会先说打算怎么做，要花时间的事等你点头。")
                    .font(.kinLabel).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    ForEach(examples, id: \.self) { example in
                        Button { onExample(example) } label: { ChipLabel(title: example, symbol: "sparkles") }
                            .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    if agent.resumable {
                        Button("接着上一次") { agent.start(continuing: true) }
                            .buttonStyle(.quietFilled)
                            .help("回到上一次的对话，停在那里等你说话（app 退出时打断的，从这里接着做）")
                    }
                    Button("只打开 agent") { agent.start() }
                        .buttonStyle(.quietFilled)
                        .help("先开着，在终端里自己跟它说")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension AgentDock {
    /// Under the screen of an agent that has stopped, the screen still up:
    /// starting it again ("加个可以重启的按钮").
    fileprivate var again: some View {
        HStack(spacing: 8) {
            Text("它停了").font(.kinCaption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if agent.resumable {
                Button { agent.start(continuing: true) } label: { Label("重启，接着这段对话", systemImage: "arrow.clockwise") }
                    .buttonStyle(.primary)
                    .help("再开 agent，回到这段对话，停在那里等你说话")
                Button("新开一个") { agent.start() }
                    .buttonStyle(.quietFilled)
                    .help("开一个新的 agent，从头说")
            } else {
                Button { agent.start() } label: { Label("重启", systemImage: "arrow.clockwise") }
                    .buttonStyle(.primary)
                    .help("再开一个 agent")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}

extension AgentDock where Starter == EmptyView {
    init(agent: StudioAgent, examples: [String], widest: CGFloat = .infinity, onExample: @escaping (String) -> Void) {
        self.init(agent: agent, examples: examples, widest: widest, onExample: onExample) { EmptyView() }
    }
}

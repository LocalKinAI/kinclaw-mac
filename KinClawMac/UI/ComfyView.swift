import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// The Comfy tab: ComfyUI's ready-made workflows as forms. Pick one on the
/// left (or say what you want and let the writer pick), fill in what it asks
/// for, run it on the box; what it made comes back here and to the art folder.
/// The node editor is one button away for when a form is not enough — the
/// same graph, so what is changed there is what runs.
struct ComfyView: View {
    @ObservedObject private var studio = ComfyStudio.shared
    @ObservedObject private var box = BoxServices.shared
    /// An agent with the Comfy tools, docked under the tab. See `StudioAgent`.
    @ObservedObject private var agent = StudioAgent.comfy
    /// What the sentence at the top goes to: the agent, which picks, runs,
    /// looks and tries again; or the writer model, which picks a template
    /// and fills it in once.
    @AppStorage("kinclaw.comfy.byAgent") private var byAgent = true
    @State private var search = ""
    @AppStorage("kinclaw.comfy.category") private var category = ""
    @AppStorage("kinclaw.comfy.cloud") private var showCloud = false
    @AppStorage("kinclaw.comfy.runnable") private var onlyRunnable = false
    @State private var linking = false
    @State private var pulling = false
    @State private var browsingPrompts = false
    @State private var fetchingAll = false
    @State private var link = ""
    @State private var words = ""
    @State private var editing = false
    @State private var naming = false
    @State private var name = ""
    @State private var confirming: ComfyStudio.Missing?
    @State private var showingNotes = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                AgentDock(agent: agent, examples: ["一张 9:16 的海报：雨夜的书店，暖光", "把最近出的那张图放大到 4K", "找一个图生视频的工作流，让这张图动起来"],
                          widest: space.size.width - 250 - 480) { agent.say($0) }
                sidebar.frame(width: 250).background(Theme.sidebar)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                VStack(spacing: 0) {
                    askBar
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    if studio.current == nil {
                        welcome
                    } else {
                        ScrollView { detail.padding(.horizontal, 24).padding(.vertical, 18).frame(maxWidth: 1100).frame(maxWidth: .infinity) }
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        runBar
                    }
                }
            }
        }
        .tint(Theme.accent)
        .task { if studio.templates.isEmpty { await studio.refresh() } }
        .onAppear { if !agent.running { agent.shown = true } }   // its column out, as on Montage
        // A workflow .json, or a PNG ComfyUI made, dropped anywhere on the tab.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ["json", "png"].contains(url.pathExtension.lowercased()) else { return }
                    Task { @MainActor in category = "我的"; await studio.importWorkflow(from: url) }
                }
            }
            return true
        }
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $editing, onDismiss: { Task { await studio.readFields() } }) { editor }
        .sheet(isPresented: $pulling) { PullModelSheet(studio: studio) }
        .sheet(isPresented: $browsingPrompts) { PromptLibrarySheet(studio: studio) }
        .confirmationDialog("把缺的 \(studio.missing.count) 个模型都拉到盒子上？", isPresented: $fetchingAll) {
            Button("全部拉取（\(totalMissing)）") { Task { await studio.fetchAll() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(studio.missing.map { "\($0.directory)/\($0.name) · \($0.onBox != nil ? "盒子上已有，直接链接" : $0.bytes.map(ComfyStudio.gigabytes) ?? "大小不明")" }
                .joined(separator: "\n") + "\n\n盒子自己下（用盒子上登录的 Hugging Face 账号），断了能续。")
        }
        .alert("从网址导入工作流", isPresented: $linking) {
            TextField("指向 .json 或 .png 的网址（GitHub 页面也行）", text: $link)
            Button("导入") { let l = link; category = "我的"; Task { await studio.importWorkflow(from: l) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("网页本身不行，要文件的地址。社区的工作流常常要装插件，导入后会告诉你缺什么。")
        }
        .alert("另存为我的工作流", isPresented: $naming) {
            TextField("名字", text: $name)
            Button("存") { Task { await studio.save(as: name) } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(confirming.map { "下载 \($0.name) 到盒子？" } ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { model in
            Button("下载（\(model.bytes.map(ComfyStudio.gigabytes) ?? "大小不明")）") { Task { await studio.fetch(model) } }
            Button("取消", role: .cancel) {}
        } message: { model in
            Text("从 \(URL(string: model.url)?.host ?? model.url) 下到盒子的 ~/ComfyUI/models/\(model.directory)/，\(model.bytes.map(ComfyStudio.gigabytes) ?? "大小不明")。盒子自己下，不经过这台 Mac。")
        }
    }

    // MARK: Templates

    private var shown: [ComfyStudio.Template] {
        let pool: [ComfyStudio.Template]
        switch category {
        case "我的": pool = studio.saved
        case "": pool = studio.saved + studio.templates
        default: pool = studio.saved.filter { $0.belongs(to: category) } + studio.templates.filter { $0.category == category }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let found = pool.filter { t in
            (showCloud || t.local) && (!onlyRunnable || studio.readiness[t.name]?.runs == true)
                && (q.isEmpty || [t.title, t.name, t.description, t.models.joined(separator: " "), t.tags.joined(separator: " ")]
                .contains { $0.lowercased().contains(q) })
        }
        // What runs now first, then what is one download away, then the rest.
        func rank(_ t: ComfyStudio.Template) -> Int {
            guard let r = studio.readiness[t.name] else { return 3 }
            return r.runs ? 0 : r.nodes.isEmpty ? (r.lacking < r.models ? 1 : 2) : 4
        }
        return found.enumerated().sorted { a, b in
            rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }.map(\.element)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
                TextField("找模板：qwen、视频、换背景…", text: $search).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            HStack {
                Picker("", selection: $category) {
                    Text("全部").tag("")
                    Text("我的").tag("我的")
                    Text("作品").tag("作品")
                    ForEach(studio.categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                Toggle("含云端", isOn: $showCloud).toggleStyle(.checkbox).controlSize(.small)
                    .help("ComfyUI 的 api_ 模板调用付费云服务，不在盒子上跑。默认不列")
            }
            HStack(spacing: 6) {
                Toggle("只看能跑的", isOn: $onlyRunnable).toggleStyle(.checkbox).controlSize(.small)
                    .help("盒子上模型和节点都齐的。其余的缺什么，点开能看到，也能下载")
                if studio.scanning { ProgressView().controlSize(.mini) }
                Spacer()
                Menu {
                    Button("从文件导入（.json 或 ComfyUI 出的 PNG）…") { importFile() }
                    Button("从网址导入…") { link = ""; linking = true }
                    Divider()
                    Button("拉模型…（Hugging Face 上任何一个文件）") { pulling = true }
                    Divider()
                    Button("提示词库（Awesome AI Image Prompts）…") { browsingPrompts = true }
                    Divider()
                    Button("重新检查哪些能跑") { Task { await studio.scan() } }
                    Divider()
                    Menu("去哪找工作流") {
                        ForEach(Self.sources, id: \.0) { source in
                            Button(source.0) { if let url = URL(string: source.1) { NSWorkspace.shared.open(url) } }
                        }
                    }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("导入别人的工作流，或者去哪里找")
            }
            if category == "作品" {
                runsList
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { t in row(t) }
                    }
                }
                let runnable = studio.readiness.values.filter(\.runs).count
                Text("\(shown.count) 个\(studio.readiness.isEmpty ? "" : " · 盒子上能直接跑 \(runnable) 个")")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(8)
    }

    private func row(_ t: ComfyStudio.Template) -> some View {
        Button { Task { await studio.open(t) } } label: {
            HStack(spacing: 8) {
                thumbnail(t).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(t.category).font(.system(size: 9)).foregroundColor(.secondary)
                        if let size = t.size, size > 0 { Text(ComfyStudio.gigabytes(size)).font(.system(size: 9)).foregroundColor(.secondary) }
                        if !t.local { Text("云").font(.system(size: 9, weight: .bold)).foregroundColor(.orange) }
                        badge(t)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(studio.current?.id == t.id ? 0.10 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t.description)
    }

    @ViewBuilder private func badge(_ t: ComfyStudio.Template) -> some View {
        if let r = studio.readiness[t.name] {
            if r.runs {
                Label("能跑", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.accent)
            } else if !r.nodes.isEmpty {
                Text("缺插件").font(.system(size: 9, weight: .semibold)).foregroundColor(.red)
                    .help("要装社区节点：" + r.nodes.joined(separator: "、"))
            } else if r.lacking > 0 {
                Text(r.lacking < r.models ? "缺 \(r.lacking)/\(r.models) 个模型" : "缺模型")
                    .font(.system(size: 9)).foregroundColor(.orange)
            }
        }
    }

    /// Where ComfyUI workflows are published. The official ones are what the
    /// list already shows; the rest are community workflows, which often need
    /// custom nodes the box does not have (the list says so after import).
    static let sources: [(String, String)] = [
        ("ComfyUI 官方模板（就是左边这些）", "https://github.com/Comfy-Org/workflow_templates"),
        ("ComfyUI 官方示例（图片里带工作流，拖 PNG 进来）", "https://comfyanonymous.github.io/ComfyUI_examples/"),
        ("OpenArt 工作流", "https://openart.ai/workflows/home"),
        ("Civitai（筛选 Workflows）", "https://civitai.com/models?types=Workflows"),
        ("ComfyWorkflows", "https://comfyworkflows.com"),
        ("RunComfy 工作流", "https://www.runcomfy.com/comfyui-workflows"),
    ]

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .png]
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        Task { for file in files { await studio.importWorkflow(from: file) } }
        category = "我的"
    }

    @ViewBuilder private func thumbnail(_ t: ComfyStudio.Template) -> some View {
        if let url = t.thumbnail {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                Color.primary.opacity(0.06).overlay(Image(systemName: t.mediaType == "video" ? "film" : "photo").foregroundColor(.secondary))
            }
        } else {
            Color.primary.opacity(0.06).overlay(Image(systemName: "folder").foregroundColor(.secondary))
        }
    }

    private var runsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(studio.runs) { run in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(run.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(run.when, style: .relative).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) { ForEach(run.outputs, id: \.self) { output($0, size: 56) } }
                        }
                        HStack {
                            Button("再开这个工作流") { Task { await studio.reopen(run) } }
                            Button("在 Finder 里") { NSWorkspace.shared.activateFileViewerSelecting([run.folder]) }
                        }
                        .controlSize(.mini)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
                if studio.runs.isEmpty { Text("还没跑过").font(.system(size: 11)).foregroundColor(.secondary) }
            }
        }
    }

    // MARK: Words

    private var askBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { byAgent.toggle() } label: {
                        ChipLabel(title: "agent", symbol: byAgent ? "checkmark" : "sparkles", on: byAgent)
                    }
                    .buttonStyle(.plain)
                    .help(byAgent ? "开着：这句话交给 agent（这台 Mac 上的 Claude Code，拿着 Comfy 的工具）——它挑工作流、跑、看结果、不对再改。关掉：写提示词的模型挑一个模板、填一次表"
                          : "关着：写提示词的模型挑一个模板、填一次表。打开：交给 agent，它会挑、跑、看、再改")
                    if byAgent, agent.running {
                        // Its own prompt, in the dock below, is where to type
                        // while it runs — not a second box up here.
                        Text("agent 在跑：在左边它的终端里说").font(.kinBody).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    } else {
                        TextField(byAgent ? "跟 agent 说你想要什么：一张 9:16 的海报、把这张照片换成夜景、让这张图动起来……"
                                  : studio.current == nil ? "说你想要什么：一张 9:16 的海报、把这张照片换成夜景、让这张图动起来……"
                                                        : "让 agent 改这个工作流：换成竖屏、提示词改成……、步数多一点", text: $words)
                            .textFieldStyle(.plain).font(.kinBody)
                            .onSubmit(send)
                    }
                    Button { browsingPrompts = true } label: { Image(systemName: "text.book.closed") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("提示词库：别人写好的高质量出图提示词，挑一个用，或者让 agent 换成你的主题")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                if byAgent, agent.running {
                    Button(agent.shown ? "收起终端" : "展开终端") { agent.shown.toggle() }.buttonStyle(.quietFilled)
                } else {
                    Button(byAgent ? "交给 agent" : studio.current == nil ? "找工作流" : "改", action: send)
                        .buttonStyle(.primary).fixedSize()
                        .disabled(words.trimmingCharacters(in: .whitespaces).isEmpty || (!byAgent && studio.working != nil))
                }
                if studio.current != nil {
                    Button { studio.close() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.quiet).help("关掉这个工作流，回到按一句话找")
                }
            }
            if let line = status {
                HStack(spacing: 6) {
                    if studio.working != nil { ProgressView().controlSize(.mini) }
                    Text(line).font(.kinCaption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var status: String? {
        if let working = studio.working {
            var text = working
            if let since = studio.since, working.hasPrefix("在跑") { text += " · \(Int(now.timeIntervalSince(since))) 秒" }
            return text + "…"
        }
        return studio.note
    }

    private func send() {
        let text = words
        words = ""
        if byAgent { agent.say(text) } else { Task { await studio.ask(text) } }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.accentWash))
            Text("ComfyUI 的现成工作流").font(.kinTitle)
            Text("左边挑一个模板，填表、运行；或者上面直接说想要什么，让 agent 挑模板、写提示词。\n不够用的时候，「编辑器」里就是 ComfyUI 自己的节点图。")
                .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(["一张 9:16 的海报", "把这张照片换成夜景", "让这张图动起来", "人像放大到 4K"], id: \.self) { example in
                    Button { words = example } label: { ChipLabel(title: example, symbol: "sparkles") }
                        .buttonStyle(.plain)
                }
            }
            if box.states[.comfy] != .up {
                Button("启动盒子上的 ComfyUI") { Task { await box.start(.comfy); await studio.refresh() } }
                    .buttonStyle(.primary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: The open workflow

    @ViewBuilder private var detail: some View {
        if let t = studio.current {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(t).frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.system(size: 14, weight: .semibold))
                        Text(t.description).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button("编辑器") { Task { await studio.pushAll(); editing = true } }
                                .help("ComfyUI 自己的节点图：连线、加节点、换模型。关掉以后表单跟着变")
                            Button("另存为…") { name = t.title; naming = true }
                            if !studio.notes.isEmpty { Button(showingNotes ? "收起说明" : "模板说明") { showingNotes.toggle() } }
                        }
                        .controlSize(.small)
                    }
                }
                if !studio.missingNodes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("盒子上的 ComfyUI 没有这些节点（社区插件），这个工作流跑不了", systemImage: "puzzlepiece.extension")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.red)
                        Text(studio.missingNodes.joined(separator: "、")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Text("要在盒子的 ~/ComfyUI/custom_nodes 里装上对应的插件（盒子上现在没有 ComfyUI-Manager）。")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.07)))
                }
                if !studio.missing.isEmpty { missingModels }
                if showingNotes {
                    ForEach(studio.notes, id: \.self) { note in
                        Text((try? AttributedString(markdown: note, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(note))
                            .font(.system(size: 11)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }
                form
                if let last = studio.runs.first, last.title == t.title {
                    Text("上一次").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) { ForEach(last.outputs, id: \.self) { output($0, size: 220) } }
                    }
                }
            }
        }
    }

    private var totalMissing: String {
        let download = studio.missing.filter { $0.onBox == nil }
        let bytes = download.compactMap { m in m.bytes.map { $0 - (m.partial ?? 0) } }.reduce(0, +)
        let linked = studio.missing.count - download.count
        return (bytes > 0 ? "下载 " + ComfyStudio.gigabytes(bytes) : "下载 \(download.count) 个")
            + (download.contains { $0.bytes == nil } && bytes > 0 ? " 以上" : "")
            + (linked > 0 ? "，链接 \(linked) 个" : "")
    }

    private var missingModels: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("盒子上缺这些模型，跑之前要先有", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.orange)
                Spacer()
                if studio.missing.count > 1 {
                    Button("全部拉取（\(totalMissing)）") { fetchingAll = true }.controlSize(.small)
                        .disabled(studio.missing.allSatisfy { studio.fetching[$0.id] != nil })
                }
            }
            ForEach(studio.missing) { m in
                HStack {
                    Text(m.directory == "?" ? m.name : "\(m.directory)/\(m.name)").font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let state = studio.fetching[m.id] {
                        Text("在下 \(state)").font(.system(size: 10)).foregroundColor(.secondary)
                    } else {
                        if m.onBox != nil {
                            Button("链接（盒子上已有）") { Task { await studio.fetch(m) } }.controlSize(.small)
                                .help("同一个文件在 \(m.onBox ?? "")，不用再下，链接过去就行")
                        } else {
                            if m.url.isEmpty {
                                Text("工作流没写去哪下 → 用「拉模型…」").font(.system(size: 10)).foregroundColor(.secondary)
                            } else {
                                if let got = m.partial {
                                    Text("只下了 \(m.bytes.map { "\(got * 100 / max($0, 1))%" } ?? ComfyStudio.gigabytes(got))，中途断了")
                                        .font(.system(size: 10)).foregroundColor(.orange)
                                    Button("接着下") { confirming = m }.controlSize(.small)
                                } else {
                                    Text(m.bytes.map(ComfyStudio.gigabytes) ?? "?").font(.system(size: 10)).foregroundColor(.secondary)
                                    Button("下载") { confirming = m }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    private var groups: [(title: String, fields: [ComfyStudio.Field])] {
        var out: [(String, [ComfyStudio.Field])] = []
        for f in studio.fields {
            let key = f.nodeTitle
            if out.last?.0 == key { out[out.count - 1].1.append(f) } else { out.append((key, [f])) }
        }
        return out
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(group.fields) { field in fieldRow(field) }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.035)))
            }
        }
    }

    private func binding(_ field: ComfyStudio.Field) -> Binding<String> {
        Binding(get: { studio.fields.first { $0.id == field.id }?.value ?? "" },
                set: { value in if let i = studio.fields.firstIndex(where: { $0.id == field.id }) { studio.fields[i].value = value } })
    }

    @ViewBuilder private func fieldRow(_ field: ComfyStudio.Field) -> some View {
        if field.isFile {
            HStack {
                Text(field.name).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                Text(field.value).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .foregroundColor(field.needsInput ? .orange : .primary)
                if field.needsInput { Text("模板示例，换成你的").font(.system(size: 9)).foregroundColor(.orange) }
                Spacer()
                Button("选文件…") { pick(into: field) }.controlSize(.small)
            }
        } else if field.isLong {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.name).font(.system(size: 11))
                TextEditor(text: binding(field))
                    .font(.system(size: 12)).frame(minHeight: 70, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(4).background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            }
        } else if let options = field.options {
            HStack {
                Text(field.name).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                Picker("", selection: binding(field)) {
                    if !options.contains(field.value) { Text(field.value).tag(field.value) }
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().controlSize(.small)
            }
        } else if field.kind == "toggle" || field.kind == "boolean" {
            Toggle(field.name, isOn: Binding(get: { binding(field).wrappedValue == "true" },
                                             set: { binding(field).wrappedValue = $0 ? "true" : "false" }))
                .toggleStyle(.checkbox).font(.system(size: 11))
        } else {
            HStack {
                Text(field.name).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                TextField("", text: binding(field)).textFieldStyle(.roundedBorder).controlSize(.small).frame(maxWidth: 220)
                if let min = field.min, let max = field.max, field.kind == "number", !field.isSeed, max < 1e6 {
                    Text("\(trim(min))–\(trim(max))").font(.system(size: 9)).foregroundColor(.secondary)
                }
                if field.isSeed {
                    Toggle("固定", isOn: $studio.keepSeed).toggleStyle(.checkbox).controlSize(.small)
                        .help("不勾：每次运行换一个新种子。勾上：用框里这个，好复现")
                }
            }
        }
    }

    private func trim(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }

    private func pick(into field: ComfyStudio.Field) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = field.name == "video" ? [.movie] : field.name == "audio" ? [.audio] : [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await studio.upload(url, into: field) }
    }

    private var runBar: some View {
        HStack(spacing: 10) {
            if studio.working != nil, studio.since != nil {
                Button("停") { studio.stop() }
                if let p = studio.progress { ProgressView(value: p).frame(width: 160) } else { ProgressView().controlSize(.small) }
            } else {
                Button("运行") { studio.run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(studio.working != nil || studio.current == nil)
                if let busy = studio.busyElsewhere ?? studio.blocked {
                    Text(busy).font(.system(size: 10)).foregroundColor(.orange).lineLimit(2)
                }
            }
            Spacer()
            Text("跑之前会让出 Film 画图服务的内存；Film/Motion 拍片时会叫 ComfyUI 放下模型")
                .font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(10)
    }

    // MARK: Results and editor

    @ViewBuilder private func output(_ file: URL, size: CGFloat) -> some View {
        let ext = file.pathExtension.lowercased()
        Group {
            if ["mp4", "mov", "webm", "m4v"].contains(ext) {
                LoopingVideoView(url: file)
            } else if let image = NSImage(contentsOf: file) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Color.primary.opacity(0.06).overlay(Text(ext).font(.system(size: 10)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { NSWorkspace.shared.open(file) }
        .help(file.lastPathComponent)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ComfyUI 编辑器 · \(studio.current?.title ?? "")").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("在这里改的就是要跑的图；关掉后表单会重新读").font(.system(size: 10)).foregroundColor(.secondary)
                Button("完成") { editing = false }.keyboardShortcut(.defaultAction)
            }
            .padding(8)
            ComfyWebSlot(view: studio.web)
        }
        .frame(minWidth: 1100, minHeight: 720)
    }
}

/// The studio's web view, shown in the editor sheet and handed back when the
/// sheet closes — the page (and the graph in it) outlives the sheet.
private struct ComfyWebSlot: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        mount(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if view.superview !== container { mount(in: container) }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for sub in container.subviews where sub is WKWebView {
            sub.removeFromSuperview()
            sub.translatesAutoresizingMaskIntoConstraints = true
            sub.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        }
    }

    private func mount(in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// 拉模型: any model file on Hugging Face, into the folder of ComfyUI's it
/// belongs in, downloaded by the box itself.
private struct PullModelSheet: View {
    @ObservedObject var studio: ComfyStudio
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var folders: [String] = []
    @State private var folder = "diffusion_models"
    @State private var size: Int64?
    @State private var checked = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("拉模型到盒子").font(.system(size: 14, weight: .semibold))
            Text("贴 Hugging Face 上一个模型文件的链接（文件页面或下载链接都行）。ComfyUI 模板说明里的「Model Links」就是这种。盒子自己下，用盒子上登录的 HF 账号，要点同意的模型先在网页上点。")
                .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("https://huggingface.co/Comfy-Org/…/resolve/main/…/xxx.safetensors", text: $link)
                .textFieldStyle(.roundedBorder)
                .onChange(of: link) { _, _ in guess() }
            HStack {
                Text("放进").font(.system(size: 11))
                Picker("", selection: $folder) { ForEach(folders, id: \.self) { Text($0).tag($0) } }
                    .labelsHidden().frame(width: 200)
                Spacer()
                if let size { Text(ComfyStudio.gigabytes(size)).font(.system(size: 11)) }
                else if !checked.isEmpty { Text("大小不明（可能要登录才能看）").font(.system(size: 10)).foregroundColor(.secondary) }
                if let free = studio.boxFree { Text("盒子剩 \(ComfyStudio.gigabytes(free))").font(.system(size: 10)).foregroundColor(.secondary) }
            }
            let active = studio.pulls + studio.missing.filter { studio.fetching[$0.id] != nil }
            if !active.isEmpty {
                Divider()
                ForEach(active) { m in
                    HStack {
                        Text(m.directory == "?" ? m.name : "\(m.directory)/\(m.name)").font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(studio.fetching[m.id] ?? "排队").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            if let note = studio.note { Text(note).font(.system(size: 11)).foregroundColor(.secondary).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("关") { dismiss() }
                Button("拉") {
                    let l = link, f = folder
                    link = ""; size = nil; checked = ""
                    Task { await studio.pull(l, into: f) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ComfyStudio.understand(link, folders: folders).map { _ in false } ?? true)
            }
        }
        .padding(16)
        .frame(width: 560)
        .task {
            folders = await studio.folders()
            _ = await studio.boxFreeBytes()
        }
    }

    private func guess() {
        guard let known = ComfyStudio.understand(link, folders: folders) else { size = nil; checked = ""; return }
        folder = known.folder
        let address = known.url
        checked = address
        Task {
            let bytes = await ComfyStudio.sizeOf(address)
            if checked == address { size = bytes }
        }
    }
}

/// The prompt library: other people's best image prompts, browsed, used as
/// they are, or kept for their craft and given a new subject.
private struct PromptLibrarySheet: View {
    @ObservedObject var studio: ComfyStudio
    @ObservedObject private var library = PromptLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category = ""
    @State private var chosen: PromptLibrary.Entry?
    @State private var text = ""
    @State private var subject = ""
    @State private var adapting = false

    private var shown: [PromptLibrary.Entry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return library.entries.filter { e in
            (category.isEmpty || e.category == category)
                && (q.isEmpty || e.title.lowercased().contains(q) || e.prompt.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("提示词库").font(.system(size: 14, weight: .semibold))
                Link("Awesome AI Image Prompts（MIT）", destination: PromptLibrary.home).font(.system(size: 10))
                Spacer()
                if library.loading { ProgressView().controlSize(.small) }
                Button("关") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    TextField("搜：portrait、cinematic、food…", text: $search).textFieldStyle(.roundedBorder)
                    Picker("", selection: $category) {
                        Text("全部 \(library.entries.count)").tag("")
                        ForEach(library.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    List(shown, selection: Binding(get: { chosen?.id }, set: { id in pick(library.entries.first { $0.id == id }) })) { e in
                        HStack(spacing: 6) {
                            AsyncImage(url: e.image) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title).font(.system(size: 11)).lineLimit(2)
                                HStack(spacing: 4) {
                                    Text(e.category).font(.system(size: 9)).foregroundColor(.secondary)
                                    if e.needsPhoto { Text("要照片").font(.system(size: 9)).foregroundColor(.orange) }
                                }
                            }
                        }
                        .tag(e.id)
                    }
                    .listStyle(.plain)
                }
                .frame(width: 290)
                .padding(8)
                Divider()
                detail.padding(10)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task { await library.load() }
    }

    private func pick(_ entry: PromptLibrary.Entry?) {
        chosen = entry
        text = entry?.prompt ?? ""
    }

    @ViewBuilder private var detail: some View {
        if let e = chosen {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: e.image) { $0.resizable().scaledToFit() } placeholder: { Color.primary.opacity(0.06) }
                        .frame(width: 180, height: 180).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title).font(.system(size: 13, weight: .semibold))
                        Text(e.category + (e.needsPhoto ? " · 这一条是改你自己的照片用的（配改图模板）" : "")).font(.system(size: 10)).foregroundColor(.secondary)
                        HStack {
                            TextField("换成我的主题：加利利海边的渔夫…", text: $subject).textFieldStyle(.roundedBorder)
                            Button(adapting ? "在改…" : "换主题") {
                                let s = subject; adapting = true
                                Task { if let new = await PromptLibrary.adapt(e, to: s) { text = new }; adapting = false }
                            }
                            .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty || adapting)
                        }
                        .help("让写手保留这条提示词的结构、镜头、光线、质感、风格和负面清单，只把画的东西换成你的")
                    }
                }
                TextEditor(text: $text).font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                HStack {
                    Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                    if studio.current != nil {
                        Button("放进当前工作流") { let t = text; Task { await studio.usePrompt(t) }; dismiss() }
                    }
                    Spacer()
                    Button(e.needsPhoto ? "用 Qwen 改图打开" : "用 Qwen 出图打开") {
                        let t = text
                        Task { await studio.open(templateNamed: e.needsPhoto ? "image_qwen_image_2_1_image_edit" : "image_qwen_image_2_1_t2i", prompt: t) }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if let note = studio.note { Text(note).font(.system(size: 10)).foregroundColor(.secondary) }
            }
        } else {
            VStack {
                Spacer()
                Text(library.trouble ?? "左边挑一条").foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

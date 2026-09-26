import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// The Motion tab: a movement from a real performance, performed by her.
///
/// A reference video goes in — dropped on the tab or picked — with where she
/// is and what she wears; what comes out is her doing that movement, as long
/// as the reference lasts. See `MotionStudio` for how and why.
struct MotionStudioView: View {
    @ObservedObject private var studio = MotionStudio.shared
    @ObservedObject private var character = CompanionCharacter.shared
    @ObservedObject private var finder = MotionFinder.shared
    /// An agent with the motion tools, docked under the tab. See `StudioAgent`.
    @ObservedObject private var agent = StudioAgent.motion
    @State private var topic = ""
    @State private var selected: String?
    @State private var video: URL?
    @State private var scene = ""
    @State private var start = 0.0
    @State private var seconds = 10.0
    @State private var credit = ""
    /// "" is the skeleton route, filmed from where the reference was; the
    /// others are `MotionStage.Camera`s — her body in 3D, on a set, walked round.
    @AppStorage("kinclaw.motion.camera") private var camera = ""
    @AppStorage("kinclaw.motion.place") private var place = MotionStage.Place.park.rawValue
    @State private var trouble: String?
    @State private var showing: [String: String] = [:]      // take id → "take" | "source" | "pose"
    @State private var tick = 0
    @State private var dropping = false
    /// A reference from an address: what was pasted, what it turned out to
    /// be, and whether the user has said they may use it.
    @State private var address = ""
    @State private var found: MotionImport.Info?
    @State private var mine = false
    @State private var fetching: String?
    /// Each video's own shape, once read: a portrait reference in a square
    /// player was a strip down the middle of a black box.
    @State private var shapes: [URL: CGFloat] = [:]

    private var take: MotionStudio.Take? {
        studio.takes.first { $0.id == selected } ?? studio.takes.first
    }

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                AgentDock(agent: agent, examples: ["找一段太极的参考视频，让她在清晨的公园里打", "拍到她的起始画面先停，给我看"],
                          widest: space.size.width - 212 - 480) { ask($0) }
                library.frame(width: 212).background(Theme.sidebar)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                VStack(spacing: 0) {
                    if finder.open { results } else if let take { detail(take) } else { empty }
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    composer
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            studio.reload()
            if !agent.running { agent.shown = true }      // its column out, as on Montage
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if studio.working != nil { tick += 1 }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { video = url } }
            }
            return true
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 2).padding(4) } }
    }

    // MARK: The takes

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("动作", detail: studio.takes.isEmpty ? nil : "\(studio.takes.count)")
                    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 6)
                ForEach(studio.takes) { take in
                    let chosen = self.take?.id == take.id
                    let working = studio.working == take.id
                    Button { selected = take.id } label: {
                        HStack(spacing: 10) {
                            Color.clear.frame(width: 44, height: 44)
                                .overlay { thumb(take.still) }
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(take.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(status(take)).font(.kinCaption)
                                    .foregroundStyle(working ? Theme.accent : take.state == .failed ? Theme.bad : Color.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chosen ? Theme.accentWash : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .id(tick)
        }
    }

    // MARK: One take

    private func detail(_ take: MotionStudio.Take) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(take.title).font(.kinTitle).textSelection(.enabled)
                        Text(status(take)).font(.kinCaption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if take.state == .failed {
                        Button("接着拍") { if case .failure(let f) = studio.resume(take.id) { trouble = f.localizedDescription } }
                            .buttonStyle(.primary).disabled(studio.working != nil)
                    }
                    Button { agent.shown = true } label: { Label("问 agent", systemImage: "sparkles") }
                        .buttonStyle(.quietFilled)
                        .help("让 agent 来：找参考视频、选段落、写场景、拍、接着拍")
                    if take.state == .done {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([take.file]) } label: {
                            Image(systemName: "folder").font(.system(size: 13))
                        }
                        .buttonStyle(.quiet).help("在访达里显示")
                    }
                }
                if studio.working == take.id {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text((studio.progress ?? "在准备…") + clock()).font(.kinLabel).lineLimit(2)
                        Spacer(minLength: 8)
                        Button("停") { studio.stop() }.buttonStyle(.quiet)
                            .help("停下这一段。已经拍好的段留着，之后点「接着拍」继续")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .card(radius: 11)
                }
                if let note = take.note {
                    Label(note, systemImage: "exclamationmark.circle").font(.kinLabel).foregroundStyle(Theme.notice)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let playing = playing(take) {
                    let ratio = shapes[playing.url] ?? 1
                    VStack(spacing: 12) {
                        MotionPlayer(url: playing.url, autoplay: playing.kind != "take")
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(maxWidth: ratio >= 1 ? 820 : 460, maxHeight: 580)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                            .task(id: playing.url) {
                                guard shapes[playing.url] == nil,
                                      let track = try? await AVURLAsset(url: playing.url).loadTracks(withMediaType: .video).first,
                                      let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0
                                else { return }
                                shapes[playing.url] = size.width / size.height
                            }
                        HStack(spacing: 4) {
                            choice("成片", "take", take, ready: FileManager.default.fileExists(atPath: take.file.path))
                            ForEach(take.segments) { segment in
                                choice("第 \(segment.id) 段", "seg\(segment.id)", take,
                                       ready: FileManager.default.fileExists(atPath: take.clip(segment.id).path))
                            }
                            Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 16).padding(.horizontal, 4)
                            choice("原视频", "source", take, ready: true)
                            choice("骨架", "pose", take, ready: FileManager.default.fileExists(atPath: take.pose(1).path))
                        }
                        .id(tick)
                    }
                    .frame(maxWidth: .infinity)
                }
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("场景").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(take.scene).font(.kinLabel).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    GridRow {
                        Text("参考").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text("原视频从第 \(Int(take.start)) 秒起，\(Int(take.seconds)) 秒，分 \(take.segments.count) 段拍").font(.kinLabel)
                    }
                    if let credit = take.credit, !credit.isEmpty {
                        GridRow {
                            Text("来源").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            Text(credit).font(.kinLabel).foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 11)
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private func playing(_ take: MotionStudio.Take) -> (url: URL, kind: String)? {
        let fm = FileManager.default
        let kind = showing[take.id] ?? "take"
        if kind == "source", fm.fileExists(atPath: take.reference.path) { return (take.reference, kind) }
        if kind == "pose", fm.fileExists(atPath: take.pose(1).path) { return (take.pose(1), kind) }
        if kind.hasPrefix("seg"), let n = Int(kind.dropFirst(3)), fm.fileExists(atPath: take.clip(n).path) { return (take.clip(n), kind) }
        if fm.fileExists(atPath: take.file.path) { return (take.file, "take") }
        if let latest = take.segments.last(where: { $0.state == .done && fm.fileExists(atPath: take.clip($0.id).path) }) {
            return (take.clip(latest.id), "seg\(latest.id)")
        }
        return nil
    }

    private func choice(_ title: String, _ kind: String, _ take: MotionStudio.Take, ready: Bool) -> some View {
        let on = (playing(take)?.kind ?? "") == kind
        return Button { showing[take.id] = kind } label: {
            ChipLabel(title: title, on: on)
        }
        .buttonStyle(.plain).disabled(!ready).opacity(ready ? 1 : 0.4)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.taichi").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.accentWash))
            Text("找一段动作，让她照着做").font(.kinTitle)
            Text("拖一段视频进来：单人、全身、机位尽量固定。\n只取里面的动作骨架——人、衣服、场地都是她自己的。\n十秒大约四分半钟，可以一直接下去。")
                .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Asking for one

    /// Where the movement comes from — a file, a topic to search, an
    /// address — then where she is and what she wears, and the button.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let trouble {
                Label(trouble, systemImage: "exclamationmark.triangle")
                    .font(.kinCaption).foregroundStyle(Theme.notice).fixedSize(horizontal: false, vertical: true)
            }
            if character.anchorURL == nil {
                Label("她还没有锚图，先给她定一张脸", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.kinCaption).foregroundStyle(Theme.notice)
            }
            HStack(spacing: 8) {
                Button { pick() } label: {
                    Label(video == nil ? "选参考视频…" : "换一段…", systemImage: "film.stack")
                }
                .buttonStyle(.quietFilled)
                Text(video?.lastPathComponent ?? "或者把视频拖进这个标签")
                    .font(.kinCaption).foregroundStyle(video == nil ? Color.secondary : Color.primary).lineLimit(1)
                Spacer(minLength: 12)
                if let fetching {
                    ProgressView().controlSize(.mini)
                    Text(fetching).font(.kinCaption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                box(TextField("想找什么动作？给个主题，它去找能用的：太极、八段锦、芭蕾基本功…", text: $topic)
                    .onSubmit { finder.find(topic) })
                Button("找") { finder.find(topic) }.buttonStyle(.quietFilled)
                    .disabled(finder.doing != nil || topic.trimmingCharacters(in: .whitespaces).isEmpty)
                box(TextField("或者粘贴视频链接：YouTube、TikTok…", text: $address).onSubmit(look))
                Button("看一下", action: look).buttonStyle(.quietFilled)
                    .disabled(fetching != nil || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let found { licence(found) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("她在哪、穿什么？比如：清晨起雾的公园，圆形砖地，穿蓝色棉袄、灰色长裤、白布鞋", text: $scene, axis: .vertical)
                    .textFieldStyle(.plain).font(.kinBody).lineLimit(1...3)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                Button(studio.working != nil ? "在拍…" : "开拍", action: go)
                    .buttonStyle(.primary).fixedSize()
                    .disabled(studio.working != nil || video == nil || character.anchorURL == nil)
                    .help(video == nil ? "先选一段参考视频" : "取动作骨架，再照着拍")
            }
            HStack(spacing: 14) {
                Stepper("从第 \(Int(start)) 秒", value: $start, in: 0...3600, step: 5).font(.kinLabel).fixedSize()
                Stepper("拍 \(Int(seconds)) 秒", value: $seconds, in: 4...120, step: seconds < 10 ? 2 : 10).font(.kinLabel).fixedSize()
                Menu {
                    Button { camera = "" } label: { Label("骨架 · 原视频的机位", systemImage: camera.isEmpty ? "checkmark" : "") }
                    ForEach(MotionStage.Camera.allCases, id: \.rawValue) { item in
                        Button { camera = item.rawValue } label: { Label(item.title, systemImage: camera == item.rawValue ? "checkmark" : "") }
                    }
                } label: {
                    ChipLabel(title: camera.isEmpty ? "骨架 · 原视频的机位" : MotionStage.Camera(rawValue: camera)?.title ?? camera,
                              symbol: "video", menu: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("机位")
                if !camera.isEmpty {
                    Menu {
                        ForEach(MotionStage.Place.allCases, id: \.rawValue) { item in
                            Button { place = item.rawValue } label: { Label(item.title, systemImage: place == item.rawValue ? "checkmark" : "") }
                        }
                    } label: {
                        ChipLabel(title: MotionStage.Place(rawValue: place)?.title ?? place, symbol: "tree", menu: true)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("布景")
                }
                box(TextField("动作来源（标题 / 作者 / 链接 / 许可），发布时要署名", text: $credit))
            }
            Text(camera.isEmpty ? "照参考视频的机位拍，动作可以走动、转身"
                 : "三维骨架 → 盒子上的 Blender 搭景、走机位、渲染深度 → 照着深度拍。她可以走动、转身；侧身时单个镜头估不准的几帧会被补上，实在估不稳的会直说")
                .font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.sidebar.opacity(0.6))
    }

    /// A one-line field, sunk into the bar.
    private func box<Field: View>(_ field: Field) -> some View {
        field
            .textFieldStyle(.plain).font(.kinLabel)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .well(radius: 8)
    }

    // MARK: Found for a topic

    /// What was found, best reference first. One click takes one: its real
    /// licence is read, it is fetched, and it becomes the reference.
    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("「\(finder.topic)」能用的参考").font(.kinTitle)
                    if let doing = finder.doing { ProgressView().controlSize(.mini); Text(doing).font(.kinCaption).foregroundColor(.secondary).lineLimit(1) }
                    Spacer()
                    Button("关掉") { finder.close() }.buttonStyle(.quiet)
                }
                Text("只搜 Creative Commons 许可的（可以取用，发布时署名）。分数是看封面打的：单人、全身、机位稳的排前面——封面不等于视频，取回来提取不到人会直接告诉你。")
                    .font(.kinCaption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if let trouble = finder.trouble { Text(trouble).font(.kinCaption).foregroundColor(Theme.notice) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(finder.found) { candidate in found(candidate) }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private func found(_ candidate: MotionFinder.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: candidate.thumbnail) { image in image.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.08) }
                    .frame(height: 120).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let fit = candidate.fit {
                    Text("适合 \(fit)/10").font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((fit >= 7 ? Theme.accent : fit >= 4 ? Color.orange : Color.red).opacity(0.85)))
                        .padding(5)
                }
            }
            Text(candidate.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Text("\(candidate.author) · \(Self.length(candidate.seconds))").font(.kinCaption).foregroundColor(.secondary).lineLimit(1)
            if candidate.onTopic == false { Text("不是「\(finder.topic)」，是别的动作").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.notice) }
            if let why = candidate.why, !why.isEmpty { Text(why).font(.kinCaption).foregroundColor(.secondary).lineLimit(2) }
            Button("用这个") { use(candidate) }.buttonStyle(.quiet).disabled(fetching != nil)
        }
        .padding(8)
        .card(radius: 11)
    }

    private static func length(_ seconds: Double) -> String {
        seconds <= 0 ? "" : String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    /// Take one: the licence is read for real, then it is fetched.
    private func use(_ candidate: MotionFinder.Candidate) {
        trouble = nil
        fetching = "在确认许可…"
        address = candidate.address
        Task { @MainActor in
            defer { fetching = nil }
            do {
                let info = try await MotionImport.look(candidate.address)
                found = info
                guard info.open else { trouble = "这段视频实际的许可是\(info.licence.isEmpty ? "标准许可" : info.licence)，没有直接取。确实有权使用的话，在下面勾选后再取。"; finder.close(); return }
                fetching = "在取视频…"
                video = try await MotionImport.fetch(info, into: MotionStudio.root.appendingPathComponent(".imports"))
                credit = info.credit
                finder.close()
            } catch { trouble = error.localizedDescription }
        }
    }

    /// What the address is and what it may be used for, before any of it is taken.
    private func licence(_ info: MotionImport.Info) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(info.title) · \(info.author) · \(Int(info.seconds)) 秒").font(.system(size: 12, weight: .medium)).lineLimit(1)
            if info.open {
                Text("许可：\(info.licence) —— 可以取用，发布成片时要署名（已经替你填到「动作来源」里了）")
                    .font(.kinCaption).foregroundColor(Theme.accent)
            } else {
                Text("许可：\(info.licence.isEmpty ? "网站的标准许可" : info.licence) —— 这是别人的作品，标准许可不允许下载再创作。是你自己的视频，或者你拿到了授权，才取。")
                    .font(.kinCaption).foregroundColor(Theme.notice).fixedSize(horizontal: false, vertical: true)
                Toggle("我有权使用这段视频", isOn: $mine).font(.kinCaption).toggleStyle(.checkbox)
            }
            Button("取回来当参考") { bring(info) }.buttonStyle(.primary)
                .disabled(fetching != nil || !(info.open || mine))
        }
        .padding(12)
        .card(radius: 10)
    }

    private func look() {
        let wanted = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, fetching == nil else { return }
        trouble = nil; found = nil; mine = false
        fetching = "在看这个链接…"
        Task { @MainActor in
            defer { fetching = nil }
            do { found = try await MotionImport.look(wanted) } catch { trouble = error.localizedDescription }
        }
    }

    private func bring(_ info: MotionImport.Info) {
        trouble = nil
        fetching = "在取视频…"
        Task { @MainActor in
            defer { fetching = nil }
            do {
                video = try await MotionImport.fetch(info, into: MotionStudio.root.appendingPathComponent(".imports"))
                credit = info.credit
            } catch { trouble = error.localizedDescription }
        }
    }

    /// Words for the agent, with the take that is open — "这一条" means it.
    private func ask(_ words: String) {
        let open = take.map { "（动作页里开着的：「\($0.title)」，id \($0.id)）\n" } ?? ""
        agent.say(open + words)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { video = panel.url }
    }

    private func go() {
        guard let video else { return }
        trouble = nil
        let words = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        switch studio.make(video: video, title: "", start: start, seconds: seconds,
                           scene: words.isEmpty ? "a quiet park in soft morning light, she wears a plain long-sleeved top, loose trousers and flat shoes" : words,
                           credit: credit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : credit,
                           camera: MotionStage.Camera(rawValue: camera), place: MotionStage.Place(rawValue: place) ?? .park) {
        case .success(let take): selected = take.id
        case .failure(let failure): trouble = failure.localizedDescription
        }
    }

    // MARK: Small things

    /// " · 已 3:12（一段约 5 分钟）" — so that five minutes of the same sentence
    /// is visibly five minutes of work.
    private func clock() -> String {
        guard let since = studio.since else { return "" }
        let spent = Int(Date().timeIntervalSince(since))
        let usual = studio.usual.map { "（上一段用了 \(Int(($0 / 60).rounded(.up))) 分钟）" } ?? "（十秒一段，约 4–5 分钟）"
        return String(format: " · 已 %d:%02d", spent / 60, spent % 60) + usual
    }

    private func status(_ take: MotionStudio.Take) -> String {
        switch take.state {
        case .waiting: return "等着"
        case .tracking: return "在提取动作"
        case .drawing: return "在画起始画面"
        case .filming: return "在拍 \(take.finished)/\(take.segments.count)"
        case .joining: return "在接起来"
        case .done: return "\(Int(take.seconds)) 秒"
        case .failed: return "没拍成"
        }
    }

    private func thumb(_ url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(Color.primary.opacity(0.08)) }
        }
    }
}

private struct MotionPlayer: NSViewRepresentable {
    let url: URL
    var autoplay = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        if autoplay { view.player?.play() }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard (view.player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        view.player = AVPlayer(url: url)
        if autoplay { view.player?.play() }
    }
}

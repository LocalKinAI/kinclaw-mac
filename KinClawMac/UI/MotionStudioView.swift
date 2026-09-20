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
    @State private var topic = ""
    @State private var selected: String?
    @State private var video: URL?
    @State private var scene = ""
    @State private var start = 0.0
    @State private var seconds = 10.0
    @State private var credit = ""
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

    private var take: MotionStudio.Take? {
        studio.takes.first { $0.id == selected } ?? studio.takes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            library.frame(width: 168)
            Divider().opacity(0.15)
            VStack(spacing: 0) {
                if finder.open { results } else if let take { detail(take) } else { empty }
                Divider().opacity(0.15)
                composer
            }
        }
        .onAppear { studio.reload() }
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
        .overlay { if dropping { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2).padding(4) } }
    }

    // MARK: The takes

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(studio.takes) { take in
                    Button { selected = take.id } label: {
                        HStack(spacing: 8) {
                            thumb(take.still).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(take.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(status(take)).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(self.take?.id == take.id ? 0.10 : 0)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: One take

    private func detail(_ take: MotionStudio.Take) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(take.title).font(.system(size: 15, weight: .semibold))
                    Text(status(take)).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    if take.state == .failed {
                        Button("接着拍") { if case .failure(let f) = studio.resume(take.id) { trouble = f.localizedDescription } }
                            .controlSize(.small).disabled(studio.working != nil)
                    }
                    if take.state == .done {
                        Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([take.file]) }.controlSize(.small)
                    }
                }
                if let playing = playing(take) {
                    MotionPlayer(url: playing.url, autoplay: playing.kind != "take")
                        .aspectRatio(1, contentMode: .fit).frame(maxWidth: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity)
                    HStack(spacing: 4) {
                        choice("成片", "take", take, ready: FileManager.default.fileExists(atPath: take.file.path))
                        ForEach(take.segments) { segment in
                            choice("第 \(segment.id) 段", "seg\(segment.id)", take,
                                   ready: FileManager.default.fileExists(atPath: take.clip(segment.id).path))
                        }
                        choice("原视频", "source", take, ready: true)
                        choice("骨架", "pose", take, ready: FileManager.default.fileExists(atPath: take.pose(1).path))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 420).frame(maxWidth: .infinity)
                } else if studio.working == take.id {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(studio.progress ?? "在准备…").font(.system(size: 11)) }
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                if studio.working == take.id, let progress = studio.progress {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(progress + clock()).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                Text(take.scene).font(.system(size: 10)).foregroundColor(.secondary)
                Text("原视频从第 \(Int(take.start)) 秒起，\(Int(take.seconds)) 秒，分 \(take.segments.count) 段拍")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                if let credit = take.credit, !credit.isEmpty {
                    Text("动作来源：\(credit)").font(.system(size: 9)).foregroundColor(.secondary).textSelection(.enabled)
                }
                if let note = take.note { Text(note).font(.system(size: 10)).foregroundColor(.orange) }
            }
            .padding(14)
            .id(tick)
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
            Text(title).font(.system(size: 10, weight: on ? .semibold : .regular))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08)))
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain).disabled(!ready).opacity(ready ? 1 : 0.35)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.taichi").font(.system(size: 34)).foregroundColor(.secondary)
            Text("找一段动作，让她照着做").font(.system(size: 13, weight: .medium))
            Text("拖一段视频进来：单人、全身、机位尽量固定。\n只取里面的动作骨架——人、衣服、场地都是她自己的。\n十秒大约四分半钟，可以一直接下去。")
                .font(.system(size: 10)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Asking for one

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(video == nil ? "选参考视频…" : "换一段…") { pick() }.controlSize(.small)
                Text(video?.lastPathComponent ?? "或者把视频拖进这个标签").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button(studio.working != nil ? "在拍…" : "开拍", action: go).controlSize(.small).fixedSize()
                    .disabled(studio.working != nil || video == nil || character.anchorURL == nil)
            }
            HStack(spacing: 8) {
                TextField("想找什么动作？给个主题，它去找能用的：太极、八段锦、芭蕾基本功…", text: $topic)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit { finder.find(topic) }
                Button("找") { finder.find(topic) }.controlSize(.mini)
                    .disabled(finder.doing != nil || topic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                TextField("或者粘贴视频链接：YouTube、TikTok…", text: $address)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit(look)
                if let fetching { ProgressView().controlSize(.mini); Text(fetching).font(.system(size: 9)).foregroundColor(.secondary) }
                Button("看一下", action: look).controlSize(.mini)
                    .disabled(fetching != nil || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let found { licence(found) }
            TextField("她在哪、穿什么？比如：清晨起雾的公园，圆形砖地，穿蓝色棉袄、灰色长裤、白布鞋", text: $scene)
                .textFieldStyle(.plain).font(.system(size: 12))
            HStack(spacing: 12) {
                Stepper("从第 \(Int(start)) 秒", value: $start, in: 0...3600, step: 5).font(.system(size: 10)).fixedSize()
                Stepper("拍 \(Int(seconds)) 秒", value: $seconds, in: 4...120, step: seconds < 10 ? 2 : 10).font(.system(size: 10)).fixedSize()
                TextField("动作来源（标题 / 作者 / 链接 / 许可），发布时要署名", text: $credit)
                    .textFieldStyle(.plain).font(.system(size: 10))
            }
            if let trouble { Text(trouble).font(.system(size: 10)).foregroundColor(.orange) }
            if character.anchorURL == nil { Text("她还没有锚图，先给她定一张脸").font(.system(size: 10)).foregroundColor(.orange) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Found for a topic

    /// What was found, best reference first. One click takes one: its real
    /// licence is read, it is fetched, and it becomes the reference.
    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("「\(finder.topic)」能用的参考").font(.system(size: 15, weight: .semibold))
                    if let doing = finder.doing { ProgressView().controlSize(.mini); Text(doing).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1) }
                    Spacer()
                    Button("关掉") { finder.close() }.controlSize(.small)
                }
                Text("只搜 Creative Commons 许可的（可以取用，发布时署名）。分数是看封面打的：单人、全身、机位稳的排前面——封面不等于视频，取回来提取不到人会直接告诉你。")
                    .font(.system(size: 9)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if let trouble = finder.trouble { Text(trouble).font(.system(size: 10)).foregroundColor(.orange) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 12) {
                    ForEach(finder.found) { candidate in found(candidate) }
                }
            }
            .padding(14)
        }
    }

    private func found(_ candidate: MotionFinder.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: candidate.thumbnail) { image in image.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.08) }
                    .frame(height: 100).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let fit = candidate.fit {
                    Text("适合 \(fit)/10").font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((fit >= 7 ? Color.green : fit >= 4 ? Color.orange : Color.red).opacity(0.85)))
                        .padding(5)
                }
            }
            Text(candidate.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
            Text("\(candidate.author) · \(Self.length(candidate.seconds))").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            if candidate.onTopic == false { Text("不是「\(finder.topic)」，是别的动作").font(.system(size: 9, weight: .medium)).foregroundColor(.orange) }
            if let why = candidate.why, !why.isEmpty { Text(why).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2) }
            Button("用这个") { use(candidate) }.controlSize(.mini).disabled(fetching != nil)
        }
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
            Text("\(info.title) · \(info.author) · \(Int(info.seconds)) 秒").font(.system(size: 10, weight: .medium)).lineLimit(1)
            if info.open {
                Text("许可：\(info.licence) —— 可以取用，发布成片时要署名（已经替你填到「动作来源」里了）")
                    .font(.system(size: 9)).foregroundColor(.green)
            } else {
                Text("许可：\(info.licence.isEmpty ? "网站的标准许可" : info.licence) —— 这是别人的作品，标准许可不允许下载再创作。是你自己的视频，或者你拿到了授权，才取。")
                    .font(.system(size: 9)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                Toggle("我有权使用这段视频", isOn: $mine).font(.system(size: 10)).toggleStyle(.checkbox)
            }
            Button("取回来当参考") { bring(info) }.controlSize(.mini)
                .disabled(fetching != nil || !(info.open || mine))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
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
                           credit: credit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : credit) {
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

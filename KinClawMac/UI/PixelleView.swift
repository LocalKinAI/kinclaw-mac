import AVKit
import ImageIO
import SwiftUI

/// The Pixelle tab: Pixelle-Video on the box, worked by its agent.
///
/// On the left, the tab's agent, as on every Studio tab — it writes the
/// script and each scene's picture words, tries a picture and a line of voice,
/// and makes the video once the person has said yes. On the right: whether the
/// service on the box is up (and a way to start it), the job in progress as it
/// goes, and every video made — the list, the one chosen playing, its scenes'
/// lines and the pictures' words, and its storyboard sheet. See `PixelleStudio`.
struct PixelleView: View {
    @ObservedObject private var studio = PixelleStudio.shared
    @ObservedObject private var agent = StudioAgent.pixelle
    @State private var words = ""
    @State private var message: String?
    @State private var forcing = false

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                AgentDock(agent: agent,
                          examples: ["做一支 40 秒竖屏：系外行星是怎么被发现的",
                                     "先试一张图和一句声音：深夜的天文台，望远镜对着一颗亮星",
                                     "看看盒子上的 Pixelle 在不在跑，有哪些模板和声音"],
                          widest: space.size.width - 560, onExample: { agent.say($0) }) {
                    starter
                }
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    if let job = studio.job {
                        jobBar(job)
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    }
                    HStack(spacing: 0) {
                        runList.frame(width: 250).background(Theme.sidebar)
                        Rectangle().fill(Theme.hairline).frame(width: 0.5)
                        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .tint(Theme.accent)
        // The agent is how this tab is used: its column is out when the tab is.
        .onAppear { if !agent.running { agent.shown = true } }
        .task {
            studio.reload()
            await studio.refresh()
        }
        .confirmationDialog("盒子上有任务在做，停了就丢了", isPresented: $forcing) {
            Button("还是停", role: .destructive) { Task { message = await studio.stop(force: true).0 } }
            Button("不停了", role: .cancel) {}
        } message: {
            Text("「\(studio.job?.title ?? "")」还没做完。等它做完再停，或者现在强行停止（这支视频就没了）。")
        }
    }

    // MARK: Header: the service

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if !agent.shown {
                    Button { agent.shown = true } label: { Label("agent", systemImage: "sidebar.left") }
                        .buttonStyle(.quietFilled)
                        .help("把 agent 那一栏拿出来")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pixelle").font(.kinTitle)
                    Text("Pixelle-Video，在盒子上 · 一段稿子一个场景：Qwen Image 出图、盒子上的声音配音、卡片加字幕、配乐，合成一支解说短视频")
                        .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                serviceChip
                if let comfy = studio.comfy {
                    ChipLabel(title: "ComfyUI \(comfy)", symbol: "square.stack.3d.up")
                        .help("盒子上的 ComfyUI，和 Film、Comfy、Montage 标签共用：它在跑别的时，这里的图要排队（一段配乐占 25–50 分钟）")
                }
                if let voices = studio.voices {
                    ChipLabel(title: "配音 \(voices)", symbol: "waveform")
                        .help("8102：按描述造声音；8101：预设声音")
                }
                serviceButton
                Button { Task { await studio.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.quiet)
                    .disabled(studio.checking)
                    .help("再看一次：API、ComfyUI 的队列、配音、盒子上的任务")
                Button {
                    try? FileManager.default.createDirectory(at: PixelleStudio.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(PixelleStudio.root)
                } label: { Image(systemName: "folder") }
                    .buttonStyle(.quiet)
                    .help("在 Finder 里打开 \(PixelleStudio.root.path)")
            }
            if case .down(let why) = studio.service, why != "没在跑" {
                // Not just stopped: no box set, the box unreachable — said where it can be read.
                Label(why, systemImage: "exclamationmark.triangle").font(.kinCaption).foregroundStyle(Theme.notice)
                    .lineLimit(2).textSelection(.enabled)
            }
            if let message {
                Text(message).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var serviceChip: some View {
        let (title, color, why): (String, Color, String) = {
            switch studio.service {
            case .unknown: return (studio.checking ? "在看…" : "还没看", .secondary, "")
            case .up: return ("API 在跑", Theme.good, "盒子的 127.0.0.1:8190，经 ssh")
            case .down(let why): return ("API 没在跑", Theme.notice, why)
            case .starting: return ("在起…", .secondary, "")
            case .stopping: return ("在停…", .secondary, "")
            }
        }()
        return HStack(spacing: 5) {
            if studio.checking { ProgressView().controlSize(.mini) } else { Circle().fill(color).frame(width: 7, height: 7) }
            Text(title).font(.kinLabel)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Theme.well))
        .help(why.isEmpty ? "Pixelle-Video 的 API，在盒子上" : why)
    }

    @ViewBuilder private var serviceButton: some View {
        switch studio.service {
        case .up:
            Button("停止") {
                if studio.job?.state == .running { forcing = true } else { Task { message = await studio.stop(force: false).0 } }
            }
            .buttonStyle(.quiet)
            .help("停掉盒子上的 Pixelle API（手动起的，盒子重启也会没）")
        case .down, .unknown:
            Button("启动") { Task { message = await studio.start().0 } }
                .buttonStyle(.quietFilled)
                .disabled(studio.checking)
                .help("在盒子上起 Pixelle API（~/.kinclaw/pixelle/pixelle-api.sh start），十几秒")
        case .starting, .stopping:
            ProgressView().controlSize(.small)
        }
    }

    // MARK: The job in progress

    private func jobBar(_ job: PixelleStudio.Job) -> some View {
        HStack(spacing: 10) {
            switch job.state {
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.notice)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title.isEmpty ? "task \(job.id)" : "「\(job.title)」").font(.kinHeadline).lineLimit(1)
                Text(jobText(job)).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if job.state == .running {
                if let percent = job.percent {
                    ProgressView(value: min(100, max(0, percent)), total: 100).frame(width: 140)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.elapsed(from: job.started, to: context.date)).font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button("取消") { Task { message = await studio.cancel(job.id).0 } }
                    .buttonStyle(.quiet)
                    .help("取消这个任务。已经交给 ComfyUI 的那张图还会在那边画完")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Theme.well.opacity(0.5))
    }

    private func jobText(_ job: PixelleStudio.Job) -> String {
        switch job.state {
        case .running:
            return "在做：\(job.progress)" + (job.waiting.map { " · \($0)" } ?? "") + " · task \(job.id)"
        case .done:
            return "做好了" + (job.folder.map { " · \($0.lastPathComponent)" } ?? "")
        case .failed(let why):
            return "没做成：\(why)"
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: The videos

    private var runList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle("做好的", detail: studio.runs.isEmpty ? nil : "\(studio.runs.count)")
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            if studio.runs.isEmpty {
                Text("还没有。跟左边的 agent 说想做什么视频").font(.kinCaption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(studio.runs) { run in runRow(run) }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
        }
    }

    private func runRow(_ run: PixelleStudio.Run) -> some View {
        let chosen = (studio.selected ?? studio.runs.first?.id) == run.id
        return Button { studio.selected = run.id } label: {
            HStack(spacing: 8) {
                StudioPicture(url: run.cover ?? run.sheet, largest: 200, fill: true)
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.title).font(.kinLabel).lineLimit(2)
                    Text(Self.summary(run)).font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chosen ? Theme.accentWash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func summary(_ run: PixelleStudio.Run) -> String {
        let when = DateFormatter()
        when.dateFormat = "M月d日 HH:mm"
        return [when.string(from: run.date), run.seconds.map { String(format: "%.1f 秒", $0) }, "\(run.scenes.count) 个场景"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var detail: some View {
        if let run = studio.runs.first(where: { $0.id == studio.selected }) ?? studio.runs.first {
            let height: CGFloat = run.aspect < 0.8 ? 480 : run.aspect < 1.2 ? 380 : 300
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        StudioVideoPlayer(url: run.video)
                            .frame(width: height * run.aspect, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(run.title).font(.kinTitle).textSelection(.enabled)
                            Text(Self.summary(run) + (run.template.map { " · \($0)" } ?? ""))
                                .font(.kinCaption).foregroundStyle(.secondary)
                            if let remark = run.remark {
                                Text(remark).font(.kinCaption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([run.video]) }
                                    .buttonStyle(.quietFilled)
                                Button("用 QuickTime 打开") { NSWorkspace.shared.open(run.video) }
                                    .buttonStyle(.quiet)
                            }
                            // Asks the agent, which says how long and waits for a yes (pixelle_rework).
                            HStack(spacing: 6) {
                                if run.moving == 0 {
                                    Button("让画面动起来") {
                                        agent.say("把「\(run.title)」（\(run.boxFolder)）做一支画面会动的：用 pixelle_rework，motion ltx"
                                                  + "（每个场景真的动，约 3 分钟一个场景；图表类的场景你看情况用 pan）。先告诉我要多久，我点头再做。")
                                    }
                                    .buttonStyle(.quiet)
                                    .help("请左边的 agent 用 LTX 把每个场景的图动起来（不重画图，原片不动，出一支新的）")
                                }
                                if !run.oneVoice {
                                    Button("重配成一个人") {
                                        agent.say("把「\(run.title)」（\(run.boxFolder)）的旁白重配：pixelle_rework revoice true，整篇一次念完，"
                                                  + "全片一个人；声音描述照原来的。")
                                    }
                                    .buttonStyle(.quiet)
                                    .help("这支是逐句配音的，每句像换了个人。请 agent 整篇一次念完重配（约 1 分钟）")
                                }
                            }
                            Rectangle().fill(Theme.hairline).frame(height: 0.5)
                            ForEach(Array(run.scenes.enumerated()), id: \.offset) { i, scene in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(i + 1)").font(.kinMicro).foregroundStyle(.secondary).frame(width: 14, alignment: .trailing)
                                        Text(scene.narration).font(.kinBody).textSelection(.enabled)
                                        Spacer(minLength: 4)
                                        if let s = scene.seconds {
                                            Text(String(format: "%.1f 秒", s)).font(.kinCaption.monospacedDigit()).foregroundStyle(.tertiary)
                                        }
                                    }
                                    if let prompt = scene.prompt, !prompt.isEmpty {
                                        Text(prompt).font(.kinCaption).foregroundStyle(.secondary).lineLimit(3)
                                            .padding(.leading, 20).textSelection(.enabled)
                                            .help(prompt)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 560, alignment: .leading)
                    }
                    if let sheet = run.sheet {
                        SectionTitle("所有场景", detail: "sheet.png")
                        StudioPicture(url: sheet, largest: 2400)
                            .frame(maxWidth: .infinity, maxHeight: 380, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars.inverse").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                Text("做好的视频会出现在这里：播放、每个场景的字和画面描述、所有场景并排的 sheet")
                    .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }

    // MARK: The first words

    private var starter: some View {
        let after = agent.terminal != nil
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(after ? "接着跟它说：回到上面这段对话"
                            : "想做什么视频？比如：40 秒竖屏，讲系外行星是怎么被发现的。它先写稿和每个场景的画面给你看，试一张图、一句声音，你点头了再做",
                      text: $words, axis: .vertical)
                .textFieldStyle(.plain).font(.kinBody).lineLimit(3...8)
                .onSubmit(send)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            Button(after ? "接着说" : "开做", action: send)
                .buttonStyle(.primary)
                .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("开一个 agent（\(agent.whereTitle)，\(agent.brainTitle)，用 Pixelle 的工具），第一句就是这个")
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

// MARK: - Shared by the Studio's newer tabs

/// A picture from disk, drawn small: read and scaled off the main thread and
/// kept for next time — a card is 1080×1440 and a few megabytes, and a list
/// of them read whole on every redraw is what makes a tab stutter.
struct StudioPicture: View {
    let url: URL?
    var largest: CGFloat = 800
    var fill = false

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Rectangle().fill(Theme.well)
            }
        }
        .task(id: (url?.path ?? "") + "@\(Int(largest))") {
            image = await StudioPictureCache.load(url, largest: largest)
        }
    }
}

enum StudioPictureCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func load(_ url: URL?, largest: CGFloat) async -> NSImage? {
        guard let url else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)@\(Int(largest))@\(modified)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let size = Int(largest)
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A finished video, with sound and the usual controls; waits to be started.
struct StudioVideoPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard (view.player?.currentItem?.asset as? AVURLAsset)?.url != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
    }
}

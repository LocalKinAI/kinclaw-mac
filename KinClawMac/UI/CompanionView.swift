import SwiftUI
import AppKit

/// Companion mode: the panel becomes a picture and a voice. No
/// transcript, no buttons, no typing — you speak, it listens, it
/// answers out loud, and the halo around the character shows which of
/// those is happening. Esc leaves.
///
/// It drives the same voice loop the panel already uses (VoiceRecorder,
/// SpeechSynthesizer, the kinclaw turn); this view only decides what
/// you look at while it runs.
struct CompanionView: View {
    @ObservedObject var art: CompanionArt

    /// Live inputs from the panel's existing voice objects.
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let audioLevel: Double
    /// Last thing said, shown small and briefly — useful when the room
    /// is loud enough that you missed it, invisible the rest of the time.
    let caption: String
    /// Non-nil when something is stopping the voice loop; shown instead
    /// of the state label, because "说话就好" over a dead mic is a lie.
    let problem: String?
    /// How the companion feels — from the reply's opening tag, or from
    /// how the user sounded. Picks the art alongside `state`.
    let mood: CompanionMood?
    /// True when talking over the agent will stop it (headphones, or
    /// forced on). Otherwise the halo is the way to cut in.
    let canBargeIn: Bool
    /// Stop the reply and open the microphone.
    let onInterrupt: () -> Void

    let onExit: () -> Void
    let onFetchArt: () -> Void
    /// Speak the sample line in the voice just chosen.
    let onPreviewVoice: () -> Void

    // The voice is a global preference, not a companion one: the panel's
    // voice mode uses the same speaker. It is offered here because this
    // is the one view where you are listening to it.
    @AppStorage("kinclaw.voice.tts.speaker") private var voice = "auto"
    @AppStorage("kinclaw.voice.tts.speed") private var speed: Double = 1.0

    @State private var current: URL?
    @State private var previous: URL?
    @State private var currentImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var showPrevious = false
    @State private var rotate: Timer?
    /// A still gets a slow push-in and drift over its time on screen,
    /// alternating direction picture to picture, so the background is
    /// never quite static even before there are clips.
    @State private var kenZoom: CGFloat = 1.03
    @State private var kenShift: CGSize = .zero
    @State private var kenSign: CGFloat = 1

    private var state: String {
        if isSpeaking { return "speaking" }
        if isThinking { return "thinking" }
        if isListening { return "listening" }
        return "idle"
    }

    private var accent: Color {
        if problem != nil { return .orange }
        switch state {
        case "listening": return .green
        case "thinking":  return .yellow
        case "speaking":  return .cyan
        default:          return .white.opacity(0.5)
        }
    }

    private var stateLabel: String {
        if let p = problem { return p }
        switch state {
        case "listening": return "在听"
        case "thinking":  return "在想"
        case "speaking":  return canBargeIn ? "在说 · 想插话就直接说" : "在说 · 点一下光晕打断"
        default:          return "说话就好"
        }
    }

    var body: some View {
        ZStack {
            background
            // A dark scrim keeps the halo and caption readable over a
            // bright picture without hiding the picture.
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                topBar
                Spacer()
                halo
                    .contentShape(Circle().scale(1.3))
                    .onTapGesture {
                        if isSpeaking || isThinking { onInterrupt() }
                    }
                    .help(isSpeaking ? "打断" : "")
                Text(stateLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(problem == nil ? .white.opacity(0.75) : .orange)
                    .padding(.top, 14)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 32)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
                Spacer()
            }
        }
        .background(Color.black)
        .onAppear {
            art.reload()
            pick()
            rotate = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
                Task { @MainActor in pick() }
            }
        }
        .onDisappear { rotate?.invalidate(); rotate = nil }
        .onChange(of: state) { _, _ in
            // Per-state art swaps immediately; a pool-only setup keeps
            // the same picture and just changes the halo.
            if art.hasGroups { pick() }
        }
        .onChange(of: mood) { _, _ in
            if art.hasGroups { pick() }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var background: some View {
        GeometryReader { geo in
            ZStack {
                if let p = previous, showPrevious {
                    media(p, image: previousImage, size: geo.size, live: false)
                }
                if let c = current {
                    media(c, image: currentImage, size: geo.size, live: true)
                        .transition(.opacity)
                        .id(c)
                } else {
                    emptyState
                }
            }
        }
        .ignoresSafeArea()
    }

    /// One piece of art filling the window: a looping clip as it is, a
    /// still with the slow camera move and a breath that follows the
    /// microphone while someone is talking.
    @ViewBuilder
    private func media(_ url: URL, image: NSImage?, size: CGSize, live: Bool) -> some View {
        if CompanionArt.isVideo(url) {
            LoopingVideoView(url: url)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else if let img = image {
            let level = (isListening || isSpeaking) ? CGFloat(min(1, audioLevel * 1.4)) : 0
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect((live ? kenZoom : 1.03) + level * 0.02)
                .offset(live ? kenShift : .zero)
                .animation(.easeOut(duration: 0.15), value: level)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🦞").font(.system(size: 60))
            Text("还没有背景图")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            Text("放几张图片到 ~/.kinclaw/companion/，\n或者让我去网上取几张。")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("去取几张…") { onFetchArt() }
                .controlSize(.small)
                .tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            voiceMenu
            themeMenu
            Spacer()
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(7)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("离开陪伴模式 (Esc)")
        }
        .padding(12)
    }

    /// Pick a voice by ear: every change speaks the sample line, so
    /// finding the one you like is a few clicks, not a trip to Settings
    /// and back for each candidate.
    private var voiceMenu: some View {
        Menu {
            Picker("声音", selection: $voice) {
                Text("自动（中文晓晓 · 英文 Bella）").tag("auto")
                Section("中文") {
                    ForEach(KokoroVoice.chinese) { v in Text(v.label).tag(v.id) }
                }
                Section("English") {
                    ForEach(KokoroVoice.english) { v in Text(v.label).tag(v.id) }
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("语速", selection: $speed) {
                ForEach(KokoroVoice.speeds, id: \.self) { sp in
                    Text(String(format: "%.1fx", sp)).tag(sp)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("再听一遍") { onPreviewVoice() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                Text(voiceLabel)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("换个声音 · 每次换都会念一句给你听")
        .onChange(of: voice) { _, _ in onPreviewVoice() }
        .onChange(of: speed) { _, _ in onPreviewVoice() }
    }

    /// Which set of pictures is behind you: the default folder or any
    /// `companion-<name>` sibling. Switching re-reads the folder and
    /// swaps the picture on the spot.
    private var themeMenu: some View {
        Menu {
            ForEach(CompanionArt.themes()) { th in
                Button {
                    art.useTheme(th)
                    pick()
                } label: {
                    if th.url.path == CompanionArt.folder.path {
                        Label(th.name, systemImage: "checkmark")
                    } else {
                        Text(th.name)
                    }
                }
            }
            Divider()
            Button("去取几张…") { onFetchArt() }
            Button("打开文件夹") { art.revealFolder() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle")
                Text(CompanionArt.themes().first { $0.url.path == CompanionArt.folder.path }?.name ?? "背景")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("换一套背景：~/.kinclaw/companion-<名字>/ 都是一套")
    }

    private var voiceLabel: String {
        let name = KokoroVoice.all.first { $0.id == voice }?.label ?? "自动"
        let rate = abs(speed - 1.0) < 0.01 ? "" : String(format: " · %.1fx", speed)
        return name + rate
    }

    /// The one moving thing: a ring that breathes on idle and tracks
    /// your voice while the mic is open, so "is it hearing me" is
    /// answerable from across the room.
    private var halo: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.04 * sin(t * 1.6)
            let level = isListening ? min(1, audioLevel * 1.6) : 0
            let pulse = isSpeaking ? 1 + 0.06 * sin(t * 5) : 1
            let scale = breathe * pulse * (1 + level * 0.35)
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.30), lineWidth: 2)
                    .frame(width: 150, height: 150)
                    .scaleEffect(scale * 1.12)
                    .blur(radius: 6)
                Circle()
                    .stroke(accent.opacity(0.85), lineWidth: 2.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(scale)
                if isThinking {
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(t * 220))
                }
            }
        }
        .frame(height: 190)
    }

    private func pick() {
        let next = art.art(for: state, mood: mood, fallback: art.pool.randomElement())
        guard next != current else { return }
        previous = current
        previousImage = currentImage
        showPrevious = current != nil
        // Decoded once here, not on every frame of the camera move.
        currentImage = next.flatMap { CompanionArt.isVideo($0) ? nil : NSImage(contentsOf: $0) }
        kenSign = -kenSign
        kenZoom = 1.03
        kenShift = .zero
        withAnimation(.easeInOut(duration: 0.8)) {
            current = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showPrevious = false }
        // Start the push-in after the crossfade has begun, so the new
        // picture arrives already moving rather than snapping into motion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard current == next else { return }
            withAnimation(.linear(duration: 45)) {
                kenZoom = 1.10
                kenShift = CGSize(width: kenSign * 14, height: -10)
            }
        }
    }
}

/// "Go get a few" — type what you want behind you, see what came back,
/// keep the ones you like. Wikimedia Commons needs no account, so this
/// works on a fresh machine; a free Pexels key in Settings swaps in a
/// better-looking source.
struct CompanionArtPicker: View {
    @ObservedObject var art: CompanionArt
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [CompanionArt.Candidate] = []
    @State private var searching = false
    @State private var kept: Set<UUID> = []
    @State private var kind: CompanionArt.MediaKind = .photo
    /// Which folder the next downloads land in: "" is the rotating
    /// pool, otherwise a state or mood.
    @State private var group = ""
    @AppStorage(CompanionArt.pexelsKeyKey) private var pexelsKey = ""

    private let suggestions = ["柴犬 puppy", "kitten", "golden retriever", "portrait", "cat sleeping", "landscape"]

    private var groupChoices: [(key: String, label: String)] {
        [("", "轮换")]
            + CompanionArt.stateKeys.map { ($0, $0) }
            + CompanionMood.allCases.map { ($0.rawValue, $0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("背景图").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("完成") { onClose() }.controlSize(.small)
            }
            HStack(spacing: 6) {
                Picker("", selection: $kind) {
                    ForEach(CompanionArt.MediaKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                TextField("小狗 / kitten / portrait…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button(searching ? "搜索中…" : "搜索") { runSearch() }
                    .controlSize(.small)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                Text("存到").font(.system(size: 10)).foregroundColor(.secondary)
                Picker("", selection: $group) {
                    ForEach(groupChoices, id: \.key) { Text($0.label).tag($0.key) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 120)
                Spacer()
                if kind == .video && pexelsKey.isEmpty {
                    Text("视频要 Pexels key（免费）— 设置 → 陪伴模式")
                        .font(.system(size: 10)).foregroundColor(.orange)
                }
            }
            HStack(spacing: 5) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { query = s; runSearch() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                Spacer()
            }

            if !results.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                        ForEach(results) { c in
                            thumb(c)
                        }
                    }
                }
                .frame(height: 260)
                Text("点一张就存到 \(CompanionArt.folder.path)")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Divider().opacity(0.2)
            HStack {
                Text("已有 \(art.count) 个")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("打开文件夹") { art.revealFolder() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.green)
            }
            Text("子文件夹按状态或情绪取名：idle / listening / thinking / speaking，开心 / 温柔 / 好奇 / 困 / 担心。小美每句话带情绪，说话时就换成那个文件夹里的图或视频；顶层的按时间轮换。mp4 / mov 循环播放。")
                .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { art.reload() }
    }

    private func thumb(_ c: CompanionArt.Candidate) -> some View {
        Button {
            kept.insert(c.id)
            Task { await art.download([c], theme: query, group: group) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: c.preview) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                if c.isVideo {
                    Label("\(c.seconds ?? 0)s", systemImage: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if kept.contains(c.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(4)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .help("\(c.title)\n\(c.credit)")
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            let r = await art.search(q, kind: kind)
            await MainActor.run {
                results = r
                searching = false
            }
        }
    }
}

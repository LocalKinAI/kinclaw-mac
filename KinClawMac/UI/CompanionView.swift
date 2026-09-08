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

    let onExit: () -> Void
    let onFetchArt: () -> Void

    @State private var current: URL?
    @State private var previous: URL?
    @State private var showPrevious = false
    @State private var rotate: Timer?

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
        case "speaking":  return "在说 · 想插话就直接说"
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
            if !art.byState.isEmpty { pick() }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var background: some View {
        GeometryReader { geo in
            ZStack {
                if let p = previous, showPrevious, let img = NSImage(contentsOf: p) {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                if let c = current, let img = NSImage(contentsOf: c) {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                        .id(c)
                } else {
                    emptyState
                }
            }
        }
        .ignoresSafeArea()
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
        HStack {
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
        let next = art.art(for: state, fallback: art.pool.randomElement())
        guard next != current else { return }
        previous = current
        showPrevious = current != nil
        withAnimation(.easeInOut(duration: 0.8)) {
            current = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showPrevious = false }
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

    private let suggestions = ["柴犬 puppy", "kitten", "golden retriever", "portrait", "cat sleeping", "landscape"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("背景图").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("完成") { onClose() }.controlSize(.small)
            }
            HStack(spacing: 6) {
                TextField("小狗 / kitten / portrait…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button(searching ? "搜索中…" : "搜索") { runSearch() }
                    .controlSize(.small)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
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
                Text("已有 \(art.pool.count + art.byState.count) 张")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("打开文件夹") { art.revealFolder() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.green)
            }
            Text("把文件命名成 idle / listening / thinking / speaking，四种状态就会各用各的图；其余的按时间轮换。")
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
            Task { await art.download([c], theme: query) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: c.url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                if kept.contains(c.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(c.title)\n\(c.credit)")
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            let r = await art.search(q)
            await MainActor.run {
                results = r
                searching = false
            }
        }
    }
}

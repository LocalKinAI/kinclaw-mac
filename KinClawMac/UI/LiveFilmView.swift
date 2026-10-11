import SwiftUI
import WebKit

/// 活画's window: the film drawn live, and what the person does with it — play, scrub across its
/// scenes, slow it down, loop it, take the lettering off, turn the knobs the film gives.
struct LiveFilmView: View {
    @ObservedObject private var live = LiveFilm.shared
    @ObservedObject private var player = LiveFilm.shared.player

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                LivePlayerView(player: player)
                if !player.ready {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(live.fetching.map { "从盒子拿「\($0)」…" } ?? "每一幕先画一遍…")
                            .font(.kinCaption).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 7) {
                LiveControls(player: player)
                HStack(spacing: 14) {
                    LiveOptions(player: player)
                    Spacer(minLength: 8)
                    if let trouble = live.trouble ?? player.trouble {
                        Text(trouble).font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(1).truncationMode(.tail)
                            .help(trouble)
                    }
                    if let id = live.current?.id {
                        LiveOutButtons(id: id, player: player)
                    }
                    if player.playing {
                        Text("\(player.fps) 帧/秒").font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if live.films.count > 1 {
                        Menu {
                            ForEach(live.films) { film in
                                Button(film.title) { Task { await live.show(film.id) } }
                            }
                        } label: { Label("换一部", systemImage: "film.stack") }
                        .menuStyle(.button).buttonStyle(.plain)
                        .fixedSize()
                    }
                    if live.current?.box != nil {
                        Button { Task { await live.update() } } label: { Label("从盒子更新", systemImage: "arrow.down.circle") }
                            .buttonStyle(.quiet)
                            .disabled(live.fetching != nil)
                            .help("盒子上的片子改过了：重新拿一遍代码和歌，再从头画")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.sidebar)
        }
    }
}

/// Play, the time, the timeline and which scene: one row.
struct LiveControls: View {
    @ObservedObject var player: LivePlayer
    var spaceBar = true
    /// Where the finger is on the timeline while it drags.
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: 10) {
            if spaceBar {
                playButton.keyboardShortcut(.space, modifiers: [])
            } else {
                playButton
            }
            Text(Self.clock(scrubbing ?? player.time) + " / " + Self.clock(player.total))
                .font(.kinLabel.monospacedDigit())
                .foregroundStyle(.secondary)
            timeline
            if player.eras.count > 1 {
                Text(scene).font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minWidth: 54, alignment: .trailing)
            }
        }
    }

    private var playButton: some View {
        Button { player.toggle() } label: {
            Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 16)
        }
        .buttonStyle(.quietFilled)
        .disabled(!player.ready)
        .help(player.playing ? "停" : "放")
    }

    /// The film's length with a mark where each scene starts; drag or click to go there.
    private var timeline: some View {
        GeometryReader { space in
            let width = max(1, space.size.width)
            let total = max(player.total, 0.001)
            let t = scrubbing ?? player.time
            let x = width * min(max(t / total, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well).frame(height: 5)
                Capsule().fill(Theme.accent).frame(width: x, height: 5)
                ForEach(player.eras.dropFirst()) { era in
                    Rectangle().fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: 11)
                        .offset(x: width * era.t0 / total)
                }
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: 12, height: 12)
                    .offset(x: x - 6)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let at = min(max(drag.location.x / width, 0), 1) * total
                    scrubbing = at
                    player.seek(at)
                }
                .onEnded { _ in scrubbing = nil })
        }
        .frame(height: 20)
        .disabled(!player.ready)
    }

    /// Which scene the time is in.
    private var scene: String {
        let t = scrubbing ?? player.time
        let index = player.eras.lastIndex { t >= $0.t0 } ?? 0
        return "第 \(index + 1)/\(player.eras.count) 幕"
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

/// Speed, loop, the lettering and the film's own knobs.
struct LiveOptions: View {
    @ObservedObject var player: LivePlayer
    var full = true
    /// One knob a line, for a narrow place (beside her in companion mode).
    var stacked = false

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) { content }
        } else {
            HStack(spacing: 14) { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if full {
                Picker("", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    Text("0.25×").tag(0.25)
                    Text("0.5×").tag(0.5)
                    Text("1×").tag(1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("慢放：歌也跟着慢，音高不变")
                Toggle("循环", isOn: Binding(get: { player.loops }, set: { player.setLoops($0) }))
                    .toggleStyle(.checkbox)
                Toggle("题字", isOn: Binding(get: { player.lettering }, set: { player.setLettering($0) }))
                    .toggleStyle(.checkbox)
                    .help("片子画在最上面的那一层：唱词、印章、字幕")
            }
            ForEach(player.knobs) { knob in
                if !knob.options.isEmpty {
                    HStack(spacing: 6) {
                        Text(knob.label).font(.kinLabel)
                        let picker = Picker("", selection: Binding(get: { knob.value.rounded() }, set: { player.setKnob(knob.id, $0) })) {
                            ForEach(Array(knob.options.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(Double(index))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        if knob.options.count <= 5 { picker.pickerStyle(.segmented) } else { picker.pickerStyle(.menu) }
                    }
                } else {
                HStack(spacing: 6) {
                    Text(knob.label).font(.kinLabel)
                    Slider(value: Binding(get: { knob.value }, set: { player.setKnob(knob.id, $0) }),
                           in: knob.min...max(knob.max, knob.min + 0.001))
                        .controlSize(.small)
                        .frame(width: 110)
                    Text(Self.number(knob.value)).font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                }
                }
            }
        }
    }

    static func number(_ value: Double) -> String {
        abs(value) >= 100 ? String(format: "%.0f", value) : abs(value) >= 10 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }
}

/// A player's web view, where SwiftUI wants it.
struct LivePlayerView: NSViewRepresentable {
    let player: LivePlayer

    func makeNSView(context: Context) -> WKWebView { player.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// 讲给我听 and 存成视频 for one film: the buttons, what they are doing, and where the video went.
struct LiveOutButtons: View {
    let id: String
    /// The player showing it: a video keeps its knobs and lettering as they are there.
    @ObservedObject var player: LivePlayer
    @ObservedObject private var out = LiveOut.shared
    @ObservedObject private var live = LiveFilm.shared

    var body: some View {
        let film = live.films.first { $0.id == id }
        HStack(spacing: 10) {
            if let step = out.narrating[id] {
                ProgressView().controlSize(.small)
                Text(step).font(.kinCaption).foregroundStyle(.secondary)
            } else if film?.song == nil || film?.lines != nil || film?.music != nil {
                Button { Task { try? await out.narrate(id) } } label: {
                    Label(film?.lines == nil ? "讲给我听" : "重新讲", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.quiet)
                .help("Claude 看着这幅画的代码写几句解说，你的陪伴的声音念出来，和画面对上；念得比画长，最后一幕停住等它说完")
            }
            if let done = out.exporting[id] {
                ProgressView(value: done).frame(width: 70)
                Text("存视频 \(Int(done * 100))%").font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Button {
                    let mine = player.film == film?.film
                    let knobs = mine ? Dictionary(player.knobs.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first }) : [:]
                    Task { try? await out.export(id, knobs: knobs, lettering: mine ? player.lettering : true) }
                } label: { Label("存成视频", systemImage: "square.and.arrow.down") }
                .buttonStyle(.quiet)
                .help("一帧一帧画成 1080p、60 帧的 MP4：旋钮和题字照现在的样子，有解说或歌就配上")
                if let url = out.exported[id] {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("打开", systemImage: "folder") }
                        .buttonStyle(.quiet)
                        .help(url.path)
                }
            }
            if let trouble = out.trouble[id] {
                Text(trouble).font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(1).truncationMode(.tail).help(trouble)
            }
        }
    }
}

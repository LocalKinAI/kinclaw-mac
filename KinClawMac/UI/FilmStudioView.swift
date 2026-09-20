import AVKit
import SwiftUI

/// The film tab: say what you want to see, and watch it get made.
///
/// Built around the wait, because the wait is the product. A shot takes a
/// minute and a half on the box, so this is not a box you type into and get
/// a video out of; it is a studio with a queue, where the storyboard appears
/// at once, each frame turns up as it is drawn, each clip as it is filmed,
/// and the cut arrives at the end. Everything on screen is what is on disk.
struct FilmStudioView: View {
    @ObservedObject private var studio = FilmStudio.shared
    @ObservedObject private var character = CompanionCharacter.shared

    @State private var idea = ""
    @State private var shots = 4
    @State private var lead = true
    @State private var trouble: String?
    @State private var selected: String?
    /// Who could write a storyboard, host by host, and who will.
    @State private var writers: [(host: String, models: [String])] = []
    @State private var writer = "自动"
    @AppStorage("kinclaw.film.writer") private var writerModel = ""
    @AppStorage("kinclaw.film.writer.host") private var writerHost = ""
    @State private var tick = 0

    private var film: FilmStudio.Film? {
        studio.films.first { $0.id == selected } ?? studio.films.first
    }

    var body: some View {
        HStack(spacing: 0) {
            library.frame(width: 168)
            Divider().opacity(0.15)
            VStack(spacing: 0) {
                if let film { detail(film) } else { empty }
                Divider().opacity(0.15)
                composer
            }
        }
        .onAppear { studio.reload() }
        // Stills and clips land on disk one by one; a glance every two
        // seconds is how they show up here as they do.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if studio.shooting != nil { tick += 1 }
        }
    }

    // MARK: The library

    private var library: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(studio.films) { film in
                    Button { selected = film.id } label: {
                        HStack(spacing: 8) {
                            thumb(film.still(film.shots.first?.id ?? 1)).frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(film.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(status(film)).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(film.id == self.film?.id ? Color.white.opacity(0.09) : .clear))
                    }
                    .buttonStyle(.plain)
                }
                if studio.films.isEmpty {
                    Text("拍过的片子会在这儿").font(.system(size: 10)).foregroundColor(.secondary).padding(8)
                }
            }
            .padding(8)
        }
    }

    // MARK: One film

    @ViewBuilder
    private func detail(_ film: FilmStudio.Film) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(film.title).font(.system(size: 15, weight: .semibold))
                    Text(status(film)).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    if film.state == .done {
                        Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([film.file]) }
                            .controlSize(.small)
                    }
                }
                if film.state == .done, FileManager.default.fileExists(atPath: film.file.path) {
                    FilmPlayer(url: film.file)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                }
                if !film.look.isEmpty {
                    Text(film.look).font(.system(size: 10)).foregroundColor(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(film.shots) { shot in card(film, shot) }
                }
                if let note = film.note {
                    Text(note).font(.system(size: 10)).foregroundColor(.orange)
                }
                if film.state != .shooting, film.state != .cutting, film.shots.contains(where: { $0.state != .done }) {
                    Button("接着拍") {
                        if case .failure(let failure) = studio.resume(film: film.id) { trouble = failure.localizedDescription }
                    }
                    .controlSize(.small)
                    .disabled(studio.shooting != nil)
                }
            }
            .padding(14)
            .id(tick)                       // re-reads the thumbnails as files land
        }
    }

    private func card(_ film: FilmStudio.Film, _ shot: FilmStudio.Shot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                thumb(film.still(shot.id)).aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("\(shot.id) · \(word(shot.state))\(shot.hq == true ? " · 精修" : "")")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(6)
                if shot.state == .drawing || shot.state == .filming {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let said = shot.narration {
                Text("「\(said)」").font(.system(size: 10)).italic().lineLimit(2)
            }
            Text(shot.motion).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(3)
            if let note = shot.note { Text(note).font(.system(size: 9)).foregroundColor(.orange).lineLimit(2) }
            if film.state == .done || film.state == .failed {
                Button("重拍这个镜头") {
                    if case .failure(let failure) = studio.reshoot(film: film.id, shot: shot.id, still: nil, motion: nil) {
                        trouble = failure.localizedDescription
                    }
                }
                .controlSize(.mini)
                .disabled(studio.shooting != nil)
                if shot.state == .done, shot.hq != true {
                    Button("精修（q8）") {
                        if case .failure(let failure) = studio.reshoot(film: film.id, shot: shot.id, still: nil, motion: nil, hq: true) {
                            trouble = failure.localizedDescription
                        }
                    }
                    .controlSize(.mini)
                    .disabled(studio.shooting != nil)
                    .help("同一张图、同一段动作，用高清模型再拍一遍：细节干净一点，约 9 分钟，要占盒子约 45 GB 内存（kinfer 得关着）")
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "film").font(.system(size: 34)).foregroundColor(.secondary)
            Text("一句话，拍个短片").font(.system(size: 13, weight: .medium))
            Text("分镜、出图、出片、剪辑都在你自己的机器上。\n一个镜头一分半钟左右，四个镜头大约七分钟。")
                .font(.system(size: 10)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Asking for one

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let trouble { Text(trouble).font(.system(size: 10)).foregroundColor(.orange) }
            // Two rows. In one, at the panel's usual width, the field had room
            // for three characters and the button that starts everything was
            // an ellipsis.
            HStack(spacing: 8) {
                TextField("想看什么？比如：她在雨夜的街上撑着伞走", text: $idea)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit(start)
                Button(studio.writing != nil ? "在写分镜…" : "开拍", action: start)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(studio.writing != nil || studio.shooting != nil || idea.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 12) {
                writerMenu
                Stepper("\(shots) 个镜头", value: $shots, in: 2...8).font(.system(size: 10)).fixedSize()
                Toggle("她当主角", isOn: $lead).font(.system(size: 10)).toggleStyle(.checkbox).fixedSize()
                    .disabled(character.anchorURL == nil)
                    .help(character.anchorURL == nil ? "她还没有锚图" : "每个镜头里都是同一个她")
                Spacer(minLength: 0)
            }
            if let id = studio.shooting, let film = studio.films.first(where: { $0.id == id }) {
                Text("在拍「\(film.title)」：\(film.finished)/\(film.shots.count)")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    /// Who writes the storyboard. 自动 asks the Ollama the app is pointed at,
    /// then this Mac, and takes the most capable chat model it finds; naming
    /// one pins it.
    private var writerMenu: some View {
        Menu {
            Button { writerModel = ""; writerHost = ""; Task { await describeWriter() } } label: {
                Label("自动（挑最强的那个）", systemImage: writerModel.isEmpty ? "checkmark" : "")
            }
            ForEach(writers, id: \.host) { entry in
                Section(entry.host == OllamaCatalog.defaultBaseURL ? "本机" : entry.host.replacingOccurrences(of: "http://", with: "")) {
                    ForEach(entry.models, id: \.self) { model in
                        Button { writerModel = model; writerHost = entry.host; Task { await describeWriter() } } label: {
                            Label(model, systemImage: writerModel == model && writerHost == entry.host ? "checkmark" : "")
                        }
                    }
                }
            }
        } label: {
            Label("分镜：\(writer)", systemImage: "pencil.and.outline").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("分镜由哪个模型写")
        .task { await loadWriters(); await describeWriter() }
    }

    private func loadWriters() async {
        writers = await FilmStudio.candidates()
    }

    private func describeWriter() async {
        guard let pick = await FilmStudio.writer() else { writer = "没有可用的模型"; return }
        let place = pick.host == OllamaCatalog.defaultBaseURL ? "本机" : "盒子"
        writer = "\(pick.model)（\(place)\(writerModel.isEmpty ? "，自动" : "")）"
    }

    private func start() {
        let wanted = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, studio.writing == nil, studio.shooting == nil else { return }
        trouble = nil
        studio.make(from: wanted, shots: shots, lead: lead && character.anchorURL != nil) { result in
            switch result {
            case .success(let film): selected = film.id; idea = ""
            case .failure(let failure): trouble = failure.localizedDescription
            }
        }
    }

    // MARK: Small things

    private func thumb(_ url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }
        }
    }

    private func word(_ state: FilmStudio.Shot.State) -> String {
        switch state {
        case .waiting: return "等着"
        case .drawing: return "在画"
        case .filming: return "在拍"
        case .done:    return "好了"
        case .failed:  return "没拍成"
        }
    }

    private func status(_ film: FilmStudio.Film) -> String {
        switch film.state {
        case .waiting:  return "等着开拍"
        case .shooting: return "在拍 \(film.finished)/\(film.shots.count)"
        case .cutting:  return "在剪"
        case .done:     return "\(film.shots.count) 个镜头 · \(Int(Double(film.finished) * film.seconds)) 秒"
        case .failed:   return "没拍成"
        }
    }
}

/// The finished film, with sound and the usual controls.
private struct FilmPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url { view.player = AVPlayer(url: url) }
    }
}

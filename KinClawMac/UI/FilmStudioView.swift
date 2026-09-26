import AVKit
import SwiftUI

/// The film tab: say what you want to see, and watch it get made.
///
/// Built around the wait, because the wait is the product. A shot takes a
/// minute and a half on the box, so this is not a box you type into and get
/// a video out of; it is a studio with a queue, where the storyboard appears
/// at once, each frame turns up as it is drawn, each clip as it is filmed,
/// and the cut arrives at the end. Everything on screen is what is on disk.
///
/// Laid out in the order a film is looked at: what is happening now, the
/// film itself, its shots, who is in it — and last, folded away, the words
/// it was made from, which are English prompts for the models and were a
/// wall of small print above the shots.
struct FilmStudioView: View {
    @ObservedObject private var studio = FilmStudio.shared
    @ObservedObject private var character = CompanionCharacter.shared
    /// The director under the tab, with the film tools. See `StudioAgent`.
    @ObservedObject private var agent = StudioAgent.film
    /// What the idea at the bottom goes to: the agent, which plans, asks and
    /// then drives the studio, or the studio's own pipeline straight away.
    @AppStorage("kinclaw.film.byAgent") private var byAgent = true

    @State private var idea = ""
    @State private var shots = 4
    @State private var lead = true
    @State private var trouble: String?
    @State private var selected: String?
    /// Who could write a storyboard, host by host, and who will.
    @State private var writers: [(host: String, models: [String])] = []
    @State private var writer = "自动"
    @State private var writerPlace = ""
    @AppStorage("kinclaw.film.writer") private var writerModel = ""
    @AppStorage("kinclaw.film.writer.host") private var writerHost = ""
    /// The voice-over's language: a tag, "none", or "" to follow the idea's.
    @AppStorage(FilmStudio.tongueKey) private var tongue = ""
    @AppStorage(FilmStudio.layaOnKey) private var layaOn = false
    @AppStorage(FilmStudio.jevOnKey) private var jevOn = false
    @AppStorage(FilmStudio.jevCountsKey) private var jevCounts = false
    /// Automatic retakes per shot on the reviewer's say-so; 0 is no reviewer.
    @AppStorage(FilmStudio.retakesKey) private var retakes = 1
    /// The shape of the picture: a phone holds a portrait one.
    @AppStorage("kinclaw.film.shape") private var shape = FilmStudio.Shape.square.rawValue
    /// 自动 reads the sentence; the other two overrule the reading.
    @AppStorage("kinclaw.film.kind") private var kind = FilmStudio.Kind.auto.rawValue
    /// What films a story: LTX from each still, or H3 from a cast.
    @AppStorage("kinclaw.film.engine") private var engine = FilmStudio.Engine.ltx.rawValue
    @AppStorage(FilmStudio.musicKey) private var musicOn = true
    @AppStorage(FilmStudio.pinKey) private var pinOn = true
    @AppStorage(FilmStudio.fastDrawKey) private var fastDraw = true
    @State private var tick = 0
    /// One shot's words, open for rewriting, and what they were when opened.
    @State private var editing: Words?
    @State private var opened: Words?
    @State private var translating = false
    /// The shot being watched in the player, by film: nil is the whole film.
    /// A shot is there to be looked at the moment it is filmed — not when
    /// the last one is, a quarter of an hour later.
    @State private var watching: [String: Int] = [:]
    /// The film somebody has asked to delete, until they say yes or no.
    @State private var doomed: FilmStudio.Film?
    /// The row under the pointer: its delete button shows only then.
    @State private var hovered: String?
    @State private var complaint: String?
    /// The words a film was made from, unfolded.
    @State private var aboutOpen = false
    /// Each video's own shape, once read: an H3 film is 928×544, not the
    /// 16:9 its stills were drawn at, and a player cut to 16:9 put black
    /// bars down its sides.
    @State private var shapes: [URL: CGFloat] = [:]

    struct Words: Equatable {
        var film: String
        var shot: Int
        /// A direction in a sentence; the words below are rewritten to it.
        var wish: String
        var framing: String
        var pose: String
        var action: String
        var narration: String
    }

    private var film: FilmStudio.Film? {
        studio.films.first { $0.id == selected } ?? studio.films.first
    }

    private var busy: Bool { studio.shooting != nil || studio.revising != nil }

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                // The director, standing along the left; the films and the
                // film keep the rest.
                AgentDock(agent: agent, examples: examples, widest: space.size.width - 212 - 480) { ask($0) }
                library
                    .frame(width: 212)
                    .background(Theme.sidebar)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                VStack(spacing: 0) {
                    if let film { detail(film) } else { empty }
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    composer
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            studio.reload()
            // The agent is how this tab is worked now: its column is out
            // when the tab is, as on Montage.
            if !agent.running { agent.shown = true }
        }
        .confirmationDialog(doomed.map { "把「\($0.title)」整部删掉？" } ?? "", isPresented: Binding(
            get: { doomed != nil }, set: { if !$0 { doomed = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let film = doomed { remove(film) } }
            Button("取消", role: .cancel) { doomed = nil }
        } message: {
            Text((doomed.map { studio.shooting == $0.id ? "这部正在拍，会先停下来。" : "" } ?? "")
                 + "分镜、每个镜头的画面和视频、留下来的旧镜头、成片，整个文件夹一起移到废纸篓；想要回来，到废纸篓里「放回原处」。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinclawFilmShow)) { show($0) }
        // Whatever starts shooting — from the box below, from the agent, from
        // her — is what the tab shows.
        .onChange(of: studio.shooting) { _, id in if let id { selected = id } }
        // Stills and clips land on disk one by one; a glance every two
        // seconds is how they show up here as they do.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if studio.shooting != nil { tick += 1 }
        }
    }

    // MARK: The library

    private var library: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                HStack {
                    SectionTitle("影片", detail: studio.films.isEmpty ? nil : "\(studio.films.count)")
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 6)
                ForEach(studio.films) { film in row(film) }
                if let complaint {
                    Text(complaint).font(.kinCaption).foregroundStyle(Theme.notice).padding(.horizontal, 8)
                }
                if studio.films.isEmpty {
                    Text("拍过的片子会在这儿").font(.kinCaption).foregroundStyle(.secondary).padding(8)
                }
            }
            .padding(8)
            .id(tick)                       // re-reads the thumbnails as files land
        }
    }

    private func row(_ film: FilmStudio.Film) -> some View {
        let chosen = film.id == self.film?.id
        let shooting = studio.shooting == film.id
        return Button { selected = film.id } label: {
            HStack(spacing: 10) {
                Color.clear.frame(width: 44, height: 44)
                    .overlay { thumb(film.opening(film.shots.first?.id ?? 1)) }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(film.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(shooting ? "在拍 \(film.finished)/\(film.shots.count)" : shortStatus(film))
                        .font(.kinCaption)
                        .foregroundStyle(shooting ? Theme.accent : film.state == .failed ? Theme.bad : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chosen ? Theme.accentWash : hovered == film.id ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovered == film.id {
                Button { doomed = film } label: {
                    Image(systemName: "trash").font(.system(size: 10.5))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.bad).padding(.trailing, 8)
                .help("删除整部影片（移到废纸篓）")
            }
        }
        .onHover { inside in hovered = inside ? film.id : (hovered == film.id ? nil : hovered) }
        .contextMenu {
            Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([film.folder]) }
            Divider()
            Button(studio.shooting == film.id ? "停下来并删除…" : "删除整部影片…", role: .destructive) { doomed = film }
        }
    }

    // MARK: One film

    @ViewBuilder
    private func detail(_ film: FilmStudio.Film) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(film)
                progress(film)
                if let note = film.note {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.kinLabel).foregroundStyle(Theme.notice)
                        .fixedSize(horizontal: false, vertical: true)
                }
                screen(film)
                if let words = editing, words.film == film.id { editor(film, words) }
                shotsSection(film)
                if let cast = film.cast, !cast.isEmpty { castSection(film, cast) }
                aboutSection(film)
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ film: FilmStudio.Film) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(.kinTitle).textSelection(.enabled)
                Text(status(film)).font(.kinCaption).foregroundStyle(.secondary)
                if let about = film.about, !about.isEmpty, about != film.title {
                    Text(about).font(.kinLabel).foregroundStyle(.secondary).lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            if film.state != .shooting, film.state != .cutting, film.shots.contains(where: { $0.state != .done }) {
                Button("接着拍") {
                    if case .failure(let failure) = studio.resume(film: film.id) { trouble = failure.localizedDescription }
                }
                .buttonStyle(.primary)
                .disabled(studio.shooting != nil)
                .help("已经拍好的镜头留着，从没拍好的那个接着拍")
            }
            if FileManager.default.fileExists(atPath: film.file.path) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([film.file]) } label: {
                    Image(systemName: "folder").font(.system(size: 13))
                }
                .buttonStyle(.quiet)
                .help("在访达里显示成片")
            }
            Button { agent.shown = true } label: { Label("问 agent", systemImage: "sparkles") }
                .buttonStyle(.quietFilled)
                .help("让 agent 看这部片子、改这部片子：「每个镜头数一遍」「第 8 镜的篮子多了，修掉」")
            more(film)
        }
    }

    /// Everything done to a finished film without shooting it again, and
    /// taking it off the shelf: in words, behind one ⋯.
    private func more(_ film: FilmStudio.Film) -> some View {
        Menu {
            if film.state == .done {
                Button {
                    if case .failure(let failure) = studio.rescore(film: film.id, music: musicOn) { trouble = failure.localizedDescription }
                } label: { Label(musicOn ? "重做旁白和配乐" : "重做旁白", systemImage: "waveform") }
                .disabled(busy)
                .help("不重拍：按片子的内容重新挑旁白的声音和语气、重读每一句旁白，\(musicOn ? "再在盒子上作一段配乐，" : "")然后重新剪。原来的旁白和成片留着")
                Button { studio.reassess(film: film.id) } label: {
                    Label("重新检查每个镜头", systemImage: "checkmark.seal")
                }
                .disabled(busy)
                .help("不重拍，只把每个镜头再看一遍：动作到不到位、有没有出错，以及 Laya / Jev 的第二意见")
                if (layaOn || jevOn), film.shots.contains(where: { $0.saw != nil }) {
                    Button { studio.reassess(film: film.id, opinionsOnly: true) } label: {
                        Label("只让 \(judges) 再判一遍", systemImage: "person.2")
                    }
                    .disabled(busy)
                    .help("不看画面：把把关已经写下的「看到的动作」再交给 \(judges) 判一遍。一个镜头一秒左右，不花看图模型的额度")
                }
                Divider()
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([film.folder]) } label: {
                Label("在访达里显示文件夹", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) { doomed = film } label: {
                Label(studio.shooting == film.id ? "停下来并删除…" : "删除整部影片…", systemImage: "trash")
            }
            .disabled(studio.revising != nil)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.well))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("重做旁白和配乐 · 重新检查 · 在访达里显示 · 删除")
    }

    /// What is being done to this film right now, and the way to stop it.
    @ViewBuilder
    private func progress(_ film: FilmStudio.Film) -> some View {
        let shooting = studio.shooting == film.id
        if shooting || studio.revising != nil {
            HStack(spacing: 12) {
                if shooting, studio.revising == nil, film.state != .cutting, !film.shots.isEmpty {
                    ProgressView(value: Double(film.finished), total: Double(film.shots.count))
                        .progressViewStyle(.linear).frame(width: 150)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(doing(film)).font(.kinLabel).lineLimit(1)
                Spacer(minLength: 8)
                Button("停") { studio.stop() }
                    .buttonStyle(.quiet)
                    .help("停下手上这一步。已经拍好的镜头留着，盒子上正在渲染的那一段会自己跑完但不要了；之后点「接着拍」继续")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .card(radius: 11)
        }
    }

    private func doing(_ film: FilmStudio.Film) -> String {
        if let revising = studio.revising { return revising }
        if film.state == .cutting { return "在剪：旁白、配乐、调色、混音" }
        let working: [FilmStudio.Shot.State] = [.drawing, .filming, .reviewing]
        if let shot = film.shots.first(where: { working.contains($0.state) }) {
            return "镜头 \(shot.id) \(word(shot.state)) · 拍好了 \(film.finished)/\(film.shots.count)"
        }
        return "拍好了 \(film.finished)/\(film.shots.count)"
    }

    /// The film's own shape, for the player and every picture of it.
    private func aspect(_ film: FilmStudio.Film) -> CGFloat {
        let size = film.size
        return size.height > 0 ? size.width / size.height : 1
    }

    /// The player, and what it can show, side by side under it: the cut, and
    /// each shot that has been filmed. The first version had a small
    /// "看整片" beside a caption, and its owner, having clicked a shot, could
    /// not find the film again.
    @ViewBuilder
    private func screen(_ film: FilmStudio.Film) -> some View {
        let still = picture(film)
        let url = still == nil ? playing(film)?.url : nil
        let ratio = url.flatMap { shapes[$0] } ?? aspect(film)
        VStack(spacing: 12) {
            Group {
                if let still {
                    // A first frame, whole, while its shot is being filmed.
                    ZStack(alignment: .bottomLeading) {
                        Color.black
                        thumb(still.url)
                        Text(caption(film, still.shot))
                            .font(.kinCaption).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(10)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { NSWorkspace.shared.open(still.url) }
                    .help("点一下用「预览」打开原图")
                    .id(tick)
                } else if let playing = playing(film) {
                    FilmPlayer(url: playing.url, autoplay: playing.shot != nil)
                } else {
                    // Nothing filmed yet: the first picture if there is one.
                    ZStack {
                        Color.black
                        thumb(film.opening(film.shots.first?.id ?? 1)).opacity(0.55)
                        VStack(spacing: 6) {
                            Image(systemName: "film").font(.system(size: 26, weight: .light))
                            Text(film.state == .failed ? "没拍成" : "第一个镜头拍好就能在这儿看")
                                .font(.kinLabel)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                    }
                    .id(tick)
                }
            }
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: ratio >= 1 ? 820 : 400, maxHeight: 560)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .task(id: url) {
                guard let url, shapes[url] == nil,
                      let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0
                else { return }
                shapes[url] = size.width / size.height
            }

            if still != nil || playing(film) != nil {
                let shown = still?.shot ?? playing(film)?.shot
                HStack(spacing: 4) {
                    let cut = FileManager.default.fileExists(atPath: film.file.path)
                    choice("整片", on: shown == nil, ready: cut, help: cut ? "看整部片子" : "还没剪好") {
                        watching[film.id] = nil
                    }
                    Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 16).padding(.horizontal, 4)
                    ForEach(film.shots) { shot in
                        let filmed = FileManager.default.fileExists(atPath: film.clip(shot.id).path)
                        let drawn = FileManager.default.fileExists(atPath: film.opening(shot.id).path)
                        choice("\(shot.id)", on: shown == shot.id, ready: filmed || drawn,
                               help: filmed ? "只看镜头 \(shot.id)" : drawn ? "看镜头 \(shot.id) 的首帧（视频还在拍）" : "镜头 \(shot.id) 还没画好") {
                            watching[film.id] = shot.id
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// One of the things the player can show.
    private func choice(_ title: String, on: Bool, ready: Bool, help: String, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            ChipLabel(title: title, on: on)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.4)
        .help(help)
    }

    /// A first frame to show in the player's place: the one picked, while its
    /// shot has no clip yet; or, with nothing filmed at all, the latest drawn.
    /// An H3 shot is filmed for ten minutes after its first frame is drawn,
    /// and the frame could not be looked at until then — dimmed on a small
    /// card, under a spinner ("film 每一帧完成不能看啊").
    private func picture(_ film: FilmStudio.Film) -> (url: URL, shot: Int)? {
        let fm = FileManager.default
        if let picked = watching[film.id], !fm.fileExists(atPath: film.clip(picked).path),
           fm.fileExists(atPath: film.opening(picked).path) {
            return (film.opening(picked), picked)
        }
        guard playing(film) == nil,
              let drawn = film.shots.last(where: { fm.fileExists(atPath: film.opening($0.id).path) }) else { return nil }
        return (film.opening(drawn.id), drawn.id)
    }

    /// What the picture in the player's place is.
    private func caption(_ film: FilmStudio.Film, _ id: Int) -> String {
        switch film.shots.first(where: { $0.id == id })?.state {
        case .filming?: return "镜头 \(id) 的首帧 · 视频在拍"
        case .reviewing?: return "镜头 \(id) 的首帧 · 在把关"
        case .drawing?: return "镜头 \(id) 的首帧 · 在重画"
        default: return "镜头 \(id) 的首帧"
        }
    }

    /// What the player shows: the shot that was picked, if its clip is
    /// there; else the finished film; else — while it is still being made —
    /// the latest shot that has been filmed.
    private func playing(_ film: FilmStudio.Film) -> (url: URL, shot: Int?)? {
        let fm = FileManager.default
        if let picked = watching[film.id], fm.fileExists(atPath: film.clip(picked).path) {
            return (film.clip(picked), picked)
        }
        if film.state == .done, fm.fileExists(atPath: film.file.path) { return (film.file, nil) }
        if let latest = film.shots.last(where: { $0.state == .done && fm.fileExists(atPath: film.clip($0.id).path) }) {
            return (film.clip(latest.id), latest.id)
        }
        return nil
    }

    // MARK: Shots

    private func shotsSection(_ film: FilmStudio.Film) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("镜头", detail: "\(film.shots.count) 个 · 点画面在上面看")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: aspect(film) >= 1 ? 220 : 160, maximum: 320),
                                         spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                ForEach(film.shots) { shot in card(film, shot) }
            }
            .id(tick)                       // re-reads the pictures as files land
        }
    }

    private func badge(_ words: String, _ colour: Color) -> some View {
        Text(words).font(.kinMicro).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.9)))
    }

    private func card(_ film: FilmStudio.Film, _ shot: FilmStudio.Shot) -> some View {
        let filmed = FileManager.default.fileExists(atPath: film.clip(shot.id).path)
        let drawn = FileManager.default.fileExists(atPath: film.opening(shot.id).path)
        let onScreen = (picture(film)?.shot ?? playing(film)?.shot) == shot.id
        let working = shot.state == .drawing || shot.state == .filming || shot.state == .reviewing
        let tags = [shot.hq == true ? "精修" : nil, shot.method?.title,
                    shot.grade?.neutral == false ? "调色" : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            // The picture, in the film's own shape, cut to it: a wider
            // picture filled past its cell and lay over the next card.
            Color.clear
                .aspectRatio(aspect(film), contentMode: .fit)
                .overlay { thumb(film.opening(shot.id)) }
                // Dimmed only while there is nothing to see: a first frame
                // being filmed stays in full, with what is happening in a
                // corner.
                .overlay { if working && !drawn { Color.black.opacity(0.35) } }
                .clipped()
                // The verdict where it cannot be missed: on the picture.
                // Under three lines of prompt text, below the fold, it
                // was data nobody saw ("我怎么没有看见").
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        if let score = shot.score {
                            badge("把关 \(score)", score >= 7 ? Theme.good : score >= 5 ? Theme.notice : Theme.bad)
                        }
                        if layaOn, let right = shot.laya?["activity"] {
                            badge("Laya \(String(format: "%.2f", right))", Theme.laya)
                        }
                        if jevOn, let right = shot.jev?["activity"] {
                            badge("Jev \(String(format: "%.2f", right))", Theme.jev)
                        }
                    }
                    .padding(7)
                }
                .overlay(alignment: .topLeading) {
                    Text("\(shot.id)")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(7)
                }
                .overlay {
                    if working && !drawn {
                        VStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text(word(shot.state)).font(.kinCaption).foregroundStyle(.white)
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if working && drawn {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini).tint(.white)
                            Text(word(shot.state)).font(.kinMicro).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(7)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Group {
                        if filmed, !working {
                            Image(systemName: onScreen ? "play.circle.fill" : "play.circle")
                        } else if drawn, !filmed {
                            Image(systemName: onScreen ? "eye.circle.fill" : "eye.circle")
                        }
                    }
                    .font(.system(size: 20)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3).padding(7)
                }
                .contentShape(Rectangle())
                .onTapGesture { if filmed || drawn { watching[film.id] = shot.id } }
                .help(filmed ? "在上面的播放器里看这个镜头" : drawn ? "在上面看这个镜头的首帧（视频还在拍）" : "这个镜头还没画好")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(word(shot.state)).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(shot.state == .failed ? Theme.bad : working ? Theme.accent : .secondary)
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.well))
                    }
                    Spacer(minLength: 0)
                    if film.state == .done || film.state == .failed { actions(film, shot) }
                }
                if let said = shot.narration, !said.isEmpty {
                    Text("「\(said)」").font(.kinLabel).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = shot.note {
                    Text(note).font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(2)
                }
                if let verdict = verdict(shot) {
                    Text(verdict).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
                }
                if layaOn, let second = second("Laya", shot.laya) {
                    Text(second).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
                        .help("Laya 对「看到的动作」的打分，只显示、不参与决定。\n看到的：\(shot.saw ?? "")")
                }
                if jevOn, let second = second("Jev", shot.jev) {
                    Text(second).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
                        .help("Jev 对同一段「看到的动作」的判断，和 Laya 问的是同样四件事。" + (jevCounts ? "按计划低于 0.30 的镜头算不过。" : "只显示、不参与决定。") + "\n看到的：\(shot.saw ?? "")")
                }
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 10)
            // The prompt it was filmed from is for the models, in English:
            // there when asked for, not printed on every card.
            .help([shot.framing, shot.action].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .card(radius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: onScreen ? 2 : 0))
    }

    /// What can be done to one shot of a finished film.
    private func actions(_ film: FilmStudio.Film, _ shot: FilmStudio.Shot) -> some View {
        HStack(spacing: 2) {
            Button("改…") { open(film, shot) }
                .buttonStyle(.quiet)
                .disabled(studio.shooting != nil)
                .help("改这个镜头的机位、画面、动作、旁白，然后只重拍它，或者从它往后都重拍")
            Menu {
                Button("重拍这个镜头") {
                    if case .failure(let failure) = studio.reshoot(film: film.id, shot: shot.id, still: nil, motion: nil) {
                        trouble = failure.localizedDescription
                    }
                }
                if shot.state == .done, shot.hq != true {
                    Button("精修（q8，约 9 分钟）") {
                        if case .failure(let failure) = studio.reshoot(film: film.id, shot: shot.id, still: nil, motion: nil, hq: true) {
                            trouble = failure.localizedDescription
                        }
                    }
                    .help("同一张图、同一段动作，用高清模型再拍一遍：细节干净一点，约 9 分钟，要占盒子约 45 GB 内存（kinfer 得关着）")
                }
                if FileManager.default.fileExists(atPath: film.clip(shot.id).path) {
                    Divider()
                    Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([film.clip(shot.id)]) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(studio.shooting != nil)
            .help("重拍 · 精修 · 在访达里显示")
        }
    }

    // MARK: Cast, and the words behind the film

    private func castSection(_ film: FilmStudio.Film, _ cast: [FilmStudio.Cast]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("演员", detail: "每个镜头都照着这几张定妆照拍")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(cast.enumerated()), id: \.offset) { i, member in
                        VStack(spacing: 5) {
                            Color.clear.frame(width: 78, height: 104)
                                .overlay {
                                    if let image = NSImage(contentsOf: film.castPicture(i)) {
                                        Image(nsImage: image).resizable().scaledToFill()
                                    } else {
                                        Theme.well.overlay(ProgressView().controlSize(.small))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                                .onTapGesture { NSWorkspace.shared.open(film.castPicture(i)) }
                            Text(member.name).font(.kinCaption).lineLimit(1).frame(width: 82)
                        }
                        .help(member.look)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// What the film was made from — the reading of the idea, the look, the
    /// place, who narrates, the brief for the music — folded away: it is
    /// mostly the English the models were given.
    private func aboutRows(_ film: FilmStudio.Film) -> [(String, String)] {
        var narrator = ""
        if let voice = film.narrator {
            narrator = voice.voice ?? voice.speaker
            if let how = voice.instruct { narrator += " · " + how }
        }
        var rows: [(String, String)] = []
        rows.append(("出处", film.source ?? ""))
        rows.append(("质感", film.look))
        rows.append(("影调", film.tone ?? ""))
        rows.append(("地点", film.place ?? ""))
        rows.append(("旁白", narrator))
        rows.append(("旁白词", film.voiceover.map { "「" + $0 + "」" } ?? ""))
        rows.append(("配乐", film.score ?? ""))
        return rows.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @ViewBuilder
    private func aboutSection(_ film: FilmStudio.Film) -> some View {
        let rows = aboutRows(film)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { aboutOpen.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(aboutOpen ? 90 : 0))
                        SectionTitle("片子是怎么写的", detail: aboutOpen ? nil : rows.map(\.0).joined(separator: " · "))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if aboutOpen {
                    Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 9) {
                        ForEach(rows, id: \.0) { row in
                            GridRow {
                                Text(row.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(row.1).font(.kinLabel).foregroundStyle(.primary.opacity(0.8))
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    if row.0 == "配乐", FileManager.default.fileExists(atPath: film.music.path) {
                                        Button { NSWorkspace.shared.open(film.music) } label: {
                                            Label("听", systemImage: "play.fill").font(.kinCaption)
                                        }
                                        .buttonStyle(.quiet).help("听配乐")
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .card(radius: 11)
                }
            }
        }
    }

    // MARK: Rewriting one shot

    /// The four things a shot is made of, open for rewriting.
    ///
    /// Inline rather than a sheet or a popover: the panel is a floating
    /// window that hides when it loses focus, and a popover that closes on
    /// the first stray click takes a paragraph of typing with it.
    private func editor(_ film: FilmStudio.Film, _ words: Words) -> some View {
        let first = film.shots.first?.id == words.shot
        let changed = words != opened
        let onlyVoice = changed && opened.map {
            $0.framing == words.framing && $0.pose == words.pose && $0.action == words.action && $0.wish == words.wish
        } == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("改镜头 \(words.shot)").font(.kinHeadline)
                Spacer()
                if translating {
                    ProgressView().controlSize(.mini)
                    Text("在转成英文…").font(.kinCaption).foregroundStyle(.secondary)
                }
                if let busy = studio.revising {
                    ProgressView().controlSize(.mini)
                    Text("在照你说的改：\(busy)").font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            field("方向", "说一句就行：「手再慢一点，脚别动」「镜头近一点，只拍上半身」「让她最后看向镜头」", binding(\.wish), lines: 2)
            Text("给个方向，提示词它自己改：会先看一眼现在这条拍成了什么样。下面是这个镜头实际用的提示词，想自己动手也可以直接改——你写的会原样用，不会再被改写。")
                .font(.kinCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            field("机位", first ? "第一个镜头固定是全景：它是全片的底图" : "medium shot from her left side, waist up",
                  binding(\.framing), lines: 1).disabled(first)
            field("画面", "她这一刻的姿势：站/坐/走，每只手脚在做什么", binding(\.pose), lines: 3)
            field("动作", "这四秒里她怎么动；镜头（身体在动就写 static camera）；环境声", binding(\.action), lines: 4)
            field("旁白", "留空就是不说话", binding(\.narration), lines: 2)
            HStack(spacing: 8) {
                Button("取消") { editing = nil; opened = nil }.buttonStyle(.quiet)
                Spacer()
                if onlyVoice {
                    Button("只换旁白（两秒）") { apply(words, following: false) }.buttonStyle(.primary)
                } else {
                    Button("从这个往后都重拍") { apply(words, following: true) }
                        .buttonStyle(.quiet)
                        .help("后面的镜头是接着这个镜头的最后一帧拍的；它变了，后面就接不上了")
                        .disabled(film.shots.last?.id == words.shot)
                    Button("只重拍这一个") { apply(words, following: false) }.buttonStyle(.primary)
                }
            }
            .disabled(!changed || translating || studio.shooting != nil || studio.revising != nil)
        }
        .padding(14)
        .card(radius: 12)
    }

    /// Off the shelf, and the selection on to whatever is next to it.
    private func remove(_ film: FilmStudio.Film) {
        doomed = nil
        let index = studio.films.firstIndex { $0.id == film.id }
        switch studio.remove(film: film.id) {
        case .failure(let failure): complaint = failure.localizedDescription
        case .success:
            complaint = nil
            watching[film.id] = nil
            if editing?.film == film.id { editing = nil; opened = nil }
            if selected == film.id || selected == nil {
                let left = studio.films
                selected = left.isEmpty ? nil : left[min(index ?? 0, left.count - 1)].id
            }
        }
    }

    /// Who would be asked for a second opinion, for the button's words.
    private var judges: String { [layaOn ? "Laya" : nil, jevOn ? "Jev" : nil].compactMap { $0 }.joined(separator: " 和 ") }

    /// A judge's numbers on the take that was kept, as one line.
    private func second(_ who: String, _ numbers: [String: Double]?) -> String? {
        guard let read = numbers, !read.isEmpty else { return nil }
        func part(_ key: String, _ name: String) -> String? { read[key].map { "\(name) \(String(format: "%.2f", $0))" } }
        let parts = [part("follows", "按计划"), part("activity", "动作到位"), part("leaves", "走掉"),
                     read["amount"].map { "幅度 \(String(format: "%.1f", $0))/2" }].compactMap { $0 }
        return "\(who)：" + parts.joined(separator: " · ")
    }

    /// What the reviewer made of the take that was kept.
    private func verdict(_ shot: FilmStudio.Shot) -> String? {
        guard let score = shot.score else { return nil }
        let again = (shot.retakes ?? 0) > 0 ? " · 自动重拍了 \(shot.retakes!) 次" : ""
        let bother = (shot.review ?? "").isEmpty ? "" : " · \(shot.review!)"
        return "把关 \(score)/10\(again)\(bother)"
    }

    private func open(_ film: FilmStudio.Film, _ shot: FilmStudio.Shot) {
        let words = Words(film: film.id, shot: shot.id, wish: shot.wish ?? "", framing: shot.framing ?? "",
                          pose: shot.pose, action: shot.action, narration: shot.narration ?? "")
        editing = words
        opened = words
    }

    /// `panel_show {mode: film, film, shot}`: "我想改第三个镜头" said to her.
    private func show(_ note: Notification) {
        guard let wanted = note.userInfo?["film"] as? String,
              let film = studio.films.first(where: { $0.id == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) })
        else { return }
        selected = film.id
        if let number = note.userInfo?["shot"] as? Int, let shot = film.shots.first(where: { $0.id == number }) {
            open(film, shot)
        }
    }

    private func binding(_ path: WritableKeyPath<Words, String>) -> Binding<String> {
        Binding(get: { editing?[keyPath: path] ?? "" }, set: { editing?[keyPath: path] = $0 })
    }

    private func field(_ label: String, _ hint: String, _ text: Binding<String>, lines: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading).padding(.top, 5)
            TextField(hint, text: text, axis: .vertical)
                .textFieldStyle(.plain).font(.kinLabel).lineLimit(lines...max(lines, 6))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .well(radius: 7)
        }
    }

    /// Only what was changed is sent, so a shot whose pose was left alone
    /// keeps the pose that was read off the previous shot.
    private func apply(_ words: Words, following: Bool) {
        guard let was = opened else { return }
        let typed = was.framing != words.framing || was.pose != words.pose || was.action != words.action
        // A direction and no words typed: the model rewrites them. Words
        // typed: they are the user's, and the direction rides along as a wish.
        if words.wish != was.wish, !typed, !words.wish.trimmingCharacters(in: .whitespaces).isEmpty {
            studio.redirect(film: words.film, shot: words.shot, note: words.wish, following: following) { result in
                switch result {
                case .success: editing = nil; opened = nil
                case .failure(let failure): trouble = failure.localizedDescription
                }
            }
            return
        }
        let voiceOnly = !typed && was.wish == words.wish
        if voiceOnly {
            if case .failure(let failure) = studio.narrate(film: words.film, shot: words.shot, line: words.narration) {
                trouble = failure.localizedDescription
            } else { editing = nil; opened = nil }
            return
        }
        translating = true
        Task { @MainActor in
            defer { translating = false }
            let framing = words.framing == was.framing ? nil : await FilmStudio.english(words.framing, as: "camera position")
            let pose = words.pose == was.pose ? nil : await FilmStudio.english(words.pose, as: "still frame (her pose)")
            let action = words.action == was.action ? nil : await FilmStudio.english(words.action, as: "movement, camera and ambient sound")
            switch studio.reshoot(film: words.film, shot: words.shot, framing: framing, still: pose, motion: action,
                                  narration: words.narration == was.narration ? nil : words.narration,
                                  following: following, wish: words.wish == was.wish ? nil : words.wish) {
            case .success: editing = nil; opened = nil
            case .failure(let failure): trouble = failure.localizedDescription
            }
        }
    }

    /// Nothing on the shelf yet: what this is, and a few ideas to start from.
    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "film").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.accentWash))
            Text("一句话，拍个短片").font(.kinTitle)
            Text("分镜、出图、出片、配音配乐、剪辑，都在你自己的机器上。\n一个镜头一分半钟左右，四个镜头大约七分钟。")
                .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(["她在雨夜的街上撑着伞走", "海边的黄昏", "五饼二鱼"], id: \.self) { example in
                    Button { idea = example } label: { ChipLabel(title: example, symbol: "sparkles") }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Asking for one

    /// The idea, the button that starts it, and how it is to be made — the
    /// choices as chips that say what they are set to, in one wrapping row
    /// instead of ten controls of four kinds squeezed onto one line.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let trouble {
                Label(trouble, systemImage: "exclamationmark.triangle")
                    .font(.kinCaption).foregroundStyle(Theme.notice).lineLimit(3)
            }
            if byAgent, agent.running {
                // The agent's own prompt is where to type while it runs.
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text("agent 在跑：直接在左边它的终端里说").font(.kinLabel).foregroundStyle(.secondary)
                    Spacer()
                    Button(agent.shown ? "收起终端" : "展开终端") { agent.shown.toggle() }.buttonStyle(.quietFilled)
                }
            } else {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(byAgent ? "想拍什么、想改哪里，跟 agent 说：它先给你方案，你点头它再拍"
                                  : "想看什么？比如：她在雨夜的街上撑着伞走", text: $idea, axis: .vertical)
                    .textFieldStyle(.plain).font(.kinBody).lineLimit(1...4)
                    .onSubmit(go)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                Button(action: go) {
                    HStack(spacing: 5) {
                        if studio.writing != nil, !byAgent { ProgressView().controlSize(.mini).tint(.white) }
                        Text(byAgent ? (agent.running ? "告诉 agent" : "交给 agent") : studio.writing != nil ? "在写分镜…" : "开拍")
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.primary)
                .fixedSize()
                .disabled(idea.trimmingCharacters(in: .whitespaces).isEmpty
                          || (!byAgent && (studio.writing != nil || studio.shooting != nil)))
                .help(byAgent ? "agent 先说打算怎么拍（几个镜头、H3 还是 LTX、多长、要多久），你点头它再拍，拍完自己一个镜头一个镜头地看、数、修"
                      : studio.shooting != nil ? "一次拍一部：等这部拍完，或者先停下它" : "先写分镜，再一个镜头一个镜头地拍")
            }
            }
            FlowLayout(spacing: 6) {
                toggleChip("agent 导演", symbol: "sparkles", on: $byAgent,
                           help: "开着：底下这句话交给 agent（这台 Mac 上的 Claude Code，拿着片场的工具）——它定方案、问你、再拍、再检查。关着：直接按下面这些设置开拍")
                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 18).padding(.horizontal, 3)
                kindMenu
                engineMenu
                countMenu
                shapeMenu
                toggleChip("配乐", symbol: "music.note", on: $musicOn,
                           help: "在盒子上按片子的内容作一段配乐（MiniMax Music 3，经 ComfyUI），垫在整部片子下面，旁白说话时自动压低")
                if engine == FilmStudio.Engine.h3.rawValue {
                    toggleChip("钉帧", symbol: "pin", on: $pinOn,
                               help: "H3 拍的片子：有人的镜头先用定妆照和布景合成第一帧（要数的东西先数对），再钉在开头让 H3 从这一帧拍；没人的镜头从布景拍，要数的空镜头开头、中间、结尾都钉。人和东西都更稳，动作也更自然")
                }
                toggleChip("快速出图", symbol: "hare", on: $fastDraw,
                           help: "经 ComfyUI 出的图（有人镜头的第一帧、改图、重画要数的布景）用 Pruna 的 8 步 LoRA，不用 25 步：快三倍左右，实测画质接近。关掉就用原来的慢方法")
                toggleChip("她当主角", symbol: "person.crop.circle", on: $lead,
                           help: character.anchorURL == nil ? "她还没有锚图" : "每个镜头里都是同一个她")
                    .disabled(character.anchorURL == nil)
                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 18).padding(.horizontal, 3)
                writerMenu
                tongueMenu
                reviewMenu
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.sidebar.opacity(0.6))
    }

    private func toggleChip(_ title: String, symbol: String, on: Binding<Bool>, help: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            ChipLabel(title: title, symbol: on.wrappedValue ? "checkmark" : symbol, on: on.wrappedValue)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func chipMenu<Content: View>(_ title: String, symbol: String, help: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) { ChipLabel(title: title, symbol: symbol, menu: true) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help(help)
    }

    private var kindMenu: some View {
        chipMenu(FilmStudio.Kind(rawValue: kind)?.title ?? "自动", symbol: "text.book.closed",
                 help: "自动：先读一遍这句话，看它是一段连续的动作还是一串发生的事，由它决定怎么拍。故事：强制当成一串事——每镜独立画，可以换景，镜头拍物、拍景、拍人影。连续动作：强制当成一个人在一个地方做一件连贯的事") {
            ForEach(FilmStudio.Kind.allCases, id: \.rawValue) { item in
                Button { kind = item.rawValue } label: {
                    Label(item.title, systemImage: kind == item.rawValue ? "checkmark" : "")
                }
            }
        }
    }

    private var engineMenu: some View {
        chipMenu(FilmStudio.Engine(rawValue: engine)?.title ?? "LTX", symbol: "video",
                 help: "拍故事用哪个模型。LTX：每镜从一张画出来的图拍，快（约 100 秒一镜），但人每镜长得不一样，所以故事里的人只拍手、背影。H3：先选角、给每个人画一张定妆照，每镜照着这些人和那一镜的布景拍，脸和衣服前后一致，自带环境声；慢（约 5–7 分钟一镜），要盒子上的 ComfyUI 和 H3 模型。连续动作的片子总是用 LTX") {
            ForEach(FilmStudio.Engine.allCases, id: \.rawValue) { item in
                Button { engine = item.rawValue } label: {
                    Label(item.title, systemImage: engine == item.rawValue ? "checkmark" : "")
                }
            }
        }
    }

    private var countMenu: some View {
        chipMenu("\(shots) 个镜头", symbol: "square.grid.2x2", help: "分几个镜头拍") {
            ForEach(2...8, id: \.self) { count in
                Button { shots = count } label: {
                    Label("\(count) 个镜头", systemImage: shots == count ? "checkmark" : "")
                }
            }
        }
    }

    private var shapeMenu: some View {
        chipMenu(FilmStudio.Shape(rawValue: shape)?.title ?? "方 1:1", symbol: "aspectratio",
                 help: "画面的形状。竖屏 9:16 是手机拿着看的那种，576×1024；方形 704×704 是这个标签原来的样子") {
            ForEach(FilmStudio.Shape.allCases, id: \.rawValue) { item in
                Button { shape = item.rawValue } label: {
                    Label(item.title, systemImage: shape == item.rawValue ? "checkmark" : "")
                }
            }
        }
    }

    /// Who writes the storyboard. 自动 asks the Ollama the app is pointed at,
    /// then this Mac, and takes the most capable chat model it finds; naming
    /// one pins it.
    private var writerMenu: some View {
        chipMenu("分镜：\(writer)", symbol: "pencil.and.outline",
                 help: "分镜由哪个模型写：\(writer)（\(writerPlace)）。它也是看图把关的那个，如果它能看图") {
            Button { writerModel = ""; writerHost = ""; Task { await describeWriter() } } label: {
                Label("自动（挑最强的那个）", systemImage: writerModel.isEmpty ? "checkmark" : "")
            }
            // The subscription, through Claude Code: it writes, and it sees.
            Section("这台 Mac 的 Claude") {
                Button { writerModel = ClaudeWriter.model; writerHost = ClaudeWriter.pick; Task { await describeWriter() } } label: {
                    Label(ClaudeWriter.title + (ClaudeWriter.binary == nil ? "（没装 Claude Code）" : ""),
                          systemImage: writerHost == ClaudeWriter.pick ? "checkmark" : "")
                }
                .disabled(ClaudeWriter.binary == nil)
            }
            ForEach(writers, id: \.host) { entry in
                Section(BoxServices.place(of: entry.host)) {
                    ForEach(entry.models, id: \.self) { model in
                        Button { writerModel = model; writerHost = entry.host; Task { await describeWriter() } } label: {
                            Label(model, systemImage: writerModel == model && writerHost == entry.host ? "checkmark" : "")
                        }
                    }
                }
            }
        }
        .task { await loadWriters(); await describeWriter() }
    }

    /// Whether each take is looked at, and how many times it may be redone.
    private var reviewMenu: some View {
        chipMenu(retakes == 0 ? "把关：关" : "把关：\(retakes) 次", symbol: "checkmark.seal",
                 help: "每个镜头拍完，让能看图的模型对着计划看一遍：跑题了、多了人、镜头乱飞，就自己改提示词重拍，留得分最高的那条。一次重拍约两分半钟") {
            Button { retakes = 0 } label: { Label("不把关（拍成什么样就是什么样）", systemImage: retakes == 0 ? "checkmark" : "") }
            ForEach(1...3, id: \.self) { count in
                Button { retakes = count } label: {
                    Label("不满意就自动重拍，每个镜头最多 \(count) 次", systemImage: retakes == count ? "checkmark" : "")
                }
            }
        }
    }

    /// What language the voice-over is written and spoken in.
    private var tongueMenu: some View {
        let shown = tongue == "none" ? "无" : FilmStudio.tongues.first { $0.tag == tongue }?.name ?? "自动"
        return chipMenu("旁白：\(shown)", symbol: "waveform", help: "旁白用哪种语言写、用哪种语言的声音念") {
            Button { tongue = "" } label: { Label("自动（跟你写的那句话）", systemImage: tongue.isEmpty ? "checkmark" : "") }
            ForEach(FilmStudio.tongues, id: \.tag) { entry in
                Button { tongue = entry.tag } label: { Label(entry.name, systemImage: tongue == entry.tag ? "checkmark" : "") }
            }
            Divider()
            Button { tongue = "none" } label: { Label("不要旁白", systemImage: tongue == "none" ? "checkmark" : "") }
        }
    }

    private func loadWriters() async {
        writers = await FilmStudio.candidates()
    }

    private func describeWriter() async {
        guard let pick = await FilmStudio.writer(claude: true) else { writer = "没有可用的模型"; return }
        if writerHost == ClaudeWriter.pick, pick.model == ClaudeWriter.model {
            writer = "Claude 订阅"
            writerPlace = "这台 Mac 的 Claude Code，你指定的；看图把关、首帧和配乐的描述也是它"
            return
        }
        let place = pick.host == OllamaCatalog.defaultBaseURL ? "本机" : "盒子"
        writer = pick.model
        writerPlace = "\(place)\(writerModel.isEmpty ? "，自动挑的" : "，你指定的")"
    }

    /// The idea at the bottom, to whichever it goes to.
    private func go() {
        if byAgent {
            ask(idea)
            idea = ""
        } else {
            start()
        }
    }

    /// Things to try in the empty dock: a new film, and work on the one open.
    private var examples: [String] {
        var some = ["拍一部一分钟的五饼二鱼，H3，配乐和旁白"]
        if film != nil { some += ["这部片子每个镜头都看一遍，数一遍，告诉我哪里不对", "哪个镜头最弱？重拍它"] }
        return some
    }

    /// Words for the agent, with the film that is open — "这部片子" means it.
    private func ask(_ words: String) {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let open = film.map { "（片场里开着的片子：「\($0.title)」，id \($0.id)）\n" } ?? ""
        agent.say(open + text)
    }

    private func start() {
        let wanted = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty, studio.writing == nil, studio.shooting == nil else { return }
        trouble = nil
        studio.make(from: wanted, shots: shots, lead: lead && character.anchorURL != nil,
                    shape: FilmStudio.Shape(rawValue: shape) ?? .square,
                    kind: FilmStudio.Kind(rawValue: kind) ?? .auto,
                    engine: FilmStudio.Engine(rawValue: engine) ?? .ltx) { result in
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
                Rectangle().fill(Theme.well)
            }
        }
    }

    private func word(_ state: FilmStudio.Shot.State) -> String {
        switch state {
        case .waiting: return "等着"
        case .drawing: return "在画"
        case .filming: return "在拍"
        case .reviewing: return "在把关"
        case .done:    return "好了"
        case .failed:  return "没拍成"
        }
    }

    private func status(_ film: FilmStudio.Film) -> String {
        (film.engine == .h3 ? "H3 · " : "") + {
        switch film.state {
        case .waiting:  return "等着开拍"
        case .shooting: return "在拍 \(film.finished)/\(film.shots.count)"
        case .cutting:  return "在剪"
        case .done:     return "\(film.shots.count) 个镜头 · \(Int(Double(film.finished) * film.seconds)) 秒" + (film.loudness.map { " · \(Int($0.rounded())) LUFS" } ?? "")
        case .failed:   return "没拍成"
        }
        }()
    }

    /// The library row's line: what it is, without the mastering numbers.
    private func shortStatus(_ film: FilmStudio.Film) -> String {
        switch film.state {
        case .done: return (film.engine == .h3 ? "H3 · " : "") + "\(film.shots.count) 镜 · \(Int(Double(film.finished) * film.seconds)) 秒"
        default: return status(film)
        }
    }
}

/// The finished film, with sound and the usual controls.
private struct FilmPlayer: NSViewRepresentable {
    let url: URL
    /// A shot that was just picked plays; the whole film waits to be started.
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

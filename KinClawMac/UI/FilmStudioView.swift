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
        .confirmationDialog(doomed.map { "把「\($0.title)」整部删掉？" } ?? "", isPresented: Binding(
            get: { doomed != nil }, set: { if !$0 { doomed = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) { if let film = doomed { remove(film) } }
            Button("取消", role: .cancel) { doomed = nil }
        } message: {
            Text((doomed.map { studio.shooting == $0.id ? "这部正在拍，会先停下来。" : "" } ?? "")
                 + "分镜、每个镜头的画面和视频、留下来的旧镜头、成片，整个文件夹一起移到废纸篓；想要回来，到废纸篓里「放回原处」。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinclawFilmShow)) { show($0) }
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
                    .overlay(alignment: .trailing) {
                        if hovered == film.id {
                            Button { doomed = film } label: {
                                Image(systemName: "trash").font(.system(size: 10))
                                    .padding(5).background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .buttonStyle(.plain).foregroundColor(.red).padding(.trailing, 6)
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
                if let complaint {
                    Text(complaint).font(.system(size: 9)).foregroundColor(.orange).padding(.horizontal, 8)
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
                    if let busy = studio.revising {
                        ProgressView().controlSize(.mini)
                        Text(busy).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                    }
                    if studio.shooting == film.id || studio.revising != nil {
                        Button("停") { studio.stop() }
                            .controlSize(.small)
                            .help("停下手上这一步。已经拍好的镜头留着，盒子上正在渲染的那一段会自己跑完但不要了；之后点「接着拍」继续")
                    }
                    if film.state == .done {
                        if (layaOn || jevOn), film.shots.contains(where: { $0.saw != nil }) {
                            Button("只问第二意见") { studio.reassess(film: film.id, opinionsOnly: true) }
                                .controlSize(.small)
                                .disabled(studio.shooting != nil || studio.revising != nil)
                                .help("不看画面：把把关已经写下的「看到的动作」再交给 \(judges) 判一遍。一个镜头一秒左右，不花看图模型的额度")
                        }
                        Button("重新配音配乐") {
                            if case .failure(let failure) = studio.rescore(film: film.id, music: musicOn) { trouble = failure.localizedDescription }
                        }
                        .controlSize(.small)
                        .disabled(studio.shooting != nil || studio.revising != nil)
                        .help("不重拍：按片子的内容重新挑旁白的声音和语气、重读每一句旁白，\(musicOn ? "再在盒子上作一段配乐，" : "")然后重新剪。原来的旁白和成片留着")
                        Button("重新把关") { studio.reassess(film: film.id) }
                            .controlSize(.small)
                            .disabled(studio.shooting != nil || studio.revising != nil)
                            .help("不重拍，只把每个镜头再看一遍：动作到不到位、有没有出错，以及 Laya / Jev 的第二意见")
                        Button("在访达里显示") { NSWorkspace.shared.activateFileViewerSelecting([film.file]) }
                            .controlSize(.small)
                    }
                    // Any film at all: finished, failed, abandoned half way —
                    // or being shot this minute, which stops first.
                    Button(role: .destructive) { doomed = film } label: { Image(systemName: "trash") }
                        .controlSize(.small)
                        .disabled(studio.revising != nil)
                        .help(studio.shooting == film.id ? "停下来并删除整部影片（移到废纸篓，可以放回）"
                              : "删除整部影片（移到废纸篓，可以放回）")
                }
                if let playing = playing(film) {
                    FilmPlayer(url: playing.url, autoplay: playing.shot != nil)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                    // What the player can show, side by side: the cut, and
                    // each shot that has been filmed. The first version had a
                    // small "看整片" beside a caption, and its owner, having
                    // clicked a shot, could not find the film again.
                    HStack(spacing: 4) {
                        let cut = FileManager.default.fileExists(atPath: film.file.path)
                        choice("整片", on: playing.shot == nil, ready: cut) { watching[film.id] = nil }
                        ForEach(film.shots) { shot in
                            choice("镜头 \(shot.id)", on: playing.shot == shot.id,
                                   ready: FileManager.default.fileExists(atPath: film.clip(shot.id).path)) {
                                watching[film.id] = shot.id
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 420).frame(maxWidth: .infinity)
                }
                if !film.look.isEmpty {
                    Text(film.look).font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let tone = film.tone {
                    Text(tone).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary).textSelection(.enabled)
                }
                // Where it all happens: one place for the whole film, and the
                // first thing to read when two shots do not look like one.
                if let place = film.place {
                    Text(place).font(.system(size: 10)).foregroundColor(.secondary)
                }
                // Who tells it and what plays under it.
                if film.narrator != nil || film.score != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let narrator = film.narrator {
                            Text("旁白：\(narrator.voice ?? narrator.speaker)\(narrator.instruct.map { " · \($0)" } ?? "")")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        if let passage = film.voiceover {
                            Text("「\(passage)」").font(.system(size: 10)).foregroundColor(.secondary).textSelection(.enabled)
                        }
                        if let score = film.score {
                            HStack(spacing: 6) {
                                Text("配乐：\(score)").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
                                if FileManager.default.fileExists(atPath: film.music.path) {
                                    Button { NSWorkspace.shared.open(film.music) } label: { Image(systemName: "music.note") }
                                        .buttonStyle(.plain).help("听配乐")
                                }
                            }
                        }
                    }
                }
                // The cast of an H3 film: who every shot is filmed from.
                if let cast = film.cast, !cast.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(cast.enumerated()), id: \.offset) { i, member in
                                VStack(spacing: 3) {
                                    if let image = NSImage(contentsOf: film.castPicture(i)) {
                                        Image(nsImage: image).resizable().scaledToFill()
                                            .frame(width: 66, height: 88).clipShape(RoundedRectangle(cornerRadius: 6))
                                            .onTapGesture { NSWorkspace.shared.open(film.castPicture(i)) }
                                    } else {
                                        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                                            .frame(width: 66, height: 88).overlay(ProgressView().controlSize(.mini))
                                    }
                                    Text(member.name).font(.system(size: 9)).lineLimit(1).frame(width: 70)
                                }
                                .help(member.look)
                            }
                        }
                    }
                }
                if let words = editing, words.film == film.id { editor(film, words) }
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

    private func badge(_ words: String, _ colour: Color) -> some View {
        Text(words).font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.85)))
    }

    /// One of the things the player can show.
    private func choice(_ title: String, on: Bool, ready: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Text(title).font(.system(size: 10, weight: on ? .semibold : .regular))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08)))
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.35)
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

    private func card(_ film: FilmStudio.Film, _ shot: FilmStudio.Shot) -> some View {
        let filmed = FileManager.default.fileExists(atPath: film.clip(shot.id).path)
        let onScreen = playing(film)?.shot == shot.id
        return VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                thumb(film.still(shot.id)).aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: onScreen ? 2 : 0))
                    // The verdict where it cannot be missed: on the picture.
                    // Under three lines of prompt text, below the fold, it
                    // was data nobody saw ("我怎么没有看见").
                    .overlay(alignment: .topTrailing) {
                        VStack(alignment: .trailing, spacing: 3) {
                            if let score = shot.score {
                                badge("把关 \(score)", score >= 7 ? Color.green : score >= 5 ? Color.orange : Color.red)
                            }
                            if layaOn, let right = shot.laya?["activity"] {
                                badge("Laya \(String(format: "%.2f", right))", Color.blue)
                            }
                            if jevOn, let right = shot.jev?["activity"] {
                                badge("Jev \(String(format: "%.2f", right))", Color.purple)
                            }
                        }
                        .padding(6)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if filmed {
                            Image(systemName: onScreen ? "play.circle.fill" : "play.circle")
                                .font(.system(size: 20)).foregroundColor(.white)
                                .shadow(radius: 3).padding(6)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if filmed { watching[film.id] = shot.id } }
                    .help(filmed ? "在上面的播放器里看这个镜头" : "这个镜头还没拍好")
                Text("\(shot.id) · \(word(shot.state))\(shot.hq == true ? " · 精修" : "")")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(6)
                if shot.state == .drawing || shot.state == .filming || shot.state == .reviewing {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let said = shot.narration {
                Text("「\(said)」").font(.system(size: 10)).italic().lineLimit(2)
            }
            if let camera = shot.framing {
                Text(camera).font(.system(size: 9, weight: .medium)).foregroundColor(.secondary).lineLimit(1)
            }
            Text(shot.action).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(3)
            if let note = shot.note { Text(note).font(.system(size: 9)).foregroundColor(.orange).lineLimit(2) }
            if let verdict = verdict(shot) {
                Text(verdict).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
            }
            if layaOn, let second = second("Laya", shot.laya) {
                Text(second).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
                    .help("Laya 对「看到的动作」的打分，只显示、不参与决定。\n看到的：\(shot.saw ?? "")")
            }
            if jevOn, let second = second("Jev", shot.jev) {
                Text(second).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
                    .help("Jev 对同一段「看到的动作」的判断，和 Laya 问的是同样四件事。" + (jevCounts ? "按计划低于 0.30 的镜头算不过。" : "只显示、不参与决定。") + "\n看到的：\(shot.saw ?? "")")
            }
            if film.state == .done || film.state == .failed {
                Button("改这个镜头…") { open(film, shot) }
                .controlSize(.mini)
                .disabled(studio.shooting != nil)
                .help("改这个镜头的机位、画面、动作、旁白，然后只重拍它，或者从它往后都重拍")
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("改镜头 \(words.shot)").font(.system(size: 12, weight: .semibold))
                Spacer()
                if translating { ProgressView().controlSize(.mini); Text("在转成英文…").font(.system(size: 9)).foregroundColor(.secondary) }
                if let busy = studio.revising { ProgressView().controlSize(.mini); Text("在照你说的改：\(busy)").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1) }
            }
            field("方向", "说一句就行：「手再慢一点，脚别动」「镜头近一点，只拍上半身」「让她最后看向镜头」", binding(\.wish), lines: 2)
            Text("给个方向，提示词它自己改：会先看一眼现在这条拍成了什么样。下面是这个镜头实际用的提示词，想自己动手也可以直接改——你写的会原样用，不会再被改写。")
                .font(.system(size: 9)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            field("机位", first ? "第一个镜头固定是全景：它是全片的底图" : "medium shot from her left side, waist up",
                  binding(\.framing), lines: 1).disabled(first)
            field("画面", "她这一刻的姿势：站/坐/走，每只手脚在做什么", binding(\.pose), lines: 3)
            field("动作", "这四秒里她怎么动；镜头（身体在动就写 static camera）；环境声", binding(\.action), lines: 4)
            field("旁白", "留空就是不说话", binding(\.narration), lines: 2)
            HStack(spacing: 8) {
                Button("取消") { editing = nil; opened = nil }.controlSize(.small)
                Spacer()
                if onlyVoice {
                    Button("只换旁白（两秒）") { apply(words, following: false) }.controlSize(.small)
                } else {
                    Button("只重拍这一个") { apply(words, following: false) }.controlSize(.small)
                    Button("从这个往后都重拍") { apply(words, following: true) }.controlSize(.small)
                        .help("后面的镜头是接着这个镜头的最后一帧拍的；它变了，后面就接不上了")
                        .disabled(film.shots.last?.id == words.shot)
                }
            }
            .disabled(!changed || translating || studio.shooting != nil || studio.revising != nil)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
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
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 10, weight: .medium)).frame(width: 30, alignment: .leading).padding(.top, 3)
            TextField(hint, text: text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 11)).lineLimit(lines...max(lines, 6))
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
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
                tongueMenu
                reviewMenu
                Stepper("\(shots) 个镜头", value: $shots, in: 2...8).font(.system(size: 10)).fixedSize()
                Picker("", selection: $shape) {
                    ForEach(FilmStudio.Shape.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                .help("画面的形状。竖屏 9:16 是手机拿着看的那种，576×1024；方形 704×704 是这个标签原来的样子")
                Toggle("配乐", isOn: $musicOn).font(.system(size: 10)).toggleStyle(.checkbox).fixedSize()
                    .help("在盒子上用 kin audio 的 MusicGen 按片子的内容作一段配乐，垫在整部片子下面，旁白说话时自动压低。第一次用要在盒子上下载 MusicGen（约 4 GB）")
                Toggle("她当主角", isOn: $lead).font(.system(size: 10)).toggleStyle(.checkbox).fixedSize()
                Picker("", selection: $kind) {
                    ForEach(FilmStudio.Kind.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                .help("自动：先读一遍这句话，看它是一段连续的动作还是一串发生的事，由它决定怎么拍。故事：强制当成一串事——每镜独立画，可以换景，镜头拍物、拍景、拍人影。连续动作：强制当成一个人在一个地方做一件连贯的事")
                Picker("", selection: $engine) {
                    ForEach(FilmStudio.Engine.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                .help("拍故事用哪个模型。LTX：每镜从一张画出来的图拍，快（约 100 秒一镜），但人每镜长得不一样，所以故事里的人只拍手、背影。H3：先选角、给每个人画一张定妆照，每镜照着这些人和那一镜的布景拍，脸和衣服前后一致，自带环境声；慢（约 5–7 分钟一镜），要盒子上的 ComfyUI 和 H3 模型。连续动作的片子总是用 LTX")
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
                Section(BoxServices.place(of: entry.host)) {
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
        .help("分镜由哪个模型写：\(writer)（\(writerPlace)）。它也是看图把关的那个，如果它能看图")
        .task { await loadWriters(); await describeWriter() }
    }

    /// Whether each take is looked at, and how many times it may be redone.
    private var reviewMenu: some View {
        Menu {
            Button { retakes = 0 } label: { Label("不把关（拍成什么样就是什么样）", systemImage: retakes == 0 ? "checkmark" : "") }
            ForEach(1...3, id: \.self) { count in
                Button { retakes = count } label: {
                    Label("不满意就自动重拍，每个镜头最多 \(count) 次", systemImage: retakes == count ? "checkmark" : "")
                }
            }
        } label: {
            Label(retakes == 0 ? "把关：关" : "把关：\(retakes) 次", systemImage: "checkmark.seal").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("每个镜头拍完，让能看图的模型对着计划看一遍：跑题了、多了人、镜头乱飞，就自己改提示词重拍，留得分最高的那条。一次重拍约两分半钟")
    }

    /// What language the voice-over is written and spoken in.
    private var tongueMenu: some View {
        Menu {
            Button { tongue = "" } label: { Label("自动（跟你写的那句话）", systemImage: tongue.isEmpty ? "checkmark" : "") }
            ForEach(FilmStudio.tongues, id: \.tag) { entry in
                Button { tongue = entry.tag } label: { Label(entry.name, systemImage: tongue == entry.tag ? "checkmark" : "") }
            }
            Divider()
            Button { tongue = "none" } label: { Label("不要旁白", systemImage: tongue == "none" ? "checkmark" : "") }
        } label: {
            let shown = tongue == "none" ? "无" : FilmStudio.tongues.first { $0.tag == tongue }?.name ?? "自动"
            Label("旁白：\(shown)", systemImage: "waveform").font(.system(size: 10))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("旁白用哪种语言写、用哪种语言的声音念")
    }

    private func loadWriters() async {
        writers = await FilmStudio.candidates()
    }

    private func describeWriter() async {
        guard let pick = await FilmStudio.writer() else { writer = "没有可用的模型"; return }
        let place = pick.host == OllamaCatalog.defaultBaseURL ? "本机" : "盒子"
        writer = pick.model
        writerPlace = "\(place)\(writerModel.isEmpty ? "，自动挑的" : "，你指定的")"
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
                Rectangle().fill(Color.white.opacity(0.06))
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
        case .done:     return "\(film.shots.count) 个镜头 · \(Int(Double(film.finished) * film.seconds)) 秒"
        case .failed:   return "没拍成"
        }
        }()
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

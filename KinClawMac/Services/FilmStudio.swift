import AVFoundation
import Foundation

/// One sentence in, a short film out — on the user's own machines.
///
/// This is the shape of Sora, not its model. What the box can do is a
/// four-second clip at 704 pixels in about eighty seconds; what that cannot
/// be is a twenty-second take with convincing physics. So a film here is
/// what a film has always been: a list of short shots, cut together.
///
///   1. **A storyboard** — a title, a look that every frame shares, and a
///      few shots, each a frame to draw and what moves in it. Written by a
///      language model: the brain that calls `film_make`, or the local one
///      when the idea comes from the tab.
///   2. **A still per shot.** When she is in it, the still is an *edit* of
///      her anchor portrait, which is the only thing that has ever kept a
///      generated person the same person from one picture to the next.
///      Otherwise it is drawn from the description. The first still is the
///      film's **master** — a wide frame of the one place the film happens
///      in — and every later still is an edit that is shown it: who from
///      her anchor, where and wearing what from the master. Words alone do
///      not hold a place: four stills written as "in the park" came back as
///      a pavilion, a stone house, a lake she stood waist-deep in, and a
///      wood, in two pairs of shoes.
///   3. **The still, filmed.** Image-to-video, so the clip is that frame
///      moving; the model writes the sound along with the picture.
///      Every shot after the first **starts where the last one stopped**: the
///      previous clip's final frame is read by a model that can see, its pose
///      is put into words, and the next still is that pose from the new
///      camera — a match cut. It has to be read rather than planned, because
///      the video model does not end a clip where the storyboard says: asked
///      for a weight shift, it finished on one knee with her hands behind her
///      back. Four stills planned in advance are four unrelated actions in
///      one place, which is what "不连贯" meant the second time.
///   3½. **Each take is looked at.** The same model that reads the last
///      frame watches the clip — four frames and the master — against the
///      plan, scores it, and when a viewer would be bothered (she walked out
///      of a film about standing still, somebody arrived from nowhere, the
///      camera went for her back) rewrites the shot's words and it is taken
///      again, a bounded number of times, and the best-scoring take is the
///      one kept. The user can do the same in a sentence — "手再慢一点，脚别动"
///      — and the words are rewritten to it. Nobody has to write a prompt.
///   4. **The cut**, with AVFoundation rather than ffmpeg — the app has no
///      ffmpeg to call — shots overlapped by a short dissolve, sound faded
///      across it.
///
/// Every step is written to `film.json` as it happens, so a film survives
/// the app being quit half way, and one shot can be redone without the rest.
@MainActor
final class FilmStudio: ObservableObject {
    static let shared = FilmStudio()

    struct Shot: Codable, Identifiable, Equatable {
        var id: Int
        /// Where the camera is — "medium shot from her left side, waist up".
        /// Its own field because it has to be said *first*: an editor that
        /// reads the pose before the camera keeps the camera it was shown.
        var framing: String? = nil
        /// The frame: what is in it and what she is doing, literally. English,
        /// for the models.
        var still: String
        /// What moves in it, and what it sounds like.
        var motion: String
        var state: State = .waiting
        var note: String?
        /// Filmed (or to be filmed) on the high-quality model.
        var hq: Bool? = nil
        /// A line of voice-over, spoken by the user's own TTS over this shot.
        var narration: String? = nil
        /// The pose the previous shot ended in, as read off its last frame —
        /// what this shot's still was actually made from.
        var seen: String? = nil
        /// The motion actually sent to the video model, when it was rewritten
        /// to carry on from `seen` rather than from the pose that was planned.
        var played: String? = nil
        /// The user wrote the pose (`posed`) or the movement (`moved`). Their
        /// words are used as written: nobody's model rewrites a director. Kept
        /// apart because changing only the camera should still have the pose
        /// read again — for the new camera, which shows different limbs.
        var posed: Bool? = nil
        var moved: Bool? = nil
        /// What the user asked of this shot, in their words ("手再慢一点，脚别动").
        /// Whoever writes or judges the shot's words is told it.
        var wish: String? = nil
        /// The reviewer's verdict on the take that was kept: a score out of
        /// ten, what bothered it (empty when nothing did), and how many takes
        /// it asked for beyond the first.
        var score: Int? = nil
        var review: String? = nil
        var retakes: Int? = nil
        /// What the reviewer saw her body do in the kept take, in two plain
        /// sentences — the facts a judgment can be made from, and kept
        /// because a text model that is to learn this job needs them.
        var saw: String? = nil
        /// A second opinion on `saw` against the plan, from Laya: the
        /// probability that the take follows the plan, that it is the film's
        /// activity, that she leaves, and how much of her body moves (0–2).
        /// Shown beside the verdict; it decides nothing.
        var laya: [String: Double]? = nil
        /// The same four numbers from TypeSafe's Jev, asked the same questions
        /// about the same description. Kept apart from Laya's so the two can
        /// be read side by side.
        var jev: [String: Double]? = nil

        enum State: String, Codable { case waiting, drawing, filming, reviewing, done, failed }

        /// The pose and the movement the shot was actually made from: the
        /// user's words, else what was read off the previous shot, else the
        /// storyboard's plan. What is shown, and what an edit is compared with.
        var pose: String { posed == true ? still : (seen ?? still) }
        var action: String { moved == true ? motion : (played ?? motion) }
    }

    struct Film: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var idea: String
        /// What every frame shares: stock, light, palette.
        var look: String
        /// The one place it all happens in, with the landmarks that make it
        /// that place. A film of four-second shots that changes location
        /// with every cut is four postcards.
        var place: String? = nil
        /// What she is wearing, said once. Each still is an edit of its own,
        /// and left to themselves they dress her differently every time — a
        /// white dress on the sand, a beige one at the water's edge — which
        /// reads as two women or two days.
        var wears: String? = nil
        /// The language the voice-over is written and spoken in — a tag from
        /// `FilmStudio.tongues`, "none" for a film with no voice-over, nil to
        /// follow the idea's own language.
        var tongue: String? = nil
        /// How many times a shot may be taken again on the reviewer's say-so.
        /// Fixed when the film is made, so a film carried on tomorrow is
        /// finished the way it was started.
        var retakeLimit: Int? = nil
        /// She is the lead, so every still is an edit of her anchor.
        var lead: Bool
        var seconds: Double
        var shots: [Shot]
        var state: State = .waiting
        var note: String?
        var created = Date()

        enum State: String, Codable { case waiting, shooting, cutting, done, failed }

        // Where it lives depends on where her art lives, which is the main
        // actor's to say.
        @MainActor var folder: URL { FilmStudio.root.appendingPathComponent(id) }
        @MainActor var file: URL { folder.appendingPathComponent("film.mp4") }
        @MainActor func still(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.png", shot)) }
        @MainActor func clip(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.mp4", shot)) }
        @MainActor func voice(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.wav", shot)) }
        /// A take set aside: `shot-03.take-auto1-1789870000.mp4`.
        @MainActor func take(_ shot: Int, _ mark: String, _ ext: String) -> URL {
            folder.appendingPathComponent(String(format: "shot-%02d.take-", shot) + mark + "." + ext)
        }
        /// A reference picture as the editor was shown it: `shot-03.ref-master.png`.
        @MainActor func reference(_ shot: Int, _ which: String) -> URL {
            folder.appendingPathComponent(String(format: "shot-%02d.ref-", shot) + which + ".png")
        }
        /// The clip's final frame: where the next shot picks up.
        @MainActor func last(_ shot: Int) -> URL { folder.appendingPathComponent(String(format: "shot-%02d.last.png", shot)) }
        var finished: Int { shots.filter { $0.state == .done }.count }
    }

    /// `<art folder>/films/` — beside her pictures, on whatever disk those are.
    static var root: URL { CompanionArt.folder.appendingPathComponent("films") }

    @Published private(set) var films: [Film] = []
    /// The film in production. One at a time: there is one video server.
    @Published private(set) var shooting: String?

    init() {
        reload()
        // A film that was being shot when the app last quit is still half
        // made on disk, and every finished shot in it is still good. It is
        // picked up where it stopped rather than left saying "shooting"
        // forever to nobody.
        if let unfinished = films.first(where: { $0.state == .shooting || $0.state == .cutting }) {
            produce(unfinished.id)
        }
    }

    /// Take a whole film off the shelf. Its folder — the storyboard, the stills,
    /// every clip, the takes that were set aside, the cut — goes to the Trash,
    /// where Put Back still works: a film is a quarter of an hour of the box's
    /// time and sometimes the only good take of something, and "deleted" ought
    /// to be a thing a person can change their mind about. The film being shot
    /// or looked at again is left alone; its makers would write it back.
    @discardableResult
    func remove(film id: String) -> Result<Film, Failure> {
        guard let film = films.first(where: { $0.id == id }) else { return .failure(.message("没有这部片子：\(id)")) }
        guard shooting != film.id else { return .failure(.message("「\(film.title)」正在拍，等它停了再删")) }
        guard revising == nil else { return .failure(.message("片场正忙（\(revising ?? "")），等这一条完了再删")) }
        do {
            try FileManager.default.trashItem(at: film.folder, resultingItemURL: nil)
        } catch {
            return .failure(.message("没能把「\(film.title)」移到废纸篓：\(error.localizedDescription)"))
        }
        films.removeAll { $0.id == film.id }
        return .success(film)
    }

    func reload() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: Self.root.path)) ?? []
        films = names.compactMap { name -> Film? in
            let file = Self.root.appendingPathComponent(name).appendingPathComponent("film.json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? Self.decoder.decode(Film.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    // MARK: - Making one

    /// The languages a voice-over can be in: the ones the user's Kokoro has a
    /// voice for. Its voices are single-language — a Chinese voice reading
    /// English mangles it, an English one reads Chinese as "Chinese letter,
    /// Chinese letter" — so the language picks the voice, not the other way.
    static let tongues: [(tag: String, name: String, english: String)] = [
        ("zh", "中文", "Chinese (中文)"), ("en", "English", "English"), ("ja", "日本語", "Japanese (日本語)"),
        ("es", "Español", "Spanish"), ("fr", "Français", "French"), ("it", "Italiano", "Italian"),
        ("pt", "Português", "Portuguese"), ("hi", "हिन्दी", "Hindi"),
    ]
    static let tongueKey = "kinclaw.film.narration"
    /// Automatic retakes per shot: 0 turns the reviewer off. One by default —
    /// it catches the take that went somewhere else, and costs two and a half
    /// minutes only when it does.
    static let retakesKey = "kinclaw.film.retakes"
    static var retakes: Int {
        let set = UserDefaults.standard.object(forKey: retakesKey) as? Int
        return min(max(set ?? 1, 0), 3)
    }

    /// A take the reviewer sent back, remembered in case nothing better comes:
    /// its score, the name it was set aside under, whether its still went with
    /// it, and the words it was made from.
    struct Take {
        var score: Int
        var mark: String
        var withStill: Bool
        var words: Shot
    }

    /// A shot as a storyboard gives it, before there is a film for it to be in.
    struct Draft {
        var still: String
        var motion: String
        var framing = ""
        var narration = ""

        /// From a storyboard's JSON, whoever wrote it: the brain behind the
        /// tab or the one calling `film_make`.
        init?(_ item: [String: Any]) {
            guard let still = item["still"] as? String else { return nil }
            self.still = still
            motion = (item["motion"] as? String) ?? "gentle natural movement"
            framing = (item["framing"] as? String) ?? ""
            narration = (item["narration"] as? String) ?? ""
        }
    }

    /// Start a film. Returns at once; the work runs for minutes.
    func make(title: String, idea: String, look: String, place: String = "", wears: String = "", lead: Bool,
              seconds: Double, shots: [Draft], tongue: String = "", retakes: Int? = nil) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        let wanted = shots.filter { !$0.still.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !wanted.isEmpty else { return .failure(.message("分镜是空的：每个镜头要有 still（画面）和 motion（动作）")) }
        guard wanted.count <= 12 else { return .failure(.message("一次最多 12 个镜头")) }
        if let trouble = CompanionArt.unreachableVolume(Self.root) { return .failure(.message(trouble)) }
        if lead, CompanionCharacter.shared.anchorURL == nil {
            return .failure(.message("她还没有锚图，没法当主角；先 character_new 定一张脸，或者 lead 填 false"))
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let slug = Self.slug(title.isEmpty ? idea : title)
        var film = Film(id: "\(slug)-\(stamp)", title: title.isEmpty ? String(idea.prefix(24)) : title,
                        idea: idea, look: look, lead: lead, seconds: min(max(seconds, 2), 10),
                        shots: wanted.enumerated().map { Shot(id: $0.offset + 1, still: $0.element.still, motion: $0.element.motion) })
        film.wears = wears.trimmingCharacters(in: .whitespaces).isEmpty ? nil : wears
        film.place = place.trimmingCharacters(in: .whitespaces).isEmpty ? nil : place
        film.tongue = tongue.isEmpty ? nil : tongue
        film.retakeLimit = retakes.map { min(max($0, 0), 3) } ?? Self.retakes
        for (index, draft) in wanted.enumerated() {
            let said = draft.narration.trimmingCharacters(in: .whitespacesAndNewlines)
            // Asked for silence, and a writer that narrates anyway is not obeyed.
            if !said.isEmpty, tongue != "none" { film.shots[index].narration = said }
            let camera = draft.framing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !camera.isEmpty { film.shots[index].framing = camera }
        }
        film.state = .shooting
        do {
            try FileManager.default.createDirectory(at: film.folder, withIntermediateDirectories: true)
        } catch { return .failure(.message("建不了片子的文件夹：\(error.localizedDescription)")) }
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// A storyboard being written, and what went wrong with the last one: the
    /// half minute before there is a film to show progress on.
    @Published private(set) var writing: String?
    @Published private(set) var trouble: String?

    /// From one sentence: the local brain writes the storyboard, then it is
    /// made. What the tab's button does, and what `film_make` does when it is
    /// given an idea and no shots.
    func make(from idea: String, shots: Int, lead: Bool, tongue: String? = nil, retakes: Int? = nil,
              then done: ((Result<Film, Failure>) -> Void)? = nil) {
        let tongue = tongue ?? UserDefaults.standard.string(forKey: Self.tongueKey) ?? ""
        guard writing == nil else { done?(.failure(.message("还在给「\(writing!)」写分镜"))); return }
        writing = idea
        trouble = nil
        Task { @MainActor in
            defer { writing = nil }
            let result: Result<Film, Failure>
            do {
                let board = try await Self.storyboard(for: idea, shots: min(max(shots, 2), 8), lead: lead,
                                                      tongue: tongue, model: Self.writerModel)
                result = make(title: board.title, idea: idea, look: board.look, place: board.place,
                              wears: board.wears, lead: lead, seconds: 4, shots: board.shots, tongue: tongue,
                              retakes: retakes)
            } catch {
                result = .failure(.message("分镜没写出来：\(error.localizedDescription)"))
            }
            if case .failure(let failure) = result { trouble = failure.localizedDescription }
            done?(result)
        }
    }

    /// Redo one shot — a new frame, a new take, or both — and cut again.
    ///
    /// New words are the director's and are used as written (`posed`, `moved`).
    /// `following` redoes every shot after it as well: each shot starts from
    /// the one before, so a shot that now ends somewhere else leaves the next
    /// one starting from a moment that no longer happened. Sometimes that is
    /// wanted — one bad shot in a film that otherwise cuts well — so it is
    /// asked for rather than assumed; it is also four minutes a shot.
    ///
    /// `manual: false` is a rewrite made *for* the user — by the model that
    /// followed their direction — rather than *by* them. It replaces the
    /// plan instead of pinning the words, so the shot is still read off the
    /// previous frame and still reviewed; `wish` is what they asked for, and
    /// goes to whoever writes or judges the shot from then on.
    func reshoot(film id: String, shot number: Int, framing: String? = nil, still: String?, motion: String?,
                 narration: String? = nil, hq: Bool = false, following: Bool = false,
                 manual: Bool = true, wish: String? = nil) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }) else {
            return .failure(.message("没有这部片子：\(id)"))
        }
        guard let index = film.shots.firstIndex(where: { $0.id == number }) else {
            return .failure(.message("「\(film.title)」没有第 \(number) 个镜头，它有 \(film.shots.count) 个"))
        }
        // The old take is kept beside the new one rather than thrown away.
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        func given(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        func aside(_ url: URL, _ name: String) { try? fm.moveItem(at: url, to: film.folder.appendingPathComponent(name)) }
        let camera = given(framing), frame = given(still), action = given(motion)
        // Compared with what the shot was actually made from — the pose that
        // was seen, the movement that was played — which is also what the
        // tab shows for editing. Words handed back unchanged change nothing.
        let was = film.shots[index]
        let pose = was.pose
        let newFrame = (camera != nil && camera != was.framing) || (frame != nil && frame != pose)
            || (!manual && given(wish) != nil)
        if let camera, camera != film.shots[index].framing {
            film.shots[index].framing = camera
            film.shots[index].seen = nil        // read again, for what the new camera shows
        }
        if let frame, frame != pose {
            film.shots[index].still = frame
            film.shots[index].posed = manual ? true : nil
            film.shots[index].seen = nil
        }
        if let action, action != was.action {
            film.shots[index].motion = action
            film.shots[index].moved = manual ? true : nil
            film.shots[index].played = nil
        }
        if let wish = given(wish) {
            film.shots[index].wish = wish
            // A wish is a reason to look again at everything the shot is
            // made of, not only the fields the rewrite happened to touch.
            if !manual { film.shots[index].seen = nil; film.shots[index].played = nil }
        }
        film.shots[index].score = nil
        film.shots[index].review = nil
        film.shots[index].retakes = nil
        // A new line is spoken again; nil leaves the old one, "" takes it out.
        if let narration, narration.trimmingCharacters(in: .whitespacesAndNewlines) != (was.narration ?? "") {
            let said = narration.trimmingCharacters(in: .whitespacesAndNewlines)
            film.shots[index].narration = said.isEmpty ? nil : said
            aside(film.voice(number), String(format: "shot-%02d.take-\(stamp).wav", number))
        }
        if newFrame { aside(film.still(number), String(format: "shot-%02d.take-\(stamp).png", number)) }
        aside(film.clip(number), String(format: "shot-%02d.take-\(stamp).mp4", number))
        aside(film.file, "film.cut-\(stamp).mp4")
        film.shots[index].state = .waiting
        film.shots[index].note = nil
        film.shots[index].hq = hq ? true : nil
        if following {
            for later in film.shots.indices where later > index {
                let id = film.shots[later].id
                aside(film.still(id), String(format: "shot-%02d.take-\(stamp).png", id))
                aside(film.clip(id), String(format: "shot-%02d.take-\(stamp).mp4", id))
                film.shots[later].state = .waiting
                film.shots[later].note = nil
                // What it saw and played belonged to the old take before it.
                film.shots[later].seen = nil
                film.shots[later].played = nil
                film.shots[later].score = nil
                film.shots[later].review = nil
                film.shots[later].retakes = nil
            }
        }
        film.state = .shooting
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// A direction being followed: the quarter minute in which the shot's
    /// words are being rewritten and there is nothing else to show for it.
    @Published private(set) var revising: String?

    /// Redo a shot to a direction given in a sentence — "手再慢一点，脚别动",
    /// "镜头近一点，只拍上半身". The model that can see looks at the current take
    /// and rewrites what has to change; nobody writes a prompt.
    func redirect(film id: String, shot number: Int, note: String, following: Bool = false,
                  then done: ((Result<Film, Failure>) -> Void)? = nil) {
        let wish = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wish.isEmpty else { done?(.failure(.message("往哪个方向改？说一句就行"))); return }
        guard shooting == nil, revising == nil else { done?(.failure(.message("片场正忙，等这一条拍完"))); return }
        guard let film = films.first(where: { $0.id == id || $0.title == id || $0.id.hasPrefix(id) }),
              let shot = film.shots.first(where: { $0.id == number }) else {
            done?(.failure(.message("没有这部片子或这个镜头"))); return
        }
        revising = "镜头 \(number)：\(wish)"
        Task { @MainActor in
            defer { revising = nil }
            // Nobody to look, or nothing it could change: the wish still goes
            // on the shot, and the shot is read and reviewed with it in mind.
            let words = await Self.revise(shot, in: film, toward: wish)
            // Into a constant first. `done?(reshoot(…))` reads as "reshoot,
            // then tell whoever asked" and means "if nobody asked, do not
            // reshoot": an optional call does not evaluate its arguments. The
            // tool asks for no callback, so from a conversation the direction
            // was accepted, acknowledged, and dropped.
            let result = reshoot(film: film.id, shot: number, framing: words?.framing, still: words?.pose,
                                 motion: words?.motion, narration: words?.narration, following: following,
                                 manual: false, wish: wish)
            done?(result)
        }
    }

    /// Look at a finished film again: every filmed shot is reviewed afresh —
    /// the verdict, what was seen, Laya's numbers — and nothing is filmed.
    /// For films made before the reviewer looked at the action, and for
    /// seeing what a changed reviewer makes of takes it has already judged.
    ///
    /// `opinionsOnly` leaves the reviewer out of it: Laya and Jev are asked
    /// again about the description the reviewer already wrote. Nothing looks
    /// at a frame, so it takes a second a shot and none of the vision model's
    /// quota — the way to see what a judge that was just switched on makes of
    /// a film that is already there.
    func reassess(film id: String, opinionsOnly: Bool = false, then done: ((Result<Film, Failure>) -> Void)? = nil) {
        guard shooting == nil, revising == nil else { done?(.failure(.message("片场正忙，等这一条拍完"))); return }
        guard var film = films.first(where: { $0.id == id || $0.title == id || $0.id.hasPrefix(id) }) else {
            done?(.failure(.message("没有这部片子：\(id)"))); return
        }
        if opinionsOnly {
            guard Self.layaOn || Self.jevOn else { done?(.failure(.message("Laya 和 Jev 都关着：在 设置 → Backend → 片场 里打开一个"))); return }
            guard film.shots.contains(where: { $0.saw != nil }) else {
                done?(.failure(.message("这部片子还没有「看到的动作」那段文字，先「重新把关」一次"))); return
            }
            revising = "在问第二意见「\(film.title)」"
            Task { @MainActor in
                defer { revising = nil }
                for index in film.shots.indices {
                    guard let saw = film.shots[index].saw else { continue }
                    // The description has not changed, so numbers already here
                    // still stand: a judge that is off, or did not answer this
                    // time, leaves its old line alone.
                    let asked = await Self.opinions(on: saw, plan: film.shots[index].action, idea: film.idea)
                    if let laya = asked.laya { film.shots[index].laya = laya }
                    if let jev = asked.jev { film.shots[index].jev = jev }
                    save(film)
                }
                done?(.success(film))
            }
            return
        }
        revising = "在重新把关「\(film.title)」"
        Task { @MainActor in
            defer { revising = nil }
            for index in film.shots.indices where FileManager.default.fileExists(atPath: film.clip(film.shots[index].id).path) {
                revising = "在重新把关「\(film.title)」镜头 \(film.shots[index].id)"
                guard var verdict = await Self.review(film.shots[index], in: film) else { continue }
                film.shots[index].saw = verdict.saw
                film.shots[index].laya = nil
                film.shots[index].jev = nil
                if let saw = verdict.saw {
                    (film.shots[index].laya, film.shots[index].jev) = await Self.opinions(on: saw, plan: film.shots[index].action, idea: film.idea)
                }
                verdict = Self.weigh(verdict, jev: film.shots[index].jev)
                film.shots[index].score = verdict.score
                film.shots[index].review = verdict.passed ? "" : verdict.problem
                save(film)
            }
            done?(.success(film))
        }
    }

    /// Everything that is not done yet, shot by shot, then the cut.
    private func produce(_ id: String) {
        shooting = id
        Task { @MainActor in
            defer { shooting = nil }
            guard var film = films.first(where: { $0.id == id }) else { return }
            let client = DiffuserClient.shared
            let fm = FileManager.default
            let sheet = CompanionCharacter.shared.sheet
            for index in film.shots.indices where film.shots[index].state != .done {
                let shot = film.shots[index]
                do {
                    // Takes. The first is the plan; any after it are the
                    // reviewer's, and the best-scoring one is what is kept.
                    let limit = film.retakeLimit ?? Self.retakes
                    var attempt = 0
                    var best: Take?
                    // A still drawn before the shot ahead of it was last
                    // filmed starts from a moment that no longer happened:
                    // that shot was redone on its own, and ends somewhere
                    // else now. (Seen: shot 2 redone to a direction ended
                    // facing the lens with her arms down; shot 3, rolled again,
                    // still opened side-on in mid-step.) Unless the pose is
                    // the user's own, it is drawn again from the new ending.
                    if index > 0, shot.posed != true,
                       let drawn = Self.modified(film.still(shot.id)),
                       let filmed = Self.modified(film.clip(film.shots[index - 1].id)), filmed > drawn {
                        try? fm.moveItem(at: film.still(shot.id),
                                         to: film.take(shot.id, "stale-\(Int(Date().timeIntervalSince1970))", "png"))
                        film.shots[index].seen = nil
                        film.shots[index].played = nil
                    }
                    while true {
                        if !fm.fileExists(atPath: film.still(shot.id).path) {
                            update(&film, index, .drawing)
                            // The master is the first shot's still, once there is
                            // one — so the first shot itself never has it, and a
                            // film whose first still failed falls back to words.
                            let first = film.shots[0].id
                            let master = shot.id != first && fm.fileExists(atPath: film.still(first).path)
                                ? film.still(first) : nil
                            // Where the last shot stopped, and what she was doing
                            // there. Without a clip before this one, or a model
                            // that can look at it, the still is made the old way:
                            // from the master and the pose that was planned.
                            // Nor from a take that went wrong and stayed wrong:
                            // a shot the reviewer scored under five after its
                            // retakes ends somewhere nobody wants to carry on
                            // from, and carrying on is how one bad ending
                            // becomes the rest of the film. The next shot is
                            // a fresh setup from the master — a cut away,
                            // which is what an editor does with a bad take.
                            var previous: URL?
                            if index > 0, film.shots[index - 1].state == .done,
                               (film.shots[index - 1].score ?? 10) >= 5 {
                                previous = try? await Self.lastFrame(of: film.clip(film.shots[index - 1].id),
                                                                     to: film.last(film.shots[index - 1].id))
                            }
                            // On a retake the words are the reviewer's already.
                            if attempt == 0, let previous, !(shot.posed == true && shot.moved == true),
                               let next = await Self.direct(film.shots[index], after: previous, in: film) {
                                if shot.posed != true { film.shots[index].seen = next.pose }
                                if shot.moved != true { film.shots[index].played = next.motion }
                                save(film)
                            }
                            // The pictures the editor is shown, cut to this
                            // shot's camera and with her face taken out of
                            // them — see FilmReference for why both.
                            let camera = film.shots[index].framing
                            let faceless = film.lead && CompanionCharacter.shared.anchorURL != nil
                            let shownMaster = master.map {
                                FilmReference.prepare($0, as: film.reference(shot.id, "master"), framing: camera, faceless: faceless)
                            }
                            let shownPrevious = previous.map {
                                FilmReference.prepare($0, as: film.reference(shot.id, "previous"), framing: camera, faceless: faceless)
                            }
                            let recipe = Self.recipe(for: film.shots[index], in: film,
                                                     anchor: CompanionCharacter.shared.anchorURL,
                                                     master: shownMaster, previous: shownPrevious, style: sheet.style)
                            let made: URL
                            if let source = recipe.pictures.first {
                                made = try await client.edit(
                                    prompt: recipe.prompt, from: source, also: Array(recipe.pictures.dropFirst()),
                                    into: film.folder,
                                    seed: CompanionCharacter.seed(for: film.id + film.shots[index].pose + String(attempt)))
                            } else {
                                made = try await client.generate(prompt: recipe.prompt, into: film.folder, width: 768, height: 768)
                            }
                            try? fm.moveItem(at: URL(fileURLWithPath: made.path + ".txt"),
                                             to: URL(fileURLWithPath: film.still(shot.id).path + ".txt"))
                            try fm.moveItem(at: made, to: film.still(shot.id))
                            await restoreFace(in: film, shot.id)
                        }
                        update(&film, index, .filming)
                        let fine = shot.hq == true
                        if fine, let crowded = await BoxServices.shared.roomForHQ() {
                            throw Failure.message(crowded)
                        }
                        _ = try await client.generateVideo(
                            prompt: Self.literal(film.shots[index].action),
                            to: film.clip(shot.id), seconds: film.seconds,
                            width: 704, height: 704, from: film.still(shot.id), hq: fine,
                            timeout: fine ? 3600 : 1800)

                        // Nobody reviews a director's own words, or a finishing
                        // pass of a take that was already accepted.
                        guard limit > 0, !fine, shot.posed != true, shot.moved != true else { break }
                        update(&film, index, .reviewing)
                        guard var verdict = await Self.review(film.shots[index], in: film) else { break }
                        film.shots[index].saw = verdict.saw
                        film.shots[index].laya = nil
                        film.shots[index].jev = nil
                        if let saw = verdict.saw {
                            (film.shots[index].laya, film.shots[index].jev) = await Self.opinions(on: saw, plan: film.shots[index].action, idea: film.idea)
                        }
                        verdict = Self.weigh(verdict, jev: film.shots[index].jev)
                        film.shots[index].score = verdict.score
                        film.shots[index].review = verdict.passed ? "" : verdict.problem
                        save(film)
                        if verdict.passed || attempt >= limit { break }

                        // Set this take aside, under a name that says which it
                        // was, and go again with the reviewer's words.
                        attempt += 1
                        let mark = "auto\(attempt)-\(Int(Date().timeIntervalSince1970))"
                        let redraw = verdict.fix == .still
                        let kept = Take(score: verdict.score, mark: mark, withStill: redraw, words: film.shots[index])
                        if best == nil || kept.score > best!.score { best = kept }
                        try? fm.moveItem(at: film.clip(shot.id), to: film.take(shot.id, mark, "mp4"))
                        if redraw {
                            try? fm.moveItem(at: film.still(shot.id), to: film.take(shot.id, mark, "png"))
                            if let pose = verdict.pose { film.shots[index].seen = pose }
                            if let camera = verdict.framing, index > 0 { film.shots[index].framing = camera }
                        }
                        if let motion = verdict.motion { film.shots[index].played = motion }
                        film.shots[index].retakes = attempt
                        save(film)
                    }
                    // An earlier take that scored higher than the last one is
                    // the one the film uses; the last goes aside in its place.
                    if let best, best.score > (film.shots[index].score ?? 0),
                       fm.fileExists(atPath: film.take(shot.id, best.mark, "mp4").path) {
                        let mark = "last-\(Int(Date().timeIntervalSince1970))"
                        try? fm.moveItem(at: film.clip(shot.id), to: film.take(shot.id, mark, "mp4"))
                        try? fm.moveItem(at: film.take(shot.id, best.mark, "mp4"), to: film.clip(shot.id))
                        if fm.fileExists(atPath: film.take(shot.id, best.mark, "png").path) {
                            try? fm.moveItem(at: film.still(shot.id), to: film.take(shot.id, mark, "png"))
                            try? fm.moveItem(at: film.take(shot.id, best.mark, "png"), to: film.still(shot.id))
                        }
                        let retakes = film.shots[index].retakes
                        film.shots[index] = best.words
                        film.shots[index].retakes = retakes
                        save(film)
                    }
                    // Where this shot ends, from the take that was kept: the
                    // next shot starts there.
                    _ = try? await Self.lastFrame(of: film.clip(shot.id), to: film.last(shot.id), fresh: true)
                    await speak(film, film.shots[index])
                    update(&film, index, .done)
                } catch {
                    // A server that is not there fails every shot after this
                    // one too, in two seconds, and what gets cut is a one-shot
                    // "film". (It happened: the edit server died under the
                    // box's memory load after the first still.) So the film
                    // stops here, says what it could not reach, keeps the
                    // shots it has, and can be carried on when the service is
                    // back — nothing is marked failed that was never tried.
                    if Self.isUnreachable(error) {
                        let stage = film.shots[index].state == .drawing ? "出图/改图服务" : "出片服务"
                        film.shots[index].state = .waiting
                        film.state = .failed
                        film.note = "\(stage)连不上（\(error.localizedDescription)）。服务起来后接着拍：film_reshoot 不带 shot，或片场里点「接着拍」"
                        save(film)
                        return
                    }
                    film.shots[index].note = error.localizedDescription
                    update(&film, index, .failed)
                }
            }
            // Cut whatever was shot: three good shots and a failed one is
            // still a film, and a better answer than nothing after ten minutes.
            let finished = film.shots.filter { $0.state == .done }
            let clips = finished.map { film.clip($0.id) }
            let voices = finished.map { film.voice($0.id) }
            guard !clips.isEmpty else {
                film.state = .failed
                film.note = "一个镜头都没拍成：" + (film.shots.first?.note ?? "")
                save(film)
                return
            }
            film.state = .cutting
            save(film)
            do {
                try await Self.cut(clips, voices: voices, to: film.file)
                film.state = .done
                let failed = film.shots.count - clips.count
                film.note = failed == 0 ? nil : "\(failed) 个镜头没拍成，剪的是其余的"
            } catch {
                film.state = .failed
                film.note = "剪不出来：\(error.localizedDescription)"
            }
            save(film)
        }
    }

    /// The clip's final frame, written beside it. Made again when the clip is
    /// newer than the picture — a reshoot ends somewhere else.
    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func lastFrame(of clip: URL, to file: URL, fresh: Bool = false) async throws -> URL {
        // `fresh` because a date cannot be trusted after takes have been
        // swapped: a better take put back is an older file than the picture
        // made from the worse one.
        if !fresh, let made = modified(file), let filmed = modified(clip), made >= filmed { return file }
        let asset = AVURLAsset(url: clip)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 12)
        // One frame back from the end: the very end of a track is past its
        // last sample more often than it is on it.
        let moment = CMTimeMaximum(.zero, CMTimeSubtract(duration, CMTime(value: 1, timescale: 24)))
        let frame = try await generator.image(at: moment).image
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure.message("写不了最后一帧：\(file.path)")
        }
        CGImageDestinationAddImage(destination, frame, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.message("写不了最后一帧：\(file.path)") }
        return file
    }

    /// The rules every rewritten shot has to keep, said once for the three
    /// places a model writes one: carrying on from a last frame, sending a
    /// take back, and following the user's direction.
    static let wording = """
        Rules for `pose` and `motion`: plain literal English, the body described limb by limb as a stranger \
        would see it; only what the camera shows; no similes or metaphors; never the name of a technique or a \
        pose. Nothing about her face, hair or clothes and nothing about the place — pictures carry those, and \
        words about them override the pictures. The camera stays on the side of her the film has already \
        shown: never film her from behind, never have her turn her back or turn around — the models have to \
        invent whatever side of her they have not seen, and her clothes change. The same goes for her head: \
        it keeps facing the way it faces in the first frame — a profile that turns to the lens comes back as \
        somebody else's face. THE ACTION IS THE FILM. `pose` catches her in the middle of the movement — a wide stance, knees \
        bent, weight on one leg, arms partway through their arc — never a neutral standing pose, which the \
        video model turns into a small gesture or a walk. `motion` LEADS with one continuous movement that \
        starts from the pose and is large and unmistakable: what the legs, the weight and the torso do as \
        well as the arms. Only then, briefly: she stays on the spot (she may step within her stance; she \
        does not walk away); the camera — "static camera" whenever her body moves; ambient sound only \
        (wind, water, birds, her breath). Never mention a person, animal or object \
        that is not already in the frame — whatever is named gets drawn. What must not happen is said as \
        what does: "her feet stay planted", "the camera does not move". End `motion` with where it leaves \
        her: "at the end she is standing in the same spot, facing the same way" — left unsaid, the video \
        model has her wander off in the last second.
        """

    /// Look at where the last shot stopped and direct the next one from there:
    /// her pose in words, for the camera the next shot uses, and the movement
    /// that carries on from it toward what the storyboard had planned.
    ///
    /// Nil when there is nobody to look — no model with eyes on any host — or
    /// the answer cannot be read; the shot is then made from the plan.
    ///
    /// It is told what the film is about. The first version was not, and it
    /// directed faithfully from what it saw: the video model ended a tai chi
    /// shot on a stray step, so the next shot "continues walking forward",
    /// and so did the one after — a continuous film of a woman leaving.
    /// Continuity with the last frame is half the job; the other half is
    /// bringing her back to what the film is of.
    static func direct(_ shot: Shot, after frame: URL, in film: Film) async -> (pose: String, motion: String)? {
        guard let picture = try? Data(contentsOf: frame) else { return nil }
        let ask = """
            This is the LAST FRAME of the previous shot of a short film about: "\(film.idea)". The next \
            4-second shot starts at this exact moment, seen by a new camera: "\(shot.framing ?? "a new angle")".
            The storyboard's plan for the next shot — the pose it expected her to be in: "\(shot.still)"; \
            what it wanted her to do: "\(shot.motion)"\(wished(shot))
            Answer with JSON only: {"pose": "...", "motion": "..."}
            - pose: ONE sentence, beginning with "she": her body exactly as it is in this frame — whether she \
            stands, sits, kneels or walks, and what each arm and leg is doing — but only the parts of her body \
            the new camera would show (no legs for a waist-up shot, only the hands for a close-up of her hands). \
            Nothing about her face, hair, clothes or the place.
            - motion: what she does in the next four seconds, starting from THIS pose and bringing her back to \
            the film's subject and the plan — if the last shot drifted into something else (a stray step, a \
            turn away), the movement returns her to the planned pose and carries on with the planned action; it \
            does not continue the drift.
            \(wording)
            """
        guard let answer = await look(ask, at: [picture]),
              let pose = text(answer["pose"]) else { return nil }
        return (pose, text(answer["motion"]) ?? shot.motion)
    }

    /// What a reviewer made of a take.
    struct Verdict {
        enum Fix { case clip, still }
        var score: Int
        var ok: Bool
        /// One sentence, in the user's language, for the card.
        var problem: String
        var fix: Fix
        var pose: String?
        var motion: String?
        var framing: String?
        var saw: String?
        var passed: Bool { ok }
    }

    /// Watch a take — four frames across it, and the master for comparison —
    /// against what the shot was meant to be. Nil when nobody can look.
    static func review(_ shot: Shot, in film: Film) async -> Verdict? {
        var pictures = await frames(of: film.clip(shot.id), at: [0.02, 0.35, 0.68, 0.98])
        guard pictures.count == 4 else { return nil }
        let opening = shot.id == film.shots.first?.id
        var compared = ""
        if !opening, let master = await MainActor.run(body: { try? Data(contentsOf: film.still(film.shots[0].id)) }) {
            pictures.append(master)
            compared = " Image 5 is the film's master frame. It is there for two things only — the place and her "
                + "clothes; its camera and her pose in it are meant to be different from this shot's."
        }
        // Who she is supposed to be, and how big her face is in this shot:
        // under about ninety pixels it cannot be held, and the cure is a
        // closer camera rather than another take from the same distance.
        var portrait = ""
        let anchor = await MainActor.run { film.lead ? CompanionCharacter.shared.anchorURL : nil }
        if let anchor, let face = try? Data(contentsOf: anchor) {
            pictures.append(face)
            let width = await MainActor.run { FilmReference.faceWidth(in: film.still(shot.id)) }
            portrait = " The last image is a portrait of the woman this film is about"
                + (width.map { "; in this shot's first frame her face is \($0) pixels wide" } ?? "") + "."
        }
        // Facts, not a mark out of ten. The first reviewer gave a score and
        // was a mood: three shots in four sent back, "ok: false, score: 7",
        // a take marked down because its camera was not the master's. Asked
        // instead what it can plainly SEE — did she leave, did somebody
        // arrive, is anything deformed, did the camera run off, did the
        // clothes change — it caught both takes where she walks away, with
        // the frame it happens in, and passed the good take three times out
        // of three. The decision is then arithmetic, made here.
        let ask = """
            You are checking one 4-second shot of a short film about: "\(film.idea)". Images 1–4 are frames \
            from the shot in order: its start, one third, two thirds, its end.\(compared)\(portrait)
            The plan for this shot — camera: "\(shot.framing ?? "not said")"; her pose at the start: \
            "\(shot.pose)"; the movement: "\(shot.action)"\(wished(shot))
            Report what you SEE, as facts. Answer with ONE JSON object and nothing else:
            {"leaves": true/false, "intruder": true/false, "deformed": true/false, "camera_wild": true/false, \
            "clothes_or_place_changed": true/false, "face_changed": true/false, "wish_ignored": true/false, \
            "performs": "no" or "partly" or "yes", "frozen": true/false, "body": "arms" or "upper" or "whole", \
            "plan_body": "arms" or "upper" or "whole", "saw": "...", \
            "problem": "...", "fix": "clip" or "still", "framing": "...", "pose": "...", "motion": "..."}
            - leaves: by the end she has walked off, sat down, turned her back, or otherwise stopped doing what \
            the film is about.
            - intruder: another person, an animal, or an object that arrives from nowhere; a second copy of her.
            - deformed: a plainly deformed body, face or hands — extra or missing limbs, melted features.
            - camera_wild: a fast zoom, the camera swinging off her, or ending out of focus.
            - clothes_or_place_changed: compared with the master frame only, never with what you think the \
            activity is usually done in.
            - face_changed: between image 1 and image 4 her face becomes recognisably somebody else's. When \
            her face is under about 90 pixels wide, answer false: it is too small to judge by eye.
            - wish_ignored: the user asked something of this shot and the shot plainly does not do it; false \
            when nothing was asked.
            - performs: does she visibly DO the planned movement between image 1 and image 4 — "yes", only \
            "partly" (a gesture toward it, or the arms without the rest), or "no".
            - frozen: she barely moves at all.
            - body: what actually took part — "arms" (hands and arms only), "upper" (arms and torso), "whole" \
            (knees bending, weight shifting or stepping, as well as the upper body).
            - plan_body: what the film's activity and this shot's plan call for, on the same scale.
            - saw: two plain English sentences on what her BODY does from image 1 to image 4 — which limbs \
            move and from where to where, whether her knees bend, whether her weight shifts, whether her feet \
            move or she travels, whether she turns. Facts only, no opinions, nothing about looks or the place.
            Say true only for what is plainly visible; when in doubt, false. Small imperfections are fine: this \
            is a generated film.
            - problem: one short sentence in \(film.tongue == "en" ? "English" : "Chinese (中文)") naming the frame \
            it happens in; empty when every answer is false.
            - When a fault is true, or the action falls short (performs is not "yes", frozen, or body is less \
            than plan_body): fix is "clip" when image 1 is fine and the movement went wrong — give a better \
            `motion`, larger and more of the body than the one that failed; "still" when image 1 itself is wrong — give a better `pose` and a `motion` from it, \
            and a new `framing` only if the camera itself is the trouble (it is behind her). Never move the \
            camera closer for the sake of her face: the distance belongs to the film.
            \(wording)
            """
        guard let answer = await look(ask, at: pictures) else { return nil }
        func seen(_ key: String) -> Bool { (answer[key] as? Bool) ?? false }
        // What each fault costs, out of ten; the opening shot's face is
        // fifty pixels wide by design and is not held against it.
        let faults: [(String, Int)] = [("leaves", 5), ("intruder", 5), ("deformed", 4), ("camera_wild", 3),
                                       ("clothes_or_place_changed", 3), ("wish_ignored", 3),
                                       ("face_changed", opening ? 0 : 3)]
        var cost = faults.reduce(0) { $0 + (seen($1.0) ? $1.1 : 0) }
        guard answer["leaves"] is Bool else { return nil }      // not the answer that was asked for
        // The action itself. A shot in which nothing goes wrong and nothing
        // much happens used to score ten — four tens for a film its owner
        // watched and said was not tai chi ("要强调动作啊").
        let reach = ["arms": 0, "upper": 1, "whole": 2]
        let did = reach[(answer["body"] as? String) ?? "whole"] ?? 2
        let asked = reach[(answer["plan_body"] as? String) ?? "arms"] ?? 0
        switch answer["performs"] as? String {
        case "no": cost += 5
        case "partly": cost += 3
        default: break
        }
        if seen("frozen") { cost += 4 }
        if did < asked { cost += 2 * (asked - did) }
        return Verdict(score: max(1, 10 - cost), ok: cost == 0, problem: text(answer["problem"]) ?? "",
                       fix: (answer["fix"] as? String) == "still" ? .still : .clip,
                       pose: text(answer["pose"]), motion: text(answer["motion"]), framing: text(answer["framing"]),
                       saw: text(answer["saw"]))
    }

    /// Laya's second opinion: off unless it is turned on in Settings → Backend.
    /// It is a service somebody has to have started, and an opinion that
    /// decides nothing; neither is a thing to be on behind anybody's back.
    static let layaOnKey = "kinclaw.film.laya.on"
    static let layaURLKey = "kinclaw.film.laya"
    static let layaDefault = "http://127.0.0.1:8005"
    static var layaOn: Bool { UserDefaults.standard.bool(forKey: layaOnKey) }

    /// Where the Laya service listens (`scripts/laya_judge.py`); not running
    /// is not an error, the card simply has one line fewer.
    ///
    /// With a box configured it is the box's, unless an address was typed in:
    /// the model is four to ten times quicker on the box's GPU than on this
    /// Mac's CPU, the LAN adds twenty milliseconds, and the Mac keeps its
    /// memory. No box, no change: the loopback.
    static var layaURL: String {
        let set = (UserDefaults.standard.string(forKey: layaURLKey) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !set.isEmpty { return set }
        return BoxServices.ssh.isEmpty ? layaDefault : BoxServices.base(.laya)
    }

    /// Bring the box's Laya up if that is the one in use and it is not there.
    static func layaReady() async {
        guard layaURL == BoxServices.base(.laya) else { return }
        _ = await BoxServices.shared.ensure(.laya)
    }

    /// Is anybody there? For the dot in Settings.
    static func layaAnswers() async -> Bool {
        guard let url = URL(string: layaURL + "/health") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Jev's second opinion: the same questions put to TypeSafe's hosted model.
    /// Off by default for the same reasons, and one more — the description of
    /// the take and the film's idea leave this Mac. The key is the one typed
    /// into the Jev tab; it stays in the Keychain.
    static let jevOnKey = "kinclaw.film.jev.on"
    static var jevOn: Bool { UserDefaults.standard.bool(forKey: jevOnKey) }

    /// Whether Jev's reading counts. A second switch, off by default, and
    /// worth nothing unless the first is on.
    static let jevCountsKey = "kinclaw.film.jev.counts"
    static var jevCounts: Bool { jevOn && UserDefaults.standard.bool(forKey: jevCountsKey) }
    /// Below this, "what was seen carries out the plan" is a no.
    static let jevFollows = 0.3

    /// What Jev's reading does to the reviewer's verdict when it counts: one
    /// thing, and only downward. A take the reviewer let through is failed
    /// when Jev reads the reviewer's own description as a different movement
    /// from the planned one — the model that looks is good at saying what it
    /// saw and moody about what that amounts to, and comparing two pieces of
    /// text is the thing Jev is for. On the eight takes it was first tried on,
    /// the three that were a different movement got 0.02, 0.00 and 0.28 and
    /// the other five 0.56 to 1.00; Laya gave all eight 0.78 to 0.95.
    ///
    /// Nothing else counts. Jev never rescues a take the reviewer failed — it
    /// cannot see an extra arm or a changed coat — and the retake is made from
    /// the same words, the reviewer having had no complaint to rewrite them by.
    static func weigh(_ verdict: Verdict, jev: [String: Double]?, counts: Bool? = nil) -> Verdict {
        guard counts ?? jevCounts, let follows = jev?["follows"], follows < jevFollows, verdict.score > 4 else { return verdict }
        var weighed = verdict
        weighed.score = 4
        weighed.ok = false
        let said = "Jev：看到的动作和计划的不是一回事（按计划 \(String(format: "%.2f", follows))）"
        weighed.problem = verdict.problem.isEmpty ? said : verdict.problem + "；" + said
        return weighed
    }

    /// Why Jev's line is missing, when it is: no key, a refused key, no network.
    /// Laya not running is ordinary and says nothing; a judge somebody paid for
    /// and switched on, silently absent, would be "我怎么没有看见" again.
    @Published private(set) var jevTrouble: String?
    /// Input tokens Jev has been sent for film reviews since the app started.
    @Published private(set) var jevTokens = 0

    /// Whoever is switched on, asked at the same time.
    static func opinions(on saw: String, plan: String, idea: String) async -> (laya: [String: Double]?, jev: [String: Double]?) {
        async let laya = second(on: saw, plan: plan, idea: idea)
        async let jev = verdictOfJev(on: saw, plan: plan, idea: idea)
        return await (laya, jev)
    }

    /// Jev's reading of what was seen against what was planned.
    ///
    /// Jev is asked Choice questions — the one kind this app has seen it answer
    /// — so a yes-or-no is put as two options and the number is the probability
    /// of the yes; how much of her moves is three options, and the number is
    /// where the probabilities balance between nought and two. That makes the
    /// four numbers mean what Laya's four mean.
    static func verdictOfJev(on saw: String, plan: String, idea: String) async -> [String: Double]? {
        guard jevOn else { return nil }
        let questions = [
            JevClient.Question(id: "follows", question: "Does what was seen carry out the planned movement?",
                               howToJudge: "Compare which limbs move, and which way, in what_was_seen with planned_movement. Different wording for the same movement is a yes; a different movement, a part of it only, or none, is a no.",
                               options: [("yes", "What was seen is the planned movement"),
                                         ("no", "What was seen is a different movement, or hardly any")]),
            JevClient.Question(id: "activity", question: "Is what was seen the activity the film is about, done properly?",
                               howToJudge: "Judge the body described in what_was_seen against what doing film_is_about properly asks of a body. Ordinary standing, walking, waving or posing is a no, however graceful.",
                               options: [("yes", "She is doing that activity, and doing it properly"),
                                         ("no", "She is only standing, walking, waving or posing")]),
            JevClient.Question(id: "leaves", question: "Does she walk away, turn her back, or stop the activity?",
                               options: [("yes", "She walks away, turns her back, or stops"),
                                         ("no", "She stays where she is, facing the same way, and keeps going")]),
            JevClient.Question(id: "amount", question: "How much of her body takes part in the movement?",
                               options: [("still", "She barely moves"),
                                         ("arms", "Only her arms or hands move"),
                                         ("whole", "Her whole body moves: arms, torso and legs")]),
        ]
        do {
            let reply = try await JevClient.ask(state: [("film_is_about", idea), ("planned_movement", plan), ("what_was_seen", saw)], questions)
            var read: [String: Double] = [:]
            for name in ["follows", "activity", "leaves"] {
                if let yes = reply.answers[name]?.chances["yes"] { read[name] = yes }
            }
            if let chances = reply.answers["amount"]?.chances, !chances.isEmpty {
                read["amount"] = (chances["arms"] ?? 0) + 2 * (chances["whole"] ?? 0)
            }
            await MainActor.run {
                shared.jevTokens += reply.tokens
                shared.jevTrouble = read.isEmpty ? "Jev 答了，但读不出数：\(reply.answers.keys.sorted().joined(separator: ", "))" : nil
            }
            return read.isEmpty ? nil : read
        } catch {
            let said = error.localizedDescription
            await MainActor.run { shared.jevTrouble = said }
            return nil
        }
    }

    /// Laya's reading of what was seen against what was planned.
    static func second(on saw: String, plan: String, idea: String) async -> [String: Double]? {
        guard layaOn, let url = URL(string: layaURL + "/decide") else { return nil }
        await layaReady()
        // Written out in order, by hand. A model reads a request from the top,
        // and a dictionary reaches it shuffled — differently at every launch:
        // one description of one take was given 0.09 for "the activity, done
        // properly" by one launch of the app and 0.83 by the next.
        let quoted = JevClient.quoted, object = JevClient.object
        func noul(_ ask: String) -> String { object([("type", quoted("noul")), ("instructions", quoted(ask))]) }
        let amounts = ["she barely moves", "only her arms or hands move", "her whole body moves: arms, torso and legs"]
        let body = object([
            ("state", object([("film_is_about", quoted(idea)), ("planned_movement", quoted(plan)), ("what_was_seen", quoted(saw))])),
            ("questions", object([
                ("follows", noul("Does what was seen carry out the planned movement?")),
                ("activity", noul("Is what was seen an instance of the activity the film is about, done properly, rather than ordinary standing, walking or waving?")),
                ("leaves", noul("Does she walk away, turn her back, or stop the activity?")),
                ("amount", object([("type", quoted("score")), ("instructions", quoted("How much of her body takes part in the movement?")),
                                   ("criteria", "[" + amounts.map(quoted).joined(separator: ", ") + "]")])),
            ])),
        ])
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let answers = reply["answers"] as? [String: [String: Any]] else { return nil }
        var read: [String: Double] = [:]
        for (name, answer) in answers {
            if let value = (answer["noul"] as? Double) ?? (answer["score"] as? Double) { read[name] = value }
        }
        return read.isEmpty ? nil : read
    }

    /// Rewrite a shot's words to follow a direction given in a sentence. The
    /// model sees the take the direction is about, when there is one — "手再慢一点"
    /// means nothing without knowing how fast they were.
    static func revise(_ shot: Shot, in film: Film, toward note: String)
        async -> (framing: String?, pose: String?, motion: String?, narration: String?)? {
        let pictures = await frames(of: film.clip(shot.id), at: [0.02, 0.5, 0.98])
        let seen = pictures.isEmpty ? "" : " The images are frames from the current take: its start, middle and end."
        let opening = shot.id == film.shots.first?.id
        let ask = """
            You are rewriting one 4-second shot of a short film about: "\(film.idea)", set in: \
            "\(film.place ?? "one place")".\(seen)
            The shot as it stands — camera: "\(shot.framing ?? "not said")"; her pose at the start: \
            "\(shot.pose)"; the movement: "\(shot.action)"; voice-over: "\(shot.narration ?? "")".
            The user's direction, in their own words: "\(note)"
            Rewrite whatever has to change to follow that direction, and nothing else. Answer with JSON only, \
            leaving out every field that stays as it is: {"framing": "...", "pose": "...", "motion": "...", \
            "narration": "..."}
            - framing: where the camera is, one phrase\(opening ? " (this is the opening shot: it stays a wide shot of her whole body)" : "").
            - narration: only if the direction is about the voice-over; in the language it is already in.
            \(wording)
            """
        guard let answer = await look(ask, at: pictures) else { return nil }
        let result = (text(answer["framing"]), text(answer["pose"]), text(answer["motion"]), text(answer["narration"]))
        if result.0 == nil, result.1 == nil, result.2 == nil, result.3 == nil { return nil }
        return result
    }

    /// The user's wish for a shot, as a line for whoever is writing or judging it.
    private static func wished(_ shot: Shot) -> String {
        guard let wish = shot.wish, !wish.isEmpty else { return "" }
        return "\nThe user asked this of the shot, and it outranks the plan: \"\(wish)\""
    }

    private static func text(_ value: Any?) -> String? {
        guard let words = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return words
    }

    /// Show pictures to the model that can see and read back its JSON.
    static func look(_ ask: String, at pictures: [Data]) async -> [String: Any]? {
        guard let seer = await seer(), let url = URL(string: seer.host + "/api/chat") else { return nil }
        var message: [String: Any] = ["role": "user", "content": ask]
        if !pictures.isEmpty { message["images"] = pictures.map { $0.base64EncodedString() } }
        let body: [String: Any] = ["model": seer.model, "stream": false, "think": false, "messages": [message]]
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let words = (reply["message"] as? [String: Any])?["content"] as? String,
              let close = words.lastIndex(of: "}") else { return nil }
        // The last object in the reply that parses. A model that thinks aloud
        // answers, argues with itself, and answers again ("修正为严格JSON：…"):
        // first-brace-to-last-brace is then two objects and an essay.
        var open = close
        while let earlier = words[..<open].lastIndex(of: "{") {
            if let object = try? JSONSerialization.jsonObject(with: Data(words[earlier...close].utf8)) as? [String: Any] {
                return object
            }
            open = earlier
        }
        return nil
    }

    /// Frames from a clip, as small JPEGs: enough for a model to judge a
    /// take by, and a tenth of the upload the full frames would be.
    static func frames(of clip: URL, at fractions: [Double]) async -> [Data] {
        guard FileManager.default.fileExists(atPath: clip.path) else { return [] }
        let asset = AVURLAsset(url: clip)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 12)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 12)
        var made: [Data] = []
        for fraction in fractions {
            let moment = CMTime(seconds: duration.seconds * min(max(fraction, 0), 0.99), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: moment).image else { continue }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, frame, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            if CGImageDestinationFinalize(destination) { made.append(data as Data) }
        }
        return made
    }

    /// A model that can look at a picture: the storyboard's writer if it can,
    /// else the best of the others that can. Ollama says which in `/api/show`.
    static func seer() async -> (host: String, model: String)? {
        func sees(_ model: String, on host: String) async -> Bool {
            guard let url = URL(string: host + "/api/show") else { return false }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let shown = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let can = shown["capabilities"] as? [String] else { return false }
            return can.contains("vision")
        }
        if let pick = await writer(), await sees(pick.model, on: pick.host) { return pick }
        for entry in await candidates() {
            for model in entry.models.sorted(by: { rank($0) < rank($1) }) where await sees(model, on: entry.host) {
                return (entry.host, model)
            }
        }
        return nil
    }

    /// Words for the image and video models, in the language they read.
    ///
    /// The tab lets a shot's words be rewritten, and the person rewriting
    /// them thinks in Chinese; the models that draw and film were trained on
    /// English captions. So anything with Chinese in it goes through the
    /// storyboard's writer first, with the same rules the storyboard had.
    /// Unreachable writer, or an answer that is not a sentence: the words go
    /// through as they were written, which still mostly works.
    static func english(_ text: String, as role: String) async -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }),
              let writer = await writer(), let url = URL(string: writer.host + "/api/chat") else { return words }
        let ask = """
            Rewrite this as plain literal English for an image/video generation model. It is the \(role) of one \
            shot of a short film. Describe the body and the camera literally, as a stranger would see them; no \
            similes or metaphors; never the name of a technique or a pose — describe the limbs; keep every detail \
            that was given and add none. Answer with the rewritten text only, no quotes.

            \(words)
            """
        let body: [String: Any] = ["model": writer.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let answer = ((reply["message"] as? [String: Any])?["content"] as? String)?
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”"))),
              !answer.isEmpty, answer.count < 1200 else { return words }
        return answer
    }

    /// A description with its similes cut out.
    ///
    /// The brief forbids them and a writer still slips one in about one shot
    /// in four — "arms curved above her head as if holding a large sphere" —
    /// and the image model draws the sphere. It is the one failure that can
    /// be caught by reading the words, so it is: the clause goes, up to the
    /// next comma or full stop, and the literal half of the sentence stays.
    ///
    /// The same for what she is wearing, which a model that describes a
    /// frame adds however it is asked not to — "…arms hanging at her sides,
    /// wearing a light blue quilted jacket over a white top, a large tree
    /// behind her, a stone bench to her right". Sent to the editor, those
    /// words outrank the master picture that is there to say the same thing
    /// better: that sentence is how an open jacket over a white top, invented
    /// by the video model for a side of her it had not seen, became her
    /// outfit for the rest of the film. From "wearing" to the full stop goes.
    static func literal(_ text: String) -> String {
        let simile = #"(?i),?\s*\b(as if|as though|like an?|like the)\b[^,.;]*"#
        let dressed = #"(?i),?\s*\b(wearing|dressed in)\b[^.;]*"#
        return text.replacingOccurrences(of: simile, with: "", options: .regularExpression)
            .replacingOccurrences(of: dressed, with: "", options: .regularExpression)
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// The words and the pictures one still is made from.
    ///
    /// Measured on the film that prompted this ("她在公园里打太极"): with the anchor
    /// and the master both shown to the editor, three different camera
    /// positions came back in the same pavilion, under the same willows, in
    /// the same shirt, trousers and sandals — which the same words without
    /// the master had not managed once in four. The order is the tested one:
    /// camera first, then what to keep from which picture, then the pose. A
    /// pose said before the camera gets the master's camera back.
    ///
    /// And once there is a master, the place and the clothes are *not* said
    /// again in words. They were, in the first film made this way, and all
    /// four stills came back as the same full-length wide shot whatever the
    /// storyboard asked for: a sentence that lists a pavilion, a willow,
    /// trousers and shoes can only be satisfied by a frame with all of them
    /// in it. With the master left to carry them, "medium shot from her left
    /// side, waist up" is one, and "close-up of her hands" is close.
    static func recipe(for shot: Shot, in film: Film, anchor: URL?, master: URL?, previous: URL? = nil,
                       style: String) -> (prompt: String, pictures: [URL]) {
        func sentence(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text.hasSuffix(".") ? String(text.dropLast()) : text
        }
        let her = film.lead ? anchor : nil
        let dressed = her != nil ? sentence(film.wears).map { "she is wearing \($0)" } : nil
        var keep: String?
        var pictures: [URL] = []
        // Carrying on from the previous shot's last frame: it holds the one
        // thing the master cannot, where she had got to. The pose is said in
        // words too, because "keep her pose" alone is not kept: asked for the
        // same moment from behind, her raised arms came back down at her
        // sides. The master comes along as well. One link into a chain the
        // result is the same with or without it; three links in, without it,
        // a padded jacket had become a jumper — each frame of video is a
        // slightly worse witness to the clothes than the one before, and the
        // master is the only picture that never was video.
        if let previous {
            let pose = sentence(Self.literal(shot.pose))
            let moved = "only the camera has moved"
            switch (her, master) {
            case let (her?, master?):
                pictures = [her, master, previous]
                keep = "Image 1 is the woman: keep her exact face and hair. Image 2 is this film's location and her "
                    + "outfit: keep the same place, the same clothes and shoes, the same light and colours. Image 3 is "
                    + "the previous moment of this film: keep her pose; \(moved)"
            case let (her?, nil):
                pictures = [her, previous]
                keep = "Image 1 is the woman: keep her exact face and hair. Image 2 is the previous moment of this "
                    + "film: keep her pose, the same place, the same clothes and shoes, the same light and colours; \(moved)"
            case let (nil, master?):
                pictures = [master, previous]
                keep = "Image 1 is this film's location: keep the same place, the same light and colours. Image 2 is "
                    + "the previous moment of this film; \(moved)"
            case (nil, nil):
                pictures = [previous]
                keep = "This is the previous moment of this film: keep the same place, the same light and colours; \(moved)"
            }
            let words = [sentence(shot.framing), keep, pose, sentence(film.look), her != nil ? sentence(style) : nil]
            return (words.compactMap { $0 }.joined(separator: ". "), pictures)
        }
        switch (her, master) {
        case let (her?, master?):
            pictures = [her, master]
            keep = "Image 1 is the woman: keep her exact face and hair. Image 2 is this film's location and her "
                + "outfit: keep the same place, the same clothes and shoes, the same light and colours"
        case let (her?, nil):
            pictures = [her]
            keep = "keep this exact woman, same face"
        case let (nil, master?):
            pictures = [master]
            keep = "This is the film's location: keep the same place, the same light and colours"
        case (nil, nil):
            break
        }
        // The opening still is the master, and a master has to show the
        // place or there is nothing for the later shots to be shown. A
        // storyboard that opens on a close-up is opened on a wide shot anyway.
        let opening = shot.id == film.shots.first?.id
        let camera = opening
            ? (her != nil ? "Full-length shot: her whole body, head to foot, fills most of the height of the frame, "
                + "the place visible around her" : "Wide establishing shot")
            : sentence(shot.framing)
        let shown = master != nil
        let words = [camera, keep, sentence(Self.literal(shot.pose)), shown ? nil : sentence(film.place),
                     shown ? nil : dressed, sentence(film.look), her != nil ? sentence(style) : nil]
        return (words.compactMap { $0 }.joined(separator: ". "), pictures)
    }

    /// Her face, put back where the camera stands too far off to have kept
    /// it: the head is cut out and enlarged, the editor redraws the face from
    /// her anchor, and the face is set back into the still where it was. The
    /// camera stays where the film put it — see `FilmReference.inlay`. The
    /// still as it was first drawn is kept beside it, `shot-NN.drawn.png`.
    /// Anything that goes wrong leaves the still as it was.
    private func restoreFace(in film: Film, _ shot: Int) async {
        guard film.lead, let anchor = CompanionCharacter.shared.anchorURL else { return }
        let still = film.still(shot)
        let head = film.folder.appendingPathComponent(String(format: "shot-%02d.head.png", shot))
        guard let found = FilmReference.head(of: still, to: head),
              let answer = try? await DiffuserClient.shared.edit(
                prompt: FilmReference.headPrompt, from: head, also: [anchor], into: film.folder,
                seed: CompanionCharacter.seed(for: film.id + "head\(shot)")) else { return }
        let fixed = film.folder.appendingPathComponent(String(format: "shot-%02d.faced.png", shot))
        let fm = FileManager.default
        if FilmReference.inlay(answer, into: still, at: found.face, as: fixed) {
            let drawn = film.folder.appendingPathComponent(String(format: "shot-%02d.drawn.png", shot))
            try? fm.moveItem(at: drawn, to: film.take(shot, "drawn-\(Int(Date().timeIntervalSince1970))", "png"))
            if (try? fm.moveItem(at: still, to: drawn)) != nil { try? fm.moveItem(at: fixed, to: still) }
        }
        // The editor's own picture and its prompt note have served their purpose.
        try? fm.moveItem(at: answer, to: film.folder.appendingPathComponent(String(format: "shot-%02d.head-answer.png", shot)))
        try? fm.moveItem(at: URL(fileURLWithPath: answer.path + ".txt"),
                         to: film.folder.appendingPathComponent(String(format: "shot-%02d.head-answer.png.txt", shot)))
    }

    /// The shot's line, spoken by the TTS on this Mac and kept beside the clip.
    /// A film is still a film without it: if the service is not there the
    /// line is simply left unsaid.
    private func speak(_ film: Film, _ shot: Shot) async {
        guard let line = shot.narration, !line.isEmpty,
              !FileManager.default.fileExists(atPath: film.voice(shot.id).path),
              let audio = await Self.synthesize(line, tongue: film.tongue) else { return }
        try? audio.write(to: film.voice(shot.id), options: .atomic)
    }

    /// Change what is said over a shot — or, with an empty line, say nothing —
    /// and cut again. Nothing is filmed: a voice-over is a second and a half
    /// of work, and re-rolling a shot to reword a sentence would be absurd.
    func narrate(film id: String, shot number: Int, line: String) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }),
              let index = film.shots.firstIndex(where: { $0.id == number }) else {
            return .failure(.message("没有这部片子或这个镜头"))
        }
        let said = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = Int(Date().timeIntervalSince1970)
        let fm = FileManager.default
        try? fm.moveItem(at: film.voice(number), to: film.folder.appendingPathComponent(String(format: "shot-%02d.take-\(stamp).wav", number)))
        film.shots[index].narration = said.isEmpty ? nil : said
        film.state = .cutting
        save(film)
        shooting = film.id
        Task { @MainActor in
            defer { shooting = nil }
            await speak(film, film.shots[index])
            try? fm.moveItem(at: film.file, to: film.folder.appendingPathComponent("film.cut-\(stamp).mp4"))
            let done = film.shots.filter { $0.state == .done }
            do {
                try await Self.cut(done.map { film.clip($0.id) }, voices: done.map { film.voice($0.id) }, to: film.file)
                film.state = .done
            } catch {
                film.state = .failed
                film.note = "剪不出来：\(error.localizedDescription)"
            }
            save(film)
        }
        return .success(film)
    }

    /// One line through the user's own Kokoro. The request is the one the
    /// companion's voice uses, field for field — `speaker` and `language`,
    /// not `voice`, or it reads Chinese out as "Chinese letter, Chinese
    /// letter" — and the padding Kokoro puts round every clip is trimmed.
    static func synthesize(_ text: String, tongue: String? = nil) async -> Data? {
        let chosen = UserDefaults.standard.string(forKey: "kinclaw.backend.tts") ?? ""
        let base = chosen.isEmpty ? "http://localhost:8001" : chosen.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/synthesize") else { return nil }
        let preferred = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        // The language decides, because a Kokoro voice can only read its own:
        // the film's, if it has one, else whatever the line is written in.
        // Her usual voice is used when it is a voice of that language.
        let kana = text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let chinese = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let asked = tongue.flatMap { tag in tongues.contains { $0.tag == tag } ? tag : nil }
        let language = asked ?? (kana ? "ja" : chinese ? "zh" : "en")
        let usual = (preferred.isEmpty || preferred == "auto") ? nil : preferred
        let speaker = usual.flatMap { TextSegmenter.language(forVoice: $0) == language ? $0 : nil }
            ?? TextSegmenter.voice(forLanguage: language) ?? "af_bella"
        let speed = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")
        let body: [String: Any] = ["text": text, "speaker": speaker,
                                   "language": TextSegmenter.language(forVoice: speaker),
                                   "speed": speed > 0 ? speed : 1.0]
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 44 else { return nil }
        return WAVTrim.trim(data)
    }

    /// Carry on with a film that stopped: everything not finished is tried
    /// again, finished shots are left alone, and it is cut at the end.
    func resume(film id: String) -> Result<Film, Failure> {
        guard shooting == nil else { return .failure(.message("片场正在拍「\(shooting!)」，等它拍完")) }
        guard var film = films.first(where: { $0.id == id || $0.title == id }) else {
            return .failure(.message("没有这部片子：\(id)"))
        }
        guard film.shots.contains(where: { $0.state != .done }) else {
            return .failure(.message("「\(film.title)」的镜头都拍好了；要重拍哪个，给 shot"))
        }
        for index in film.shots.indices where film.shots[index].state != .done {
            film.shots[index].state = .waiting
            film.shots[index].note = nil
        }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.moveItem(at: film.file, to: film.folder.appendingPathComponent("film.cut-\(stamp).mp4"))
        film.state = .shooting
        film.note = nil
        save(film)
        produce(film.id)
        return .success(film)
    }

    /// The service is not there, as opposed to having refused the work.
    static func isUnreachable(_ error: Error) -> Bool {
        if let url = error as? URLError {
            return [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
                    .timedOut, .dnsLookupFailed].contains(url.code)
        }
        let text = error.localizedDescription.lowercased()
        return ["could not connect", "连不上", "connection refused", "network connection was lost",
                "timed out", "offline"].contains { text.contains($0) }
    }

    private func update(_ film: inout Film, _ index: Int, _ state: Shot.State) {
        film.shots[index].state = state
        save(film)
    }

    private func save(_ film: Film) {
        if let at = films.firstIndex(where: { $0.id == film.id }) { films[at] = film } else { films.insert(film, at: 0) }
        if let data = try? Self.encoder.encode(film) {
            try? data.write(to: film.folder.appendingPathComponent("film.json"), options: .atomic)
        }
    }

    // MARK: - The cut

    /// Shots end to end, each dissolving into the next, sound faded across.
    ///
    /// Two video tracks and two audio tracks, the shots dealt alternately
    /// between them, because a dissolve needs both pictures to exist at once
    /// and a single track cannot overlap itself.
    ///
    /// `voices` runs alongside `clips`: where a shot has a spoken line, it
    /// goes on a track of its own a quarter of a second into the shot, and
    /// the shot's own sound sits at a third under it — waves under a
    /// sentence, not against it.
    static func cut(_ clips: [URL], voices: [URL] = [], fade: Double = 0.4, to out: URL) async throws {
        let composition = AVMutableComposition()
        let video = (0..<2).compactMap { _ in composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) }
        let audio = (0..<2).compactMap { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
        guard video.count == 2, audio.count == 2 else { throw Failure.message("建不了剪辑轨道") }

        let overlap = CMTime(seconds: fade, preferredTimescale: 600)
        var cursor = CMTime.zero
        var spans: [(track: Int, range: CMTimeRange)] = []
        var size = CGSize(width: 704, height: 704)
        for (index, url) in clips.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            if index == 0 { size = try await source.load(.naturalSize) }
            let lane = index % 2
            let range = CMTimeRange(start: .zero, duration: duration)
            try video[lane].insertTimeRange(range, of: source, at: cursor)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                try audio[lane].insertTimeRange(range, of: sound, at: cursor)
            }
            spans.append((lane, CMTimeRange(start: cursor, duration: duration)))
            cursor = CMTimeSubtract(CMTimeAdd(cursor, duration), overlap)
        }
        guard !spans.isEmpty else { throw Failure.message("没有能剪的镜头") }

        // One instruction per stretch of time: a shot alone, or two dissolving.
        // The spoken lines, and how loud each shot's own sound is allowed to be.
        let narration = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var level = [Float](repeating: 1, count: spans.count)
        for (index, span) in spans.enumerated() where index < voices.count {
            guard FileManager.default.fileExists(atPath: voices[index].path) else { continue }
            let asset = AVURLAsset(url: voices[index])
            guard let line = try? await asset.loadTracks(withMediaType: .audio).first,
                  let length = try? await asset.load(.duration) else { continue }
            let start = CMTimeAdd(span.range.start, CMTime(seconds: 0.25, preferredTimescale: 600))
            // A line that runs past the end of the film is cut there.
            let room = CMTimeSubtract(spans.last!.range.end, start)
            let use = CMTimeCompare(length, room) > 0 ? room : length
            guard CMTimeCompare(use, .zero) > 0 else { continue }
            try? narration?.insertTimeRange(CMTimeRange(start: .zero, duration: use), of: line, at: start)
            level[index] = 0.32
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let mix = AVMutableAudioMix()
        var volumes: [AVMutableAudioMixInputParameters] = audio.map { AVMutableAudioMixInputParameters(track: $0) }
        volumes[spans[0].track].setVolume(level[0], at: .zero)
        for (index, span) in spans.enumerated() {
            let next = index + 1 < spans.count ? spans[index + 1] : nil
            let soloStart = index == 0 ? span.range.start : CMTimeAdd(span.range.start, overlap)
            let soloEnd = next == nil ? span.range.end : next!.range.start
            if CMTimeCompare(soloEnd, soloStart) > 0 {
                let alone = AVMutableVideoCompositionInstruction()
                alone.timeRange = CMTimeRange(start: soloStart, end: soloEnd)
                alone.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: video[span.track])]
                instructions.append(alone)
            }
            if let next {
                let dissolve = CMTimeRange(start: next.range.start, end: span.range.end)
                let both = AVMutableVideoCompositionInstruction()
                both.timeRange = dissolve
                let leaving = AVMutableVideoCompositionLayerInstruction(assetTrack: video[span.track])
                leaving.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: dissolve)
                let arriving = AVMutableVideoCompositionLayerInstruction(assetTrack: video[next.track])
                both.layerInstructions = [leaving, arriving]
                instructions.append(both)
                volumes[span.track].setVolumeRamp(fromStartVolume: level[index], toEndVolume: 0, timeRange: dissolve)
                volumes[next.track].setVolumeRamp(fromStartVolume: 0, toEndVolume: level[index + 1], timeRange: dissolve)
            }
        }
        if let narration { volumes.append(AVMutableAudioMixInputParameters(track: narration)) }
        mix.inputParameters = volumes
        let frame = AVMutableVideoComposition()
        frame.instructions = instructions
        frame.renderSize = size
        frame.frameDuration = CMTime(value: 1, timescale: 24)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.message("这台机器导不出视频")
        }
        let partial = out.deletingLastPathComponent().appendingPathComponent("film.partial.mp4")
        try? FileManager.default.removeItem(at: partial)
        export.outputURL = partial
        export.outputFileType = .mp4
        export.videoComposition = frame
        export.audioMix = mix
        await export.export()
        guard export.status == .completed else {
            throw Failure.message(export.error?.localizedDescription ?? "导出没完成")
        }
        if FileManager.default.fileExists(atPath: out.path) {
            _ = try FileManager.default.replaceItemAt(out, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: out)
        }
    }

    // MARK: - A storyboard from one sentence

    /// What a storyboard has to be, for whoever writes one.
    ///
    /// Rewritten after "她在公园里打太极" came back as four postcards. The first brief
    /// asked for "one photograph in concrete English" and got a director's
    /// prose: "hands pushing forward as if moving water" put her waist-deep in
    /// a lake, "reflected in a puddle" sat her on a ledge with her feet in
    /// one, "the opening gesture of tai chi" was a T-pose, and "sound of
    /// distant park keepers sweeping" walked a man into the last frame. None
    /// of that is the writer being bad at writing. It is the writer not
    /// knowing who reads it — so the brief now says who.
    static let brief = """
        You are writing the shot list for a very short film made of 4-second shots. It will be drawn and \
        filmed by image and video models, which take every word literally and know nothing you do not \
        tell them. Write a shot list, not prose.

        ONE PLACE. The whole film happens in one spot. `place` describes it once: what it is, the two or \
        three landmarks that make it that spot, the weather ("a narrow cobbled alley in an old town, a \
        blue wooden door on the left, laundry lines overhead, wet ground after rain" — an example of \
        the form, never to be reused). It is added to every frame. Never move to a second location; variety comes from where the camera stands.

        ONE ACTIVITY, IN ORDER. The shots are consecutive moments of the same activity, as if filmed in \
        one visit, and they are chained: every shot after the first starts from the exact frame the \
        previous one ended on, seen by a new camera. So write each `motion` as the next phase of one \
        continuous movement, and each later `still` as the pose you expect the previous shot to end in.

        Each shot is ONE still photograph that is then animated:
        - `framing`: where the camera is, one phrase — "wide shot from the front, whole body", "medium \
        shot from her left side, waist up", "close-up of her hands", "wide shot from her right, a little \
        lower". Shot 1 is always a full-length shot showing her whole body and the place. After it, \
        give each shot the framing its action needs: something done with the whole body — tai chi, \
        dancing, walking, stretching — is filmed full-length or from the knees up in EVERY shot, \
        because from the waist up it is a woman moving her arms. Get variety from the angle (front, \
        three-quarter left, three-quarter right, a little lower, a little higher), not from the \
        distance; go close only when the hands or the face ARE the action. Vary the shots, but \
        never from behind her and never have her turn around: the models invent whatever side of her \
        they have not been shown, and her clothes change with it.
        - `still`: what that photograph shows, literally, as a stranger would describe it. It catches \
        her IN THE MIDDLE of the movement — for anything physical, a wide stance with the knees bent, the \
        weight on one leg, the arms partway through their arc — never standing straight with her arms at \
        her sides: the video model continues the energy of its first frame, and a neutral pose becomes a \
        small gesture or a walk. Say whether she \
        stands, sits or walks, and what each limb that is in the frame is doing ("she sits on the top \
        step with her knees together, her left hand flat on the stone beside her, her right hand \
        holding a paper cup at chest height"). Only what is inside the frame — no legs in a waist-up shot. No \
        similes and no metaphors, ever: "as if holding a ball" draws a ball, "as if moving water" puts \
        her in a lake. Never name a technique, a dance step or a pose and expect it to be known — \
        describe the body. Do not repeat the place, her clothes, her face or her hair here; they are added.
        - `motion`: what moves during the four seconds. THE ACTION IS THE FILM: lead with it and make \
        it large and unmistakable, with the whole body when the activity is of the whole body — what the \
        legs, the weight and the torso do as well as the arms ("she sinks lower on her bent knees and \
        shifts her weight onto her left leg while both arms sweep in a wide slow arc from her right hip \
        past her chest to the left, her torso turning with them"). One continuous movement that \
        starts from the pose in `still` ("she slowly lifts the cup to her lips, tilts her head back a \
        little, and lowers it again"); then, in a few words, that she stays on the spot — she may step \
        within her stance, she does not walk away; then the camera — "static camera" whenever her body moves, and a \
        move (slow push in, slow pan) only in a shot where she holds still: asked for both at once, \
        the video model gives up her movement for a zoom — then the sound. Sound is ambient only — wind, water, birds, \
        rain, distant traffic, her own footsteps or breath. Never mention a person, an animal or an \
        object that is not already in the still, not even as a sound: whatever is named gets drawn. No \
        fights, no fine hand work, no text.

        `look` is what every frame shares: film stock, palette, time of day. When the lead is "her", \
        write `still` as "she …" and say what she wears ONCE, in `wears`: one line, head to foot, shoes \
        included, chosen for THIS story and its weather. It is added to every frame so she is dressed \
        the same throughout. `narration` is an optional line of voice-over for the shot, written in the \
        SAME language as the Idea line below — a Chinese idea gets Chinese narration, whatever \
        language this brief is in: a storyteller's sentence, not a description of the picture, \
        and short enough to say in three seconds — a dozen Chinese characters or eight English words. \
        Leave it out where the shot should be left to breathe.
        """

    /// Ask the local brain for a storyboard. JSON in, JSON out.
    static func storyboard(for idea: String, shots: Int, lead: Bool, tongue: String = "",
                           model _: String = "") async throws
        -> (title: String, look: String, place: String, wears: String, shots: [Draft]) {
        guard let writer = await writer() else {
            throw Failure.message("找不到能写分镜的模型：\(OllamaCatalog.baseURL) 和本机 Ollama 上都没有可用的对话模型")
        }
        let model = writer.model
        guard let url = URL(string: writer.host + "/api/chat") else { throw Failure.message("Ollama 地址不对") }
        let ask = """
            Idea: \(idea)
            Lead: \(lead ? "her (the same woman in every shot)" : "none — nobody needs to recur")
            Shots: \(shots)
            Narration: \(voiceOver(tongue))
            Answer with JSON only: {"title": "...", "look": "...", "place": "...", "wears": "...", "shots": [{"framing": "...", "still": "...", "motion": "...", "narration": "..."}]}
            """
        // Thinking off, and no JSON mode. Measured on kimi: with both on, this
        // request had not answered after three minutes — a model that reasons
        // first does all of it before the first byte when nothing is streamed,
        // and constrained decoding on top of that is slower still. With
        // thinking off and the shape merely asked for, sixteen seconds and a
        // better storyboard than the one written to test the pipeline.
        let body: [String: Any] = [
            "model": model, "stream": false, "think": false,
            "messages": [["role": "system", "content": brief], ["role": "user", "content": ask]],
        ]
        var request = URLRequest(url: url, timeoutInterval: 150)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        // What the server said, not "no usable storyboard": the first failure
        // here was a model the configured host does not have, and the message
        // that hid it cost a round of guessing.
        if let refusal = reply?["error"] as? String {
            throw Failure.message("\(model) @ \(writer.host)：\(refusal.prefix(160))")
        }
        guard let reply,
              let message = reply["message"] as? [String: Any],
              let text = message["content"] as? String,
              // Whatever is between the outermost braces: asked for JSON only,
              // a model still sometimes wraps it in a fence or a sentence.
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let board = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let list = board["shots"] as? [[String: Any]] else {
            throw Failure.message("大脑没给出能用的分镜")
        }
        let written = list.compactMap { Draft($0) }
        guard !written.isEmpty else { throw Failure.message("分镜是空的") }
        return ((board["title"] as? String) ?? "", (board["look"] as? String) ?? "",
                (board["place"] as? String) ?? "", (board["wears"] as? String) ?? "", written)
    }

    /// What the writer is told about the voice-over's language.
    static func voiceOver(_ tongue: String) -> String {
        if tongue == "none" { return "none — this film has no voice-over; leave `narration` out of every shot" }
        if let chosen = tongues.first(where: { $0.tag == tongue }) {
            return "write every narration line in \(chosen.english), whatever language the idea is in"
        }
        return "in the same language as the Idea line above"
    }

    /// Kept for callers that still pass a model; the writer is discovered.
    static var writerModel: String { UserDefaults.standard.string(forKey: "kinclaw.film.writer") ?? "" }

    /// Who writes storyboards: a capable chat model on the Ollama (or kinfer)
    /// the app is pointed at, else on this Mac's own.
    ///
    /// Discovered rather than assumed. There is no one "current brain" to
    /// read — the kernel holds that per soul — and the obvious default, kimi
    /// on this Mac, is not there at all when the app is pointed at a box on
    /// the LAN. So the host is asked what it has. `kinclaw.film.writer` names
    /// one outright for anybody who wants to.
    /// Every host that might have a writer, and what each has that could be one.
    static func candidates() async -> [(host: String, models: [String])] {
        var found: [(String, [String])] = []
        for host in hosts {
            let usable = await models(on: host).filter { name in !never.contains { name.lowercased().contains($0) } }
            if !usable.isEmpty { found.append((host, usable.sorted())) }
        }
        return found
    }

    /// Every Ollama a model can be picked from: the one the app is pointed
    /// at, this Mac's, and the box's. The box's is only ever *offered* — what
    /// is picked automatically (`writer`) still comes from the first two, so
    /// adding a machine to the menus changes nobody's default.
    private static var hosts: [String] {
        var list = [OllamaCatalog.baseURL]
        if !list.contains(OllamaCatalog.defaultBaseURL) { list.append(OllamaCatalog.defaultBaseURL) }
        if let box = BoxServices.ollama, !list.contains(box) { list.append(box) }
        return list
    }

    // Not an embedding model, not a toy, and not the one that starves the box
    // of the memory the video model needs.
    private static let never = ["embed", "bge", "nomic", "0.5b", "bench", "flash-next", "exp-local", "whisper"]

    private static func models(on host: String) async -> [String] {
        guard let url = URL(string: host + "/api/tags") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = list["models"] as? [[String: Any]] else { return [] }
        return entries.compactMap { $0["name"] as? String }
    }

    /// Best first. Not an embedding model, not a toy, and not the one that
    /// starves the box of the memory the video model needs (`never` has those).
    static let families = ["kimi", "glm", "deepseek", "ornith", "qwen", "llama", "gemma", "mistral"]
    static func rank(_ model: String) -> Int {
        families.firstIndex { model.lowercased().contains($0) } ?? families.count
    }

    static func writer() async -> (host: String, model: String)? {
        let named = writerModel
        // Pinned to a host as well as a model: the same name can exist on two
        // machines, and only one of them is the one that was chosen.
        let pinned = UserDefaults.standard.string(forKey: "kinclaw.film.writer.host") ?? ""
        if !named.isEmpty, !pinned.isEmpty, await models(on: pinned).contains(named) { return (pinned, named) }
        var hosts = [OllamaCatalog.baseURL]
        if !hosts.contains(OllamaCatalog.defaultBaseURL) { hosts.append(OllamaCatalog.defaultBaseURL) }
        for host in hosts {
            guard let url = URL(string: host + "/api/tags") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let models = list["models"] as? [[String: Any]] else { continue }
            let names = models.compactMap { $0["name"] as? String }
            if !named.isEmpty, names.contains(named) { return (host, named) }
            let usable = names.filter { name in !never.contains { name.lowercased().contains($0) } }
            for family in families {
                if let pick = usable.first(where: { $0.lowercased().contains(family) }) { return (host, pick) }
            }
            if let any = usable.first { return (host, any) }
        }
        return nil
    }

    // MARK: - Small things

    enum Failure: Error, LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static func slug(_ text: String) -> String {
        let kept = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(kept).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "film" : String(joined.prefix(32))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

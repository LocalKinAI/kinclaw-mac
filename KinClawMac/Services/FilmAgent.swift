import Foundation

/// The Film tab, worked by an agent (see StudioAgent): all of a shot readable,
/// what a director decides settable, and a film carried on from where it
/// stopped to where it should stop next.
///
/// The pipeline was written for a person at the tab. It decided the cast, who
/// is in each shot, what each set shows and what H3 is told, in passes nobody
/// saw — and an agent's shots of a woman walking by the sea came out of them
/// as an empty dress on the sand, twice, while the agent could only press
/// stop. An agent that can look at every picture does better deciding those
/// itself ("之前我们都是写死给人用的，现在要可以灵活由 agent 操作").
extension FilmStudio {
    /// Where `stop_after` may stop: once the sets are drawn, or once every
    /// first frame is made.
    static func hold(_ value: Any?) -> String? {
        switch (value as? String)?.lowercased() {
        case "sets", "set", "pictures", "picture": return "sets"
        case "frames", "frame", "first_frames", "first_frame", "start": return "frames"
        default: return nil
        }
    }

    // MARK: film_shot

    /// Everything about one shot: its words as planned and as used, what the
    /// passes wrote, who is in it, what was given as written, the verdict, its
    /// files with the words each model was actually given, and the pictures —
    /// the set, the first frame, the portraits of who is in it.
    func describeShot(film name: String, shot number: Int) -> Result<(said: String, pictures: [URL]), Failure> {
        guard let film = film(named: name) else { return .failure(.message("没有这部片子：\(name)")) }
        guard let shot = film.shots.first(where: { $0.id == number }) else {
            return .failure(.message("「\(film.title)」没有第 \(number) 镜（有 \(film.shots.count) 镜）"))
        }
        let fm = FileManager.default
        var lines = ["「\(film.title)」\(film.id) 第 \(shot.id) 镜：\(shot.state.rawValue)" + (shot.note.map { " —— \($0)" } ?? "")]
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append("\(label)：\(value)") }
        }
        add("subject（拍的是）", shot.of.rawValue)
        add("framing（镜头）", shot.framing)
        add("still（画面，计划）", shot.still)
        if shot.pose != shot.still { add("画面（实际用的，从上一镜读出来的）", shot.pose) }
        add("motion（动作，计划）", shot.motion)
        if shot.action != shot.motion { add("动作（实际用的，改写过）", shot.action) }
        add("picture（出图用的画面描述；H3 是布景，没有人）", shot.picture)
        if let who = shot.who { lines.append("who（有谁）：" + (who.isEmpty ? "没有人" : who.joined(separator: "、"))) }
        add("h3（H3 拍这一镜用的话）", shot.h3)
        add("照原样用的（你给的）", shot.given?.joined(separator: "、"))
        if shot.posed == true || shot.moved == true {
            lines.append("画面\(shot.posed == true ? "" : "不")照原样，动作\(shot.moved == true ? "" : "不")照原样（照原样的镜头不送去把关）")
        }
        add("旁白", shot.narration)
        add("方向（要求）", shot.wish)
        if let score = shot.score {
            lines.append("把关：\(score)/10" + ((shot.review ?? "").isEmpty ? "" : "，\(shot.review!)"))
        }
        add("把关看到的", shot.saw)
        var pictures: [URL] = []
        for (label, url) in [("布景 / 画面", film.still(shot.id)), ("首帧", film.start(shot.id)),
                             ("拍好的镜头", film.clip(shot.id)), ("上次看的样片", film.sheet(shot.id))]
        where fm.fileExists(atPath: url.path) {
            lines.append("\(label)：\(url.path)")
            // The words the model was given, kept beside what it made.
            if let words = try? String(contentsOf: url.appendingPathExtension("txt"), encoding: .utf8), !words.isEmpty {
                lines.append("  给模型的原话：\(words.prefix(1500))")
            }
            if url.pathExtension == "png" { pictures.append(url) }
        }
        for member in shot.who ?? [] {
            guard let index = film.cast?.firstIndex(where: { $0.name == member }) else { continue }
            let portrait = film.castPicture(index)
            guard fm.fileExists(atPath: portrait.path) else { continue }
            lines.append("演员 \(member) 的定妆照：\(portrait.path)")
            pictures.append(portrait)
        }
        let takes = ((try? fm.contentsOfDirectory(atPath: film.folder.path)) ?? [])
            .filter { $0.hasPrefix(String(format: "shot-%02d.take-", shot.id)) }.sorted()
        if !takes.isEmpty { lines.append("放在一边的旧版本：" + takes.joined(separator: "、")) }
        return .success((lines.joined(separator: "\n"), pictures))
    }

    // MARK: film_edit

    /// Change what a shot is, and let go of what was made from the old words:
    /// set aside as takes (never deleted), to be made again on film_continue.
    /// A new picture, camera or subject redraws the set and the first frame; new
    /// people remake the first frame; new motion or H3 words film it again. H3
    /// words nobody gave are written again for what changed.
    func editShot(film name: String, shot number: Int, subject: String? = nil, framing: String? = nil,
                  still: String? = nil, motion: String? = nil, picture: String? = nil, who: [String]? = nil,
                  h3: String? = nil, narration: String? = nil) -> Result<String, Failure> {
        guard var film = film(named: name) else { return .failure(.message("没有这部片子：\(name)")) }
        guard shooting != film.id, revising == nil else {
            return .failure(.message("「\(film.title)」正在拍或在改：先 film_stop，或者等它停下（film_status wait）"))
        }
        guard let index = film.shots.firstIndex(where: { $0.id == number }) else {
            return .failure(.message("「\(film.title)」没有第 \(number) 镜"))
        }
        var shot = film.shots[index]
        var changed: [String] = []
        func mark(_ field: String) { shot.given = Array(Set(shot.given ?? []).union([field])).sorted() }

        if let subject {
            guard let kind = Subject(rawValue: subject) else { return .failure(.message("subject 只能是 her、figure、thing、place")) }
            shot.subject = kind
            changed.append("subject")
        }
        if let framing { shot.framing = framing; changed.append("framing") }
        if let still { shot.still = still; shot.posed = true; shot.seen = nil; changed.append("still") }
        if let motion { shot.motion = motion; shot.moved = true; shot.played = nil; changed.append("motion") }
        if let picture { shot.picture = picture; mark("picture"); changed.append("picture") }
        if let who {
            let cast = film.cast ?? []
            var named: [String] = []
            for person in who {
                guard let member = Self.member(named: person, in: cast) else {
                    return .failure(.message("「\(person)」不在演员表里" + (cast.isEmpty ? "（还没有演员）" : "（有：\(cast.map(\.name).joined(separator: "、"))）") + "：先 film_cast 加"))
                }
                named.append(member)
            }
            shot.who = named
            mark("who")
            changed.append("who")
        }
        if let h3 {
            let words = h3.trimmingCharacters(in: .whitespacesAndNewlines)
            shot.h3 = words.isEmpty ? nil : words
            if words.isEmpty { shot.given = shot.given?.filter { $0 != "h3" } } else { mark("h3") }
            changed.append("h3")
        }
        if let narration {
            let said = narration.trimmingCharacters(in: .whitespacesAndNewlines)
            shot.narration = said.isEmpty ? nil : said
            changed.append("narration")
        }
        guard !changed.isEmpty else { return .failure(.message("没说要改什么：subject、framing、still、motion、picture、who、h3、narration 至少给一个")) }

        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        var setAside: [String] = []
        func putAway(_ url: URL, _ tag: String, _ what: String) {
            guard fm.fileExists(atPath: url.path) else { return }
            let ext = url.pathExtension
            try? fm.moveItem(at: url, to: film.take(shot.id, "\(tag)-\(stamp)", ext))
            setAside.append(what)
        }
        let story = film.engine == .h3 || film.continuous == false
        let newPicture = picture != nil || still != nil || framing != nil || subject != nil
        // The picture the set was drawn from was written from the old words:
        // written again from the new, unless it is one's own.
        if newPicture, picture == nil, story, !shot.gave("picture") { shot.picture = nil }
        if newPicture {
            putAway(film.still(shot.id), "edit", "布景 / 画面")
            putAway(film.start(shot.id), "edit-start", "首帧")
        } else if who != nil {
            putAway(film.start(shot.id), "edit-start", "首帧")
        }
        // H3 words nobody gave describe what was there before.
        if !shot.gave("h3"), newPicture || who != nil || motion != nil { shot.h3 = nil }
        let refilm = newPicture || who != nil || motion != nil || h3 != nil
        if refilm {
            putAway(film.clip(shot.id), "edit", "拍好的镜头")
            shot.state = .waiting
            shot.score = nil
            shot.review = nil
            shot.saw = nil
        }
        shot.note = nil
        film.shots[index] = shot
        if refilm, film.state == .done || film.state == .failed {
            film.state = .waiting
            film.note = "改了第 \(shot.id) 镜：film_continue 重拍它、再剪"
        }
        save(film)

        var said = "改好了第 \(shot.id) 镜的 " + changed.joined(separator: "、") + "。"
        if !setAside.isEmpty { said += "旧的" + setAside.joined(separator: "、") + "放在一边了（文件名带 take-edit），" }
        said += refilm ? "film_continue 会重做这一镜。" : "不用重拍。"
        if narration != nil, film.voiceover != nil {
            said += "这部片子的旁白是一整段连着念的（voiceover），单镜的旁白不会被念出来。"
        }
        return .success(said)
    }

    // MARK: film_cast

    /// The cast, with their looks and their portraits.
    func describeCast(film name: String) -> Result<(said: String, pictures: [URL]), Failure> {
        guard let film = film(named: name) else { return .failure(.message("没有这部片子：\(name)")) }
        guard let cast = film.cast, !cast.isEmpty else {
            return .success(((film.cast == nil ? "「\(film.title)」还没选角。" : "「\(film.title)」没有演员。")
                             + "film_cast 给 name 和 look 加一个", []))
        }
        var lines = ["「\(film.title)」的演员："]
        var pictures: [URL] = []
        for (index, member) in cast.enumerated() {
            let portrait = film.castPicture(index)
            let drawn = FileManager.default.fileExists(atPath: portrait.path)
            let shots = film.shots.filter { ($0.who ?? []).contains(member.name) }.map { String($0.id) }
            lines.append("\(index + 1). \(member.name)：\(member.look)")
            lines.append("   出现在：" + (shots.isEmpty ? "没有镜头" : "第 " + shots.joined(separator: "、") + " 镜")
                         + (drawn ? "；定妆照 \(portrait.path)" : "；定妆照还没画"))
            if drawn { pictures.append(portrait) }
        }
        return .success((lines.joined(separator: "\n"), pictures))
    }

    /// Add a cast member or change one: a new look draws their portrait again,
    /// a picture given is their portrait as it is. The first frames of their
    /// shots were made from the old portrait and are made again.
    func setCast(film name: String, member: String, look: String?, portrait: String?) -> Result<String, Failure> {
        guard var film = film(named: name) else { return .failure(.message("没有这部片子：\(name)")) }
        guard shooting != film.id, revising == nil else {
            return .failure(.message("「\(film.title)」正在拍或在改：先 film_stop，或者等它停下"))
        }
        let person = member.trimmingCharacters(in: .whitespaces)
        guard !person.isEmpty else { return .failure(.message("film_cast 要 name")) }
        var cast = film.cast ?? []
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        var said: [String] = []
        let index: Int
        if let known = Self.member(named: person, in: cast).flatMap({ found in cast.firstIndex { $0.name == found } }) {
            index = known
            if let look = look?.trimmingCharacters(in: .whitespacesAndNewlines), !look.isEmpty, look != cast[index].look {
                cast[index].look = look
                said.append("改了 \(cast[index].name) 的样子")
                if portrait == nil, fm.fileExists(atPath: film.castPicture(index).path) {
                    try? fm.moveItem(at: film.castPicture(index),
                                     to: film.folder.appendingPathComponent(String(format: "cast-%02d.take-%d.png", index + 1, stamp)))
                    said.append("旧定妆照放在一边，会重画")
                }
            }
        } else {
            let described = look?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !described.isEmpty || portrait != nil else {
                return .failure(.message("「\(person)」不在演员表里：加新演员要给 look（相貌、发型、身材、穿着，英文 40–70 词）或者 portrait"))
            }
            guard cast.count < 4 else { return .failure(.message("最多 4 个演员（H3 一镜最多 9 张参考图）")) }
            cast.append(Cast(name: person, look: described))
            index = cast.count - 1
            said.append("加了演员 \(person)")
        }
        if let portrait {
            let source = URL(fileURLWithPath: (portrait as NSString).expandingTildeInPath)
            guard fm.fileExists(atPath: source.path) else { return .failure(.message("没有这张图：\(portrait)")) }
            if fm.fileExists(atPath: film.castPicture(index).path) {
                try? fm.moveItem(at: film.castPicture(index),
                                 to: film.folder.appendingPathComponent(String(format: "cast-%02d.take-%d.png", index + 1, stamp)))
            }
            do { try fm.copyItem(at: source, to: film.castPicture(index)) } catch {
                return .failure(.message("定妆照放不进去：\(error.localizedDescription)"))
            }
            said.append("用这张图当 \(cast[index].name) 的定妆照")
        }
        film.cast = cast
        // Their shots' first frames came from the old portrait.
        var remade: [String] = []
        for i in film.shots.indices where (film.shots[i].who ?? []).contains(cast[index].name) && film.shots[i].state != .done {
            let start = film.start(film.shots[i].id)
            if fm.fileExists(atPath: start.path) {
                try? fm.moveItem(at: start, to: film.take(film.shots[i].id, "cast-\(stamp)", "png"))
                remade.append(String(film.shots[i].id))
            }
        }
        save(film)
        if !remade.isEmpty { said.append("第 " + remade.joined(separator: "、") + " 镜的首帧会重做") }
        return .success(said.joined(separator: "；") + "。film_continue 接着拍")
    }
}

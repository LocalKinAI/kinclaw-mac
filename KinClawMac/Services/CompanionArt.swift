import Foundation
import AppKit

/// The pictures — and clips — behind companion mode: what is on disk,
/// and how to get more without leaving the app.
///
/// Art lives in `~/.kinclaw/companion/`. Anything dropped at the top
/// level is used as-is and rotated through. A subfolder named for a
/// state (`idle`, `listening`, `thinking`, `speaking`) or a mood
/// (`happy`, `gentle`, `curious`, `sleepy`, `worried` — or their
/// Chinese tag words) holds art for that state or mood; the view picks
/// from it when the companion is in it. Top-level files *named* for a
/// state still work, from before folders. Short video loops (mp4 / mov
/// / m4v) count as art everywhere a picture does.
@MainActor
final class CompanionArt: ObservableObject {

    /// One downloadable picture or clip with the credit it came with.
    struct Candidate: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let credit: String
        /// Small still to show in the grid; for clips, Pexels' poster frame.
        let preview: URL
        let isVideo: Bool
        let seconds: Int?
    }

    enum MediaKind: String, CaseIterable {
        case photo = "图片"
        case video = "视频"
    }

    static let stateKeys = ["idle", "listening", "thinking", "speaking"]

    @Published private(set) var pool: [URL] = []
    /// Every file's keywords, for matching against what is being
    /// talked about. Built from the filename and the credit line, both
    /// of which already describe the picture: art arrives named for the
    /// search that found it — `corgi-dog-enjoying-the-beach-25174.mp4`,
    /// `kitten-walking-alone-26370.mp4` — and the sidecar .txt carries
    /// the source's own title. Nothing had to be added to the format;
    /// the description was there all along, unread.
    private var keywords: [URL: Set<String>] = [:]
    /// State or mood key → files in its folder.
    @Published private(set) var groups: [String: [URL]] = [:]
    @Published private(set) var fetching = false
    @Published var lastError: String?

    static let folderKey = "kinclaw.companion.folder"
    static let pexelsKeyKey = "kinclaw.companion.pexelsKey"

    /// Where the art lives. Overridable so a user can point at an
    /// existing wallpaper folder instead of copying files around.
    static var folder: URL {
        if let custom = UserDefaults.standard.string(forKey: folderKey), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/companion")
    }

    /// A theme is a sibling folder: `~/.kinclaw/companion` (the default)
    /// and any `~/.kinclaw/companion-<name>/` next to it, so a shiba set,
    /// a kitten set and a portrait set can live side by side and be
    /// switched from the companion view rather than by retyping a path.
    struct Theme: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { url.path }
    }

    /// The drive a folder lives on, when that drive is not mounted — as a
    /// sentence to show, or nil when there is nothing wrong.
    ///
    /// The art folder is settable to anywhere, and "anywhere" is usually a
    /// big external disk, which is exactly the kind that is not plugged in
    /// on a Tuesday. Unasked, that looks like "she has no pictures" and
    /// like an unreadable write error; asked, it is one sentence naming the
    /// drive to plug in. A missing folder on a mounted disk is not trouble —
    /// it is made on first write.
    static func unreachableVolume(_ url: URL) -> String? {
        if FileManager.default.fileExists(atPath: url.path) { return nil }
        let parts = url.pathComponents
        guard parts.count > 2, parts[1] == "Volumes" else { return nil }
        let drive = parts[2]
        return FileManager.default.fileExists(atPath: "/Volumes/" + drive)
            ? nil : "「\(drive)」这个盘没挂上——图片和视频都在它上面"
    }

    /// The same, for wherever the art currently lives.
    static var folderTrouble: String? { unreachableVolume(folder) }

    /// How many pictures and clips are on disk, without a view.
    ///
    /// The published `count` belongs to whoever is showing them; a tool that
    /// answers "how many does she have" should not need one to exist.
    static func countOnDisk() -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return 0 }
        var total = 0
        for n in names where !n.hasPrefix(".") {
            let url = folder.appendingPathComponent(n)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                guard groupKey(for: n) != nil,
                      let inner = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
                total += inner.filter { !$0.hasPrefix(".") && isMedia(url.appendingPathComponent($0)) }.count
            } else if isMedia(url) {
                total += 1
            }
        }
        return total
    }

    /// The scenes on disk, without a view — the same list the tools answer
    /// with, read straight from the folder.
    static func scenesOnDisk() -> [String] {
        let root = folder.appendingPathComponent("scenes")
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted().filter { name in
            guard !name.hasPrefix(".") else { return false }
            let dir = root.appendingPathComponent(name)
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return files.contains { $0.lowercased().hasPrefix("wait") || $0.lowercased().hasPrefix("talk") }
        }
    }

    /// Places that are the same footage under two names.
    ///
    /// A scene is a folder, and nothing checks that what is in the folder is
    /// the place on its label. Two folders with one picture in them look, from
    /// the chair, exactly like a switch that does not work — she goes to the
    /// park and the kitchen is still on screen — and no amount of reading the
    /// decision code finds it, because the decision was right. Bytes are cheap
    /// to compare, so the tools say so.
    static func twinScenes() -> [(String, String)] {
        let root = folder.appendingPathComponent("scenes")
        var seen: [Data: String] = [:]
        var twins: [(String, String)] = []
        for name in scenesOnDisk() {
            let dir = root.appendingPathComponent(name)
            for file in ["still.png", "wait.mp4"] {
                guard let bytes = try? Data(contentsOf: dir.appendingPathComponent(file)) else { continue }
                if let first = seen[bytes] { twins.append((first, name)) } else { seen[bytes] = name }
                break
            }
        }
        return twins
    }

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kinclaw/companion")
    }

    static func themes() -> [Theme] {
        let base = defaultFolder.deletingLastPathComponent()
        var out = [Theme(name: "默认", url: defaultFolder)]
        if let names = try? FileManager.default.contentsOfDirectory(atPath: base.path) {
            for n in names.sorted() where n.hasPrefix("companion-") {
                let u = base.appendingPathComponent(n)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    out.append(Theme(name: String(n.dropFirst("companion-".count)), url: u))
                }
            }
        }
        // A custom folder set in Settings that is none of the above still
        // deserves a name in the menu.
        let current = folder
        if !out.contains(where: { $0.url.path == current.path }) {
            out.append(Theme(name: current.lastPathComponent, url: current))
        }
        return out
    }

    /// Switch the active folder and re-read it. The default clears the
    /// override rather than pinning its path, so moving home keeps working.
    func useTheme(_ theme: Theme) {
        if theme.url.path == Self.defaultFolder.path {
            UserDefaults.standard.removeObject(forKey: Self.folderKey)
        } else {
            UserDefaults.standard.set(theme.url.path, forKey: Self.folderKey)
        }
        reload()
    }

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "bmp"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isMedia(_ url: URL) -> Bool {
        let e = url.pathExtension.lowercased()
        return imageExtensions.contains(e) || videoExtensions.contains(e)
    }

    /// A folder or file name → the state/mood it belongs to, if any.
    /// `happy`, `开心` and `speaking` all resolve; `shiba-3` does not.
    static func groupKey(for name: String) -> String? {
        let n = name.lowercased()
        if stateKeys.contains(n) { return n }
        return CompanionMood.parse(n)?.rawValue
    }

    /// Re-read the folder. Cheap; called on appear and after a fetch.
    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        guard let names = try? fm.contentsOfDirectory(atPath: Self.folder.path) else {
            pool = []; groups = [:]; return
        }
        var found: [String: [URL]] = [:]
        var general: [URL] = []
        for n in names.sorted() where !n.hasPrefix(".") {
            let url = Self.folder.appendingPathComponent(n)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                guard let key = Self.groupKey(for: n),
                      let inner = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
                for f in inner.sorted() where !f.hasPrefix(".") {
                    let u = url.appendingPathComponent(f)
                    if Self.isMedia(u) { found[key, default: []].append(u) }
                }
                continue
            }
            guard Self.isMedia(url) else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            if let key = Self.groupKey(for: base) {
                found[key, default: []].append(url)
            } else {
                general.append(url)
            }
        }
        groups = found
        pool = general
        indexKeywords()
        loadScenes()
    }

    /// Words that describe each file. Split on the separators filenames
    /// use, drop the noise (ids, dimensions, one-letter fragments) and
    /// the words every file shares, which carry no signal.
    private func indexKeywords() {
        var idx: [URL: Set<String>] = [:]
        var all: [URL] = pool
        for (_, urls) in groups { all += urls }
        for url in all {
            var words = Set<String>()
            let name = url.deletingPathExtension().lastPathComponent
            var text = name
            // The credit line names the picture in the source's words:
            // "Wikimedia Commons · Shiba inu puppy and adult.jpg · CC0".
            if let credit = try? String(contentsOf: url.appendingPathExtension("txt"),
                                        encoding: .utf8) {
                text += " " + credit
            }
            for raw in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
                let w = String(raw)
                if w.count < 3 || Self.stopWords.contains(w) { continue }
                words.insert(w)
            }
            idx[url] = words
        }
        keywords = idx
    }

    /// Words that appear in nearly every file's name or credit, and so
    /// separate nothing. Without this, "commons" matches everything
    /// from Wikimedia and the subject stops meaning anything.
    private static let stopWords: Set<String> = [
        "jpg", "jpeg", "png", "mp4", "mov", "webp", "heic",
        "wikimedia", "commons", "pexels", "mixkit", "unknown",
        "free", "license", "attribution", "required", "photo", "video",
        "the", "and", "with", "her", "his", "its", "for", "from",
        "idle", "listening", "thinking", "speaking",
        "happy", "gentle", "curious", "sleepy", "worried",
    ]

    // MARK: - Scenes

    /// A place she is in, with a clip for waiting and a clip for talking.
    ///
    /// The flat folders answer "what fits this mood", which is right for
    /// photographs and wrong for a person: a reply that waits in a kitchen
    /// and answers from a night market is two different evenings. A scene
    /// holds both clips in one place, so between them only her state changes
    /// — she is smiling at you, she speaks, she goes back to waiting — and
    /// the place changes only when the conversation goes somewhere else.
    ///
    /// On disk:
    ///
    ///     <art folder>/scenes/<name>/
    ///         wait.mp4     she looks at you, smiling, waiting
    ///         talk.mp4     she speaks, same place, same clothes
    ///         still.png    the frame both were animated from
    ///         plate.png    the same place with nobody in it — what the 3D
    ///                      companion stands in front of
    ///         about.txt    words the conversation might use for this place
    struct Scene: Equatable, Identifiable {
        let name: String
        let wait: URL?
        let talk: URL?
        /// The place without her. The clips have the generated woman in
        /// them, and a 3D character in front of those is two people.
        var plate: URL? = nil
        /// The same place from further back, at eye level, with ground in the
        /// lower half — somewhere to walk, where the plate is only somewhere
        /// to stand.
        var wide: URL? = nil

        /// Out of doors, as far as its own words say. It decides how far away
        /// she may wander: down a path until she is small, but not through
        /// the back wall of a kitchen. Wrong in the safe direction — a place
        /// not recognised is a room.
        var isOutdoors: Bool {
            let open: Set<String> = ["park", "beach", "forest", "street", "market", "mountain", "snow", "garden",
                "field", "lake", "river", "sea", "seaside", "desert", "road", "trail", "rain", "square", "bridge",
                "meadow", "harbor", "harbour", "campsite", "camp", "公园", "海边", "沙滩", "夜市", "雨天", "森林",
                "街", "山", "湖", "田野", "草地", "花园"]
            return !open.isDisjoint(with: words + names)
        }
        /// Topic words, for a reply's subject tag: kitchen, coffee, 咖啡.
        let words: [String]
        /// What a person calls the place out loud: 厨房, kitchen. Kept apart
        /// from `words` because those are loose on purpose — 早上 and 晚上 are
        /// fine as hints from a tag, and would teleport her around the house
        /// if they were matched against everything the user says.
        let names: [String]
        var id: String { name }

        func clip(for state: String) -> URL? {
            state == "speaking" ? (talk ?? wait) : (wait ?? talk)
        }

        /// Whether there is anything to show here. A place is two different
        /// sets of files depending on who is standing in it: clips of her for
        /// the filmed companion, an empty plate for the 3D one.
        func usable(in3D: Bool) -> Bool {
            in3D ? plate != nil : (wait != nil || talk != nil)
        }
    }

    /// The 3D companion is the one on screen, so places are plates rather
    /// than clips. Set by the view, which is the only thing that knows.
    var stage3D = false {
        didSet { if stage3D != oldValue { objectWillChange.send() } }
    }

    /// Which scene she goes back to. Empty means the first one found.
    static let mainSceneKey = "kinclaw.companion.scene.main"

    @Published private(set) var scenes: [Scene] = []
    /// The place she is in now.
    @Published private(set) var scene: Scene?
    /// Replies since the conversation last pointed at a place. Two of them
    /// and she goes home: one reply that mentions nothing is normal in the
    /// middle of a topic, three in a row means the topic moved on.
    private var repliesAwayFromHome = 0

    /// How many replies in a row have named nowhere. Two and she goes home.
    var repliesAwayFromHomeCount: Int { repliesAwayFromHome }
    /// The last few clips the picker handed out, newest first, one entry per
    /// change. Diagnostics only: when she will not leave a place, the question
    /// is always what was actually put on screen, and nothing else in the
    /// chain records it.
    private(set) var shown: [String] = []
    /// What the last ask returned. "Which file is she showing" has no other
    /// answer from outside the view, and it is the question that separates a
    /// selection that did not change from a picture that did not.
    private(set) var lastPicked: URL?

    var mainScene: Scene? {
        let wanted = UserDefaults.standard.string(forKey: Self.mainSceneKey) ?? ""
        return scenes.first { $0.name == wanted } ?? scenes.first
    }

    /// Scan `scenes/`. Called by reload, so it follows the art folder.
    private func loadScenes() {
        let fm = FileManager.default
        let root = Self.folder.appendingPathComponent("scenes")
        var found: [Scene] = []
        for name in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        where !name.hasPrefix(".") {
            let dir = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: dir.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            func find(_ stem: String) -> URL? {
                files.first { $0.lowercased().hasPrefix(stem) && Self.isVideo(dir.appendingPathComponent($0)) }
                    .map { dir.appendingPathComponent($0) }
            }
            let about = (try? String(contentsOf: dir.appendingPathComponent("about.txt"),
                                     encoding: .utf8)) ?? ""
            // Line one: the place's names, comma-separated, as spoken.
            let firstLine = about.components(separatedBy: .newlines).first ?? ""
            let spoken = firstLine.contains(",") || firstLine.contains("，")
                ? firstLine.components(separatedBy: CharacterSet(charactersIn: ",，、"))
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                : []
            let words = (about + " " + name).lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                // Two characters is a word in Chinese — 厨房, 海边 — and a
                // three-character floor threw every one of them away, so a
                // scene could never be reached by its own name.
                .filter { word in
                    guard !Self.stopWords.contains(word) else { return false }
                    return word.allSatisfy(\.isASCII) ? word.count >= 3 : word.count >= 2
                }
            let plate = files.first { $0.lowercased().hasPrefix("plate") && !Self.isVideo(dir.appendingPathComponent($0))
                                      && Self.isMedia(dir.appendingPathComponent($0)) }
                .map { dir.appendingPathComponent($0) }
            let wide = files.first { $0.lowercased().hasPrefix("wide") && !Self.isVideo(dir.appendingPathComponent($0))
                                     && Self.isMedia(dir.appendingPathComponent($0)) }
                .map { dir.appendingPathComponent($0) }
            let scene = Scene(name: name, wait: find("wait"), talk: find("talk"), plate: plate, wide: wide,
                              words: words, names: spoken + [name.lowercased()])
            if scene.wait != nil || scene.talk != nil || scene.plate != nil { found.append(scene) }
        }
        scenes = found
        assignKeys()
        // A place she was waiting for has landed: she walks in. The builder
        // names the folder after the word that asked for it, so this is an
        // exact match — a loose one would have matched before anything was
        // built, and there would have been nothing to wait for.
        if let wanted = awaiting,
           let built = found.first(where: { $0.name.lowercased() == wanted && $0.usable(in3D: stage3D) }) {
            awaiting = nil
            repliesAwayFromHome = 0
            scene = built
            return
        }
        // Re-read where she is rather than keep the copy from the last scan:
        // a place is usable the moment its wait clip lands, and the talk clip
        // that arrives a minute later is only in the new copy.
        let here = found.first { $0.name == scene?.name } ?? mainScene
        if here != scene { scene = here }
    }

    // MARK: - What the model is told

    /// The one English word the model writes for each place, keyed by scene
    /// name. A spoken name from `about.txt` that is a single English word —
    /// "park", "beach" — else the folder's own name when she had the place
    /// built ("forest"), else the first topic word nobody else has claimed.
    private(set) var keys: [String: String] = [:]

    private func assignKeys() {
        var byScene: [String: String] = [:]
        var taken = Set<String>()
        func single(_ w: String) -> Bool { w.count >= 3 && w.allSatisfy { $0.isASCII && $0.isLetter } }
        for s in scenes {
            let candidates = s.names.filter(single) + s.words.filter(single)
            if let key = candidates.first(where: { !taken.contains($0) }) {
                taken.insert(key)
                byScene[s.name] = key
            }
        }
        keys = byScene
    }

    /// One line sent under the user's words: where she is, which places she
    /// has, and what is being built.
    ///
    /// Without it the model tags blind. It cannot know she has a park and no
    /// forest, so its subject is a guess matched against word lists, and the
    /// only switch that works reliably is the user saying "去公园" out loud.
    /// With it the tag names a real place, and the picture follows the
    /// conversation by itself — tired, and she is on the sofa; hungry, the
    /// kitchen — which is the whole point of her having places.
    func placesCue(building: String?) -> String? {
        guard !scenes.isEmpty, let here = scene ?? mainScene else { return nil }
        let list = scenes.compactMap { s in keys[s.name].map { "\($0)=\(s.name)" } }
        guard !list.isEmpty else { return nil }
        let home = mainScene?.name ?? here.name
        var line = here.name == home
            ? "(场景线索:你现在在「\(here.name)」,这是主场景。"
            : "(场景线索:你现在在「\(here.name)」,主场景是「\(home)」。"
        line += "你有的地方:\(list.joined(separator: "、"))。"
        // The rule rides along with the list. In the soul alone it lost to the
        // soul's own older examples — a story about a dog came back tagged
        // `dog`, which is a four-minute build of a place that is not a place.
        line += "主题词只写地方:这一句落在哪个地方就写等号左边那个词;还在聊这儿的事就接着写这儿;"
              + "这儿的话题聊完了就回主场景;真去了单子外的新地方才写新词;聊的是东西不是地方就不换地方。"
        if let b = building ?? awaiting {
            line += "「\(b)」正在造,还没好:造好之前你就留在这儿,别换地方、别回主场景、也别要别的新地方;造好了画面自己切过去。"
        }
        return line + ")"
    }

    /// Long enough to name a place: three characters of English, two of
    /// Chinese — 厨房 is two, and the old three-character rule meant she could
    /// never be sent anywhere by its Chinese name.
    static func longEnough(_ subject: String) -> Bool {
        subject.allSatisfy(\.isASCII) ? subject.count >= 3 : subject.count >= 2
    }

    /// Move her to a named place, or back to the main one with "".
    ///
    /// The conversation moves her by subject; this is for being told
    /// directly — "go to the park" — and for finding out whether a scene
    /// switch works at all when the subject matching is in question.
    @discardableResult
    func goTo(_ name: String) -> Scene? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        if wanted.isEmpty { scene = mainScene; repliesAwayFromHome = 0; repeatsHere = 0; return scene }
        guard let found = scenes.first(where: { $0.name == wanted })
            ?? scenes.first(where: { $0.name.localizedCaseInsensitiveContains(wanted) })
            ?? scenes.first(where: { $0.words.contains(where: { $0.hasPrefix(wanted.lowercased()) }) })
        else { return nil }
        scene = found
        repliesAwayFromHome = 0
        repeatsHere = 0
        // Told to go, she goes — and the half of the place this companion
        // needs is made behind her if it is missing.
        if !found.usable(in3D: stage3D) {
            CompanionCharacter.shared.wantScene(found.name, plateOnly: stage3D)
        }
        return found
    }

    /// What she would match for a subject, without moving her. The tool that
    /// reports this is how "why did she not go to the park" gets answered.
    func sceneMatching(_ subject: String) -> Scene? {
        let s = subject.trimmingCharacters(in: .whitespaces).lowercased()
        guard Self.longEnough(s) else { return nil }
        // The word she was told to use for a place is that place, whatever
        // else it happens to be a prefix of.
        if let named = keys.first(where: { $0.value == s })?.key {
            return scenes.first { $0.name == named }
        }
        return scenes.first { $0.words.contains(s) }
            ?? scenes.first { $0.words.contains { $0.hasPrefix(s) || s.hasPrefix($0) } }
    }

    // MARK: - Where the conversation puts her
    //
    // Two events decide it, and the picker only reads the result.
    //
    // It used to be decided inside the picker, at the moment her state
    // turned to "speaking", from the subject of the reply's tag. Both halves
    // of that failed in practice. The tag: a model follows its own history,
    // so once one reply said `[温柔·beach]` every reply did — three in a row,
    // measured — and she lived at the beach whatever the soul's rules said.
    // The moment: twelve consecutive asks came through without one
    // "speaking" among them, so the decision point simply never arrived.
    //
    // Now what the *user* says moves her directly, before the model has
    // answered at all, and a tag only moves her when it changes — while one
    // that names the place she is already in keeps her there.

    /// A place the conversation asked for that does not exist yet. It is
    /// being built in the background, and until it lands she stays in the
    /// scene she is in — not the main one. When it lands she goes there,
    /// unless the user has taken her somewhere else in the meantime.
    private(set) var awaiting: String?
    /// Replies in a row that did nothing but name the place she is already
    /// in. The user naming it starts the count again.
    private var repeatsHere = 0
    /// The user already said where, this turn.
    private var heardPlaceThisTurn = false
    /// The previous reply's subject. A repeat carries no information.
    private var lastReplySubject = ""

    /// What the user just said. If it names one of her places she goes there
    /// now; "回家" and "go home" send her to the main one.
    @discardableResult
    func hear(_ utterance: String) -> Scene? {
        guard !scenes.isEmpty else { return nil }
        let text = utterance.lowercased()
        if ["回家", "回去吧", "回主场景", "go home", "back home"].contains(where: text.contains) {
            heardPlaceThisTurn = true
            awaiting = nil
            repeatsHere = 0
            return goTo("")
        }
        for candidate in scenes {
            let hit = candidate.names.contains { name in
                // Chinese has no spaces, so containment; English by whole
                // word, or "sea" would fire on "season".
                name.allSatisfy(\.isASCII)
                    ? text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b",
                                 options: .regularExpression) != nil
                    : text.contains(name)
            }
            if hit {
                heardPlaceThisTurn = true
                repliesAwayFromHome = 0
                repeatsHere = 0
                // She has the place, but not the half of it this companion
                // needs — clips made while she was 3D, or a plate never made
                // because she never was. Ordered, and she waits where she is.
                if !candidate.usable(in3D: stage3D) {
                    awaiting = CompanionCharacter.shared.wantScene(candidate.name, plateOnly: stage3D)
                        ? candidate.name.lowercased() : nil
                    return nil
                }
                if candidate.name != scene?.name { scene = candidate }
                awaiting = nil
                return candidate
            }
        }
        return nil
    }

    /// A reply's tag arrived — or the reply turned out to have none, which
    /// is "" and counts the same as a tag that names nowhere.
    func replyTagged(subject raw: String) {
        guard !scenes.isEmpty else { return }
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        defer { heardPlaceThisTurn = false; lastReplySubject = s }
        // The user said where; whatever the model tagged, they win.
        if heardPlaceThisTurn { return }
        // While a place is on order she stays exactly where she is: no tag
        // moves her and nothing counts toward going home. A wait that changes
        // the picture twice is not a wait, and the new place should cut in
        // from the room the conversation was actually in. Only the user's own
        // words move her meanwhile. The builder going idle without the place
        // having landed means it gave up; then nothing is coming and the
        // ordinary rules apply again.
        if awaiting != nil {
            if CompanionCharacter.shared.building != nil { return }
            awaiting = nil
        }
        // Only a subject that *changed* can move her. A model repeats its
        // last tag for as long as the history shows it, and a repeat must not
        // drag her back to a place the user has since led her away from.
        let fresh = Self.longEnough(s) && s != lastReplySubject
        if Self.longEnough(s), let match = sceneMatching(s) {
            // A repeat that names where she already is, though, is the model
            // saying "still here". Counting it as a reply about nowhere sent
            // her home in the middle of a conversation about the leaves.
            if match.name == (scene ?? mainScene)?.name {
                // Believed for a while, not forever. A small local brain
                // repeats its last tag until the history scrolls away, and
                // "she went to the beach once and lived there" is the bug
                // this file has been fixed for more times than any other.
                // Six replies is a long visit; past that a repeat counts as
                // a reply about nowhere, and two of those take her home.
                repeatsHere += 1
                if repeatsHere <= 6 || match.name == mainScene?.name {
                    repliesAwayFromHome = 0
                    return
                }
            } else if fresh {
                repliesAwayFromHome = 0
                repeatsHere = 0
                if match.usable(in3D: stage3D) {
                    scene = match
                } else if CompanionCharacter.shared.wantScene(match.name, plateOnly: stage3D) {
                    awaiting = match.name.lowercased()
                }
                return
            }
        }
        if fresh {
            // Somewhere she has never been: made once, in the background,
            // while she waits where she is. Remembered only when the builder
            // took the order — it makes one place at a time.
            // The reply that orders a place is not a reply about nowhere.
            if CompanionCharacter.shared.wantScene(s, plateOnly: stage3D) { awaiting = s; return }
        }
        repliesAwayFromHome += 1
        if repliesAwayFromHome >= 2, let home = mainScene, home.name != scene?.name {
            scene = home
            repliesAwayFromHome = 0
            repeatsHere = 0
        }
    }

    /// The clip for this moment, when she lives in scenes. Reads where she
    /// is; does not decide it.
    func sceneArt(for state: String, subject: String) -> URL? {
        guard !scenes.isEmpty else { return nil }
        let here = scene ?? mainScene
        // The 3D companion stands in front of the empty place. Without a
        // plate yet she gets the clip, which is wrong in the way it always
        // was — two of her — and is replaced the moment the plate lands.
        let clip = stage3D ? (here?.plate ?? here?.clip(for: state)) : here?.clip(for: state)
        // Only changes: the microphone opening and closing asks several times
        // a second for the same clip, and twelve of those told nobody whether
        // she had ever been shown talking.
        let label = clip.map { $0.deletingLastPathComponent().lastPathComponent
                             + "/" + $0.deletingPathExtension().lastPathComponent } ?? "—"
        if shown.first?.hasSuffix(" " + label) != true {
            let time = Date().formatted(date: .omitted, time: .standard)
            shown.insert("\(time) \(label)", at: 0)
            shown = Array(shown.prefix(16))
        }
        return clip
    }

    /// True when any group has art beyond the rotating pool — the view
    /// then swaps on every state and mood change rather than on a timer.
    var hasGroups: Bool { !groups.isEmpty }

    /// The art for a moment. While the companion speaks, its mood wins
    /// over the generic "speaking" art; the rest of the time the state
    /// wins, since "listening" is about you, not about how it feels.
    /// Then the caller's current picture, then the pool.
    func art(for state: String, mood: CompanionMood?, fallback: URL?) -> URL? {
        art(for: state, mood: mood, subject: "", fallback: fallback)
    }

    /// The art for a moment.
    ///
    /// Subject first when the reply named one and something on disk
    /// matches it: a picture of what you are talking about beats a
    /// picture of how it feels about it. Then mood while it speaks, then
    /// state — "listening" is about you, not about the subject — then
    /// whatever is already showing, then the pool.
    ///
    /// A subject with no match on disk changes nothing rather than
    /// picking at random: a wrong picture claimed with confidence is
    /// worse than the one already there.
    func art(for state: String, mood: CompanionMood?, subject: String, fallback: URL?) -> URL? {
        // Scenes win when she has any: staying in one place through a whole
        // exchange is the difference between a companion and a slideshow.
        if let inScene = sceneArt(for: state, subject: subject) {
            lastPicked = inScene
            return inScene
        }
        if let m = bestMatch(for: subject, mood: mood) { lastPicked = m; return m }
        let stateArt = groups[state]?.randomElement()
        let moodArt = mood.flatMap { groups[$0.rawValue]?.randomElement() }
        let preferred = state == "speaking" ? (moodArt ?? stateArt) : (stateArt ?? moodArt)
        let answer = preferred ?? fallback ?? pool.randomElement() ?? groups.values.first?.first
        lastPicked = answer
        return answer
    }

    /// The file whose keywords best fit the subject, or nil when
    /// nothing does. Scored rather than filtered so "beach" prefers a
    /// beach in the current mood's folder over a beach anywhere, and
    /// exactness beats prefix so "cat" does not lose to "caterpillar".
    func bestMatch(for subject: String, mood: CompanionMood?) -> URL? {
        let s = subject.trimmingCharacters(in: .whitespaces).lowercased()
        guard s.count >= 3 else { return nil }
        let moodFolder = mood.map { groups[$0.rawValue] ?? [] } ?? []
        var best: (url: URL, score: Int)?
        for (url, words) in keywords {
            var score = 0
            if words.contains(s) {
                score = 3
            } else if words.contains(where: { $0.hasPrefix(s) || s.hasPrefix($0) }) {
                score = 1
            }
            guard score > 0 else { continue }
            if moodFolder.contains(url) { score += 1 }
            if best == nil || score > best!.score { best = (url, score) }
        }
        return best?.url
    }

    /// True when nothing on disk is about this subject — the caller
    /// uses it to decide whether going to fetch one is worth it.
    func hasNothingAbout(_ subject: String) -> Bool {
        bestMatch(for: subject, mood: nil) == nil
    }

    var isEmpty: Bool { pool.isEmpty && groups.isEmpty }

    var count: Int { pool.count + groups.values.reduce(0) { $0 + $1.count } }

    /// True when this theme is mostly moving pictures, so anything
    /// fetched to join it should move too.
    var mostlyVideo: Bool {
        var all = pool
        for (_, urls) in groups { all += urls }
        guard !all.isEmpty else { return false }
        let videos = all.filter { Self.isVideo($0) }.count
        return videos * 2 > all.count
    }

    // MARK: - Fetching

    /// Search for pictures or clips. Pexels when a key is configured
    /// (bigger, better, no attribution required, and the only one of
    /// the two with video), Wikimedia Commons otherwise — it needs no
    /// key at all, so companion mode works on a machine that has never
    /// been configured.
    func search(_ query: String, kind: MediaKind = .photo, limit: Int = 12) async -> [Candidate] {
        let key = UserDefaults.standard.string(forKey: Self.pexelsKeyKey) ?? ""
        if kind == .video {
            guard !key.isEmpty else { return [] }
            return (try? await pexelsVideos(query, limit: limit, key: key)) ?? []
        }
        if !key.isEmpty {
            if let r = try? await pexels(query, limit: limit, key: key), !r.isEmpty { return r }
        }
        return (try? await wikimedia(query, limit: limit)) ?? []
    }

    /// Download the chosen art into the companion folder — into the
    /// state/mood subfolder when `group` names one. Filenames carry the
    /// query so a folder of mixed themes stays legible, and the credit
    /// line is written alongside as .txt for the CC-licensed ones.
    func download(_ candidates: [Candidate], theme: String, group: String = "") async {
        fetching = true
        defer { fetching = false; reload() }
        let fm = FileManager.default
        let dest = group.isEmpty ? Self.folder : Self.folder.appendingPathComponent(group)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let slug = theme.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        for (i, c) in candidates.enumerated() {
            do {
                let (data, _) = try await URLSession.shared.data(from: c.url)
                let ext: String
                if c.isVideo {
                    // A clip that small is a thumbnail-sized encode.
                    guard data.count > 200_000 else { continue }
                    ext = "mp4"
                } else {
                    // A 400px thumbnail looks like a smear once it fills a
                    // window; search results happily return them.
                    guard let img = NSImage(data: data), img.size.width >= 900 else { continue }
                    ext = c.url.pathExtension.isEmpty ? "jpg" : c.url.pathExtension
                }
                let name = "\(slug.isEmpty ? "art" : slug)-\(Int(Date().timeIntervalSince1970))-\(i).\(ext)"
                try data.write(to: dest.appendingPathComponent(name))
                if !c.credit.isEmpty {
                    try? c.credit.write(
                        to: dest.appendingPathComponent(name + ".txt"),
                        atomically: true, encoding: .utf8)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Go and find art for a subject nothing on disk covers, so the
    /// next time it comes up there is something.
    ///
    /// Not on the first mention: most subjects pass through a
    /// conversation once and fetching for each would be a download per
    /// sentence. A subject earns a fetch by coming back — which is also
    /// what makes it worth having a picture of.
    ///
    /// Silent either way. It is for later, and a spinner over someone's
    /// dog to announce a background download is worse than the download.
    func prefetch(subject: String, wantVideo: Bool) {
        let s = subject.trimmingCharacters(in: .whitespaces).lowercased()
        guard s.count >= 3, !prefetched.contains(s), hasNothingAbout(s) else { return }
        prefetched.insert(s)
        Task { [weak self] in
            guard let self else { return }
            let kind: MediaKind = wantVideo ? .video : .photo
            var found = await self.search(s, kind: kind, limit: 4)
            if found.isEmpty, kind == .video {
                // Video needs a Pexels key; a photo does not. Better the
                // right subject as a still than the wrong one moving.
                found = await self.search(s, kind: .photo, limit: 4)
            }
            guard !found.isEmpty else { return }
            await self.download(Array(found.prefix(2)), theme: s)
        }
    }

    /// Subjects already looked for this session, so a topic that keeps
    /// coming up is not fetched again every time it does.
    private var prefetched: Set<String> = []

    func revealFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.folder])
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("txt"))
        reload()
    }

    // MARK: - Sources

    private func pexels(_ query: String, limit: Int, key: String) async throws -> [Candidate] {
        var c = URLComponents(string: "https://api.pexels.com/v1/search")!
        c.queryItems = [.init(name: "query", value: query),
                        .init(name: "per_page", value: String(limit)),
                        .init(name: "orientation", value: "portrait")]
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct R: Decodable {
            struct Photo: Decodable {
                struct Src: Decodable { let large2x: String?; let large: String?; let medium: String? }
                let src: Src
                let photographer: String?
                let alt: String?
            }
            let photos: [Photo]
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        return r.photos.compactMap { p in
            guard let s = p.src.large2x ?? p.src.large, let u = URL(string: s) else { return nil }
            let thumb = p.src.medium.flatMap(URL.init(string:)) ?? u
            return Candidate(url: u,
                             title: p.alt ?? query,
                             credit: "Pexels · \(p.photographer ?? "unknown")",
                             preview: thumb, isVideo: false, seconds: nil)
        }
    }

    /// Pexels' video search. Clips between a few seconds and a minute,
    /// portrait to match the companion window; the file chosen is the
    /// smallest rendition that still fills the window (≥720 on the
    /// short side), since a 4K loop of a sleeping cat is 200MB of the
    /// same cat.
    private func pexelsVideos(_ query: String, limit: Int, key: String) async throws -> [Candidate] {
        var c = URLComponents(string: "https://api.pexels.com/videos/search")!
        c.queryItems = [.init(name: "query", value: query),
                        .init(name: "per_page", value: String(limit)),
                        .init(name: "orientation", value: "portrait"),
                        .init(name: "size", value: "medium")]
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct R: Decodable {
            struct Video: Decodable {
                struct File: Decodable {
                    let link: String
                    let width: Int?
                    let height: Int?
                    let file_type: String?
                }
                struct User: Decodable { let name: String? }
                let image: String?
                let duration: Int?
                let user: User?
                let video_files: [File]
            }
            let videos: [Video]
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        return r.videos.compactMap { v in
            guard let dur = v.duration, dur >= 3, dur <= 60 else { return nil }
            let mp4s = v.video_files.filter { ($0.file_type ?? "").contains("mp4") }
            let fitting = mp4s.filter { min($0.width ?? 0, $0.height ?? 0) >= 720 }
            let pick = fitting.min { min($0.width ?? 0, $0.height ?? 0) < min($1.width ?? 0, $1.height ?? 0) }
                ?? mp4s.max { min($0.width ?? 0, $0.height ?? 0) < min($1.width ?? 0, $1.height ?? 0) }
            guard let file = pick, let u = URL(string: file.link),
                  let poster = v.image.flatMap(URL.init(string:)) else { return nil }
            return Candidate(url: u,
                             title: "\(query) · \(dur)s",
                             credit: "Pexels · \(v.user?.name ?? "unknown")",
                             preview: poster, isVideo: true, seconds: dur)
        }
    }

    /// Wikimedia Commons needs no key. `gsrnamespace=6` restricts the
    /// search to the File namespace — without it the search returns
    /// article pages and the image list comes back empty.
    private func wikimedia(_ query: String, limit: Int) async throws -> [Candidate] {
        var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        c.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "generator", value: "search"),
            .init(name: "gsrsearch", value: "filetype:bitmap \(query)"),
            .init(name: "gsrnamespace", value: "6"),
            .init(name: "gsrlimit", value: String(limit)),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|extmetadata"),
            .init(name: "iiurlwidth", value: "1600"),
            .init(name: "format", value: "json"),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue("kinclaw-mac (https://localkin.dev)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (root["query"] as? [String: Any])?["pages"] as? [String: Any]
        else { return [] }
        return pages.values.compactMap { page in
            guard let p = page as? [String: Any],
                  let ii = (p["imageinfo"] as? [[String: Any]])?.first,
                  let s = ii["thumburl"] as? String, let u = URL(string: s) else { return nil }
            let meta = ii["extmetadata"] as? [String: Any] ?? [:]
            func field(_ k: String) -> String {
                ((meta[k] as? [String: Any])?["value"] as? String ?? "")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
            let title = (p["title"] as? String ?? "").replacingOccurrences(of: "File:", with: "")
            let lic = field("LicenseShortName")
            let author = field("Artist")
            return Candidate(
                url: u, title: title,
                credit: "Wikimedia Commons · \(title) · \(author) · \(lic)",
                preview: u, isVideo: false, seconds: nil)
        }
    }
}

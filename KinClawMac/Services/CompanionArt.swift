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
    ///         about.txt    words the conversation might use for this place
    struct Scene: Equatable, Identifiable {
        let name: String
        let wait: URL?
        let talk: URL?
        let words: [String]
        var id: String { name }

        func clip(for state: String) -> URL? {
            state == "speaking" ? (talk ?? wait) : (wait ?? talk)
        }
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
    /// The state at the previous ask. A reply is one *transition* into
    /// speaking, not every call made while she speaks — the art is chosen
    /// again for each sentence's mood, and counting those would send her
    /// home in the middle of answering.
    private var lastAskedState = ""

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
            let words = (about + " " + name).lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !Self.stopWords.contains($0) }
            let scene = Scene(name: name, wait: find("wait"), talk: find("talk"), words: words)
            if scene.wait != nil || scene.talk != nil { found.append(scene) }
        }
        scenes = found
        if scene == nil || !found.contains(where: { $0.name == scene?.name }) {
            scene = mainScene
        }
    }

    /// The clip for this moment, when she lives in scenes.
    ///
    /// The subject moves her: a reply about the sea goes to the sea if there
    /// is a sea, and anything that names nowhere counts towards going home.
    /// Nothing here picks at random — a place that changes on its own reads
    /// as a slideshow, not as somebody's evening.
    func sceneArt(for state: String, subject: String) -> URL? {
        guard !scenes.isEmpty else { return nil }
        let s = subject.trimmingCharacters(in: .whitespaces).lowercased()
        let startedReplying = state == "speaking" && lastAskedState != "speaking"
        lastAskedState = state
        if s.count >= 3,
           let match = scenes.first(where: { $0.words.contains(where: { $0.hasPrefix(s) || s.hasPrefix($0) }) }) {
            if match.name != scene?.name { scene = match }
            repliesAwayFromHome = 0
        } else if startedReplying {
            // A place she does not have is worth making, once, in the
            // background — she waits where she is until it exists.
            if s.count >= 3 {
                Task { @MainActor in CompanionCharacter.shared.wantScene(s) }
            }
            // Counted per reply, and a reply is what "speaking" marks.
            repliesAwayFromHome += 1
            if repliesAwayFromHome >= 2, let home = mainScene, home.name != scene?.name {
                scene = home
                repliesAwayFromHome = 0
            }
        }
        return (scene ?? mainScene)?.clip(for: state)
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
        if let inScene = sceneArt(for: state, subject: subject) { return inScene }
        if let m = bestMatch(for: subject, mood: mood) { return m }
        let stateArt = groups[state]?.randomElement()
        let moodArt = mood.flatMap { groups[$0.rawValue]?.randomElement() }
        let preferred = state == "speaking" ? (moodArt ?? stateArt) : (stateArt ?? moodArt)
        return preferred ?? fallback ?? pool.randomElement() ?? groups.values.first?.first
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

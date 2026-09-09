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
    }

    /// True when any group has art beyond the rotating pool — the view
    /// then swaps on every state and mood change rather than on a timer.
    var hasGroups: Bool { !groups.isEmpty }

    /// The art for a moment. While the companion speaks, its mood wins
    /// over the generic "speaking" art; the rest of the time the state
    /// wins, since "listening" is about you, not about how it feels.
    /// Then the caller's current picture, then the pool.
    func art(for state: String, mood: CompanionMood?, fallback: URL?) -> URL? {
        let stateArt = groups[state]?.randomElement()
        let moodArt = mood.flatMap { groups[$0.rawValue]?.randomElement() }
        let preferred = state == "speaking" ? (moodArt ?? stateArt) : (stateArt ?? moodArt)
        return preferred ?? fallback ?? pool.randomElement() ?? groups.values.first?.first
    }

    var isEmpty: Bool { pool.isEmpty && groups.isEmpty }

    var count: Int { pool.count + groups.values.reduce(0) { $0 + $1.count } }

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

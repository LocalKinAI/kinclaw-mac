import Foundation
import AppKit

/// The pictures behind companion mode: what is on disk, and how to get
/// more without leaving the app.
///
/// Art lives in `~/.kinclaw/companion/`. Anything the user drops there
/// is used as-is. Files named `idle`, `listening`, `thinking` or
/// `speaking` (any image extension) are treated as per-state art; the
/// rest form a general pool the view rotates through. That way a single
/// dropped photo works, and a four-file set works better, with no
/// configuration in between.
@MainActor
final class CompanionArt: ObservableObject {

    /// One downloadable picture with the credit it came with.
    struct Candidate: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let credit: String
    }

    @Published private(set) var pool: [URL] = []
    @Published private(set) var byState: [String: URL] = [:]
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

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff", "bmp"]

    /// Re-read the folder. Cheap; called on appear and after a fetch.
    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        guard let names = try? fm.contentsOfDirectory(atPath: Self.folder.path) else {
            pool = []; byState = [:]; return
        }
        var states: [String: URL] = [:]
        var general: [URL] = []
        for n in names.sorted() where !n.hasPrefix(".") {
            let url = Self.folder.appendingPathComponent(n)
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if ["idle", "listening", "thinking", "speaking"].contains(base) {
                states[base] = url
            } else {
                general.append(url)
            }
        }
        byState = states
        pool = general
    }

    /// The picture for a state: its own file when there is one, else
    /// whatever the caller is currently showing from the pool.
    func art(for state: String, fallback: URL?) -> URL? {
        byState[state] ?? fallback ?? pool.first ?? byState.values.first
    }

    var isEmpty: Bool { pool.isEmpty && byState.isEmpty }

    // MARK: - Fetching

    /// Search for pictures. Pexels when a key is configured (bigger,
    /// better, no attribution required), Wikimedia Commons otherwise —
    /// it needs no key at all, so companion mode works on a machine
    /// that has never been configured.
    func search(_ query: String, limit: Int = 12) async -> [Candidate] {
        let key = UserDefaults.standard.string(forKey: Self.pexelsKeyKey) ?? ""
        if !key.isEmpty {
            if let r = try? await pexels(query, limit: limit, key: key), !r.isEmpty { return r }
        }
        return (try? await wikimedia(query, limit: limit)) ?? []
    }

    /// Download the chosen pictures into the companion folder.
    /// Filenames carry the query so a folder of mixed themes stays
    /// legible, and the credit line is written alongside as .txt for
    /// the CC-licensed ones.
    func download(_ candidates: [Candidate], theme: String) async {
        fetching = true
        defer { fetching = false; reload() }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let slug = theme.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        for (i, c) in candidates.enumerated() {
            do {
                let (data, _) = try await URLSession.shared.data(from: c.url)
                // A 400px thumbnail looks like a smear once it fills a
                // window; search results happily return them.
                guard let img = NSImage(data: data), img.size.width >= 900 else { continue }
                let ext = c.url.pathExtension.isEmpty ? "jpg" : c.url.pathExtension
                let name = "\(slug.isEmpty ? "art" : slug)-\(Int(Date().timeIntervalSince1970))-\(i).\(ext)"
                try data.write(to: Self.folder.appendingPathComponent(name))
                if !c.credit.isEmpty {
                    try? c.credit.write(
                        to: Self.folder.appendingPathComponent(name + ".txt"),
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
                struct Src: Decodable { let large2x: String?; let large: String? }
                let src: Src
                let photographer: String?
                let alt: String?
            }
            let photos: [Photo]
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        return r.photos.compactMap { p in
            guard let s = p.src.large2x ?? p.src.large, let u = URL(string: s) else { return nil }
            return Candidate(url: u,
                             title: p.alt ?? query,
                             credit: "Pexels · \(p.photographer ?? "unknown")")
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
                credit: "Wikimedia Commons · \(title) · \(author) · \(lic)")
        }
    }
}

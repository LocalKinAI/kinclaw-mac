import Foundation

// MARK: - PrivateSoulLoader
//
// Studio tab's runtime sibling-repo detector. Mirrors the Makefile's
// LOCALKIN_REPO discovery (lines 60-67) — checks the same five
// candidate paths in order:
//
//   $REPO_ROOT/../localkin            — sibling layout, the documented one
//   $HOME/Documents/Workspace/localkin
//   $HOME/code/localkin
//   $HOME/dev/localkin
//   $HOME/src/localkin
//
// First one with `.git/` AND `souls/private/` wins. If none, the
// Studio tab renders an empty state — public users see a placeholder
// inviting them to either set up their own private workflows OR
// describing that this tab is for self-hosted private souls.
//
// Why "self-hosted" framing rather than "feature gate": KinClaw Mac is
// Apache 2.0. We can't and don't want a feature flag that's secretly
// disabled for everyone else. The Studio tab IS the framework; what
// fills it is per-user. Anyone running the binary CAN populate
// `~/Documents/Workspace/localkin/souls/private/` with their own
// souls and have them show up — that's the contract.

/// Resolves a sibling private repo at runtime and enumerates its
/// `souls/private/*.soul.md` files.
@MainActor
final class PrivateSoulLoader: ObservableObject {
    /// Souls discovered in the sibling repo, sorted by display name.
    /// Empty when no sibling repo is present — the Studio tab uses
    /// this to switch between populated view and empty state.
    @Published private(set) var souls: [PrivateSoul] = []

    /// Absolute path to the sibling repo that matched, or nil when
    /// none did. Surfaced in the empty state so the user knows where
    /// to drop souls if they want to populate the tab.
    @Published private(set) var siblingRepoPath: String?

    /// Last scan time. UI shows "Refreshed N seconds ago" to make
    /// re-scan feel responsive when the user creates a new soul.
    @Published private(set) var lastScan: Date?

    /// Re-scan the candidate paths. Cheap — five `fileExists` calls
    /// plus an enumeration of one directory. Safe to call on the
    /// main thread; doesn't read soul contents (only names).
    func rescan() {
        let candidate = Self.candidatePaths()
        guard let repo = candidate else {
            self.souls = []
            self.siblingRepoPath = nil
            self.lastScan = Date()
            return
        }
        self.siblingRepoPath = repo
        self.souls = Self.enumerate(soulsDirIn: repo)
        self.lastScan = Date()
    }

    // MARK: - Private implementation

    /// Walk the five candidate paths and return the first one whose
    /// `.git/` AND `souls/private/` both exist. Match the Makefile's
    /// order exactly so build-time and runtime detection agree.
    static func candidatePaths() -> String? {
        let home = NSHomeDirectory()

        // REPO_ROOT in the Makefile is the kinclaw-mac source tree.
        // For a release .app we can't reliably reach that, but the
        // four $HOME-based fallbacks cover the documented dev layouts.
        // Adding the bundle's parent dir handles the niche case of
        // running an unsigned debug build from the Xcode build folder.
        let bundleParent = Bundle.main.bundlePath
            + "/../../../../../localkin"

        let candidates: [String] = [
            bundleParent,
            "\(home)/Documents/Workspace/localkin",
            "\(home)/code/localkin",
            "\(home)/dev/localkin",
            "\(home)/src/localkin",
        ]

        let fm = FileManager.default
        for raw in candidates {
            // Normalise — resolve any ".." in the path so the
            // .git check hits the real location.
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            let gitDir = url.appendingPathComponent(".git")
            let soulsDir = url.appendingPathComponent("souls/private")
            if fm.fileExists(atPath: gitDir.path)
                && fm.fileExists(atPath: soulsDir.path) {
                return url.path
            }
        }
        return nil
    }

    /// List every `*.soul.md` under `<repo>/souls/private/`. Parses
    /// only the YAML frontmatter name/version/description fields —
    /// the full soul prose stays on disk and only loads when the
    /// user opens a card.
    static func enumerate(soulsDirIn repoPath: String) -> [PrivateSoul] {
        let soulsDir = URL(fileURLWithPath: repoPath)
            .appendingPathComponent("souls/private")

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: soulsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        let soulFiles = entries.filter { $0.lastPathComponent.hasSuffix(".soul.md") }

        return soulFiles
            .compactMap { url in PrivateSoul.parse(at: url) }
            .sorted { $0.displayName < $1.displayName }
    }
}

// MARK: - PrivateSoul model

/// One soul card in the Studio tab. Lightweight — holds only the
/// frontmatter fields we display, plus the absolute path so the Run
/// button knows where to point kinclaw.
struct PrivateSoul: Identifiable, Hashable {
    let path: String
    let name: String
    let version: String?
    let description: String?

    /// File mtime, surfaced in the card as "Updated 3 days ago" so
    /// the user notices when they last touched a workflow.
    let modifiedAt: Date?

    var id: String { path }

    var displayName: String {
        // Title-case the snake_case name. Same convention as
        // `Soul.displayName` for the public agents tab.
        name.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Parse just enough of the YAML frontmatter for the card view.
    /// We avoid pulling Yams into the dependency graph for a 3-field
    /// peek — the frontmatter shape is stable enough that line-by-line
    /// matching is reliable here.
    ///
    /// Returns nil if the file has no frontmatter or no `name:` key —
    /// those aren't valid kinclaw souls and would just confuse the UI.
    static func parse(at url: URL) -> PrivateSoul? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // Frontmatter is between the first two "---" lines.
        let lines = raw.components(separatedBy: .newlines)
        guard lines.first == "---" else { return nil }

        var name: String?
        var version: String?
        var description: String?
        var inFrontmatter = false
        for line in lines {
            if line == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            guard inFrontmatter else { continue }
            // We only care about top-level keys; skip indented lines.
            guard !line.hasPrefix(" ") && !line.hasPrefix("\t") else { continue }
            if let v = strip(line, prefix: "name:") { name = v }
            if let v = strip(line, prefix: "version:") { version = v }
            if let v = strip(line, prefix: "description:") { description = v }
        }

        guard let name else { return nil }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = attrs?[.modificationDate] as? Date

        return PrivateSoul(
            path: url.path,
            name: name,
            version: version,
            description: description,
            modifiedAt: mtime
        )
    }

    /// Strip `key:` prefix + surrounding quotes/whitespace. Returns nil
    /// if the line doesn't match the key.
    private static func strip(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        var v = String(line.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes if present — both styles are
        // legal YAML for plain strings.
        if (v.hasPrefix("\"") && v.hasSuffix("\""))
            || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v.isEmpty ? nil : v
    }
}

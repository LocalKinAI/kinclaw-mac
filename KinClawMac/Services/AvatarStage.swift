import Foundation

/// Where the avatar's web assets live, and which character is in them.
///
/// The upstream page hardcodes `let asset_dir = "assets"`, so rather
/// than patch their JavaScript — which would have to be re-patched
/// every time the avatar service updates — the staging directory has
/// an `assets` symlink pointing at whichever character is chosen.
/// Switching is one symlink and a reload.
///
/// Everything else is symlinked too, so this costs no disk and picks up
/// their updates for free.
@MainActor
enum AvatarStage {

    /// The characters the avatar service ships, in the order they are
    /// offered. Names are ours: the folders are called assets2, assets3.
    struct Character: Identifiable, Hashable {
        let dir: String
        let name: String
        var id: String { dir }
    }

    static let characters: [Character] = [
        Character(dir: "assets2", name: "女生 · 真人"),
        Character(dir: "assets",  name: "男生 · 真人"),
        Character(dir: "assets3", name: "少年 · 动漫"),
        Character(dir: "assets5", name: "女生 · 动漫"),
    ]

    static let characterKey = "kinclaw.companion.avatar.character"
    static let enabledKey = "kinclaw.companion.avatar.enabled"

    static var chosen: Character {
        let d = UserDefaults.standard.string(forKey: characterKey) ?? ""
        return characters.first { $0.dir == d } ?? characters[0]
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Where the avatar service's web files are, if it is checked out
    /// next to the other repos. nil means the feature is unavailable —
    /// not an error, just a face we cannot draw.
    static var source: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/Workspace/localkin-service-avatar/web_demo/static"),
            home.appendingPathComponent("localkin-service-avatar/web_demo/static"),
        ]
        for c in candidates where FileManager.default.fileExists(
            atPath: c.appendingPathComponent("DHLiveMini.wasm").path) {
            return c
        }
        return nil
    }

    static var stageDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/avatar")
    }

    /// Build (or refresh) the staging directory for a character.
    /// Returns nil when the avatar service is not present.
    @discardableResult
    static func prepare(_ character: Character? = nil) -> URL? {
        let character = character ?? chosen
        guard let src = source else { return nil }
        let fm = FileManager.default
        let stage = stageDir
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)

        // Everything the page loads, symlinked. `dialog.html` is their
        // chat UI in a hidden iframe — the page asks for it, so it has
        // to resolve, but we never show it.
        let linked = ["MiniLive.html", "DHLiveMini.wasm", "dialog.html",
                      "js", "common", "css", "background", "fonts"]
        for name in linked {
            let dst = stage.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            try? fm.createSymbolicLink(at: dst, withDestinationURL: src.appendingPathComponent(name))
        }
        // The character, under the name their code expects.
        let assets = stage.appendingPathComponent("assets")
        try? fm.removeItem(at: assets)
        try? fm.createSymbolicLink(at: assets,
                                   withDestinationURL: src.appendingPathComponent(character.dir))
        return stage
    }
}

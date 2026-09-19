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

    /// One look: a folder holding `01.mp4` and `combined_data.json.gz`, which
    /// is all a DH_live character is. The four the avatar service ships are
    /// named by us — their folders are called assets2, assets3 — and anything
    /// under `~/.kinclaw/avatars-real/` is named by its own folder.
    struct Character: Identifiable, Hashable {
        let assets: URL
        let name: String
        var id: String { assets.path }
    }

    /// Where a look you made yourself lives. A sibling of the 3D wardrobe:
    /// same idea, real people instead of VRM models.
    static var madeFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/avatars-real")
    }

    /// Built-in names, in the order they are offered.
    private static let shipped = [("assets2", "女生 · 真人"), ("assets", "男生 · 真人"),
                                  ("assets3", "少年 · 动漫"), ("assets5", "女生 · 动漫")]

    /// Every look there is: the service's own, then the ones made here.
    ///
    /// Scanned rather than listed, which is what makes a wardrobe out of it —
    /// a new look is a folder, and the menu picks it up without a build.
    static var characters: [Character] {
        var out: [Character] = []
        if let src = source {
            for (dir, name) in shipped
            where isComplete(src.appendingPathComponent(dir)) {
                out.append(Character(assets: src.appendingPathComponent(dir), name: name))
            }
        }
        let fm = FileManager.default
        let made = (try? fm.contentsOfDirectory(at: madeFolder, includingPropertiesForKeys: nil)) ?? []
        for folder in made.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Either the folder is the assets itself, or it is a run of the
            // preparation scripts, whose output lands in `assets/`.
            for candidate in [folder.appendingPathComponent("assets"), folder]
            where isComplete(candidate) {
                out.append(Character(assets: candidate, name: folder.lastPathComponent))
                break
            }
        }
        return out
    }

    /// A look needs both files, not just the video.
    ///
    /// `01.mp4` alone is what an interrupted preparation leaves behind — and
    /// the mouth data is what the runtime actually reads, so a folder with
    /// only the video loads a face that never renders: the companion goes
    /// black and stays there, with her own pictures hidden behind the layer
    /// that failed. Measured the hard way, on a preparation that stopped at
    /// the last step.
    /// The runtime a look brings with it, if it brought one.
    ///
    /// DH_live's data format changed with its 2.0 upgrade — the reference
    /// feature went from 6480 numbers to 80 — and upstream publishes the 1.x
    /// weights with the 2.0 runtime, so a look you build yourself can only be
    /// 1.x and the shipped runtime cannot read it. A look that carries its own
    /// `runtime/` is staged against that instead of against the service's, so
    /// the two generations can sit side by side.
    nonisolated static func runtime(beside assets: URL) -> URL? {
        let folder = assets.lastPathComponent == "assets"
            ? assets.deletingLastPathComponent() : assets
        let runtime = folder.appendingPathComponent("runtime")
        return FileManager.default.fileExists(
            atPath: runtime.appendingPathComponent("DHLiveMini.wasm").path) ? runtime : nil
    }

    nonisolated static func isComplete(_ assets: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: assets.appendingPathComponent("01.mp4").path)
            && fm.fileExists(atPath: assets.appendingPathComponent("combined_data.json.gz").path)
    }

    static let characterKey = "kinclaw.companion.avatar.character"
    static let enabledKey = "kinclaw.companion.avatar.enabled"

    /// The look she is wearing: the remembered one while it still exists, else
    /// the first there is. nil only when the avatar service is not on disk and
    /// nothing has been made — there is then no face to draw.
    static var chosen: Character? {
        let all = characters
        let remembered = UserDefaults.standard.string(forKey: characterKey) ?? ""
        return all.first { $0.id == remembered }
            // Folder names were the key before looks could live anywhere.
            ?? all.first { $0.assets.lastPathComponent == remembered }
            ?? all.first
    }

    /// Find a look the way a person names it, for the agent's `avatar_wear`.
    static func match(_ text: String) -> Character? {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        let all = characters
        return all.first { $0.name.lowercased() == wanted }
            ?? all.first { $0.name.lowercased().contains(wanted) }
            ?? all.first { wanted.contains($0.name.lowercased()) }
            ?? all.first { $0.assets.lastPathComponent.lowercased() == wanted }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// The same flag, settable — the panel's tools turn her on when the agent
    /// is asked to change how she looks.
    ///
    /// Turning her on turns the 3D one off, here rather than at the call sites:
    /// both being on is a cartoon standing in front of a person, which is what
    /// shipped the day the 3D one arrived, and the two menus, the two tools and
    /// the restore-on-launch path would each have had to remember not to.
    static var isEnabledSetting: Bool {
        get { isEnabled }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { UserDefaults.standard.set(false, forKey: VRMWardrobe.enabledKey) }
        }
    }

    /// Where the avatar service's web files are, if it is checked out
    /// next to the other repos. nil means the feature is unavailable —
    /// not an error, just a face we cannot draw.
    nonisolated static var source: URL? {
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
        guard let character = character ?? chosen else { return nil }
        // Her own runtime if she has one, else the service's.
        guard let src = runtime(beside: character.assets) ?? source else { return nil }
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
        try? fm.createSymbolicLink(at: assets, withDestinationURL: character.assets)
        return stage
    }
}

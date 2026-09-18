import Foundation
import SwiftUI

/// The companion's models and their clothes: what is on disk, and which one
/// she is wearing.
///
/// A wardrobe is a folder of `.vrm` files — `~/.kinclaw/avatars/` — and
/// changing clothes is choosing another one. That sounds crude next to Desktop
/// Mate's outfit switch, and it is the same thing underneath: a VRM carries its
/// clothes baked in, so both DLC costumes and VRoid Hub's paid outfits arrive as
/// another file. The difference is only that ours is a folder you can drop
/// anything into.
///
/// The app ships no model. A character is somebody's work, licensed per model
/// on VRoid Hub, and shipping one would be shipping a licence we do not have.
@MainActor
enum VRMWardrobe {

    /// Where the models live. Sits beside the companion's pictures.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/avatars")
    }

    static let modelKey = "kinclaw.companion.vrm.model"
    static let enabledKey = "kinclaw.companion.vrm.enabled"

    /// Where to get one, offered where the wardrobe is empty.
    static let sourceURL = URL(string: "https://hub.vroid.com")!

    /// One model, named by its file.
    struct Outfit: Identifiable, Hashable {
        let url: URL
        var name: String { url.deletingPathExtension().lastPathComponent }
        var id: String { url.lastPathComponent }
    }

    static var outfits: [Outfit] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder,
                                                        includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.pathExtension.lowercased() == "vrm" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(Outfit.init)
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The one she is wearing: the remembered choice while it still exists,
    /// else the first in the folder.
    static var chosen: Outfit? {
        let all = outfits
        let remembered = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return all.first { $0.id == remembered } ?? all.first
    }

    static func wear(_ outfit: Outfit) {
        UserDefaults.standard.set(outfit.id, forKey: modelKey)
    }

    /// Find an outfit the way a person names it — "裙子", "summer" — so the
    /// agent's `avatar_wear` does not need the exact filename.
    static func match(_ text: String) -> Outfit? {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        let all = outfits
        return all.first { $0.id.lowercased() == wanted }
            ?? all.first { $0.name.lowercased() == wanted }
            ?? all.first { $0.name.lowercased().contains(wanted) }
            ?? all.first { wanted.contains($0.name.lowercased()) }
    }

    /// Make sure the folder exists, so "打开文件夹" has something to open and
    /// a drag of a .vrm has somewhere to land.
    @discardableResult
    static func ensureFolder() -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - The served stage

    /// Where the page and its libraries are served from: the bundle's copies,
    /// symlinked, plus `models` pointing at the wardrobe.
    ///
    /// A web view needs an origin for this — ES modules and a `.vrm` fetch both
    /// refuse to load from `file://` — and the page has to sit in the same
    /// origin as the models. Symlinks rather than copies: the libraries are
    /// 700 KB and they update with the app.
    static var stageDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kinclaw/vrm")
    }

    /// Build (or refresh) the stage. nil when the app's own resources are
    /// missing, which means a broken build rather than a missing character.
    @discardableResult
    static func prepareStage() -> URL? {
        guard let source = Bundle.main.url(forResource: "stage", withExtension: "html",
                                           subdirectory: "vrm")?.deletingLastPathComponent()
                ?? Bundle.main.resourceURL?.appendingPathComponent("vrm") else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appendingPathComponent("stage.html").path) else { return nil }

        let stage = stageDir
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)
        // three ships as two files that import each other by name, so both
        // have to be here under the names they expect.
        for name in ["stage.html", "three.module.js", "three.core.js",
                     "three-vrm.module.min.js", "loaders", "utils"] {
            let dst = stage.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            try? fm.createSymbolicLink(at: dst, withDestinationURL: source.appendingPathComponent(name))
        }
        let models = stage.appendingPathComponent("models")
        try? fm.removeItem(at: models)
        try? fm.createSymbolicLink(at: models, withDestinationURL: ensureFolder())
        return stage
    }
}

/// Owns the stage's local server for the lifetime of companion mode — the same
/// job AvatarServerBox does for the digital human, and for the same reason: the
/// port is not known until it is assigned, and the view is built before that.
@MainActor
final class VRMServerBox: ObservableObject {
    static let shared = VRMServerBox()

    @Published private(set) var base: URL?
    private var server: AvatarServer?

    /// Start only if the user turned her on and there is a model to show.
    func startIfWanted() {
        guard base == nil, VRMWardrobe.isEnabled, VRMWardrobe.chosen != nil,
              let stage = VRMWardrobe.prepareStage() else { return }
        let s = AvatarServer(root: stage)
        guard let url = s.start() else { return }
        server = s
        base = url
    }

    func stop() {
        server?.stop()
        server = nil
        base = nil
    }
}

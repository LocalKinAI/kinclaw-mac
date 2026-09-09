import Foundation
import SwiftUI

/// Owns the avatar's local server for the lifetime of companion mode.
///
/// A tiny observable wrapper so SwiftUI can react to the server coming
/// up: the base URL is not known until a port is assigned, and the view
/// that needs it is built before that happens.
@MainActor
final class AvatarServerBox: ObservableObject {
    @Published private(set) var base: URL?
    private var server: AvatarServer?

    /// Start only if the user turned the digital human on and the
    /// avatar service is actually on disk. Neither being true is the
    /// normal case, not an error.
    func startIfWanted() {
        guard base == nil, AvatarStage.isEnabled, let stage = AvatarStage.prepare() else { return }
        let s = AvatarServer(root: stage)
        guard let url = s.start() else { return }
        server = s
        base = url
    }

    /// Re-stage for a different character and reload from the same
    /// origin — the page reads `assets/`, which is a symlink.
    func switchCharacter(_ c: AvatarStage.Character) {
        UserDefaults.standard.set(c.dir, forKey: AvatarStage.characterKey)
        guard AvatarStage.prepare(c) != nil else { return }
        // Bounce the base URL so the view reloads.
        let current = base
        base = nil
        DispatchQueue.main.async { self.base = current }
    }

    func stop() {
        server?.stop()
        server = nil
        base = nil
    }
}

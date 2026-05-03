import Foundation
import KeyboardShortcuts

/// Global hotkey definitions for KinClaw Mac.
///
/// Default: **⌘⌥ K** — picked over the obvious alternatives because:
///   - ⌘ Space is reserved for macOS Spotlight (system-level, can't
///     politely override)
///   - ⌥ Space is Alfred's default — many users have it bound
///   - ⌘ Space (double-tap) is Raycast's default
///   - ⌘⌥ K = "K for KinClaw", no major collisions in stock macOS
///
/// User can re-bind via the Settings UI in M5 — `KeyboardShortcuts`
/// ships its own SwiftUI recorder view we'll drop in there.
extension KeyboardShortcuts.Name {
    /// Toggle the floating spotlight panel — primary entry point.
    static let toggleKinClaw = Self(
        "toggleKinClaw",
        default: .init(.k, modifiers: [.command, .option])
    )
}

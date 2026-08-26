import SwiftUI
import AppKit

/// SwiftUI escape-hatch to get at the underlying NSWindow.
/// Used by KinClawMacSettingsView to apply the same glass-blur
/// chrome as the SpotlightWindow main panel — `.containerBackground`
/// + SwiftUI's `.ultraThinMaterial` blurs against the window only;
/// the panel uses `NSVisualEffectView` with `.behindWindow` blending
/// for desktop-show-through, which has no SwiftUI-native equivalent
/// in macOS 14.
///
/// Drop into any view's `.background()`:
///
///     .background(WindowAccessor { window in
///         applyGlassChrome(to: window)
///     })
///
/// Fires once when the host NSWindow attaches; if the window is
/// already attached at make-time it dispatches asynchronously to
/// avoid `objectWillChange` warnings.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.applied { return }
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
                context.coordinator.applied = true
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var applied = false }
}

/// Apply the same window chrome as `SpotlightWindow` to any host
/// NSWindow — transparent titlebar, hidden title text, glass-blur
/// behind-window content, but standard traffic-light buttons left
/// in place. Used by Settings + any other future "secondary panel"
/// surface that should match the main dock.
@MainActor
func applyGlassChrome(to window: NSWindow) {
    // Already done? Bail. Otherwise this fires every appear and
    // would re-wrap the contentView each time.
    if window.contentView is NSVisualEffectView { return }

    // Float alongside the spotlight panel.
    //
    // SpotlightWindow sets `.floating`, so a Settings window at the default
    // `.normal` level opens *behind* it — the user clicks Settings, the panel
    // stays on top, and it reads as Settings not opening at all. Same level
    // means the most recently activated one wins, which is the behaviour
    // clicking a window is supposed to have.
    window.level = .floating

    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.styleMask.insert(.fullSizeContentView)

    let effect = NSVisualEffectView()
    effect.material = .hudWindow            // matches SpotlightWindow
    effect.blendingMode = .behindWindow     // sees through to the desktop
    effect.state = .active
    effect.translatesAutoresizingMaskIntoConstraints = false

    guard let existing = window.contentView else { return }
    let prevFrame = existing.frame
    existing.removeFromSuperview()
    effect.addSubview(existing)
    existing.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        existing.topAnchor.constraint(equalTo: effect.topAnchor),
        existing.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        existing.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        existing.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])
    window.contentView = effect

    // Restore frame size so SwiftUI's .frame(width:height:) holds.
    window.setContentSize(prevFrame.size)
}

import SwiftUI
import AppKit

/// The floating chat panel — frameless, glass-blurred, always-on-top.
/// Hosts a SwiftUI tree (currently the ported `ContentView`; M3+ will
/// replace that with a single-column Spotlight UX).
///
/// Form factor decisions (locked in `docs/spotlight-shell-plan.md`):
///   - **380 × 600 default**, user-resizable, size + position
///     remembered between launches.
///   - **Centered with a slight upward bias** on first run, mimicking
///     macOS Spotlight (which sits ~1/3 down the screen, not dead
///     center).
///   - **`.floating` window level** — above normal app windows, below
///     modal sheets / system alerts.
///   - **`.canJoinAllSpaces`** — ⌘⌥K (M3) summons the panel regardless
///     of which Space the user is on.
///   - **`.nonactivatingPanel`** — opening the panel does NOT pull
///     focus away from whatever app the user was operating. This is
///     the whole point: KinClaw rides alongside the work, it doesn't
///     hijack it.
///
/// Lifecycle: AppDelegate owns one instance; `toggle()` is the
/// hotkey entry point; ESC also hides.
final class SpotlightWindow: NSPanel {

    /// First-run size. After that we restore the user's last frame.
    private static let defaultSize = NSSize(width: 380, height: 600)
    private static let frameUserDefaultsKey = "kinclaw.spotlight.frame"

    // MARK: - Init

    /// Build the panel and embed any SwiftUI view tree as its content.
    /// The view tree is fixed at construction; AppDelegate is expected
    /// to inject the right `EnvironmentObject`s in the closure.
    init<Content: View>(@ViewBuilder content: () -> Content) {
        let initialFrame = Self.savedFrame ?? Self.centeredFrame()

        // .titled (rather than .borderless) gives us the standard
        // edge-resize hit zones — borderless panels are technically
        // resizable but the cursor doesn't change at edges, which
        // makes the affordance invisible. We hide the titlebar's
        // visual chrome below and let .fullSizeContentView push the
        // SwiftUI tree up under it; the result looks identical to
        // borderless but resize works the way users expect.
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .resizable, .nonactivatingPanel,
                        .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Floating above normal windows; sticks across Spaces.
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                   .fullScreenAuxiliary]

        // Transparent shell so the NSVisualEffectView underneath shows.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        // Hide the title text but keep the titlebar surface so the
        // traffic-light controls (close / minimize / zoom) stay
        // visible and usable. titlebarAppearsTransparent + .fullSize
        // ContentView lets the SwiftUI tree underneath fill behind
        // the buttons; the user gets standard window chrome
        // affordance with the panel-style aesthetic.
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        // Don't auto-release on close; AppDelegate manages lifetime.
        self.isReleasedWhenClosed = false

        // Be honest about being a key window — by default NSPanel
        // hides from key window list to avoid stealing focus, but
        // we DO want keyboard input (text field) once shown.
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false

        // Glass-blur background. `.hudWindow` is the same material
        // Spotlight / Notification Center / TouchBar stripe use.
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true

        // SwiftUI content via NSHostingView. Pin to all four edges so
        // resizing the panel resizes the chat.
        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        self.contentView = visualEffect

        // Hard floor so the chat doesn't collapse to unreadable.
        // 280×280 lets users tuck the panel into a corner of a small
        // laptop screen as a "command stripe" while still keeping
        // the input + at least two message bubbles visible.
        self.minSize = NSSize(width: 280, height: 280)

        // Persist position + size as the user drags / resizes.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(persistCurrentFrame),
                       name: NSWindow.didMoveNotification, object: self)
        nc.addObserver(self, selector: #selector(persistCurrentFrame),
                       name: NSWindow.didResizeNotification, object: self)
    }

    // NSPanel defaults block becomeKey / becomeMain. We need
    // becomeKey for keyboard input; becomeMain stays off so the
    // app doesn't think the floating panel is its main document
    // window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Show / hide / toggle (the hotkey entry points)

    /// Make the panel visible without activating the app — the user
    /// keeps focus on whatever they were doing; clicking inside our
    /// panel will then transfer keyboard focus on demand.
    func show() {
        if Self.savedFrame == nil {
            self.setFrame(Self.centeredFrame(), display: true)
        }
        self.orderFrontRegardless()
        // Hand keyboard focus to the panel so the chat input is
        // immediately typable. `makeKey` is a no-op on already-key
        // windows so this is safe to call repeatedly.
        self.makeKey()
    }

    func hide() { self.orderOut(nil) }

    /// Hotkey-style: visible → hide; hidden → show. The whole point
    /// of the Spotlight form factor.
    func toggle() {
        if self.isVisible { hide() } else { show() }
    }

    // ESC hides — same gesture as Spotlight / Raycast / Alfred.
    // (M5 will gate this behind a Settings toggle in case anyone
    // uses ESC for chat-clear or similar.)
    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    /// The red traffic-light close button calls this — we redirect
    /// it to hide rather than destroy the window. KinClaw Mac is a
    /// menubar-only app; closing the panel must NOT quit the
    /// process. The user can re-summon with ⌘⌥K or the 🦞 menubar.
    /// Quit happens via menubar → Quit or ⌘Q (which goes through
    /// NSApp.terminate, not this method).
    override func close() {
        self.orderOut(nil)
    }

    // MARK: - Frame persistence

    @objc private func persistCurrentFrame() {
        let r = self.frame
        UserDefaults.standard.set(
            ["x": r.origin.x, "y": r.origin.y,
             "w": r.size.width, "h": r.size.height],
            forKey: Self.frameUserDefaultsKey
        )
    }

    private static var savedFrame: NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: frameUserDefaultsKey),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let w = dict["w"] as? CGFloat,
              let h = dict["h"] as? CGFloat else {
            return nil
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private static func centeredFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: defaultSize)
        }
        let v = screen.visibleFrame
        let s = defaultSize
        // Slight upward bias mimicking Spotlight's "1/3 down" rule —
        // looks intentional, leaves room for the assistant's reply
        // to grow downward without obscuring the input.
        let yOffset: CGFloat = 60
        return NSRect(
            x: v.midX - s.width / 2,
            y: v.midY - s.height / 2 + yOffset,
            width: s.width,
            height: s.height
        )
    }
}

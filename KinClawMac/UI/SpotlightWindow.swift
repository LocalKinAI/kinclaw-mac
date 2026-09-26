import SwiftUI
import AppKit

private extension NSRect {
    /// Convenience for picking the most-overlapping screen.
    var area: CGFloat { width * height }
}

/// The chat panel — frameless, glass-blurred, a window among windows.
/// Hosts a SwiftUI tree (currently the ported `ContentView`; M3+ will
/// replace that with a single-column Spotlight UX).
///
/// Form factor decisions (locked in `docs/spotlight-shell-plan.md`):
///   - **380 × 600 default**, user-resizable, size + position
///     remembered between launches.
///   - **Centered with a slight upward bias** on first run, mimicking
///     macOS Spotlight (which sits ~1/3 down the screen, not dead
///     center).
///   - **`.normal` window level** — it comes to the front when summoned
///     or clicked, and other windows go over it when they are. It was
///     `.floating`, always above every app, which suited a quick question
///     and not a Term tab running an agent for an hour beside the editor
///     it works on.
///   - **One Space, and full screen** — ⌘⌥K brings the panel to the Space
///     the user is on (`.moveToActiveSpace`); otherwise it stays on the one
///     it was left on, and the green button makes it full screen. It used
///     to join every Space, stationary, as an auxiliary to other apps' full
///     screens: on every desktop at once, which read as "always in front",
///     and an auxiliary window cannot be full screen itself — the green
///     button did nothing ("不能全屏，点了也不行").
///   - **`.nonactivatingPanel`** — opening the panel does NOT pull
///     focus away from whatever app the user was operating. This is
///     the whole point: KinClaw rides alongside the work, it doesn't
///     hijack it.
///
/// Lifecycle: AppDelegate owns one instance; `toggle()` is the
/// hotkey entry point — it hides a panel you can see and brings forward
/// one you can't; ESC also hides.
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
        // Each traffic-light button is gated by its corresponding
        // styleMask flag:
        //   .closable        → red (close)
        //   .miniaturizable  → yellow (minimize)
        //   .resizable       → green (zoom) AND edge-resize hit zones
        // Without all three, you get an asymmetric titlebar with
        // only some buttons enabled — exactly the bug just caught
        // (only zoom showed because only .resizable was in the mask).
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // An ordinary window in the stacking order, on one Space at a time.
        self.level = .normal
        self.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]

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
        self.glass = visualEffect

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
        // Square corners in full screen: a rounded panel filling a display
        // shows the black behind it at the corners.
        nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: self, queue: .main) { [weak self] _ in
            self?.glass?.layer?.cornerRadius = 0
        }
        nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: self, queue: .main) { [weak self] _ in
            self?.glass?.layer?.cornerRadius = 16
        }
    }

    /// The blur everything sits on; its corners are squared in full screen.
    private weak var glass: NSVisualEffectView?

    var isFullScreen: Bool { styleMask.contains(.fullScreen) }

    /// Full screen is a Space of the app's own, which a panel that never
    /// activates the app cannot take: the app is activated first.
    override func toggleFullScreen(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        super.toggleFullScreen(sender)
    }

    /// For `panel_show {full_screen}`.
    func setFullScreen(_ on: Bool) {
        if !isVisible { show() }
        if on != isFullScreen { toggleFullScreen(nil) }
    }

    // NSPanel defaults block becomeKey / becomeMain. We need
    // becomeKey for keyboard input; becomeMain stays off so the
    // app doesn't think the floating panel is its main document
    // window.
    override var canBecomeKey: Bool { true }
    // Main as well: a full-screen window is the app's main window.
    override var canBecomeMain: Bool { true }

    /// A click brings the panel forward. A panel that never activates the
    /// app is not raised by activation the way an ordinary window is, so at
    /// `.normal` level a click into one half-covered by another app's
    /// window would type into it while leaving it covered.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            orderFrontRegardless()
        default:
            break
        }
        super.sendEvent(event)
    }

    // MARK: - Show / hide / toggle (the hotkey entry points)

    /// Make the panel visible without activating the app — the user
    /// keeps focus on whatever they were doing; clicking inside our
    /// panel will then transfer keyboard focus on demand.
    ///
    /// Also clamps the saved frame back into a visible screen — if
    /// the user dragged the panel onto an external monitor, then
    /// unplugged it, the saved position would land off-screen and
    /// the panel would summon invisibly. Clamping fixes that
    /// silently.
    ///
    /// Visual: 150ms fade-in. Pure pop felt jarring; the slide-up
    /// from Spotlight / Raycast / Alfred is what users expect.
    /// Companion mode wants a picture-sized window, not a chat column.
    /// The chat frame is remembered and restored on the way out, so
    /// entering and leaving never costs the user their layout.
    private var frameBeforeCompanion: NSRect?

    func enterCompanion() {
        guard frameBeforeCompanion == nil else { return }
        frameBeforeCompanion = self.frame
        let screen = self.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Portrait-ish and generous, capped to what fits on this screen.
        let h = min(vis.height * 0.82, 900)
        let w = min(vis.width * 0.55, h * 0.78)
        let target = NSRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(target, display: true)
        }
    }

    func exitCompanion() {
        guard let back = frameBeforeCompanion else { return }
        frameBeforeCompanion = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(back, display: true)
        }
    }

    func show() {
        // Full screen lives on its own Space, which only an active app is
        // taken to.
        if isFullScreen { NSApp.activate(ignoringOtherApps: true) }
        // Already up, perhaps under another window: raise it, without the
        // fade from nothing that would blink a panel already on screen.
        if self.isVisible {
            self.orderFrontRegardless()
            self.makeKey()
            return
        }
        if Self.savedFrame == nil {
            self.setFrame(Self.centeredFrame(), display: true)
        } else {
            self.setFrame(self.clampedToVisibleScreen(self.frame),
                          display: true)
        }
        // Start invisible so the alpha animation has somewhere to
        // animate FROM. .makeKey + orderFrontRegardless then fade.
        self.alphaValue = 0
        self.orderFrontRegardless()
        self.makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        // Ordered out, a full-screen window would leave its Space behind,
        // black and empty: the app is hidden instead, and the Space goes
        // with it.
        if isFullScreen { NSApp.hide(nil); return }
        // Mirror the show animation — quick fade-out before
        // orderOut. Skip if already invisible to avoid double-
        // animation when toggle() races itself.
        guard self.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            // Reset alpha so the next show() starts from 0 cleanly
            // (orderOut hides; the alpha set above persists).
            self?.alphaValue = 1
        })
    }

    /// Push the frame back inside the union of visible screens.
    /// Handles the "external monitor unplugged since last save"
    /// case + any saved frame whose origin / size has somehow
    /// drifted out of bounds.
    private func clampedToVisibleScreen(_ frame: NSRect) -> NSRect {
        // Use the screen the frame intersects most, falling back
        // to NSScreen.main if there's no intersection at all.
        let target = NSScreen.screens.max(by: { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        }) ?? NSScreen.main
        guard let visible = target?.visibleFrame else { return frame }

        var clamped = frame
        // Shrink to fit if the frame exceeds the screen.
        clamped.size.width  = min(clamped.size.width,  visible.size.width)
        clamped.size.height = min(clamped.size.height, visible.size.height)
        // Slide back inside.
        if clamped.maxX > visible.maxX { clamped.origin.x = visible.maxX - clamped.width }
        if clamped.minX < visible.minX { clamped.origin.x = visible.minX }
        if clamped.maxY > visible.maxY { clamped.origin.y = visible.maxY - clamped.height }
        if clamped.minY < visible.minY { clamped.origin.y = visible.minY }
        return clamped
    }

    /// Hotkey-style: a panel you can see hides; one you can't — hidden, or
    /// on screen under another app's window — comes forward. The second
    /// case exists since the panel stopped floating: hiding a panel the user
    /// was pressing the hotkey to find would take two presses to get back.
    func toggle() {
        if self.isVisible && !isCovered { hide() } else { show() }
    }

    /// Whether a normal-level window of any app overlaps the panel from
    /// above. Window server order, not key status: clicking the menubar
    /// item can take key status away from a panel that is plainly in front.
    /// Bounds and layers need no screen-recording permission; only window
    /// titles do.
    private var isCovered: Bool {
        guard let above = CGWindowListCopyWindowInfo(
            [.optionOnScreenAboveWindow, .excludeDesktopElements],
            CGWindowID(self.windowNumber)) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else {
            return false
        }
        // The window server measures from the top-left of the main display;
        // AppKit from its bottom-left.
        let mine = CGRect(x: frame.minX, y: mainHeight - frame.maxY,
                          width: frame.width, height: frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        return above.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                return false
            }
            return bounds.intersects(mine)
        }
    }

    // ESC hides — same gesture as Spotlight / Raycast / Alfred.
    // (M5 will gate this behind a Settings toggle in case anyone
    // uses ESC for chat-clear or similar.)
    override func cancelOperation(_ sender: Any?) {
        // In full screen ESC does what it does in every full-screen window.
        if isFullScreen { toggleFullScreen(nil) } else { hide() }
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
        // The full-screen frame is the display's, not one to come back to.
        guard !isFullScreen else { return }
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

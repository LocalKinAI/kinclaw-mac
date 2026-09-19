import AppKit
import SwiftUI

/// Her, on the desktop, in front of everything.
///
/// The panel is a window you summon, and a companion who only exists inside
/// one is a media player you open. What makes a desktop companion feel
/// present is that she is *already there* — over the editor, over the
/// browser, in the corner of the screen you are not using — and that she
/// stays put while you work.
///
/// So this is a second window, deliberately unlike the panel:
///
///   - **No frame and no background.** Borderless, `isOpaque = false`, clear
///     colour, and the stage's own page is transparent — so what shows is the
///     character and nothing else.
///   - **Above other apps**, at `.floating`. The panel is explicitly at
///     `.normal` so it does not sit on top of everything; this one is the
///     opposite by intent, and it is off until asked for.
///   - **On every Space, and stationary**, so she does not slide away with
///     Mission Control or vanish when you switch desktop.
///   - **Drag her anywhere** — the whole window is the handle — and the frame
///     is remembered. Or turn on 穿透 and she stops taking clicks at all,
///     which is what you want while typing behind her.
///
/// One web view exists for the character (`VRMStage` keeps it alive between
/// visits), so while the overlay is up the panel does not draw the stage:
/// two views would mean two copies of the model in memory, both animating.
@MainActor
final class CompanionOverlay: ObservableObject {
    static let shared = CompanionOverlay()

    static let onKey = "kinclaw.companion.overlay"
    static let frameKey = "kinclaw.companion.overlay.frame"
    static let clickThroughKey = "kinclaw.companion.overlay.clickThrough"

    /// Whether she is on the desktop right now.
    @Published private(set) var isOn = false
    /// Whether she ignores the mouse entirely.
    @Published private(set) var clickThrough =
        UserDefaults.standard.bool(forKey: CompanionOverlay.clickThroughKey)

    private var window: NSPanel?

    private init() {}

    /// Put her back where she was, if she was out.
    ///
    /// Not in `init`: the content view holds `CompanionOverlay.shared`, so
    /// showing the window while the singleton is still being created
    /// re-enters its own `dispatch_once` and traps. Called once at launch
    /// instead, when there is a `shared` to observe.
    func restoreIfWanted() {
        guard !isOn, UserDefaults.standard.bool(forKey: Self.onKey) else { return }
        show()
    }

    func toggle() { isOn ? hide() : show() }

    func show() {
        // She is the whole content of this window, so the stage has to be
        // running for it to be worth putting up. Companion mode starts it on
        // entry; the desktop has no entry — she is just there, including on
        // the launch after a restart.
        if VRMWardrobe.isEnabled, VRMServerBox.shared.base == nil {
            VRMServerBox.shared.startIfWanted()
        }
        guard window == nil else { window?.orderFrontRegardless(); isOn = true; return }
        let panel = NSPanel(contentRect: savedFrame(),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = clickThrough
        // A WKWebView eats every mouse event it is offered, so
        // `isMovableByWindowBackground` never sees the drag and she cannot be
        // picked up. The window's own view takes the hit instead and asks the
        // window to drag itself; only the top strip is passed through, which
        // is where the controls are.
        let root = OverlayRootView(frame: NSRect(origin: .zero, size: savedFrame().size))
        let host = NSHostingView(rootView: CompanionOverlayContent())
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        panel.contentView = root
        panel.delegate = frameSaver
        panel.orderFrontRegardless()
        window = panel
        isOn = true
        UserDefaults.standard.set(true, forKey: Self.onKey)
        watchPointer()
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.orderOut(nil)
        window = nil
        isOn = false
        UserDefaults.standard.set(false, forKey: Self.onKey)
    }

    /// Stop taking clicks — she is then scenery, and the window behind her
    /// gets every event. Persisted, because someone who wants it wants it.
    func setClickThrough(_ on: Bool) {
        clickThrough = on
        UserDefaults.standard.set(on, forKey: Self.clickThroughKey)
        window?.ignoresMouseEvents = on
    }

    // MARK: - Her eyes

    private var monitor: Any?

    /// Follow the cursor anywhere on screen.
    ///
    /// The page's own listener never fires here: the window has to swallow
    /// the mouse to be draggable, and under 穿透 it receives nothing at all.
    /// Watched globally instead, which is also the better behaviour — a
    /// figure on the desktop looking at what you are doing across the whole
    /// screen, rather than only when the pointer crosses her.
    private func watchPointer() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.aimAtCursor() }
        }
        aimAtCursor()
    }

    private func aimAtCursor() {
        guard let frame = window?.frame else { return }
        let cursor = NSEvent.mouseLocation
        // Normalised against her own head's neighbourhood: the width of the
        // window either side is as far as her eyes need to travel before
        // they are simply "looking that way".
        let x = (cursor.x - frame.midX) / max(frame.width, 1)
        let y = (cursor.y - (frame.minY + frame.height * 0.78)) / max(frame.height * 0.5, 1)
        VRMStage.shared.look(x: Double(x), y: Double(y))
    }

    // MARK: - Where she stands

    /// Bottom-right by default, a figure's worth of screen, and never
    /// off-screen: a remembered frame from a monitor that is now unplugged
    /// would put her somewhere nobody can reach.
    private func savedFrame() -> NSRect {
        let size = NSSize(width: 360, height: 560)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fallback = NSRect(x: screen.maxX - size.width - 24,
                              y: screen.minY + 24, width: size.width, height: size.height)
        guard let saved = UserDefaults.standard.string(forKey: Self.frameKey) else { return fallback }
        let parts = saved.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return fallback }
        let rect = NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
        return visible ? rect : fallback
    }

    private lazy var frameSaver = OverlayFrameSaver()
}

/// The window's content view: it takes the drag so she can be picked up, and
/// lets the top strip through to the controls that live there.
///
/// AppKit hands `hitTest` a point in the *superview's* coordinates, which for
/// a content view is the window's content rect — origin bottom-left, so the
/// strip is at the top of `bounds`.
private final class OverlayRootView: NSView {
    /// How much of the top is controls rather than her.
    private let strip: CGFloat = 44

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if local.y > bounds.height - strip { return super.hitTest(point) }
        return self
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Remembers where she was put. A window delegate rather than a closure
/// because AppKit wants an object and this one has a single job.
@MainActor
private final class OverlayFrameSaver: NSObject, NSWindowDelegate {
    func windowDidMove(_ notification: Notification) { save(notification) }
    func windowDidResize(_ notification: Notification) { save(notification) }

    private func save(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        let f = w.frame
        UserDefaults.standard.set("\(f.origin.x),\(f.origin.y),\(f.width),\(f.height)",
                                  forKey: CompanionOverlay.frameKey)
    }
}

/// What the overlay draws: the character, and nothing that looks like a
/// window. The controls appear on hover, because a floating figure with a
/// permanent toolbar is a widget rather than somebody in the room.
private struct CompanionOverlayContent: View {
    @ObservedObject private var vrmServer = VRMServerBox.shared
    @ObservedObject private var vrm = VRMStage.shared
    @ObservedObject private var overlay = CompanionOverlay.shared
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            if let base = vrmServer.base {
                VRMStageView(base: base, onReady: { vrm.attach($0) })
            } else {
                // Nothing to draw yet: say so quietly rather than showing an
                // empty rectangle nobody can explain.
                Text("3D 形象没开")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(8)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .padding(.top, 20)
            }
            if hovering {
                HStack(spacing: 8) {
                    Button(overlay.clickThrough ? "可点" : "穿透") {
                        overlay.setClickThrough(!overlay.clickThrough)
                    }
                    .help("穿透之后她不再接收鼠标，点击会落到她后面的窗口")
                    Button("收起") { overlay.hide() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering = $0 }
    }
}

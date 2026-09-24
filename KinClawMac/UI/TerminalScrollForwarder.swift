import AppKit
import SwiftTerm

// MARK: - The wheel, for full-screen agents

/// SwiftTerm 1.10.1 never hands a wheel event to the program in the terminal.
/// `MacTerminalView.scrollWheel` (`Mac/MacTerminalView.swift:1198`) only ever
/// calls its own `scrollUp`/`scrollDown`, and those are bounded by the
/// scrollback the buffer has. The alternate screen buffer has none —
/// `Terminal.swift:626` builds `altBuffer` with `scrollback: nil`, deliberately,
/// since a full-screen TUI has nothing to scroll back through. So the wheel is
/// dead exactly where a program most wants it.
///
/// Claude Code is the case that shows. It switches to the alternate screen at
/// byte 13 of its first output (`?1049h`) and asks for every mouse mode it can
/// get (`?1000h ?1002h ?1003h ?1006h`) precisely so it can handle the wheel
/// itself — and in this version, never hears about it. Codex does not use the
/// alternate screen, which is why only Claude's Terminal looks broken.
///
/// Upstream fixed it in 1.19.0 (`b00cc898`). We are not taking that upgrade:
/// 1.19+ ships `Apple/Metal/Shaders.metal` as an SPM resource, which needs the
/// multi-gigabyte Metal toolchain Xcode 26 no longer bundles (`metallib` is
/// absent on this machine), on top of a plugin-trust flag for
/// `SwiftTermBuildInfoPlugin`. `project.yml` pinned 1.10.1 to stay clear of
/// exactly that, and a scrollbar is not worth reversing it for.
///
/// Overriding `scrollWheel` in a subclass is not an option either: it is
/// `public override`, not `open`, so no other module may override it.
///
/// So we take the event first and report it ourselves. Nothing here is
/// private API — `Terminal.encodeButton` (`Terminal.swift:5333`) and
/// `Terminal.sendEvent` (`Terminal.swift:5379`) already speak SGR, and
/// `cols`/`rows`/`mouseMode`/`isCurrentBufferAlternate`/`allowMouseReporting`
/// are all public.
///
/// Delete this file when SwiftTerm is bumped to >= 1.19.
@MainActor
enum TerminalScrollForwarder {

    private static var monitor: Any?

    /// Fractions of a cell left over from the last precise-delta event.
    /// A trackpad reports in points, a report is per line; without carrying
    /// the remainder a slow two-finger scroll rounds to zero every time and
    /// nothing ever moves.
    private static var residue: CGFloat = 0

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            forward(event)
        }
    }

    /// The event back, to let SwiftTerm have it; nil to swallow it.
    private static func forward(_ event: NSEvent) -> NSEvent? {
        guard let (view, point) = target(of: event) else { return event }
        let terminal = view.getTerminal()

        // Only the alternate screen. On the normal buffer SwiftTerm scrolls
        // its own scrollback and does it well — and a program that asks for
        // mouse reporting without taking the whole screen still expects the
        // buffer to scroll. Leave both alone.
        guard terminal.isCurrentBufferAlternate,
              view.allowMouseReporting,
              terminal.mouseMode != .off
        else {
            residue = 0
            return event
        }

        // Shift is the standing "let me scroll instead" escape hatch. On the
        // alternate screen there is nowhere to scroll to, so holding it does
        // nothing — which is what upstream settled on too.
        guard !event.modifierFlags.contains(.shift) else {
            residue = 0
            return event
        }

        let height = view.bounds.height
        let cellHeight = height / CGFloat(terminal.rows)
        let cellWidth = view.bounds.width / CGFloat(terminal.cols)
        guard cellHeight > 0, cellWidth > 0 else { return event }

        let lines: Int
        if event.hasPreciseScrollingDeltas {
            residue += event.scrollingDeltaY
            lines = Int(residue / cellHeight)
            residue -= CGFloat(lines) * cellHeight
        } else {
            residue = 0
            lines = Int(event.scrollingDeltaY.rounded())
        }
        // Swallow a zero-line event rather than passing it on: SwiftTerm's
        // handler is the one we are here to pre-empt, and on the alternate
        // screen it has nothing useful to do with it.
        guard lines != 0 else { return nil }

        let col = clamp(Int(point.x / cellWidth), 0, terminal.cols - 1)
        // The view is not flipped, so y grows upward from its bottom edge.
        let row = clamp(Int((height - point.y) / cellHeight), 0, terminal.rows - 1)

        // 4 and 5 are wheel up and wheel down; encodeButton turns them into
        // the 64/65 the SGR report wants.
        let flags = terminal.encodeButton(button: lines > 0 ? 4 : 5, release: false,
                                          shift: false, meta: false, control: false)
        for _ in 0 ..< abs(lines) {
            terminal.sendEvent(buttonFlags: flags, x: col, y: row,
                               pixelX: Int(point.x), pixelY: Int(height - point.y))
        }
        return nil
    }

    /// The terminal the pointer is over, and where in it, in its own
    /// coordinates. The hit test lands on the deepest view and SwiftTerm keeps
    /// a caret and a scroller in the way, so walk up until a terminal shows.
    private static func target(of event: NSEvent) -> (LocalProcessTerminalView, NSPoint)? {
        // A scroll event carries the window it was delivered to. An event that
        // arrives without one still came from wherever the pointer is.
        let window = event.window ?? windowUnderCursor()
        guard let root = window?.contentView, let window else { return nil }
        let inWindow = event.window != nil
            ? event.locationInWindow
            : window.convertPoint(fromScreen: NSEvent.mouseLocation)

        var view: NSView? = root.hitTest(root.convert(inWindow, from: nil))
        while let current = view {
            if let terminal = current as? LocalProcessTerminalView {
                return (terminal, terminal.convert(inWindow, from: nil))
            }
            view = current.superview
        }
        return nil
    }

    private static func windowUnderCursor() -> NSWindow? {
        let cursor = NSEvent.mouseLocation
        return NSApp.windows.first { $0.isVisible && $0.frame.contains(cursor) }
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(high, max(low, value))
    }
}

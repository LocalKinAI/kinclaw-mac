import AppKit
import SwiftTerm

/// The scroll wheel, for a program in a terminal.
///
/// SwiftTerm (1.10) turns the wheel into scrolling its own scrollback and
/// nothing else, and its `scrollWheel` is not open to override. A full-screen
/// program — Claude Code's own TUI among them — draws on the alternate screen,
/// which has no scrollback, and asks for the mouse so that it can scroll
/// itself: in the agents' terminals the wheel did nothing ("不能在claude code
/// 里面滚轮啊"). So the wheel is caught on its way in, before the view sees it,
/// and given to the program the way Terminal.app and iTerm give it: as mouse
/// buttons 4 and 5 to one that asked for the mouse, as arrow keys to one on the
/// alternate screen that did not. Everything else goes on to SwiftTerm.
@MainActor
enum TerminalWheel {
    private static var monitor: Any?
    /// Wheel travel not yet a whole line: a trackpad sends it in points.
    private static var pending: CGFloat = 0

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// True when the wheel went to a program, and SwiftTerm is not to see it.
    private static func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window,
              var view = window.contentView?.hitTest(event.locationInWindow) else { return false }
        while !(view is TerminalView) {
            guard let up = view.superview else { return false }
            view = up
        }
        guard let terminalView = view as? TerminalView else { return false }
        let terminal = terminalView.getTerminal()
        let wantsMouse = terminalView.allowMouseReporting && terminal.mouseMode != .off
        guard wantsMouse || terminal.isCurrentBufferAlternate else { return false }

        let lineHeight = max(1, terminalView.bounds.height / CGFloat(max(terminal.rows, 1)))
        pending += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / lineHeight : event.deltaY
        let lines = Int(pending)                       // whole lines, toward zero
        guard lines != 0 else { return true }
        pending -= CGFloat(lines)
        let up = lines > 0, count = min(abs(lines), 8)

        if wantsMouse {
            let point = terminalView.convert(event.locationInWindow, from: nil)
            let cellWidth = terminalView.bounds.width / CGFloat(max(terminal.cols, 1))
            let col = min(max(0, Int(point.x / cellWidth)), terminal.cols - 1)
            let row = min(max(0, Int((terminalView.bounds.height - point.y) / lineHeight)), terminal.rows - 1)
            let flags = terminal.encodeButton(button: up ? 4 : 5, release: false,
                                              shift: event.modifierFlags.contains(.shift),
                                              meta: event.modifierFlags.contains(.option),
                                              control: event.modifierFlags.contains(.control))
            for _ in 0..<count { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        } else {
            let key = terminal.applicationCursor ? (up ? "\u{1b}OA" : "\u{1b}OB") : (up ? "\u{1b}[A" : "\u{1b}[B")
            for _ in 0..<count { terminalView.send(txt: key) }
        }
        return true
    }
}

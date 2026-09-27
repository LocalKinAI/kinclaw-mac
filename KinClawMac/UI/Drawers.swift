import AppKit
import SwiftUI

/// The browser and the shell: tools beside whichever tab is up, not tabs of
/// their own ("web 和 shell 可以作为辅助工具……不是在 tab 上，用时自动打开，
/// 或者手动打开"). The browser comes in on the right, the shell along the
/// bottom. Each opens by hand from the title bar; the browser also opens on
/// its own when an agent opens a page in it, without taking the keyboard from
/// wherever you were typing. Closing a drawer only hides it: its pages and
/// its shells go on (BrowserTabs and AgentTerminalSessions hold them).
@MainActor
final class Drawers: ObservableObject {
    static let shared = Drawers()

    @Published private(set) var browser = UserDefaults.standard.bool(forKey: "kinclaw.drawer.browser")
    @Published private(set) var shell = UserDefaults.standard.bool(forKey: "kinclaw.drawer.shell")
    @Published var browserWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "kinclaw.drawer.browser.width")
        return saved > 0 ? saved : 520
    }() {
        didSet { UserDefaults.standard.set(Double(browserWidth), forKey: "kinclaw.drawer.browser.width") }
    }
    @Published var shellHeight: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "kinclaw.drawer.shell.height")
        return saved > 0 ? saved : 220
    }() {
        didSet { UserDefaults.standard.set(Double(shellHeight), forKey: "kinclaw.drawer.shell.height") }
    }

    /// The window as it was before the browser widened it, to go back to.
    private var widenedFrom: (before: NSRect, after: NSRect)?

    // MARK: The browser

    func toggleBrowser() { browser ? closeBrowser() : openBrowser() }

    /// Open the browser drawer. A tool opening a page opens it too; the page
    /// is the tool's, so nothing in the drawer asks for the keyboard then.
    func openBrowser() {
        guard !browser else { return }
        widen()
        withAnimation(.easeOut(duration: 0.18)) { browser = true }
        UserDefaults.standard.set(true, forKey: "kinclaw.drawer.browser")
    }

    func closeBrowser() {
        guard browser else { return }
        withAnimation(.easeOut(duration: 0.18)) { browser = false }
        UserDefaults.standard.set(false, forKey: "kinclaw.drawer.browser")
        narrow()
    }

    /// A panel too narrow for a page beside what it shows grows to hold both.
    private func widen() {
        guard let window = (NSApp.delegate as? AppDelegate)?.spotlightWindow,
              !window.styleMask.contains(.fullScreen) else { return }
        let wanted = browserWidth + 440
        guard window.frame.width < wanted else { widenedFrom = nil; return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        var frame = window.frame
        frame.size.width = min(wanted, visible.width)
        if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        widenedFrom = (window.frame, frame)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Back to the width it had — unless the window has been resized since.
    private func narrow() {
        defer { widenedFrom = nil }
        guard let (before, after) = widenedFrom,
              let window = (NSApp.delegate as? AppDelegate)?.spotlightWindow,
              !window.styleMask.contains(.fullScreen), window.frame.size == after.size else { return }
        var frame = window.frame
        frame.size.width = before.width
        frame.origin.x = window.frame.origin.x + (after.origin.x == before.origin.x ? 0 : before.origin.x - after.origin.x)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: The shell

    func toggleShell() {
        if shell {
            withAnimation(.easeOut(duration: 0.18)) { shell = false }
        } else {
            if AgentTerminalSessions.shared.shells.isEmpty { AgentTerminalSessions.shared.newShell() }
            withAnimation(.easeOut(duration: 0.18)) { shell = true }
        }
        UserDefaults.standard.set(shell, forKey: "kinclaw.drawer.shell")
    }

    /// A new shell in `folder`, the drawer open on it.
    func openShell(in folder: String?) {
        AgentTerminalSessions.shared.newShell(in: folder)
        withAnimation(.easeOut(duration: 0.18)) { shell = true }
        UserDefaults.standard.set(true, forKey: "kinclaw.drawer.shell")
    }
}

// MARK: - The drawers

/// The browser, down the right of the panel.
struct BrowserDrawer: View {
    @ObservedObject private var drawers = Drawers.shared

    var body: some View {
        HStack(spacing: 0) {
            DrawerHandle(vertical: true) { delta in
                drawers.browserWidth = min(max(drawers.browserWidth - delta, 320), 1400)
            }
            WebPane()
        }
        .frame(width: drawers.browserWidth)
    }
}

/// Your own shells, along the bottom of the panel.
struct ShellDrawer: View {
    @ObservedObject private var drawers = Drawers.shared
    @ObservedObject private var sessions = AgentTerminalSessions.shared

    private typealias Session = AgentTerminalSessions.Session

    var body: some View {
        VStack(spacing: 0) {
            DrawerHandle(vertical: false) { delta in
                drawers.shellHeight = min(max(drawers.shellHeight - delta, 120), 900)
            }
            HStack(spacing: 6) {
                Image(systemName: "apple.terminal").font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sessions.shells) { s in tab(s) }
                    }
                }
                Button { sessions.newShell(in: sessions.selectedShell.map(AgentTerminalSessions.folder(of:))) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("再开一个 shell，在同一个文件夹里")
                Button { drawers.toggleShell() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("收起（shell 还在跑）")
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.sidebar)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            if let s = sessions.selectedShell, let terminal = sessions.terminal(for: s) {
                TerminalSlot(terminal: terminal)
                    .id(s.id)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(nsColor: NSColor(calibratedWhite: 0.06, alpha: 1)))
            } else {
                HStack {
                    Text("没有开着的 shell").font(.kinCaption).foregroundStyle(.secondary)
                    Button("开一个") { sessions.newShell() }.buttonStyle(.quietFilled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: drawers.shellHeight)
    }

    private func tab(_ s: Session) -> some View {
        let active = s.id == sessions.selectedShell?.id
        let running = sessions.running.contains(s.id)
        return HStack(spacing: 5) {
            Circle().fill(running ? Theme.good : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
            Text((AgentTerminalSessions.folder(of: s) as NSString).lastPathComponent)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .lineLimit(1)
            Button { sessions.close(s.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("关掉这个 shell")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(active ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { sessions.selectedShellID = s.id }
        .help(AgentTerminalSessions.folder(of: s) + (sessions.notes[s.id].map { "\n" + $0 } ?? ""))
    }
}

/// The edge a drawer is dragged by.
private struct DrawerHandle: View {
    /// A vertical line, dragged sideways; else a horizontal one, dragged up and down.
    let vertical: Bool
    let moved: (CGFloat) -> Void

    @State private var last: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
            .padding(vertical ? .horizontal : .vertical, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let now = vertical ? value.translation.width : value.translation.height
                    moved(now - last)
                    last = now
                }
                .onEnded { _ in last = 0 })
    }
}

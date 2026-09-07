import AppKit
import KeyboardShortcuts

/// Owns the 🦞 NSStatusItem in the system menubar and its dropdown.
/// One instance, held by AppDelegate.
///
/// What lives in the menu (M3 minimum):
///
///   🦞  KinClawMac (status item)
///   ├─ Show / Hide KinClaw       ⌘⌥K
///   ├─ ─────────
///   ├─ Settings…                 ⌘,
///   ├─ ─────────
///   └─ Quit KinClaw Mac          ⌘Q
///
/// M5 will add: soul switcher submenu, About, Open Logs Folder,
/// "Launch at Login" toggle.
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem

    /// Dispatched to AppDelegate. Each callback is independent so a
    /// future test harness can drive the menu without instantiating
    /// the whole delegate.
    var onShowHide: (() -> Void)?
    var onCompanion: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()
        configureButton()
        statusItem.menu = buildMenu()
    }

    // MARK: - Status item button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Emoji glyph as the icon. Once we ship a proper template
        // image (M5 / icon design pass) this becomes
        // `button.image = NSImage(named: "MenubarIcon")`.
        button.title = "🦞"
        button.toolTip = "KinClaw Mac — ⌘⌥K to summon"
        // Slight font tweak so the lobster doesn't look cramped on
        // the system menubar.
        button.font = NSFont.systemFont(ofSize: 14)
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show / Hide KinClaw",
            action: #selector(showHideTapped),
            keyEquivalent: "k"
        )
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = self
        menu.addItem(toggle)

        let companion = NSMenuItem(
            title: "陪伴模式 · Companion",
            action: #selector(companionTapped),
            keyEquivalent: "")
        companion.target = self
        menu.addItem(companion)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsTapped),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit KinClaw Mac",
            action: #selector(quitTapped),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Menu actions

    @objc private func showHideTapped() { onShowHide?() }
    @objc private func companionTapped() { onCompanion?() }
    @objc private func settingsTapped() { onOpenSettings?() }
    @objc private func quitTapped()     { onQuit?() }
}

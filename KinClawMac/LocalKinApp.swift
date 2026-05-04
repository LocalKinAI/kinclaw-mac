import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - App entry
//
// KinClaw Mac is a menubar-only app (LSUIElement = true in Info.plist).
// We don't ship a `WindowGroup` — instead AppDelegate constructs a
// single floating `SpotlightWindow` whose content is the SwiftUI tree
// previously hosted in the iOS WindowGroup. The Settings scene gives
// the user the standard ⌘, hotkey for preferences.
//
// M3 will add the global hotkey + menubar; for now the panel just
// shows on launch.

@main
struct KinClawMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Mac-native settings — hotkey recorder + launch-at-login
            // + about. The iOS-ported SettingsView (license keys /
            // trial / Lemon Squeezy) lives on disk but isn't
            // referenced from here; that whole tier belongs on
            // localkin.dev account pages, not on a free local dock.
            KinClawMacSettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App Delegate

/// Owns the spotlight window + AppState singleton-ish instance.
/// AppDelegate is wired via `@NSApplicationDelegateAdaptor` so its
/// lifetime matches the process. Storing AppState here (rather than
/// `@StateObject` on the App struct) lets the AppKit-native window
/// path access it without going through SwiftUI's environment.
///
/// `@MainActor` because every property and method here touches AppKit
/// or SwiftUI state — AppKit guarantees delegate calls land on main,
/// and the @MainActor isolation lets us own a @MainActor-isolated
/// KinClawSupervisor without async hops in `applicationWillTerminate`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single source of truth for trial / license / counters. Both
    /// the spotlight panel's SwiftUI tree and the Settings scene
    /// observe it via `.environmentObject`.
    let appState = AppState()

    /// The one floating chat panel.
    private(set) var spotlightWindow: SpotlightWindow!

    /// 🦞 NSStatusItem in the menubar.
    private(set) var menuBar: MenuBarController!

    /// Local kinclaw subprocess manager.
    let supervisor = KinClawSupervisor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-shot migration: if the user has chat history saved
        // under the old UserDefaults `chat_<slug>` keys, rewrite as
        // session JSONs in ~/.kinclaw/sessions/ and clear the keys.
        // Idempotent — flag stops re-runs.
        ChatSessionStore.migrateFromUserDefaults()
        // 1. Build the floating spotlight panel with the
        //    Spotlight-shaped single-pane chat view (replacing the
        //    iOS-shaped TabView ContentView, which was too cramped
        //    in a 380×600 floating panel).
        spotlightWindow = SpotlightWindow {
            SpotlightContentView()
                .environmentObject(self.appState)
                .preferredColorScheme(.dark)
        }

        // 2. Wire the menubar (🦞) + its dropdown actions.
        menuBar = MenuBarController()
        menuBar.onShowHide      = { [weak self] in self?.spotlightWindow.toggle() }
        menuBar.onOpenSettings  = { [weak self] in self?.openSettingsWindow() }
        menuBar.onQuit          = { NSApp.terminate(nil) }
        // The menubar's "Settings…" item triggers via NSApp.activate
        // + sendAction; that route works because clicking a menu bar
        // item DOES activate the app properly. The panel header's
        // ⚙ uses SwiftUI's SettingsLink instead (more reliable
        // when the panel is the only visible UI surface).

        // 3. Register the global ⌘⌥K hotkey. KeyboardShortcuts
        //    handles the Carbon-level event tap; we just provide
        //    the toggle closure.
        KeyboardShortcuts.onKeyDown(for: .toggleKinClaw) { [weak self] in
            self?.spotlightWindow.toggle()
        }

        // 4. First-launch courtesy: show the panel so a brand-new
        //    user can see what they just installed. Subsequent
        //    launches stay hidden — the hotkey / menubar are now
        //    the entry points.
        let firstShownKey = "kinclaw.firstLaunchPanelShown"
        if !UserDefaults.standard.bool(forKey: firstShownKey) {
            spotlightWindow.show()
            UserDefaults.standard.set(true, forKey: firstShownKey)
        }

        // 5. Cloud auth refresh — same as the iOS version did at launch.
        Task { await TokenManager.shared.refreshFromRemote() }

        // 6. Bring up the local kinclaw subprocess (or adopt an
        //    existing one on :5001). Runs async so the UI doesn't
        //    block on the boot probe.
        Task { await supervisor.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown of our owned kinclaw subprocess. Adopted
        // external kinclaws are left alone — they belong to the user.
        supervisor.stop()
    }

    /// Opens (or focuses) the SwiftUI Settings scene. The legacy
    /// `showSettingsWindow:` selector is the only sanctioned way
    /// to programmatically open a `Settings { }` scene from AppKit
    /// land; SwiftUI 14's `SettingsLink` only works inside a SwiftUI
    /// hierarchy.
    private func openSettingsWindow() {
        // Bring the app forward first — settings appears as a normal
        // window which expects an active app.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            // Newer SwiftUI selector form
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            // Pre-14 fallback (we target 14+ so this branch never
            // runs, but keeping it documents the older API).
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menubar-only app: closing the spotlight window must NOT
        // quit the process. Quit comes from the menubar (M3) or
        // ⌘Q while the panel is key.
        false
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var licenseKey: String {
        didSet { UserDefaults.standard.set(licenseKey, forKey: "license_key") }
    }
    @Published var isPro: Bool = false
    @Published var dailyMessageCount: Int {
        didSet { UserDefaults.standard.set(dailyMessageCount, forKey: "daily_msg_count") }
    }
    @Published var lastMessageDate: String {
        didSet { UserDefaults.standard.set(lastMessageDate, forKey: "last_msg_date") }
    }

    let freeMessageLimit = 30
    let trialDays = 7

    // MARK: - Trial System

    /// First launch date — set once, never changes
    var firstLaunchDate: Date {
        if let stored = UserDefaults.standard.object(forKey: "first_launch_date") as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: "first_launch_date")
        return now
    }

    /// Days since first launch
    var daysSinceFirstLaunch: Int {
        Calendar.current.dateComponents([.day], from: firstLaunchDate, to: Date()).day ?? 0
    }

    /// Is the user still in the free trial period?
    var isInTrial: Bool {
        daysSinceFirstLaunch < trialDays
    }

    /// Days remaining in trial
    var trialDaysRemaining: Int {
        max(0, trialDays - daysSinceFirstLaunch)
    }

    // MARK: - Message Limits

    var messagesRemaining: Int {
        if isPro || isInTrial { return .max }
        return max(0, freeMessageLimit - dailyMessageCount)
    }

    var canSendMessage: Bool {
        isPro || isInTrial || dailyMessageCount < freeMessageLimit
    }

    /// Display string for remaining messages
    var remainingDisplay: String {
        if isPro { return "Pro" }
        if isInTrial { return "Trial: \(trialDaysRemaining)d left" }
        return "\(max(0, freeMessageLimit - dailyMessageCount)) msgs left"
    }

    // MARK: - Restricted Boards

    var canAccessProBoards: Bool {
        isPro || isInTrial
    }

    // MARK: - Init

    init() {
        self.licenseKey = UserDefaults.standard.string(forKey: "license_key") ?? ""
        self.dailyMessageCount = UserDefaults.standard.integer(forKey: "daily_msg_count")
        self.lastMessageDate = UserDefaults.standard.string(forKey: "last_msg_date") ?? ""
        self.isPro = !self.licenseKey.isEmpty

        // Ensure firstLaunchDate is set
        _ = firstLaunchDate

        // Reset daily count if new day
        let today = Self.todayString()
        if self.lastMessageDate != today {
            self.dailyMessageCount = 0
            self.lastMessageDate = today
        }
    }

    func recordMessage() {
        // Pro and trial users: don't count
        guard !isPro && !isInTrial else { return }

        let today = Self.todayString()
        if lastMessageDate != today {
            dailyMessageCount = 0
            lastMessageDate = today
        }
        dailyMessageCount += 1
    }

    func setLicenseKey(_ key: String) {
        licenseKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        isPro = !licenseKey.isEmpty
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            AgentListView()
                .tabItem {
                    Label("Agents", systemImage: "person.3.fill")
                }

            HomeView()
                .tabItem {
                    Label("KinBook", systemImage: "newspaper.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color("AccentGreen"))
    }
}

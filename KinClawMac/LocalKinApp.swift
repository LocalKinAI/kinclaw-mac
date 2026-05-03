import SwiftUI
import AppKit

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
            SettingsView()
                .environmentObject(appDelegate.appState)
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single source of truth for trial / license / counters. Both
    /// the spotlight panel's SwiftUI tree and the Settings scene
    /// observe it via `.environmentObject`.
    let appState = AppState()

    /// The one floating chat panel.
    private(set) var spotlightWindow: SpotlightWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build the panel with the existing SwiftUI ContentView as
        // its body. M3+ will swap ContentView for a Spotlight-shape
        // single-column UX; for now we want to validate the panel
        // hosts our existing views correctly.
        spotlightWindow = SpotlightWindow {
            ContentView()
                .environmentObject(self.appState)
                .preferredColorScheme(.dark)
        }
        // Show on launch. Once M3 lands the global hotkey we'll
        // start hidden and let ⌘⌥K do the summoning.
        spotlightWindow.show()

        // Cloud auth refresh — same as the iOS version did at launch.
        Task { await TokenManager.shared.refreshFromRemote() }
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

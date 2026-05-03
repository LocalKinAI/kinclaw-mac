import SwiftUI
import KeyboardShortcuts
import ServiceManagement

/// Native macOS settings for KinClaw Mac, served by the
/// `Settings { }` scene in KinClawMacApp. Replaces the iOS-ported
/// SettingsView (license keys / trial / Lemon Squeezy) which was
/// mismatched for the dock context — KinClaw Mac is free + local-
/// first; the trial/Pro mechanics live on the cloud-side LocalKin
/// account, not here.
///
/// What lives here:
///   - General: launch at login
///   - Hotkey: ⌘⌥K recorder (rebindable)
///   - About: version / GitHub / kinclaw status
///
/// Sectioned NSTabView via SwiftUI `TabView` with default macOS
/// settings styling (`.tabViewStyle(.automatic)` becomes the
/// pill-tab style on macOS).
struct KinClawMacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "command") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 460, minHeight: 280)
        .padding(20)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("kinclaw.launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        applyLaunchAtLogin(enabled)
                    }
                Text("KinClaw Mac runs in the menubar. Enable this to have it ready as soon as you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// macOS 13+ ServiceManagement API — no plist editing, no
    /// LaunchAgent file shuffling. Errors are silent here; if the
    /// user wants a louder failure mode it lands in M-something.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status != .enabled { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] launch-at-login toggle failed: \(error)")
        }
    }
}

// MARK: - Hotkey

private struct HotkeySettingsTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Toggle KinClaw") {
                    KeyboardShortcuts.Recorder(for: .toggleKinClaw)
                }
                Text("Click the field to record a new shortcut. Default is ⌘⌥K. Pick something the rest of macOS doesn't already use — Spotlight (⌘Space), Raycast / Alfred (⌥Space) etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    @StateObject private var supervisor = ObservableSupervisor()

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Bundle ID",
                               value: Bundle.main.bundleIdentifier ?? "?")
                LabeledContent("Local kinclaw",
                               value: supervisor.statusDescription)
                    .foregroundColor(supervisor.statusColor)
            }
            Section {
                Link("kinclaw on GitHub",
                     destination: URL(string: "https://github.com/LocalKinAI/kinclaw")!)
                Link("LocalKin Dev",
                     destination: URL(string: "https://www.localkin.dev")!)
            }
        }
        .formStyle(.grouped)
        .task { await supervisor.refresh() }
    }
}

// MARK: - Supervisor probe (for the About panel)
//
// We don't get easy access to AppDelegate.supervisor from here
// without env-injecting it through the Scene — for the read-only
// About display we re-probe `localhost:5001/api/souls` directly.
// The real supervisor inside AppDelegate is what's actually managing
// the subprocess; this is just a UI mirror.

@MainActor
private final class ObservableSupervisor: ObservableObject {
    enum State {
        case probing
        case running(soulCount: Int)
        case unreachable
    }

    @Published var state: State = .probing

    var statusDescription: String {
        switch state {
        case .probing:           return "Probing…"
        case .unreachable:       return "Not running"
        case .running(let n):    return "Running — \(n) souls"
        }
    }

    var statusColor: Color {
        switch state {
        case .probing:     return .secondary
        case .unreachable: return .red
        case .running:     return .green
        }
    }

    func refresh() async {
        do {
            let souls = try await KinClawAPIClient.default.fetchSouls()
            state = .running(soulCount: souls.count)
        } catch {
            state = .unreachable
        }
    }
}

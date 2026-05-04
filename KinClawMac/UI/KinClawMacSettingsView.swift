import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit

/// Native macOS settings for KinClaw Mac, served by the
/// `Settings { }` scene in KinClawMacApp.
///
/// Six tabs:
///   - General — launch-at-login + startup behavior + language
///   - Hotkey — ⌘⌥K rebind
///   - Backend — local kinclaw port / binary path + SearXNG / STT / TTS endpoints
///   - Agents — default agent + visible groups + welcome chips toggle
///   - Voice — TTS voice/speed + silence threshold + auto-continue
///   - Data — disk locations / sizes / clear-all + reveal-in-Finder
///   - About — version + cloud status + GitHub
///
/// All prefs persist via @AppStorage under the `kinclaw.` prefix so
/// the existing UserDefaults plist already collects them — no new
/// storage layer needed for the settings themselves.
struct KinClawMacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "command") }

            BackendSettingsTab()
                .tabItem { Label("Backend", systemImage: "server.rack") }

            AgentsSettingsTab()
                .tabItem { Label("Agents", systemImage: "person.3") }

            VoiceSettingsTab()
                .tabItem { Label("Voice", systemImage: "waveform") }

            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "externaldrive") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("kinclaw.launchAtLogin") private var launchAtLogin = false
    @AppStorage("kinclaw.startupBehavior") private var startupBehavior =
        StartupBehavior.lastState.rawValue
    @AppStorage("kinclaw.lang") private var lang = "auto"

    enum StartupBehavior: String, CaseIterable, Identifiable {
        case lastState = "last"
        case alwaysShow = "show"
        case alwaysHidden = "hidden"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastState:    return "Restore last state"
            case .alwaysShow:   return "Always show panel"
            case .alwaysHidden: return "Always hidden (menubar only)"
            }
        }
    }

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        applyLaunchAtLogin(enabled)
                    }
                Picker("On startup", selection: $startupBehavior) {
                    ForEach(StartupBehavior.allCases) { b in
                        Text(b.label).tag(b.rawValue)
                    }
                }
            }

            Section("Language") {
                Picker("Interface & agent replies", selection: $lang) {
                    Text("Auto (system locale)").tag("auto")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                Text("Cloud agents honor this for replies (X-Lang header). UI labels stay bilingual; full localization comes later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

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
            Section("Global hotkey") {
                LabeledContent("Toggle KinClaw") {
                    KeyboardShortcuts.Recorder(for: .toggleKinClaw)
                }
                Text("Click the field to record a new shortcut. Default is ⌘⌥K. Pick something macOS doesn't already use — Spotlight (⌘Space), Alfred / Raycast (⌥Space) etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Backend

private struct BackendSettingsTab: View {
    @AppStorage("kinclaw.backend.port") private var port = 5001
    @AppStorage("kinclaw.backend.binaryOverride") private var binaryOverride = ""
    @AppStorage("kinclaw.backend.searxng") private var searxng = "http://localhost:8080"
    @AppStorage("kinclaw.backend.stt") private var stt = "http://localhost:8000"
    @AppStorage("kinclaw.backend.tts") private var tts = "http://localhost:8001"

    @State private var localStatus = "Probing…"

    var body: some View {
        Form {
            Section("Local kinclaw") {
                LabeledContent("Port") {
                    TextField("5001", value: $port, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Binary override") {
                    HStack {
                        TextField("auto-detect", text: $binaryOverride)
                            .textFieldStyle(.roundedBorder)
                        Button("Pick…") { pickBinary() }
                    }
                }
                LabeledContent("Status", value: localStatus)
                Text("Changes take effect on next supervisor restart. Quit + relaunch KinClaw Mac to apply.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Sidecars") {
                LabeledContent("SearXNG") {
                    TextField("", text: $searxng)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("STT") {
                    TextField("", text: $stt)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("TTS") {
                    TextField("", text: $tts)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Hot-reloaded — voice / search calls use the new endpoints immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        do {
            let souls = try await KinClawAPIClient.default.fetchSouls()
            localStatus = "Running — \(souls.count) soul\(souls.count == 1 ? "" : "s")"
        } catch {
            localStatus = "Not reachable"
        }
    }

    private func pickBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Pick the kinclaw binary"
        if panel.runModal() == .OK, let url = panel.url {
            binaryOverride = url.path
        }
    }
}

// MARK: - Agents

private struct AgentsSettingsTab: View {
    @AppStorage("kinclaw.agents.defaultMode") private var defaultMode = DefaultMode.lastUsed.rawValue
    @AppStorage("kinclaw.agents.showKinClaw") private var showKinClaw = true
    @AppStorage("kinclaw.agents.showCore") private var showCore = true
    @AppStorage("kinclaw.agents.showFaith") private var showFaith = true
    @AppStorage("kinclaw.agents.showHeal") private var showHeal = true
    @AppStorage("kinclaw.agents.showSuggestionChips") private var showSuggestionChips = true
    @AppStorage("kinclaw.agents.showRecentRow") private var showRecentRow = true

    enum DefaultMode: String, CaseIterable, Identifiable {
        case lastUsed = "last"
        case pilot = "pilot"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastUsed: return "Last used"
            case .pilot:    return "Always KinClaw Pilot"
            }
        }
    }

    var body: some View {
        Form {
            Section("Default on launch") {
                Picker("Selected agent", selection: $defaultMode) {
                    ForEach(DefaultMode.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
            }

            Section("Visible groups in picker") {
                Toggle("🦞  KinClaw  (local computer-use)", isOn: $showKinClaw)
                Toggle("⭐  Core  (api.localkin.dev landing)", isOn: $showCore)
                Toggle("📜  Faith / Selah  (spiritual masters)", isOn: $showFaith)
                Toggle("🌿  Heal / 岐黄  (TCM masters)", isOn: $showHeal)
            }

            Section("Welcome screen") {
                Toggle("Show suggestion chips", isOn: $showSuggestionChips)
                Toggle("Show recent agents on hover", isOn: $showRecentRow)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Voice

private struct VoiceSettingsTab: View {
    @AppStorage("kinclaw.voice.tts.speaker") private var speaker = "auto"
    @AppStorage("kinclaw.voice.tts.speed") private var speed: Double = 1.0
    @AppStorage("kinclaw.voice.silenceThresholdDB") private var silenceDB: Double = -35
    @AppStorage("kinclaw.voice.autoContinue") private var autoContinue = false

    var body: some View {
        Form {
            Section("Speech-to-Text (microphone)") {
                LabeledContent("Silence threshold") {
                    HStack {
                        Slider(value: $silenceDB, in: -60 ... -20, step: 1)
                        Text("\(Int(silenceDB)) dB")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                Toggle("Voice-mode auto-continue (continuous conversation)",
                       isOn: $autoContinue)
                Text("Lower threshold = stops sooner on silence. -35dB suits a typical office; raise to -20dB for noisy rooms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Text-to-Speech (replies spoken)") {
                Picker("Voice", selection: $speaker) {
                    Text("Auto (zh: zf_xiaoxiao, en: af_heart)").tag("auto")
                    Text("zf_xiaoxiao (中文女声)").tag("zf_xiaoxiao")
                    Text("zf_xiaobei (中文女声)").tag("zf_xiaobei")
                    Text("zm_yunjian (中文男声)").tag("zm_yunjian")
                    Text("af_heart (English)").tag("af_heart")
                    Text("am_michael (English M)").tag("am_michael")
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $speed, in: 0.5 ... 2.0, step: 0.1)
                        Text(String(format: "%.1fx", speed))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Data

private struct DataSettingsTab: View {
    @State private var sessionsCount = 0
    @State private var kinclawSize = "calculating…"
    @State private var localkinSize = "calculating…"
    @State private var showingClearConfirm = false

    var body: some View {
        Form {
            Section("Locations") {
                pathRow("~/.kinclaw/", size: kinclawSize, action: revealKinclaw)
                pathRow("~/.localkin/", size: localkinSize, action: revealLocalkin)
            }

            Section("Sessions") {
                LabeledContent("Total saved",
                               value: "\(sessionsCount) session\(sessionsCount == 1 ? "" : "s")")
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear all sessions…",
                          systemImage: "trash")
                }
                .alert("Delete all chat sessions?",
                       isPresented: $showingClearConfirm) {
                    Button("Delete all", role: .destructive) { clearAllSessions() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes \(sessionsCount) session JSON file(s) under ~/.kinclaw/sessions/. Cannot be undone.")
                }
                Text("Individual sessions can be deleted via the 🕐 history popover in the chat header.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await refresh() }
    }

    private func pathRow(_ path: String, size: String,
                          action: @escaping () -> Void) -> some View {
        HStack {
            Text(path)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(size)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Reveal") { action() }
                .controlSize(.small)
        }
    }

    private func revealKinclaw() { reveal(path: ".kinclaw") }
    private func revealLocalkin() { reveal(path: ".localkin") }

    private func reveal(path: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func refresh() async {
        sessionsCount = ChatSessionStore.totalCount()
        kinclawSize = await dirSize(".kinclaw")
        localkinSize = await dirSize(".localkin")
    }

    private func dirSize(_ rel: String) async -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(rel)
        return await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { return "—" }
            var total: Int64 = 0
            for case let fileURL as URL in enumerator {
                let r = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey])
                if r?.isRegularFile == true {
                    total += Int64(r?.fileSize ?? 0)
                }
            }
            let f = ByteCountFormatter()
            f.countStyle = .file
            return f.string(fromByteCount: total)
        }.value
    }

    private func clearAllSessions() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".kinclaw/sessions")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { await refresh() }
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
            Section("Build") {
                LabeledContent("Version", value: version)
                LabeledContent("Bundle ID",
                               value: Bundle.main.bundleIdentifier ?? "?")
            }
            Section("Status") {
                LabeledContent("Local kinclaw",
                               value: supervisor.statusDescription)
                    .foregroundColor(supervisor.statusColor)
            }
            Section("Links") {
                Link("kinclaw on GitHub",
                     destination: URL(string: "https://github.com/LocalKinAI/kinclaw")!)
                Link("LocalKin Dev",
                     destination: URL(string: "https://www.localkin.dev")!)
                Link("Report an issue",
                     destination: URL(string: "https://github.com/LocalKinAI/kinclaw-mac/issues/new")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await supervisor.refresh() }
    }
}

// MARK: - Supervisor probe (for the About panel)

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

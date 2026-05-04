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
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, hotkey, backend, agents, voice, data, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .hotkey:  return "Hotkey"
            case .backend: return "Backend"
            case .agents:  return "Agents"
            case .voice:   return "Voice"
            case .data:    return "Data"
            case .about:   return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .hotkey:  return "command"
            case .backend: return "server.rack"
            case .agents:  return "person.3"
            case .voice:   return "waveform"
            case .data:    return "externaldrive"
            case .about:   return "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.15)
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
        }
        .frame(width: 540, height: 460)
        .preferredColorScheme(.dark)
        // Inject NSVisualEffectView .hudWindow .behindWindow into
        // the host NSWindow so Settings looks identical to the main
        // SpotlightWindow — true desktop-show-through glass, not
        // the SwiftUI-only .ultraThinMaterial layer that blurs only
        // against the window's own background.
        .background(WindowAccessor { window in
            applyGlassChrome(to: window)
        })
    }

    // Pill-style tab strip that mirrors the spotlight panel's
    // header buttons — small icons + labels on a translucent strip,
    // active tab highlighted with the green accent. Replaces the
    // default macOS Settings TabView chrome (which felt mismatched
    // next to the glass-blur main panel).
    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab
                                  ? Color.green.opacity(0.18)
                                  : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedTab == tab
                                    ? Color.green.opacity(0.4)
                                    : Color.clear,
                                    lineWidth: 0.5)
                    )
                    .foregroundColor(selectedTab == tab
                                     ? .green
                                     : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selectedTab {
                case .general: GeneralSettingsTab()
                case .hotkey:  HotkeySettingsTab()
                case .backend: BackendSettingsTab()
                case .agents:  AgentsSettingsTab()
                case .voice:   VoiceSettingsTab()
                case .data:    DataSettingsTab()
                case .about:   AboutSettingsTab()
                }
            }
            .padding(16)
        }
    }
}

// Card container mimicking the bubble surfaces in the main panel:
// rounded rectangle, secondary-background fill, subtle border.
private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.85))
                    .tracking(0.5)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.platformSecondaryBackground.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }
}

// Helper for "label : control" rows inside SettingsCard. Aligns
// labels to a fixed column for a tidy two-column look.
private struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
                .frame(width: 120, alignment: .leading)
            trailing()
            Spacer()
        }
    }
}

private struct SettingsCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Launch") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        applyLaunchAtLogin(enabled)
                    }
                SettingsRow(label: "On startup") {
                    Picker("", selection: $startupBehavior) {
                        ForEach(StartupBehavior.allCases) { b in
                            Text(b.label).tag(b.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
            }

            SettingsCard("Language") {
                SettingsRow(label: "Replies") {
                    Picker("", selection: $lang) {
                        Text("Auto (system locale)").tag("auto")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                SettingsCaption("Cloud agents honor this via X-Lang header. UI labels stay bilingual; full localization comes later.")
            }
        }
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
        SettingsCard("Global hotkey") {
            SettingsRow(label: "Toggle KinClaw") {
                KeyboardShortcuts.Recorder(for: .toggleKinClaw)
            }
            SettingsCaption("Click the field to record a new shortcut. Default is ⌘⌥K. Pick something macOS doesn't already use — Spotlight (⌘Space), Alfred / Raycast (⌥Space) etc.")
        }
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
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Local kinclaw") {
                SettingsRow(label: "Port") {
                    TextField("5001", value: $port, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsRow(label: "Binary override") {
                    HStack {
                        TextField("auto-detect", text: $binaryOverride)
                            .textFieldStyle(.roundedBorder)
                        Button("Pick…") { pickBinary() }
                            .controlSize(.small)
                    }
                }
                SettingsRow(label: "Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(localStatus.contains("Running")
                                  ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(localStatus)
                            .font(.system(size: 12))
                    }
                }
                SettingsCaption("Port / binary changes apply on next supervisor restart. Quit + relaunch to apply.")
            }

            SettingsCard("Sidecars") {
                SettingsRow(label: "SearXNG") {
                    TextField("", text: $searxng)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsRow(label: "STT") {
                    TextField("", text: $stt)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsRow(label: "TTS") {
                    TextField("", text: $tts)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsCaption("Hot-reloaded — voice / search calls use the new endpoints immediately.")
            }
        }
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
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Default on launch") {
                SettingsRow(label: "Selected agent") {
                    Picker("", selection: $defaultMode) {
                        ForEach(DefaultMode.allCases) { m in
                            Text(m.label).tag(m.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
            }

            SettingsCard("Visible groups in picker") {
                Toggle("🦞  KinClaw  (local computer-use)", isOn: $showKinClaw)
                Toggle("⭐  Core  (api.localkin.dev landing)", isOn: $showCore)
                Toggle("📜  Faith / Selah  (spiritual masters)", isOn: $showFaith)
                Toggle("🌿  Heal / 岐黄  (TCM masters)", isOn: $showHeal)
            }

            SettingsCard("Welcome screen") {
                Toggle("Show suggestion chips", isOn: $showSuggestionChips)
                Toggle("Show recent agents on hover", isOn: $showRecentRow)
            }
        }
    }
}

// MARK: - Voice

private struct VoiceSettingsTab: View {
    @AppStorage("kinclaw.voice.tts.speaker") private var speaker = "auto"
    @AppStorage("kinclaw.voice.tts.speed") private var speed: Double = 1.0
    @AppStorage("kinclaw.voice.silenceThresholdDB") private var silenceDB: Double = -35
    @AppStorage("kinclaw.voice.autoContinue") private var autoContinue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Speech-to-Text (microphone)") {
                SettingsRow(label: "Silence threshold") {
                    HStack {
                        Slider(value: $silenceDB, in: -60 ... -20, step: 1)
                            .frame(maxWidth: 200)
                        Text("\(Int(silenceDB)) dB")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Toggle("Voice-mode auto-continue (continuous conversation)",
                       isOn: $autoContinue)
                SettingsCaption("Lower threshold = stops sooner on silence. -35 dB suits a typical office; raise toward -20 dB for noisier rooms.")
            }

            SettingsCard("Text-to-Speech (replies spoken)") {
                SettingsRow(label: "Voice") {
                    Picker("", selection: $speaker) {
                        Text("Auto (zh: xiaoxiao · en: af_bella)").tag("auto")
                        Text("zf_xiaoxiao (中文女声)").tag("zf_xiaoxiao")
                        Text("zf_xiaobei (中文女声)").tag("zf_xiaobei")
                        Text("zm_yunjian (中文男声)").tag("zm_yunjian")
                        Text("af_bella (English F · default)").tag("af_bella")
                        Text("af_heart (English F)").tag("af_heart")
                        Text("am_michael (English M)").tag("am_michael")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                SettingsRow(label: "Speed") {
                    HStack {
                        Slider(value: $speed, in: 0.5 ... 2.0, step: 0.1)
                            .frame(maxWidth: 200)
                        Text(String(format: "%.1fx", speed))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Data

private struct DataSettingsTab: View {
    @State private var sessionsCount = 0
    @State private var kinclawSize = "calculating…"
    @State private var localkinSize = "calculating…"
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Locations") {
                pathRow("~/.kinclaw/", size: kinclawSize, action: revealKinclaw)
                pathRow("~/.localkin/", size: localkinSize, action: revealLocalkin)
            }

            SettingsCard("Sessions") {
                SettingsRow(label: "Total saved") {
                    Text("\(sessionsCount) session\(sessionsCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("Clear all sessions…", systemImage: "trash")
                }
                .controlSize(.small)
                .alert("Delete all chat sessions?",
                       isPresented: $showingClearConfirm) {
                    Button("Delete all", role: .destructive) { clearAllSessions() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes \(sessionsCount) session JSON file(s) under ~/.kinclaw/sessions/. Cannot be undone.")
                }
                SettingsCaption("Individual sessions can be deleted via the 🕐 history popover in the chat header.")
            }
        }
        .task { await refresh() }
    }

    private func pathRow(_ path: String, size: String,
                          action: @escaping () -> Void) -> some View {
        HStack {
            Text(path)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
            Text(size)
                .font(.system(size: 11, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 14) {
            // Hero: 🦞 + product name + version
            HStack(spacing: 14) {
                Text("🦞")
                    .font(.system(size: 42))
                VStack(alignment: .leading, spacing: 2) {
                    Text("KinClaw Mac")
                        .font(.system(size: 18, weight: .semibold))
                    Text(version)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(Bundle.main.bundleIdentifier ?? "?")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            }
            .padding(.bottom, 4)

            SettingsCard("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(supervisor.statusColor)
                        .frame(width: 6, height: 6)
                    Text(supervisor.statusDescription)
                        .font(.system(size: 12))
                        .foregroundColor(supervisor.statusColor)
                    Spacer()
                }
            }

            SettingsCard("Links") {
                aboutLink("kinclaw on GitHub",
                          url: "https://github.com/LocalKinAI/kinclaw",
                          icon: "arrow.up.right.square")
                aboutLink("LocalKin Dev",
                          url: "https://www.localkin.dev",
                          icon: "arrow.up.right.square")
                aboutLink("Report an issue",
                          url: "https://github.com/LocalKinAI/kinclaw-mac/issues/new",
                          icon: "exclamationmark.bubble")
            }
        }
        .task { await supervisor.refresh() }
    }

    @ViewBuilder
    private func aboutLink(_ title: String, url: String, icon: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

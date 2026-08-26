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
///   - Skills — what the active soul actually exposes, out of everything loaded
///   - Voice — TTS voice/speed + silence threshold + auto-continue
///   - MCP — Model Context Protocol servers (tools from outside this app)
///   - Harvest — external skill sources the nightly job scans
///   - Data — disk locations / sizes / clear-all + reveal-in-Finder
///   - About — version + cloud status + GitHub
///
/// All prefs persist via @AppStorage under the `kinclaw.` prefix so
/// the existing UserDefaults plist already collects them — no new
/// storage layer needed for the settings themselves.
struct KinClawMacSettingsView: View {
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, hotkey, backend, agents, skills, voice, mcp, harvest, data, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .hotkey:  return "Hotkey"
            case .backend: return "Backend"
            case .agents:  return "Agents"
            case .skills:  return "Skills"
            case .voice:   return "Voice"
            case .mcp:     return "MCP"
            case .harvest: return "Harvest"
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
            case .skills:  return "wrench.and.screwdriver"
            case .voice:   return "waveform"
            case .mcp:     return "puzzlepiece.extension"
            case .harvest: return "leaf"
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
        // Was 620×460, sized when Voice was the busiest tab. MCP and Harvest both
        // list rows that carry a command line, a status, and an error message, and
        // at the old width those wrapped into unreadable stacks.
        .frame(minWidth: 820, idealWidth: 860, maxWidth: 1100,
               minHeight: 620, idealHeight: 680, maxHeight: 900)
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
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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
                case .skills:  SkillsSettingsTab()
                case .voice:   VoiceSettingsTab()
                case .mcp:     MCPSettingsTab()
                case .harvest: HarvestSettingsTab()
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

    // Kincode (Code mode kernel — Stage 1 / 5).
    @AppStorage("kinclaw.kincode.autostart") private var kincodeAutostart = true
    @AppStorage("kinclaw.kincode.port") private var kincodePort = 5002

    // Default brain — what the supervisor passes via -provider/-model
    // when it spawns kincode at app launch. Live-switch in the Code
    // tab (POST /api/brain) doesn't touch these.
    @AppStorage("kinclaw.kincode.brain.provider") private var defaultBrainProvider = ""
    @AppStorage("kinclaw.kincode.brain.model") private var defaultBrainModel = ""

    @State private var localStatus = "Probing…"
    @State private var kincodeStatus = "Probing…"

    /// Brain presets loaded from local Ollama. Same source as
    /// CodePane's dropdown — Settings just persists the choice
    /// instead of live-switching. Defaults to the static fallback
    /// while loading; replaced when /api/tags returns.
    @State private var brainPresets: [BrainPreset] = BrainPreset.fallbackPresets

    /// Human-readable label for the current Default brain selection.
    /// Empty pref = use whatever soul says (kimi-k2.6:cloud).
    private var brainDefaultLabel: String {
        if defaultBrainProvider.isEmpty {
            return "From soul"
        }
        if let preset = BrainPreset.find(provider: defaultBrainProvider,
                                          model: defaultBrainModel,
                                          in: brainPresets) {
            return preset.label
        }
        return defaultBrainModel.isEmpty ? "From soul" : defaultBrainModel
    }

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

            SettingsCard("Kincode (Code mode)") {
                SettingsRow(label: "Autostart") {
                    Toggle("", isOn: $kincodeAutostart)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(label: "Port") {
                    TextField("5002", value: $kincodePort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsRow(label: "Default brain") {
                    Menu {
                        Button {
                            defaultBrainProvider = ""
                            defaultBrainModel = ""
                        } label: {
                            HStack {
                                Text("From soul (kimi-k2.6:cloud)")
                                Spacer()
                                if defaultBrainProvider.isEmpty {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Divider()
                        if brainPresets.isEmpty {
                            Text("Ollama not reachable on :11434")
                                .foregroundColor(.secondary)
                        }
                        ForEach(brainPresets) { preset in
                            Button {
                                defaultBrainProvider = preset.provider
                                defaultBrainModel = preset.model
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    Spacer()
                                    if let tag = preset.tag {
                                        Text(tag)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if defaultBrainProvider == preset.provider
                                        && defaultBrainModel == preset.model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Reload from Ollama") {
                            Task {
                                let fresh = await OllamaCatalog.loadPresets()
                                if !fresh.isEmpty {
                                    await MainActor.run { brainPresets = fresh }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(brainDefaultLabel)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                SettingsRow(label: "Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(kincodeStatus.contains("Running")
                                  ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(kincodeStatus)
                            .font(.system(size: 12))
                    }
                }
                SettingsCaption("Coding agent on :5002. Default brain is what the supervisor spawns kincode with — switch live in the Code tab without touching this. Apply on relaunch.")
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
        .task {
            // All three probes run concurrently — neither blocks
            // the others.
            async let kc: Void = refreshStatus()
            async let kk: Void = refreshKincodeStatus()
            async let ol: Void = loadBrainPresets()
            _ = await (kc, kk, ol)
        }
    }

    /// Load installed Ollama models for the Default-brain dropdown.
    /// Empty result keeps the static fallback list visible.
    private func loadBrainPresets() async {
        let fresh = await OllamaCatalog.loadPresets()
        if !fresh.isEmpty {
            await MainActor.run { brainPresets = fresh }
        }
    }

    private func refreshStatus() async {
        do {
            let souls = try await KinClawAPIClient.default.fetchSouls()
            localStatus = "Running — \(souls.count) soul\(souls.count == 1 ? "" : "s")"
        } catch {
            localStatus = "Not reachable"
        }
    }

    /// Hits kincode's /api/health (and /api/state for the model
    /// label, when the health probe succeeds). State JSON is cheap
    /// — the agent has at most one assistant message in memory at
    /// idle so the response is tiny.
    private func refreshKincodeStatus() async {
        guard let url = URL(string: "http://localhost:\(kincodePort)/api/health") else {
            kincodeStatus = "Not reachable"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                // Optionally fetch the model + provider label for richer status.
                if let stateURL = URL(string: "http://localhost:\(kincodePort)/api/state") {
                    var sreq = URLRequest(url: stateURL)
                    sreq.timeoutInterval = 1.0
                    if let (data, _) = try? await URLSession.shared.data(for: sreq),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let model = obj["model"] as? String {
                        kincodeStatus = "Running — \(model)"
                        return
                    }
                }
                kincodeStatus = "Running"
            } else {
                kincodeStatus = "Not reachable"
            }
        } catch {
            kincodeStatus = "Not reachable"
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
    @AppStorage("kinclaw.voice.silenceMarginDB") private var silenceMargin: Double = 5
    @AppStorage("kinclaw.voice.autoContinue") private var autoContinue = false
    @AppStorage("kinclaw.voice.wakeWord") private var wakeWord = ""
    @AppStorage("kinclaw.voice.wakeSessionSeconds") private var wakeSessionSeconds: Double = 45

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard("Speech-to-Text (microphone)") {
                SettingsRow(label: "Speech margin") {
                    HStack {
                        Slider(value: $silenceMargin, in: 2 ... 15, step: 1)
                            .frame(maxWidth: 200)
                        Text("+\(Int(silenceMargin)) dB")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Toggle("Voice-mode auto-continue (continuous conversation)",
                       isOn: $autoContinue)
                SettingsCaption("The mic measures your room's noise for 0.5s at the start of each recording; this sets how far above it a sound must be to count as speech. Raise it if recording keeps running after you stop talking, lower it if quiet speech gets cut off.")
            }

            SettingsCard("Wake word (hands-free mode only)") {
                SettingsRow(label: "Wake word") {
                    TextField("off", text: $wakeWord)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                SettingsRow(label: "Stay open for") {
                    HStack {
                        Slider(value: $wakeSessionSeconds, in: 10 ... 180, step: 5)
                            .frame(maxWidth: 200)
                        Text("\(Int(wakeSessionSeconds))s")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                SettingsCaption("Leave the word empty to send everything you say. When set, say it once to start a conversation — after that you can keep talking normally. The conversation stays open for this long after each exchange (counted from when the reply finishes, not when you stop speaking), then the word is needed again. Anything said while it's closed is discarded, so nearby conversation doesn't reach the agent. Matching ignores case, spacing and punctuation. Push-to-talk ignores this entirely.")
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

// MARK: - MCP

/// Model Context Protocol servers — tools published by programs outside this
/// app (filesystem access, GitHub, databases, whatever a server exposes).
///
/// Deliberately not a full editor. Servers are launched by the kinclaw kernel
/// at startup, so anything changed here takes effect on the next restart; a UI
/// that looked live would be lying. What it does instead is make the two
/// things a file can't show visible: whether each server actually connected,
/// and what it contributed.
private struct MCPSettingsTab: View {
    @StateObject private var store = MCPConfigStore()

    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newArgs = ""
    @State private var showAddForm = false
    @State private var formError: String?
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.needsRestart {
                restartBanner
            }
            if let err = store.loadError {
                errorBanner(err)
            }

            SettingsCard("Servers") {
                if store.serverNames.isEmpty {
                    emptyState
                } else {
                    ForEach(store.serverNames, id: \.self) { name in
                        serverRow(name)
                        if name != store.serverNames.last {
                            Divider().opacity(0.12)
                        }
                    }
                }
            }

            SettingsCard("Add a server") {
                if showAddForm {
                    addForm
                } else {
                    Button {
                        showAddForm = true
                    } label: {
                        Label("Add MCP server", systemImage: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                    SettingsCaption("Uses the standard `mcpServers` format — the same one Claude Desktop uses, so a server's published install snippet can be pasted in as-is. Remote servers aren't configured here; that block only describes local programs.")
                }
            }

            SettingsCard("Files") {
                SettingsRow(label: "Config") {
                    HStack(spacing: 8) {
                        Text("~/.localkin/mcp.json")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([MCPConfigStore.configPath])
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    }
                }
                SettingsCaption("Tools appear to the agent as mcp_<server>_<tool>. A soul only sees them if its skills.enable list includes them — add \"mcp_*\" to allow every server, or \"mcp_github_*\" for just one.")
            }
        }
        .task {
            store.loadConfig()
            await store.refreshStatus()
        }
    }

    // MARK: Pieces

    private var restartBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill").foregroundColor(.orange)
            Text("Changes take effect after the kinclaw kernel restarts.")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(message).font(.system(size: 11))
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No MCP servers configured.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("An MCP server is a small program that publishes tools. Adding one gives the agent abilities this app doesn't ship with.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func serverRow(_ name: String) -> some View {
        let status = store.status(for: name)
        let cfg = store.config.mcpServers[name]
        let isDisabled = cfg?.disabled == true

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon(status, disabled: isDisabled))
                    .foregroundColor(statusColor(status, disabled: isDisabled))
                    .font(.system(size: 11))

                Text(name)
                    .font(.system(size: 12, weight: .medium))

                Text(statusText(status, disabled: isDisabled))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                if let tools = status?.tools, !tools.isEmpty {
                    Button(expanded.contains(name) ? "Hide tools" : "\(tools.count) tools") {
                        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                }

                Toggle("", isOn: Binding(
                    get: { !isDisabled },
                    set: { store.setDisabled(!$0, for: name) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

                Button {
                    store.remove(name)
                    expanded.remove(name)
                } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Text(commandLine(cfg))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)

            // The failure message is the whole point of showing runtime state,
            // so it gets room — and a link to the server's own output, which
            // is usually where the real reason is.
            if let err = status?.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if let log = status?.logPath, !log.isEmpty {
                    Button("Open server log") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: log))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                }
            }

            if expanded.contains(name), let tools = status?.tools {
                Text(tools.joined(separator: ", "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(label: "Name") {
                TextField("filesystem", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            SettingsRow(label: "Command") {
                TextField("npx", text: $newCommand)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Arguments — one per line")
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.85))
                TextEditor(text: $newArgs)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
            }
            if let err = formError {
                Text(err).font(.system(size: 10)).foregroundColor(.red)
            }
            HStack(spacing: 10) {
                Button("Save") {
                    formError = store.upsert(name: newName, command: newCommand, argsText: newArgs)
                    if formError == nil {
                        newName = ""; newCommand = ""; newArgs = ""
                        showAddForm = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    showAddForm = false; formError = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            SettingsCaption("One argument per line, not space-separated — MCP arguments are usually paths, and paths contain spaces.")
        }
    }

    // MARK: Formatting

    private func commandLine(_ cfg: MCPConfigStore.ServerConfig?) -> String {
        guard let cfg else { return "" }
        return ([cfg.command] + (cfg.args ?? [])).joined(separator: " ")
    }

    private func statusIcon(_ s: MCPConfigStore.ServerStatus?, disabled: Bool) -> String {
        if disabled { return "pause.circle" }
        guard let s else { return "questionmark.circle" }
        if !s.error.isNilOrEmpty { return "xmark.circle.fill" }
        return s.connected ? "checkmark.circle.fill" : "questionmark.circle"
    }

    private func statusColor(_ s: MCPConfigStore.ServerStatus?, disabled: Bool) -> Color {
        if disabled { return .secondary }
        guard let s else { return .secondary }
        if !s.error.isNilOrEmpty { return .red }
        return s.connected ? .green : .secondary
    }

    private func statusText(_ s: MCPConfigStore.ServerStatus?, disabled: Bool) -> String {
        if disabled { return "disabled" }
        guard let s else {
            // No status at all means the kernel hasn't reported — usually it
            // is still starting. Saying "unknown" beats implying failure.
            return "not reported yet"
        }
        if !s.error.isNilOrEmpty { return "failed" }
        if s.connected { return "\(s.toolCount) tools" }
        return "no tools"
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

// MARK: - Harvest

/// External skill sources the nightly job scans, and what it found.
///
/// Read-only by design. Harvest runs from a LaunchAgent and writes to disk on
/// its own schedule; a UI that edited that state while a run was in flight
/// would be racing a background job. What it does instead is answer the two
/// questions the CLI makes you dig for: is the schedule actually doing the
/// whole job, and is each source earning its keep.
private struct HarvestSettingsTab: View {
    @StateObject private var store = HarvestStore()

    /// Candidate awaiting confirmation. Accept writes code into the repo via
    /// the coder agent, so it asks first — this is the one destructive-ish
    /// action in Settings and a mis-click costs a stray directory in skills/.
    @State private var pendingAccept: HarvestStore.Candidate?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            scheduleCard

            if !store.barrenSources.isEmpty {
                barrenCard
            }

            SettingsCard("Sources") {
                if let sources = store.status?.sources, !sources.isEmpty {
                    ForEach(sources) { src in
                        sourceRow(src)
                        if src.id != sources.last?.id { Divider().opacity(0.12) }
                    }
                } else if store.fetchFailed {
                    SettingsCaption("Couldn't reach the local kinclaw kernel. Sources are read from it, so this fills in once it's running.")
                } else {
                    SettingsCaption("No sources configured. Harvest reads them from the manifest below.")
                }
            }

            candidatesCard

            SettingsCard("Files") {
                SettingsRow(label: "Manifest") {
                    HStack(spacing: 8) {
                        Text(store.status?.manifestPath ?? "~/.kinclaw/harvest.toml")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let url = store.manifestURL {
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        }
                    }
                }
                SettingsCaption("Sources are edited in the manifest (TOML). Accepting a candidate is a CLI step — `kinclaw harvest --accept <source>/<skill>` — because it runs the coder agent to rewrite the skill, and the result lands in your repo as code you then maintain.")
            }
        }
        .task { await store.refresh() }
    }

    // MARK: Cards

    private var scheduleCard: some View {
        SettingsCard("Schedule") {
            HStack(spacing: 8) {
                Image(systemName: store.scheduled ? "clock.badge.checkmark" : "clock.badge.xmark")
                    .foregroundColor(store.scheduled ? .green : .secondary)
                Text(store.scheduled
                     ? (store.scheduleSummary.isEmpty ? "scheduled" : store.scheduleSummary)
                     : "Not scheduled")
                    .font(.system(size: 12))
                Spacer()
                if let n = store.status?.cachedVerdicts, n > 0 {
                    Text("\(n) cached verdicts")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            SettingsCaption("Cached verdicts are candidates the curator already judged; a scheduled run skips them, so only new or edited skills cost anything.")
        }
    }

    private var barrenCard: some View {
        SettingsCard("Producing nothing") {
            ForEach(store.barrenSources) { src in
                HStack(spacing: 8) {
                    Image(systemName: "circle.slash").foregroundColor(.orange).font(.system(size: 10))
                    Text(src.name).font(.system(size: 12))
                    Spacer()
                }
            }
            SettingsCaption("These sources have staged nothing. Often the library is written as prompt templates rather than command wrappers — a shape mismatch that re-scanning won't resolve. Each one still costs a clone and a scan every run.")
        }
    }

    @ViewBuilder
    private var candidatesCard: some View {
        let candidates = store.sortedCandidates
        SettingsCard("Awaiting review (\(candidates.count))") {
            if candidates.isEmpty {
                SettingsCaption("Nothing staged. Either harvest hasn't triaged yet, or the curator rejected everything it found.")
            } else {
                ForEach(candidates.prefix(30)) { c in
                    candidateRow(c)
                    if c.id != candidates.prefix(30).last?.id { Divider().opacity(0.1) }
                }
                if candidates.count > 30 {
                    SettingsCaption("Showing 30 of \(candidates.count). The rest are in `kinclaw harvest --review`.")
                }
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ c: HarvestStore.Candidate) -> some View {
        let job = store.job(for: c)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(c.verdict.lowercased() == "yes" ? "✓" : "?")
                    .foregroundColor(c.verdict.lowercased() == "yes" ? .green : .orange)
                    .font(.system(size: 11, weight: .semibold))
                Text(c.name).font(.system(size: 12, weight: .medium))
                Text(c.source).font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                acceptControl(c, job: job)
            }
            Text(c.reason)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if let job { jobResult(job) }
        }
        .padding(.vertical, 3)
        .confirmationDialog(
            "Forge “\(pendingAccept?.name ?? "")” into your skills?",
            isPresented: Binding(
                get: { pendingAccept?.id == c.id },
                set: { if !$0 { pendingAccept = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forge it") {
                let target = c
                pendingAccept = nil
                Task { await store.accept(target) }
            }
            Button("Cancel", role: .cancel) { pendingAccept = nil }
        } message: {
            Text("The coder agent rewrites this skill into KinClaw's command form and writes it into your skills/ directory as code you'll maintain. Takes up to a few minutes. If it can't be expressed as a command, the original is filed under skills/library/ instead.")
        }
    }

    @ViewBuilder
    private func acceptControl(_ c: HarvestStore.Candidate, job: HarvestStore.AcceptJob?) -> some View {
        if let job, job.isRunning {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("forging…").font(.system(size: 10)).foregroundColor(.secondary)
            }
        } else if let job, !job.isRunning {
            // Finished — the outcome is shown below; offer a retry only when
            // it failed outright, since a "library" result is a real answer
            // rather than something to try again.
            if job.status == "failed" || job.verdict == "error" {
                Button("Retry") { pendingAccept = c }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.green)
            }
        } else {
            Button("Accept") { pendingAccept = c }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)
        }
    }

    /// Report what the forge actually did.
    ///
    /// Four outcomes, and three of them are not "it worked": coder may decide
    /// the skill can't be a command and file the original under library/, the
    /// destination may already exist, or the forge may fail. Collapsing those
    /// into a checkmark would misrepresent what landed in the repo.
    @ViewBuilder
    private func jobResult(_ job: HarvestStore.AcceptJob) -> some View {
        if job.isRunning {
            EmptyView()
        } else if job.status == "failed" {
            Label(job.error ?? "forge failed", systemImage: "xmark.circle.fill")
                .font(.system(size: 10)).foregroundColor(.red)
        } else {
            switch job.verdict {
            case "forged":
                VStack(alignment: .leading, spacing: 2) {
                    Label("forged as \(job.forgedName ?? "?")", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundColor(.green)
                    Text("Restart the kernel for the agent to load it.")
                        .font(.system(size: 9)).foregroundColor(.orange)
                }
            case "library":
                VStack(alignment: .leading, spacing: 2) {
                    Label("filed under skills/library/", systemImage: "books.vertical")
                        .font(.system(size: 10)).foregroundColor(.blue)
                    if let r = job.reason, !r.isEmpty {
                        Text(r).font(.system(size: 9)).foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            case "duplicate":
                Label("a skill with that name already exists", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundColor(.orange)
            default:
                Label(job.reason ?? "forge failed", systemImage: "xmark.circle")
                    .font(.system(size: 10)).foregroundColor(.red)
            }
        }
    }

    private func sourceRow(_ src: HarvestStore.Source) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(src.name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(src.staged > 0 ? "\(src.staged) staged" : "none")
                    .font(.system(size: 10))
                    .foregroundColor(src.staged > 0 ? .green : .secondary)
            }
            Text(src.url)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Skills

/// What the active soul can actually use, out of everything the kernel loaded.
///
/// Two numbers, deliberately not merged: *registered* is what loaded
/// successfully, *exposed* is what this soul's `skills.enable` lets the model
/// see. For pilot that's 189 vs 25. Every "the skill is installed but my agent
/// says it can't do that" question is this gap, and it was previously only
/// visible as one line of startup output in a terminal nobody watches.
private struct SkillsSettingsTab: View {
    @StateObject private var store = SkillStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard

            if !store.missing.isEmpty {
                missingCard
            }

            SettingsCard("Skills") {
                controls
                Divider().opacity(0.12)
                skillList
            }
        }
        .task { await store.refresh() }
    }

    private var summaryCard: some View {
        SettingsCard("Active soul") {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").foregroundColor(.green)
                Text(store.soulName).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(store.exposedCount) exposed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
                Text("/ \(store.registeredCount) loaded")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            if store.fetchFailed {
                SettingsCaption("Couldn't reach the local kinclaw kernel — this fills in once it's running.")
            } else {
                SettingsCaption("Loaded means the kernel started the skill successfully. Exposed means this soul can see it. Ticking a box below grants a skill to this soul without editing its file — it's stored separately in ~/.localkin/skill_extras.json and takes effect immediately. Skills the soul itself grants show a fixed checkmark; removing one of those is an edit to the soul, so it stays in git.")
            }
        }
    }

    private var missingCard: some View {
        SettingsCard("Enabled but not loaded") {
            ForEach(store.missing, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.system(size: 10))
                    Text(name).font(.system(size: 12, design: .monospaced))
                    Spacer()
                }
            }
            SettingsCaption("This soul's enable list names these, but nothing registered under them — a typo, a skill that failed to load, or an MCP server that's turned off. The agent silently lacks a capability its soul claims to grant.")
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("Filter by name or description", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            Toggle("Exposed only", isOn: $store.exposedOnly)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Spacer()
            Text("\(store.filtered.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var skillList: some View {
        let items = store.filtered
        if items.isEmpty {
            SettingsCaption(store.exposedOnly
                ? "No exposed skills match. Untick “Exposed only” to see everything loaded."
                : "Nothing matches that filter.")
        } else {
            // Capped rather than paginated: this is a reference list, and past
            // a screenful the filter box is the faster way to find something.
            ForEach(items.prefix(60)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    // Soul-granted skills show a static mark; everything else
                    // is a live toggle writing to the extras overlay. The
                    // difference is deliberate — the overlay only adds, so a
                    // skill the soul grants can't be revoked from here.
                    if store.grantedBySoul(entry.name) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.system(size: 10))
                            .padding(.top, 2)
                            .help("Granted by the soul file")
                    } else {
                        Toggle("", isOn: Binding(
                            get: { entry.exposed },
                            set: { on in Task { await store.setExtra(entry.name, enabled: on) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.mini)
                        .padding(.top, 1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.name)
                                .font(.system(size: 12, design: .monospaced))
                            if store.isExtra(entry.name) {
                                Text("added here")
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.green.opacity(0.2)))
                                    .foregroundColor(.green)
                            }
                            if entry.isMCP {
                                Text("MCP")
                                    .font(.system(size: 8, weight: .semibold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.blue.opacity(0.25)))
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                        if !entry.description.isEmpty {
                            Text(entry.description)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.75))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if items.count > 60 {
                SettingsCaption("Showing 60 of \(items.count) — narrow it with the filter.")
            }
        }
    }
}

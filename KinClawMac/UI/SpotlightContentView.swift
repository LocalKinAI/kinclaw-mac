import SwiftUI

/// The single-pane chat surface that lives inside `SpotlightWindow`.
///
/// Replaces the iOS-shaped `TabView { Agents / KinBook / Settings }` —
/// that layout only makes sense at iPhone full-screen, not in a 380×600
/// floating panel. The Spotlight form factor wants ONE thing on screen
/// at a time:
///
///   ┌──────────────────────────────────────┐
///   │ 🦞  KinClaw Pilot  ▾           [⚙]  │  ← header / soul switcher
///   ├──────────────────────────────────────┤
///   │  user: 帮我打开 Music                  │
///   │                                      │
///   │  Pilot: 好的, 我用 spawn ...           │  ← chat fills here
///   │  (streaming…)                         │
///   ├──────────────────────────────────────┤
///   │ 🎙  Message Pilot…              ⏎    │  ← input bar
///   └──────────────────────────────────────┘
///
/// KinBook is intentionally dropped from this surface — it doesn't
/// belong in a chat dock. If we want it back later it ships as its
/// own dedicated window opened from the menubar (M-something).
struct SpotlightContentView: View {

    // MARK: - State

    @EnvironmentObject var appState: AppState

    // Agent directory (refreshed on appear).
    @State private var allAgents: [Agent] = []
    @State private var loadError: String?
    @State private var isLoadingAgents = true
    /// Set when the cloud /v1/agents fetch fails or returns nothing
    /// — shown in the picker so users see a real signal rather than
    /// a silently-empty section.
    @State private var cloudErrorReason: String?

    // Active conversation.
    @State private var selectedAgent: Agent?
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var scrollTrigger = 0

    // Transports.
    @State private var sseClient: SSEClient?
    @State private var localStreamTask: Task<Void, Never>?

    // Voice.
    @StateObject private var speaker = SpeechSynthesizer()
    @StateObject private var recorder = VoiceRecorder()
    @State private var ttsEnabled = false
    @State private var voiceMode = false

    @FocusState private var inputFocused: Bool

    // MARK: - Derived (4 group buckets surfaced in the picker)
    //
    // Local souls are split into KinClaw computer-use agents (the
    // dock's marquee surface) vs the generic LocalKin chat souls
    // that happen to live under ~/.localkin/souls/. They share the
    // local-soul transport but are conceptually different products
    // and group differently in the picker.
    //
    // Cloud agents are split by their published vertical — Faith /
    // Selah (spiritual masters) and Heal / 岐黄 (TCM masters) —
    // matching the way faith.localkin.ai / heal.localkin.ai present
    // them.

    private var localAgents: [Agent] { allAgents.filter { $0.isLocal } }
    private var cloudAgents: [Agent] { allAgents.filter { !$0.isLocal } }

    private var kinClawSouls: [Agent] {
        // Names emitted by kinclaw's soul list start with "KinClaw "
        // (Pilot / Coder / Critic / Curator / Eye / Marketer /
        // Researcher = 7 today).
        localAgents.filter { $0.name.hasPrefix("KinClaw") }
    }
    private var localKinSouls: [Agent] {
        // The rest — souls under ~/.localkin/souls/ that aren't
        // KinClaw branded (Claude / Cloud / default = 3 today).
        localAgents.filter { !$0.name.hasPrefix("KinClaw") }
    }
    private var spiritualAgents: [Agent] {
        cloudAgents.filter { $0.domain == "spiritual" }
    }
    private var tcmAgents: [Agent] {
        cloudAgents.filter { $0.domain == "tcm" }
    }
    private var otherCloudAgents: [Agent] {
        cloudAgents.filter { $0.domain != "spiritual" && $0.domain != "tcm" }
    }

    private var hostname: String {
        selectedAgent?.hostname ?? "api.localkin.dev"
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isStreaming
            && selectedAgent != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider().opacity(0.25)

            messagesView

            Divider().opacity(0.25)

            inputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .preferredColorScheme(.dark)
        .background(Color.clear) // SpotlightWindow's blur shows through
        .frame(minWidth: 320, minHeight: 380)
        .onAppear { Task { await loadAgents() } }
        .onChange(of: selectedAgent?.id) { _, _ in
            handleAgentChange()
        }
        .onDisappear {
            sseClient?.cancel()
            localStreamTask?.cancel()
            speaker.stop()
        }
    }

    // MARK: - Header (soul/agent picker)

    private var header: some View {
        HStack(spacing: 10) {
            Text("🦞")
                .font(.system(size: 16))

            agentMenu
                .frame(maxWidth: .infinity, alignment: .leading)

            // Quick actions
            if !messages.isEmpty {
                Button {
                    clearChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear chat")
            }

            Button {
                ttsEnabled.toggle()
                UserDefaults.standard.set(ttsEnabled, forKey: "tts_enabled")
            } label: {
                Image(systemName: ttsEnabled ? "speaker.wave.2.fill"
                                              : "speaker.slash")
                    .font(.system(size: 12))
                    .foregroundColor(ttsEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(ttsEnabled ? "Speech on" : "Speech off")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var agentMenu: some View {
        Menu {
            // Nested submenus = collapsed-by-default groups. The
            // top-level dropdown shows just the 4 group titles +
            // their counts; users click / hover to expand each.

            // ── KinClaw computer-use souls (7 today) ──
            if !kinClawSouls.isEmpty {
                Menu("🦞  KinClaw  (\(kinClawSouls.count))") {
                    ForEach(kinClawSouls) { agentMenuRow($0) }
                }
            }

            // ── Generic local LocalKin souls (3 today, from
            //     ~/.localkin/souls/) ──
            if !localKinSouls.isEmpty {
                Menu("💻  LocalKin  (\(localKinSouls.count))") {
                    ForEach(localKinSouls) { agentMenuRow($0) }
                }
            }

            // ── Cloud Faith / Selah masters ──
            if !spiritualAgents.isEmpty {
                Menu("📜  Faith / Selah  (\(spiritualAgents.count))") {
                    ForEach(spiritualAgents) { agentMenuRow($0) }
                }
            } else if !isLoadingAgents && cloudErrorReason != nil {
                Text("📜  Faith — \(cloudErrorReason ?? "unreachable")")
                    .foregroundColor(.secondary)
            }

            // ── Cloud Heal / 岐黄 masters ──
            if !tcmAgents.isEmpty {
                Menu("🌿  Heal / 岐黄  (\(tcmAgents.count))") {
                    ForEach(tcmAgents) { agentMenuRow($0) }
                }
            } else if !isLoadingAgents && cloudErrorReason != nil {
                Text("🌿  Heal — \(cloudErrorReason ?? "unreachable")")
                    .foregroundColor(.secondary)
            }

            // ── Cloud agents that don't match either vertical
            //     (defensive — empty today, here in case the catalog
            //     gains a new domain like "qa" before the UI does) ──
            if !otherCloudAgents.isEmpty {
                Menu("☁️  Other cloud  (\(otherCloudAgents.count))") {
                    ForEach(otherCloudAgents.prefix(80)) { agentMenuRow($0) }
                }
            }

            // ── No groups at all → empty / loading ──
            if allAgents.isEmpty {
                if isLoadingAgents {
                    Text("Loading…").foregroundColor(.secondary)
                } else if let err = loadError {
                    Text(err).foregroundColor(.secondary)
                }
            }

            Divider()
            Button("Reload") {
                Task { await loadAgents() }
            }
        } label: {
            HStack(spacing: 6) {
                if let agent = selectedAgent {
                    Text(AgentDecor.emoji(for: agent))
                        .font(.system(size: 14))
                    Text(activeNameLabel(for: agent))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                } else if isLoadingAgents {
                    Text("Loading agents…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    Text("Choose an agent")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func agentMenuRow(_ agent: Agent) -> some View {
        Button {
            selectedAgent = agent
        } label: {
            HStack {
                Text(AgentDecor.displayLabel(for: agent))
                Spacer()
                if let era = AgentDecor.caption(for: agent) {
                    Text(era)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                if selectedAgent?.id == agent.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && selectedAgent != nil {
                        welcomeCard
                            .padding(.top, 40)
                    } else if messages.isEmpty && loadError != nil {
                        errorState
                    } else {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    if isStreaming {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.55)
                            Text("thinking…")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        .id("streaming-indicator")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    if isStreaming {
                        proxy.scrollTo("streaming-indicator", anchor: .bottom)
                    } else {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollTrigger) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    if isStreaming {
                        proxy.scrollTo("streaming-indicator", anchor: .bottom)
                    } else {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeCard: some View {
        VStack(spacing: 8) {
            if let agent = selectedAgent {
                Text(AgentDecor.emoji(for: agent))
                    .font(.system(size: 44))
                    .padding(.bottom, 4)

                // Cloud masters get bilingual rendering; local souls
                // just get their plain name.
                if let master = CloudAgentCatalog.master(for: agent.slug) {
                    Text(master.nameZh)
                        .font(.system(size: 18, weight: .semibold))
                    Text(master.nameEn)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    Text(agent.displayName)
                        .font(.system(size: 18, weight: .semibold))
                }

                if let caption = AgentDecor.caption(for: agent) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.85))
                        .padding(.top, 2)
                }

                Text(agent.isLocal
                     ? "Type below to start. ⌘⏎ to send."
                     : "Type below — ⌘⏎ to send. Bilingual; mix freely.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 6)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Header label shown next to the dropdown chevron. For cloud
    /// masters: "盖恩夫人 · Madame Guyon" (bilingual). For local:
    /// just the plain display name. Truncates to fit narrow panels.
    private func activeNameLabel(for agent: Agent) -> String {
        if let master = CloudAgentCatalog.master(for: agent.slug) {
            return "\(master.nameZh)  ·  \(master.nameEn)"
        }
        return agent.displayName
    }

    private var errorState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(loadError ?? "")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadAgents() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let isLastAssistantWhileStreaming = !msg.isUser
            && isStreaming
            && msg.id == messages.last?.id
        return HStack(alignment: .top, spacing: 8) {
            if msg.isUser {
                Spacer(minLength: 30)
                Text(msg.content)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.18))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            } else {
                assistantBubble(msg, showCursor: isLastAssistantWhileStreaming)
                Spacer(minLength: 30)
            }
        }
    }

    private func assistantBubble(_ msg: ChatMessage,
                                 showCursor: Bool) -> some View {
        // Use TimelineView at 2Hz so the cursor blinks without a
        // standing Timer. Only the streaming bubble pays the cost;
        // settled messages re-render once and stop.
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let cursorVisible = showCursor
                && Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text(msg.content + (cursorVisible ? " █" : "   "))
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.platformSecondaryBackground.opacity(0.6))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                if recorder.isRecording {
                    recorder.cancelRecording()
                } else {
                    recorder.startRecording(hostname: hostname)
                }
            } label: {
                Image(systemName: recorder.isRecording
                                  ? "stop.circle.fill"
                                  : "mic")
                    .font(.system(size: 14))
                    .foregroundColor(recorder.isRecording ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help("Voice input")

            TextField(
                selectedAgent.map { "Message \($0.displayName)…" }
                    ?? "Pick an agent first…",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($inputFocused)
            .onSubmit { send() }
            .lineLimit(1...5)
            .disabled(selectedAgent == nil)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canSend ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformSecondaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Behavior

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func clearChat() {
        guard let agent = selectedAgent else { return }
        messages = []
        ChatHistory.clear(for: agent.slug)
    }

    private func handleAgentChange() {
        guard let agent = selectedAgent else { return }
        // Restore per-agent history
        messages = ChatHistory.load(for: agent.slug)

        // Persist last-used selection so the next launch lands on
        // the same agent (rather than re-defaulting to Pilot every
        // time and losing the user's last choice).
        UserDefaults.standard.set(agent.slug, forKey: "kinclaw.lastAgent")

        // Local kinclaw: switch the server-side active soul.
        if let soulPath = agent.localSoulPath {
            Task {
                try? await KinClawAPIClient.default.switchSoul(path: soulPath)
            }
        }
    }

    // MARK: - Loading

    private func loadAgents() async {
        isLoadingAgents = allAgents.isEmpty
        loadError = nil
        cloudErrorReason = nil

        // Cloud fetch with explicit error capture so the dropdown can
        // explain WHY the cloud section is empty (network down vs
        // 0 agents online vs API moved).
        async let cloudTask: (agents: [Agent], reason: String?) = {
            do {
                let agents = try await APIClient.shared.fetchAgents()
                if agents.isEmpty {
                    return ([], "0 agents online")
                }
                return (agents, nil)
            } catch let error as URLError where error.code == .notConnectedToInternet {
                return ([], "Offline")
            } catch {
                // Decode failure (404 with non-array JSON) lands here
                // too, so the user gets a useful "cloud unreachable"
                // signal rather than an empty section.
                return ([], "Cloud unreachable")
            }
        }()

        async let localTask: [Agent] = {
            do {
                let souls = try await KinClawAPIClient.default.fetchSouls()
                return souls.map(\.asAgent)
            } catch { return [] }
        }()

        let (cloud, cloudReason) = await cloudTask
        let local = await localTask
        let merged = local + cloud
        allAgents = merged
        cloudErrorReason = cloud.isEmpty ? cloudReason : nil

        if merged.isEmpty {
            loadError = "No agents available — start kinclaw locally or check your internet."
        } else if selectedAgent == nil {
            selectedAgent = pickDefaultAgent(merged: merged, local: local, cloud: cloud)
        }
        isLoadingAgents = false
    }

    /// Pick the default agent surfaced when KinClaw Mac launches.
    ///
    /// Priority order:
    ///   1. Last-used agent (if persisted slug still resolves in
    ///      the current catalog) — respects user choice across
    ///      sessions.
    ///   2. KinClaw Pilot (the dock's marquee soul — operates the
    ///      Mac via the 5 claws + skills). Per Jacky 2026-05-03.
    ///   3. Any other KinClaw soul (Coder / Critic / etc.)
    ///   4. Any other local soul (~/.localkin/souls/).
    ///   5. First cloud agent (Selah Irenaeus, alphabetically).
    private func pickDefaultAgent(merged: [Agent], local: [Agent],
                                  cloud: [Agent]) -> Agent? {
        let lastUsed = UserDefaults.standard.string(forKey: "kinclaw.lastAgent")
        if let slug = lastUsed,
           let agent = merged.first(where: { $0.slug == slug }) {
            return agent
        }
        if let pilot = local.first(where: { $0.name == "KinClaw Pilot" }) {
            return pilot
        }
        return local.first ?? cloud.first
    }

    // MARK: - Send (router → cloud / local)

    private func send() {
        guard let agent = selectedAgent else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        messages.append(.user(text))
        messages.append(.assistant())
        let assistantIndex = messages.count - 1
        isStreaming = true
        inputFocused = true

        if agent.isLocal {
            sendLocal(text: text, assistantIndex: assistantIndex)
        } else {
            sendCloud(text: text, agent: agent, assistantIndex: assistantIndex)
        }
    }

    private func sendCloud(text: String, agent: Agent, assistantIndex: Int) {
        let apiMessages = messages.suffix(20).map {
            APIMessage(role: $0.role.rawValue, content: $0.content)
        }
        let client = SSEClient()
        sseClient = client

        client.onToken = { token in
            messages[assistantIndex].content += token
            scrollTrigger += 1
        }
        client.onComplete = {
            isStreaming = false
            sseClient = nil
            if !messages[assistantIndex].content.isEmpty {
                appState.recordMessage()
                if ttsEnabled {
                    speaker.speak(messages[assistantIndex].content,
                                  hostname: hostname) {}
                }
                ChatHistory.save(messages: messages, for: agent.slug)
            }
        }
        client.onError = { _ in
            if messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content = "Connection error."
            }
            isStreaming = false
            sseClient = nil
        }
        client.startStreaming(hostname: hostname,
                              agentSlug: agent.slug,
                              messages: apiMessages)
    }

    private func sendLocal(text: String, assistantIndex: Int) {
        guard let agent = selectedAgent else { return }
        localStreamTask?.cancel()
        let task = Task { @MainActor in
            let client = KinClawAPIClient.default
            let stream = client.eventStream()
            do {
                try await client.sendChat(text)
            } catch {
                messages[assistantIndex].content =
                    "kinclaw error: \(error.localizedDescription)"
                isStreaming = false
                return
            }
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    handleLocalEvent(event, assistantIndex: assistantIndex)
                    if event.kind == .turnDone || event.kind == .error { break }
                }
            } catch {
                if messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content =
                        "stream error: \(error.localizedDescription)"
                }
            }
            isStreaming = false
            ChatHistory.save(messages: messages, for: agent.slug)
            if ttsEnabled, !messages[assistantIndex].content.isEmpty {
                speaker.speak(messages[assistantIndex].content,
                              hostname: hostname) {}
            }
        }
        localStreamTask = task
    }

    private func handleLocalEvent(_ event: KinClawEvent, assistantIndex: Int) {
        switch event.kind {
        case .textDelta:
            if let t = event.text, !t.isEmpty {
                messages[assistantIndex].content += t
                scrollTrigger += 1
            }
        case .toolCall:
            if let name = event.name {
                messages[assistantIndex].content += "\n\n*🔧 \(name)*"
                scrollTrigger += 1
            }
        case .toolResult:
            if let output = event.output, !output.isEmpty {
                let preview = output.count > 400
                    ? String(output.prefix(400)) + "…"
                    : output
                messages[assistantIndex].content += "\n```\n\(preview)\n```"
                scrollTrigger += 1
            }
        case .error:
            let msg = event.message ?? "kinclaw reported an error"
            if !messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content += "\n\n"
            }
            messages[assistantIndex].content += "[error: \(msg)]"
            scrollTrigger += 1
        case .hello, .userMessage, .turnDone,
             .screenFrame, .recordDone, .soulSwitched, .none:
            break
        }
    }
}

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

    // MARK: - Derived

    private var localAgents: [Agent] { allAgents.filter { $0.isLocal } }
    private var cloudAgents: [Agent] { allAgents.filter { !$0.isLocal } }

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
            if !localAgents.isEmpty {
                Section("Local KinClaw") {
                    ForEach(localAgents) { agent in
                        agentMenuRow(agent)
                    }
                }
            }
            if !cloudAgents.isEmpty {
                Section("Cloud LocalKin") {
                    ForEach(cloudAgents.prefix(50)) { agent in
                        agentMenuRow(agent)
                    }
                    if cloudAgents.count > 50 {
                        Text("…and \(cloudAgents.count - 50) more")
                            .foregroundColor(.secondary)
                    }
                }
            }
            if isLoadingAgents {
                Text("Loading…").foregroundColor(.secondary)
            }
            Divider()
            Button("Reload") {
                Task { await loadAgents() }
            }
        } label: {
            HStack(spacing: 4) {
                if let agent = selectedAgent {
                    Circle()
                        .fill(agent.isLocal ? Color.green : Color.blue)
                        .frame(width: 6, height: 6)
                    Text(agent.displayName)
                        .font(.system(size: 13, weight: .semibold))
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
                Text(agent.displayName)
                Spacer()
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
        VStack(spacing: 10) {
            if let agent = selectedAgent {
                Image(systemName: agent.isLocal
                                  ? "laptopcomputer"
                                  : "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(agent.isLocal ? .green : .blue)

                Text(agent.displayName)
                    .font(.system(size: 18, weight: .semibold))

                Text(agent.isLocal
                     ? "Local KinClaw — operates your Mac"
                     : "Cloud agent — \(agent.domain ?? "general")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("Type below to start.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
        HStack(alignment: .top, spacing: 8) {
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
                Text(LocalizedStringKey(msg.content))
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.platformSecondaryBackground.opacity(0.6))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
                Spacer(minLength: 30)
            }
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

        async let cloudTask: [Agent] = {
            do { return try await APIClient.shared.fetchAgents() }
            catch { return [] }
        }()
        async let localTask: [Agent] = {
            do {
                let souls = try await KinClawAPIClient.default.fetchSouls()
                return souls.map(\.asAgent)
            } catch { return [] }
        }()

        let cloud = await cloudTask
        let local = await localTask
        let merged = local + cloud
        allAgents = merged

        if merged.isEmpty {
            loadError = "No agents available — start kinclaw locally or check your internet."
        } else if selectedAgent == nil {
            // Default to first local agent (the dock's marquee surface);
            // fall back to first cloud agent if no kinclaw is running.
            selectedAgent = local.first ?? cloud.first
        }
        isLoadingAgents = false
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
        client.startStreaming(hostname: hostname, messages: apiMessages)
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

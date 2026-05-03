import SwiftUI
import AVFoundation

struct ChatView: View {
    let agent: Agent
    @EnvironmentObject var appState: AppState
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var sseClient: SSEClient?
    @State private var ttsEnabled = false
    @State private var voiceMode = false       // Continuous voice conversation
    @State private var scrollTrigger = 0
    @StateObject private var speaker = SpeechSynthesizer()
    @StateObject private var recorder = VoiceRecorder()
    @FocusState private var inputFocused: Bool

    private var hostname: String {
        agent.hostname ?? "api.localkin.dev"
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesView

            if !appState.canSendMessage {
                rateLimitBanner
            }

            // Voice mode overlay or transcribing indicator
            if voiceMode {
                voiceModeBar
            } else {
                if recorder.isTranscribing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                inputBar
            }
        }
        .navigationTitle(agent.displayName)
        .compactNavTitle()
        .toolbar {
            ToolbarItem(placement: .trailingAction) {
                HStack(spacing: 12) {
                    // TTS toggle (小喇叭)
                    Button {
                        ttsEnabled.toggle()
                        UserDefaults.standard.set(ttsEnabled, forKey: "tts_enabled")
                    } label: {
                        Image(systemName: ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.caption)
                            .foregroundColor(ttsEnabled ? .green : .secondary)
                    }

                    // Clear history
                    if !messages.isEmpty {
                        Button {
                            messages = []
                            ChatHistory.clear(for: agent.slug)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    agentStatusBadge
                }
            }
        }
        .onAppear {
            messages = ChatHistory.load(for: agent.slug)
            ttsEnabled = UserDefaults.standard.bool(forKey: "tts_enabled")
            inputFocused = true

            // Voice mode callbacks
            recorder.onTranscript = { text in
                inputText = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    sendMessage()
                }
            }
            recorder.onNoSpeech = {
                // No speech detected — restart listening in voice mode
                if voiceMode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard voiceMode else { return }
                        recorder.startRecording(hostname: hostname)
                    }
                }
            }
        }
        .onDisappear {
            exitVoiceMode()
            sseClient?.cancel()
            speaker.stop()
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        welcomeCard
                    }

                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            agentSlug: agent.slug,
                            agentDomain: agent.domain ?? "",
                            hostname: hostname
                        )
                        .id(message.id)
                    }

                    if isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("streaming-indicator")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    if isStreaming {
                        proxy.scrollTo("streaming-indicator", anchor: .bottom)
                    } else {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollTrigger) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    if isStreaming {
                        proxy.scrollTo("streaming-indicator", anchor: .bottom)
                    } else {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        let icon = AgentListView.agentIcon(agent.slug, domain: agent.domain ?? "")
        let color = AgentListView.domainColor(agent.domain ?? "")

        return VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(color)

            Text(agent.displayName)
                .font(.title2)
                .fontWeight(.bold)

            if let domain = agent.domain {
                HStack(spacing: 4) {
                    Image(systemName: AgentListView.domainIcon(domain))
                        .font(.system(size: 10))
                    Text(domain.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .clipShape(Capsule())
            }

            Text("Start a conversation with this agent.\nThey have specialized knowledge and skills.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Input Bar (Text Mode)

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Voice mode button
            Button {
                enterVoiceMode()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
            .disabled(isStreaming)

            TextField("Message \(agent.displayName)...", text: $inputText)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(12)
                .background(Color.platformSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(!appState.canSendMessage)
                .onSubmit {
                    sendMessage()
                }
                .submitLabel(.send)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming || !appState.canSendMessage
                            ? .gray
                            : .green
                    )
            }
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                isStreaming ||
                !appState.canSendMessage
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.platformBackground)
    }

    // MARK: - Voice Mode Bar (Continuous Conversation)

    private var voiceModeBar: some View {
        VStack(spacing: 8) {
            // Status text
            HStack {
                if recorder.isRecording {
                    // Pulsing red dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(recorder.isRecording ? 1 : 0.3)
                    Text("Listening...")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else if recorder.isTranscribing {
                    ProgressView().scaleEffect(0.7)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if isStreaming {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if speaker.isSpeaking {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.green)
                    Text("Speaking...")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                    Text("Voice Mode")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                Spacer()
            }
            .padding(.horizontal)

            // Big stop button
            Button {
                exitVoiceMode()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                    Text("End Voice Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color.platformBackground)
    }

    // MARK: - Voice Mode Control

    private func enterVoiceMode() {
        voiceMode = true
        ttsEnabled = true
        UserDefaults.standard.set(true, forKey: "tts_enabled")
        inputFocused = false
        // Start listening with hostname
        recorder.startRecording(hostname: hostname)
    }

    private func exitVoiceMode() {
        voiceMode = false
        recorder.cancelRecording()
        speaker.stop()
    }

    /// Called after TTS finishes in voice mode — auto-start listening again
    private func voiceModeContinue() {
        guard voiceMode, !isStreaming else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.voiceMode else { return }
            self.recorder.startRecording(hostname: self.hostname)
        }
    }

    // MARK: - Stop Recording Helper (text mode only)

    private func stopRecordingTextMode() {
        recorder.stopRecording()
    }

    // MARK: - Rate Limit Banner

    private var rateLimitBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
            Text("Daily free limit reached.")
                .font(.caption)
            Spacer()
            Button("Upgrade") {
                if let url = URL(string: "https://localkin.dev/pricing") {
                    openExternalURL(url)
                }
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.orange)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Agent Status Badge

    private var agentStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("Online")
                .font(.caption2)
                .foregroundColor(.green)
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)

        // Keep focus on input in text mode
        if !voiceMode {
            inputFocused = true
        }

        let apiMessages = messages.suffix(20).map { msg in
            APIMessage(role: msg.role.rawValue, content: msg.content)
        }

        isStreaming = true
        let assistantMessage = ChatMessage.assistant()
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

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

                // Voice mode: TTS then auto-listen again
                if voiceMode {
                    speaker.speak(
                        messages[assistantIndex].content,
                        hostname: hostname
                    ) {
                        voiceModeContinue()
                    }
                } else if ttsEnabled {
                    speaker.speak(
                        messages[assistantIndex].content,
                        hostname: hostname
                    ) {}
                }
            }
            ChatHistory.save(messages: messages, for: agent.slug)
        }

        client.onError = { error in
            if messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content = "Connection error. Please try again."
            }
            isStreaming = false
            sseClient = nil
            // In voice mode, continue listening even on error
            if voiceMode {
                voiceModeContinue()
            }
        }

        client.startStreaming(
            hostname: hostname,
            messages: apiMessages
        )
    }
}

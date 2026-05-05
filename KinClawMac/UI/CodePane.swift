import SwiftUI
import AppKit

/// "Code" mode: repo-aware coding agent driven by kincode on :5002.
///
/// Stage 4 MVP layout:
///
///   ┌────────────────────────────────────────┐
///   │ 📁 ~/Documents/Workspace/kincode  ▾    │  ← repo picker
///   ├────────────────────────────────────────┤
///   │  user: refactor pkg/server              │
///   │  kincode: I'll edit server.go ...        │  ← message stream
///   │  🔨 file_edit  pkg/server/server.go      │  ← tool_call inline
///   │  ✓ +12 −3                                │  ← tool_result inline
///   ├────────────────────────────────────────┤
///   │ 🪞 Message kincode…                  ⏎  │  ← input bar
///   └────────────────────────────────────────┘
///
/// File tree sidebar + diff viewer are post-MVP. The MVP gives the
/// user a working chat against kincode with inline tool feedback —
/// enough to actually drive a coding session, with diff visualization
/// (real diff viewer) coming in a follow-up.
///
/// State is kept inside CodePane (separate from SpotlightContentView's
/// chat state) because Code mode is a fundamentally different
/// conversation: kincode-only, repo-scoped, no agent picker, no voice
/// / TTS / attachments. Sharing state with Chat mode would complicate
/// without payoff.
struct CodePane: View {

    // MARK: - State

    /// Active repo path. Persisted across launches as the last-used.
    /// Empty string = no repo picked yet (user sees the picker hint).
    @AppStorage("kinclaw.kincode.repo") private var repoPath: String = ""

    /// Last 5 repos for the recent-repos dropdown. Comma-separated paths.
    @AppStorage("kinclaw.kincode.recents") private var recentsRaw: String = ""

    @State private var messages: [CodeMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @State private var connectError: String?

    /// Currently-streaming assistant message ID — text_delta events
    /// append to this bubble. Reset on turn_done.
    @State private var streamingMessageID: UUID?

    /// Active session id. One session per repo in v1; switching
    /// repos creates or loads a different one.
    @State private var sessionID: UUID = UUID()
    @State private var sessionCreatedAt: Date = Date()

    @FocusState private var inputFocused: Bool

    private let client = KinClawAPIClient.kincode

    // MARK: - Computed

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isStreaming
    }

    private var recents: [String] {
        recentsRaw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private var repoLabel: String {
        if repoPath.isEmpty { return "Pick a repo…" }
        let home = NSHomeDirectory()
        if repoPath.hasPrefix(home) {
            return "~" + repoPath.dropFirst(home.count)
        }
        return repoPath
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            repoBar
            Divider().opacity(0.15)
            messagesArea
            Divider().opacity(0.15)
            // Outer paddings match chatBody.inputBar wrapping —
            // 12pt horizontal, 8pt vertical around the rounded
            // input pill.
            inputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .onAppear {
            inputFocused = true
            startStreamIfNeeded()
            loadSessionIfNeeded()
            // Sync the persisted repo to kincode's cwd. Without this,
            // kincode boots in whatever cwd the supervisor spawn used
            // (~/Documents/Workspace/kinclaw or wherever the .app
            // launches from), regardless of what the UI's repo
            // dropdown shows. Result: agent's bash/file_* tools
            // operated on the wrong directory while the UI looked
            // pointed at the user's saved repo.
            syncRepoIfPersisted()
        }
        .onDisappear {
            streamTask?.cancel()
            streamTask = nil
            // Save on every disappear — covers mode switches without
            // waiting for app quit. save() is cheap (atomic write).
            saveSession()
        }
        .onChange(of: repoPath) { _, newPath in
            // Repo changed → start a fresh session (or resume the
            // existing one for this repo).
            messages.removeAll()
            sessionID = UUID()
            sessionCreatedAt = Date()
            loadSessionIfNeeded()
            // Re-sync to kincode whenever the repo state changes from
            // anywhere — applyRepo posts immediately on user click,
            // but onAppear-driven loads also need the sync.
            if !newPath.isEmpty {
                Task { try? await client.setRepo(newPath) }
            }
        }
    }

    /// Push the persisted `repoPath` to kincode's `/api/repo` so the
    /// subprocess's cwd matches what the UI shows. No-op when no
    /// repo has been picked yet.
    private func syncRepoIfPersisted() {
        guard !repoPath.isEmpty else { return }
        Task {
            do {
                try await client.setRepo(repoPath)
                connectError = nil
            } catch {
                // Don't surface as a fatal — kincode might still be
                // booting. The streamLoop's reconnect path picks it
                // up; next user message triggers another setRepo
                // attempt via send().
            }
        }
    }

    // MARK: - Repo bar

    /// Repo picker + utility buttons. Visually mirrors the agentBar
    /// in Chat / Cowork modes so the three tabs read as one product:
    /// same height, same paddings, status indicator on the right
    /// instead of inline error text.
    private var repoBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Pick repo…") { pickRepo() }
                if !recents.isEmpty {
                    Divider()
                    ForEach(recents, id: \.self) { r in
                        Button(prettify(r)) {
                            applyRepo(r)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(repoLabel)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status dot — green when SSE is live, orange when
            // reconnecting. Replaces the prominent "kincode unreachable
            // — retrying" inline text that competed with the repo name
            // for visual weight.
            Circle()
                .fill(connectError == nil
                      ? Color.green.opacity(0.7)
                      : Color.orange.opacity(0.7))
                .frame(width: 6, height: 6)
                .help(connectError ?? "kincode :5002 connected")

            // Stop button — interrupts the in-flight turn via
            // DELETE /api/chat. Only visible while streaming, so the
            // repoBar visual mass fluctuates with turn state but
            // never shows a useless dimmed icon.
            if isStreaming {
                Button {
                    interruptTurn()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Stop the agent (\u{2318}.)")
                .keyboardShortcut(".", modifiers: .command)
            }

            // Fresh session — saves current + starts new id + clears
            // kincode server-side memory (so a stuck error doesn't
            // resurrect through retry).
            Button {
                startNewSession()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundColor(messages.isEmpty
                                     ? .secondary.opacity(0.4)
                                     : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)
            .help("New session (saves current + clears kincode memory)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        emptyState
                            .padding(.top, 36)
                    } else {
                        ForEach(messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last(where: { $0.role != .toolResult })?.id {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Welcome card — mirrors the Chat/Cowork welcomeCard layout.
    /// Centered identity (🦞 + name) plus suggestion chips that
    /// fill the input on click. Same visual rhythm as the cloud-
    /// agent welcome so the three tabs feel like one product.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🦞")
                .font(.system(size: 44))
                .padding(.bottom, 4)

            Text("kincode")
                .font(.system(size: 18, weight: .semibold))

            Text(repoPath.isEmpty
                 ? "Pick a repo above to start"
                 : "Repo-aware coding agent")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.85))
                .padding(.top, 2)

            // Suggestion chips — same visual style as Chat/Cowork's
            // welcomeCard. Click fills the input field.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(suggestionPrompts, id: \.self) { prompt in
                    Button {
                        inputText = prompt
                        inputFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(prompt)
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.85))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.platformSecondaryBackground.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15),
                                        lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)

            Text("⌘⏎ to send · ✏ for new session")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.55))
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestionPrompts: [String] {
        if repoPath.isEmpty {
            return [
                "Pick a repo, then ask me to explain its layout",
                "Show me what files are in this project",
            ]
        }
        return [
            "Walk me through the main entry points",
            "Find all TODO comments and summarize",
            "Suggest the next high-leverage cleanup",
        ]
    }

    @ViewBuilder
    private func messageRow(_ msg: CodeMessage) -> some View {
        switch msg.role {
        case .user:
            // Right-aligned green-tinted bubble — exact same shape
            // and styling as Chat/Cowork's user bubble.
            HStack(alignment: .top, spacing: 6) {
                Spacer(minLength: 24)
                Text(msg.text)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.18))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        case .assistant:
            // 🦞 avatar + secondary-bg bubble — same shape as
            // Chat/Cowork's assistantBubble.
            HStack(alignment: .top, spacing: 6) {
                Text("🦞")
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22, alignment: .top)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    if msg.text.isEmpty {
                        StreamingDots(color: .secondary, size: 5, spacing: 5)
                            .padding(.vertical, 2)
                    } else {
                        MarkdownView(text: msg.text)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.platformSecondaryBackground.opacity(0.6))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)

                Spacer(minLength: 24)
            }
        case .toolCall:
            // Tool call pill — sits visually under the assistant
            // bubble it belongs to (avatar gutter padding 28pt
            // matches the avatar's 22pt + spacing 6).
            HStack(spacing: 6) {
                Image(systemName: "hammer")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.9))
                Text(msg.toolName ?? "tool")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.9))
                Text(msg.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .padding(.leading, 28)
        case .toolResult:
            if msg.toolName == "file_edit" && msg.toolError == nil {
                DiffView(raw: msg.text)
                    .padding(.leading, 28)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: msg.toolError == nil
                                      ? "checkmark"
                                      : "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(msg.toolError == nil
                                         ? .green.opacity(0.85)
                                         : .orange.opacity(0.9))
                    Text(truncate(msg.text, max: 220))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
                .padding(.leading, 28)
            }
        case .error:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.octagon")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.85))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .padding(.leading, 28)
        }
    }

    // MARK: - Input bar
    //
    // Same visual primitives as chatBody.inputBar — secondary-bg
    // pill with rounded 10pt corner. No paperclip / mic since
    // Code mode doesn't take attachments or voice (typing is the
    // right input modality for coding).

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message kincode…",
                      text: $inputText,
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { send() }

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

    // MARK: - Actions

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pick a repo for kincode"
        if panel.runModal() == .OK, let url = panel.url {
            applyRepo(url.path)
        }
    }

    private func applyRepo(_ path: String) {
        repoPath = path
        // Move to front of recents, dedup, cap at 5.
        var rs = recents.filter { $0 != path }
        rs.insert(path, at: 0)
        if rs.count > 5 { rs = Array(rs.prefix(5)) }
        recentsRaw = rs.joined(separator: ",")

        // Inform kincode. Server-side this just os.Chdir's the
        // subprocess; future tool calls operate relative to it.
        Task {
            do {
                try await client.setRepo(path)
                connectError = nil
            } catch {
                connectError = "kincode unreachable"
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        messages.append(CodeMessage(role: .user, text: text))
        isStreaming = true

        // Open assistant placeholder so streaming deltas have a target.
        let assistantID = UUID()
        streamingMessageID = assistantID
        messages.append(CodeMessage(id: assistantID, role: .assistant, text: ""))

        Task {
            do {
                try await client.sendChat(text)
            } catch {
                appendError("send failed: \(error.localizedDescription)")
                isStreaming = false
            }
        }
    }

    /// Idempotent — won't double-subscribe if start runs twice.
    private func startStreamIfNeeded() {
        guard streamTask == nil else { return }
        streamTask = Task { await streamLoop() }
    }

    private func streamLoop() async {
        // Outer loop: reconnect when the SSE connection drops (kinclaw
        // / kincode supervisor restarts, network blip). Inner loop:
        // pull events from the live stream.
        while !Task.isCancelled {
            do {
                connectError = nil
                let stream = client.eventStream()
                for try await event in stream {
                    if Task.isCancelled { break }
                    handle(event)
                }
            } catch {
                connectError = "kincode unreachable — retrying"
            }
            // Backoff before retry. 2s is short enough that the user
            // gets reconnected promptly after a quick blip; long
            // enough not to hammer a kernel that isn't coming back.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func handle(_ event: KinClawEvent) {
        guard let kind = event.kind else { return }
        switch kind {
        case .userMessage:
            // Already appended on send; ignore the echo.
            break
        case .textDelta:
            guard let chunk = event.text, !chunk.isEmpty else { return }
            appendDelta(chunk)
        case .toolCall:
            let summary = event.summary ?? deriveSummary(name: event.name, params: event.params)
            messages.append(CodeMessage(
                role: .toolCall,
                text: summary,
                toolName: event.name
            ))
        case .toolResult:
            messages.append(CodeMessage(
                role: .toolResult,
                text: event.output ?? "",
                toolName: event.name,
                toolError: event.message
            ))
        case .turnDone:
            isStreaming = false
            streamingMessageID = nil
            // Persist after each completed turn — survives app
            // quit, hotkey-driven panel close, repo switch.
            saveSession()
        case .error:
            appendError(event.message ?? "(unknown error)")
            isStreaming = false
            streamingMessageID = nil
            saveSession()
        default:
            // hello / soulSwitched / screenFrame / recordDone don't
            // apply to Code mode — drop quietly.
            break
        }
    }

    private func appendDelta(_ chunk: String) {
        guard let id = streamingMessageID,
              let idx = messages.lastIndex(where: { $0.id == id }) else {
            return
        }
        messages[idx].text += chunk
    }

    private func appendError(_ msg: String) {
        messages.append(CodeMessage(role: .error, text: msg))
    }

    /// Best-effort fallback display string when an event has params
    /// but no precomputed summary. Mirrors the kinclaw kernel's
    /// approach to formatting tool labels.
    private func deriveSummary(name: String?, params: [String: String]?) -> String {
        guard let p = params, !p.isEmpty else { return "" }
        // Common keys, ordered by likelihood of being the meaningful
        // identifier for a quick visual.
        for key in ["command", "file_path", "path", "pattern", "url", "query", "task"] {
            if let v = p[key] { return v }
        }
        // Last resort — pick any one.
        if let pair = p.first {
            return "\(pair.key)=\(pair.value)"
        }
        return ""
    }

    private func truncate(_ s: String, max n: Int) -> String {
        if s.count <= n { return s }
        return String(s.prefix(n)) + "…"
    }

    private func prettify(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: - Session persistence

    /// Resume the most-recent session for the active repo, if any.
    /// No-op when no repo is picked yet (sessions are repo-scoped).
    private func loadSessionIfNeeded() {
        guard !repoPath.isEmpty else { return }
        guard let session = CodeSessionStore.mostRecent(repoPath: repoPath) else {
            return
        }
        sessionID = session.id
        sessionCreatedAt = session.createdAt
        messages = session.messages.map { CodeMessage(
            id: $0.id,
            role: codeRoleFromPersisted($0.role),
            text: $0.text,
            toolName: $0.toolName,
            toolError: $0.toolError
        ) }
    }

    /// Persist current state. Cheap (atomic JSON write); called on
    /// turn_done, view disappear, error events.
    private func saveSession() {
        guard !repoPath.isEmpty, !messages.isEmpty else { return }
        let persisted = messages.map { msg in
            PersistedCodeMessage(
                id: msg.id,
                role: persistedRole(msg.role),
                text: msg.text,
                toolName: msg.toolName,
                toolError: msg.toolError
            )
        }
        let session = CodeSession(
            id: sessionID,
            repoPath: repoPath,
            messages: persisted,
            createdAt: sessionCreatedAt,
            updatedAt: Date()
        )
        CodeSessionStore.save(session)
    }

    private func persistedRole(_ r: CodeMessage.Role) -> PersistedCodeMessage.Role {
        switch r {
        case .user:       return .user
        case .assistant:  return .assistant
        case .toolCall:   return .toolCall
        case .toolResult: return .toolResult
        case .error:      return .error
        }
    }

    private func codeRoleFromPersisted(_ r: PersistedCodeMessage.Role) -> CodeMessage.Role {
        switch r {
        case .user:       return .user
        case .assistant:  return .assistant
        case .toolCall:   return .toolCall
        case .toolResult: return .toolResult
        case .error:      return .error
        }
    }

    /// Start a fresh session for the active repo. Old session stays
    /// on disk (one file per session id) — multi-session-per-repo is
    /// supported by the schema, this just doesn't surface a picker yet.
    ///
    /// Also clears kincode's SERVER-SIDE conversation memory via
    /// POST /api/clear. Without this, a stuck error state (e.g. a
    /// malformed history that 400s on every retry) would survive a
    /// "new session" click — kincode keeps the bad messages around
    /// until restart. Best-effort: if the call fails, local state
    /// still resets and the user can manually fix kincode by quit +
    /// relaunch.
    fileprivate func startNewSession() {
        // Persist the current one before discarding in-memory state.
        saveSession()
        messages.removeAll()
        sessionID = UUID()
        sessionCreatedAt = Date()
        isStreaming = false
        streamingMessageID = nil

        Task {
            try? await client.clearConversation()
        }
    }

    /// Cancel the in-flight turn via DELETE /api/chat. The agent's
    /// chatHandler goroutine observes the ctx cancellation, exits
    /// cleanly, and pushes turn_done as usual — handle() will then
    /// flip isStreaming false. We DON'T optimistically flip it here
    /// because we want the visual confirmation when the agent really
    /// stops (cancellation propagation can take a beat through the
    /// provider HTTP timeout).
    fileprivate func interruptTurn() {
        Task {
            try? await client.cancelTurn()
        }
    }
}

// MARK: - Message model

/// One row in the Code mode message stream. Compact representation
/// covering all event types we display inline (user, assistant, tool
/// call, tool result, error). Kept local to CodePane — Chat mode's
/// ChatMessage is richer (attachments, sources, voice) and a bad fit.
struct CodeMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case toolCall
        case toolResult
        case error
    }

    let id: UUID
    let role: Role
    var text: String
    /// Tool name for toolCall / toolResult rows ("bash", "file_read"…).
    let toolName: String?
    /// Non-nil for toolResult events that also carried a hard error
    /// (parse failure, denied permission). Distinguished from
    /// "tool ran but failed" — those have a normal output string with
    /// the tool's own error message folded in.
    let toolError: String?

    init(id: UUID = UUID(),
         role: Role,
         text: String,
         toolName: String? = nil,
         toolError: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolError = toolError
    }
}

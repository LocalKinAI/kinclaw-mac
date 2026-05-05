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
            inputBar
        }
        .onAppear {
            inputFocused = true
            startStreamIfNeeded()
            loadSessionIfNeeded()
        }
        .onDisappear {
            streamTask?.cancel()
            streamTask = nil
            // Save on every disappear — covers mode switches without
            // waiting for app quit. save() is cheap (atomic write).
            saveSession()
        }
        .onChange(of: repoPath) { _, _ in
            // Repo changed → start a fresh session (or resume the
            // existing one for this repo).
            messages.removeAll()
            sessionID = UUID()
            sessionCreatedAt = Date()
            loadSessionIfNeeded()
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

            // Fresh session — saves current + starts new id.
            // Always rendered for visual symmetry with Chat / Cowork's
            // 3-button right cluster (visible mass even with empty
            // history); disabled when there's nothing to save.
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
            .help("New session (saves current)")
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

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.secondary)
            Text("Code mode")
                .font(.system(size: 14, weight: .semibold))
            Text(repoPath.isEmpty
                 ? "Pick a repo above, then ask kincode to refactor, debug, or explain code."
                 : "Ask kincode to refactor, debug, or explain code in this repo.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func messageRow(_ msg: CodeMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(0.55))
                    )
            }
        case .assistant:
            HStack(alignment: .top) {
                if msg.text.isEmpty {
                    // Pre-stream placeholder. Plain Text avoids the
                    // MarkdownParser running on an empty string every
                    // delta tick (parser is cheap but still ~µs).
                    Text("…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    // Same MarkdownView the Chat surface uses so
                    // fenced code blocks, lists, and headings render
                    // properly — kincode replies are heavy on
                    // ```code``` blocks, plain Text would show the
                    // backticks raw and collapse the formatting.
                    MarkdownView(text: msg.text)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        case .toolCall:
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
        case .toolResult:
            // file_edit results carry a unified diff with ANSI color
            // codes — render them as a colored diff block instead of
            // truncated monospace. Other tools (bash, file_read, glob,
            // grep, web_*) keep the simple truncated row.
            if msg.toolName == "file_edit" && msg.toolError == nil {
                DiffView(raw: msg.text)
                    .padding(.leading, 18)
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
                .padding(.leading, 18)  // align under the parent tool_call
            }
        case .error:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.octagon")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                Text(msg.text)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message kincode…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(canSend ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    fileprivate func startNewSession() {
        // Persist the current one before discarding the in-memory state.
        saveSession()
        messages.removeAll()
        sessionID = UUID()
        sessionCreatedAt = Date()
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

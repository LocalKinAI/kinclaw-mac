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

    /// Pending image attachments — populated by the paperclip picker
    /// and the drag-and-drop receiver. Cleared on send. Each entry
    /// owns the base64-encoded payload; thumbnails decode on demand
    /// from `data` for the chip preview.
    @State private var pendingImages: [KinClawAPIClient.ImageAttachment] = []

    /// Plan mode: when true, kincode denies write/exec/spawn tools
    /// and the model emits a markdown plan instead. Synced bi-
    /// directionally — UI toggle POSTs /api/plan_mode, server SSE
    /// broadcasts plan_mode events that update this state. Initial
    /// value comes from the /api/state probe on .task.
    @State private var planMode: Bool = false

    /// Currently-streaming assistant message ID — text_delta events
    /// append to this bubble. Reset on turn_done.
    @State private var streamingMessageID: UUID?

    /// Live brain (provider/model) reported by /api/state. Distinct
    /// from the persisted *default* brain in Settings — the dropdown
    /// here switches the running subprocess via /api/brain only,
    /// next launch uses Settings' default.
    @State private var activeProvider: String = ""
    @State private var activeModel: String = ""

    /// Brain presets loaded from the user's local Ollama install
    /// (`:11434/api/tags`). Populated on .task; falls back to a
    /// minimum static list if Ollama is unreachable.
    @State private var brainPresets: [BrainPreset] = BrainPreset.fallbackPresets

    /// Active session id. One session per repo in v1; switching
    /// repos creates or loads a different one.
    @State private var sessionID: UUID = UUID()
    @State private var sessionCreatedAt: Date = Date()

    @FocusState private var inputFocused: Bool

    private let client = KinClawAPIClient.kincode

    // MARK: - Computed

    private var canSend: Bool {
        // Send is allowed if there's text OR pending images. An
        // images-only turn lets the user drop a screenshot and ask
        // "what's this?" without typing anything (kincode forwards
        // an empty string + images to the model).
        let hasText = !inputText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !pendingImages.isEmpty
        return (hasText || hasImages) && !isStreaming
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
            // Fetch live brain (provider/model) for the dropdown
            // label. Refresh again after the SSE stream connects
            // (in streamLoop's success path) since kincode might
            // still be booting on first onAppear.
            Task { await refreshState() }
            // Load the user's actual Ollama models for the brain
            // dropdown. Cached for the rest of the session;
            // "Reload from Ollama" in the menu refreshes manually.
            Task { await reloadBrainPresets() }
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

            // Brain picker — live switch via POST /api/brain. Doesn't
            // persist (Settings → Backend → Kincode is where you set
            // the default). Compact: emoji + truncated model label.
            brainMenu

            Spacer(minLength: 0)

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
            // and styling as Chat/Cowork's user bubble. Adds a
            // "📎 N images" footer when attachmentCount > 0 so the
            // user can verify their drop / paperclip pick attached.
            HStack(alignment: .top, spacing: 6) {
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: 3) {
                    if !msg.text.isEmpty {
                        Text(msg.text)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textSelection(.enabled)
                    }
                    if msg.attachmentCount > 0 {
                        Label(
                            "\(msg.attachmentCount) image\(msg.attachmentCount == 1 ? "" : "s")",
                            systemImage: "paperclip"
                        )
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                }
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
                        // Brain footer — Claude.ai / ChatGPT-style
                        // "via <model>" tag below the bubble. Only
                        // shown on the most recent assistant message
                        // (mid-session brain switches would mis-tag
                        // older messages with the new brain otherwise).
                        if isLatestAssistant(msg) && !activeModel.isEmpty {
                            Text("via \(brainLabel)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 2)
                        }
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
            // Special case: todo_write renders as a checklist instead
            // of the standard tool-call pill. The todos array lives in
            // toolParams["todos"] as JSON (kincode JSON-encodes complex
            // args at SSE emission). We parse + render inline so the
            // user sees the agent's plan as a real checklist, not as
            // "🔨 todo_write [{...}]".
            if msg.toolName == "todo_write",
               let todos = parseTodos(from: msg.toolParams) {
                TodoChecklistView(items: todos)
                    .padding(.leading, 28)
            } else {
                // Standard tool-call pill — sits visually under the
                // assistant bubble it belongs to (avatar gutter padding
                // 28pt matches the avatar's 22pt + spacing 6).
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
            }
        case .toolResult:
            // todo_write's tool_result is just a text re-render of the
            // checklist that's already shown by the tool_call's
            // TodoChecklistView. Skip to avoid duplication.
            if msg.toolName == "todo_write" {
                EmptyView()
            } else if msg.toolName == "file_edit" && msg.toolError == nil {
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
    // pill with rounded 10pt corner. Paperclip + drop target wire
    // image attachments through to /api/chat's `images` array (vision
    // models only — Anthropic claude-3+ / OpenAI gpt-4o); paperclip
    // opens NSOpenPanel filtered to PNG/JPG/GIF/WEBP.

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Plan-mode banner: shown above attachments when on, so
            // the user knows kincode won't actually modify anything
            // until they toggle off.
            if planMode {
                planModeBanner
            }

            // Pending-image chip strip. Hidden when no images attached.
            // Each chip shows a 32pt thumbnail + filename suffix + ×
            // button. Click × to remove without losing the rest.
            if !pendingImages.isEmpty {
                attachmentStrip
            }

            HStack(spacing: 8) {
                Button {
                    pickImages()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach images (PNG, JPG, GIF, WEBP)")

                Button {
                    togglePlanMode()
                } label: {
                    Image(systemName: planMode
                          ? "list.bullet.rectangle.fill"
                          : "list.bullet.rectangle")
                        .font(.system(size: 14))
                        .foregroundColor(planMode ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(planMode
                      ? "Plan mode is ON — kincode will plan, not execute. Click to disable."
                      : "Enable plan mode — kincode plans only, no file writes or shell.")

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformSecondaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // Drag-and-drop receiver: accept image file URLs dropped from
        // Finder / screenshots. Decodes synchronously off the main
        // thread inside ingestImage().
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pendingImages) { att in
                    attachmentChip(att)
                }
            }
        }
        .frame(height: 38)
    }

    /// Plan-mode banner: thin orange-tinted pill above the input
    /// reminding the user that kincode will plan but not execute
    /// while the toggle is on. Tapping the banner toggles off, same
    /// as clicking the icon — gives the user two paths back to
    /// normal mode.
    @ViewBuilder
    private var planModeBanner: some View {
        Button {
            togglePlanMode()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Plan mode — read-only, no edits / shell. Tap to disable.")
                    .font(.system(size: 10, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(.orange.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func attachmentChip(_ att: KinClawAPIClient.ImageAttachment)
        -> some View
    {
        HStack(spacing: 4) {
            if let nsImage = decodeImagePreview(att.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
            }
            Text(att.mediaType
                .replacingOccurrences(of: "image/", with: ""))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Button {
                pendingImages.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.platformSecondaryBackground.opacity(0.7))
        )
    }

    /// Best-effort thumbnail decode for the chip strip. Returns nil
    /// (caller falls back to a generic photo glyph) on failure rather
    /// than crashing — a corrupt base64 payload would still send to
    /// the model fine; only the preview is missing.
    private func decodeImagePreview(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
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

        // Snapshot + clear pending images. The user sees them clear
        // immediately; the local message bubble shows an attachment
        // count so they don't lose track of what was sent.
        let images = pendingImages
        pendingImages = []

        var bubble = CodeMessage(role: .user, text: text)
        if !images.isEmpty {
            bubble.attachmentCount = images.count
        }
        messages.append(bubble)
        isStreaming = true

        // Open assistant placeholder so streaming deltas have a target.
        let assistantID = UUID()
        streamingMessageID = assistantID
        messages.append(CodeMessage(id: assistantID, role: .assistant, text: ""))

        Task {
            do {
                try await client.sendChat(text, images: images)
            } catch {
                appendError("send failed: \(error.localizedDescription)")
                isStreaming = false
            }
        }
    }

    /// Open NSOpenPanel filtered to image types. Encodes selected
    /// files to base64 and appends to pendingImages. Caps at 8 per
    /// turn — each PNG can be hundreds of KB and the model context
    /// budget chokes past that.
    private func pickImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.message = "Attach images for kincode"
        if panel.runModal() == .OK {
            for url in panel.urls.prefix(8) {
                ingestImage(at: url)
            }
        }
    }

    /// Read a local file, sniff its media type from the extension,
    /// base64-encode, and append to pendingImages. Silent on
    /// failure — the user can re-attach if the picker glitched.
    private func ingestImage(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mediaType: String
        switch ext {
        case "png":   mediaType = "image/png"
        case "jpg",
             "jpeg": mediaType = "image/jpeg"
        case "gif":   mediaType = "image/gif"
        case "webp":  mediaType = "image/webp"
        default:      return  // unsupported format
        }
        guard pendingImages.count < 8 else { return }
        pendingImages.append(KinClawAPIClient.ImageAttachment(
            mediaType: mediaType,
            data: data.base64EncodedString()
        ))
    }

    /// Drag-and-drop handler. Resolves each provider into a URL or
    /// raw image data and routes through ingestImage. Always returns
    /// true so SwiftUI doesn't bounce the drop visual.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { ingestImage(at: url) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") {
                    data, _ in
                    guard let data = data,
                          NSImage(data: data) != nil
                    else { return }
                    // Default to PNG for raw drops (screenshots,
                    // pasteboard images) — every vision model
                    // accepts it.
                    let att = KinClawAPIClient.ImageAttachment(
                        mediaType: "image/png",
                        data: data.base64EncodedString()
                    )
                    DispatchQueue.main.async {
                        if pendingImages.count < 8 {
                            pendingImages.append(att)
                        }
                    }
                }
            }
        }
        return true
    }

    /// Flip plan mode locally + on the server. Optimistic update —
    /// the SSE plan_mode event will reconcile if the server refused
    /// (e.g. mid-turn). On error we revert and surface a status
    /// message so the user sees the toggle didn't take.
    private func togglePlanMode() {
        let target = !planMode
        planMode = target  // optimistic
        Task {
            do {
                let confirmed = try await client.setPlanMode(target)
                planMode = confirmed
            } catch {
                // Revert + log. The user will see the icon flip back.
                planMode = !target
                appendError("plan mode toggle failed: \(error.localizedDescription)")
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
                // First successful subscribe = kincode is up. Re-fetch
                // /api/state to populate activeProvider/activeModel —
                // the onAppear refreshState call may have raced with
                // kincode's boot and silently failed, leaving the 🧠
                // label stuck on "loading…".
                Task { await refreshState() }
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
                toolName: event.name,
                toolParams: event.params
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
        case .planMode:
            // Server-side plan-mode change — could be from this UI
            // (echo of our /api/plan_mode POST) or from a sibling
            // window. Sync the toggle either way.
            if let p = event.plan_mode {
                planMode = p
            }
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

    // MARK: - Brain picker

    /// Compact brain dropdown next to the repo picker. Shows the
    /// currently-active model (truncated) with a 🧠 prefix; clicking
    /// opens a list of presets. Switching is a live action — POSTs
    /// /api/brain — and DOES NOT persist. The Settings → Backend →
    /// Kincode card is where the default is set.
    private var brainMenu: some View {
        Menu {
            if brainPresets.isEmpty {
                Text("Ollama not reachable on :11434")
                    .foregroundColor(.secondary)
            } else {
                ForEach(brainPresets) { preset in
                    Button {
                        switchBrain(to: preset)
                    } label: {
                        let isCurrent = (preset.provider == activeProvider
                                         && preset.model == activeModel)
                        HStack {
                            Text(preset.label)
                            Spacer()
                            if let tag = preset.tag {
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if isCurrent {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Reload from Ollama") {
                Task { await reloadBrainPresets() }
            }
            Text("Default brain → Settings → Backend")
                .foregroundColor(.secondary)
        } label: {
            HStack(spacing: 4) {
                Text("🧠")
                    .font(.system(size: 12))
                Text(brainLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(activeModel.isEmpty
                                     ? .secondary
                                     : .primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch brain for this session (default: Settings → Backend)")
    }

    /// Display label for the current brain — preset's pretty name
    /// when known, else the raw model string for custom configs.
    private var brainLabel: String {
        if activeModel.isEmpty { return "loading…" }
        if let preset = BrainPreset.find(provider: activeProvider,
                                          model: activeModel,
                                          in: brainPresets) {
            return preset.label
        }
        return activeModel  // model installed but not in current catalog snapshot
    }

    /// True if `msg` is the most recently-appended assistant message
    /// in the stream. Used to gate the "via <brain>" footer so only
    /// the freshest reply carries the tag (avoids mis-attributing
    /// older messages when the brain was switched mid-session).
    private func isLatestAssistant(_ msg: CodeMessage) -> Bool {
        messages.last(where: { $0.role == .assistant })?.id == msg.id
    }

    /// Parse the `todos` JSON string out of a todo_write tool_call's
    /// params and decode into structured TodoItem rows. Returns nil
    /// when params is missing, todos field is missing, or the JSON
    /// fails to decode — the caller falls back to rendering the
    /// standard tool-call pill, so a malformed payload is graceful.
    private func parseTodos(from params: [String: String]?) -> [TodoItem]? {
        guard let json = params?["todos"],
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([TodoItem].self, from: data)
    }

    /// Re-query Ollama for installed models. Called on .task and
    /// from the "Reload from Ollama" menu item. Empty result means
    /// Ollama is unreachable — keep the existing list rather than
    /// blanking the menu.
    fileprivate func reloadBrainPresets() async {
        let fresh = await OllamaCatalog.loadPresets()
        if !fresh.isEmpty {
            await MainActor.run { brainPresets = fresh }
        }
    }

    /// POST /api/brain. Server side cancels any in-flight turn first
    /// and rebuilds the provider; on success we re-fetch /api/state to
    /// pick up the new model. Errors (e.g. missing API key) come back
    /// through the API client and surface as connectError text.
    private func switchBrain(to preset: BrainPreset) {
        Task {
            do {
                try await client.switchBrain(provider: preset.provider,
                                             model: preset.model)
                await refreshState()
                connectError = nil
            } catch {
                connectError = "brain switch failed — \(error.localizedDescription)"
            }
        }
    }

    /// Pull the live state (provider + model) from /api/state. Called
    /// onAppear and after every successful brain switch. Failure is
    /// silent — Mac stays on the old activeModel label until next try.
    fileprivate func refreshState() async {
        do {
            let state = try await client.fetchState()
            await MainActor.run {
                activeProvider = state.provider ?? ""
                activeModel = state.model ?? ""
            }
        } catch {
            // ignore — kincode might still be booting
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
    /// Raw tool params (kincode stringifies arrays/maps to JSON).
    /// Surfaced for tools where the structured args matter for
    /// rendering — todo_write needs the todos array, multi_edit
    /// could expose the edits array, etc. Optional + only populated
    /// for `.toolCall` rows; other rows leave it nil.
    let toolParams: [String: String]?
    /// Number of image attachments on a user message. Rendered as a
    /// small "📎 N images" footer on the user bubble. Settable via
    /// var so send() can stamp it after constructing the bubble.
    var attachmentCount: Int = 0

    init(id: UUID = UUID(),
         role: Role,
         text: String,
         toolName: String? = nil,
         toolError: String? = nil,
         toolParams: [String: String]? = nil,
         attachmentCount: Int = 0) {
        self.id = id
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolError = toolError
        self.toolParams = toolParams
        self.attachmentCount = attachmentCount
    }
}

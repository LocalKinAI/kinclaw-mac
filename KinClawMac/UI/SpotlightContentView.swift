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
    /// Files the user has dragged in but not yet sent. Render as
    /// chips above the input bar; cleared after each send.
    @State private var pendingAttachments: [Attachment] = []
    /// Drop-zone visual state — used to highlight the input area
    /// when the cursor is dragging a file over it.
    @State private var isDropTarget = false
    /// Currently-active session id. Changes when the user picks
    /// "New chat" or selects an item from the history popover.
    @State private var currentSessionID: UUID = UUID()
    @State private var sessionTitle: String = "New chat"
    @State private var showingHistoryPopover = false
    /// Reveal state for the recent-agents row at the top of the
    /// messages area. Latched on hover, latched off via small
    /// delayed timer so brief mouse exits don't flicker the row.
    @State private var showingRecentRow = false
    @State private var recentRowHideTask: DispatchWorkItem?

    /// Active surface — Chat / Cowork / Code. Loaded from UserDefaults
    /// so the user's last choice survives a relaunch.
    @State private var mode: ChatMode = ChatMode.loadPersisted()

    /// Per-mode last-used agent slug. Each tab has its OWN active
    /// agent — switching tabs swaps which agent is in use. This is
    /// the conceptual heart of the three-tab split:
    ///
    ///   Chat   → cloud personalities (Selah / Heal / Core / Faith)
    ///   Cowork → KinClaw computer-use souls (Pilot / Coder / etc.)
    ///   Code   → fixed kincode kernel (no picker)
    ///
    /// Without this separation, "I was chatting with Selah, switched
    /// to Cowork" would leave Selah selected — and Selah can't drive
    /// the screen claw, so the surface silently fails to do what the
    /// user expects.
    @AppStorage("kinclaw.chat.lastAgent") private var chatLastAgentSlug: String = ""
    @AppStorage("kinclaw.cowork.lastSoul") private var coworkLastSoulSlug: String = ""

    // Cowork brain state — populated from kinclaw's hello event
    // (params.brain = "ollama/kimi-k2.5:cloud") and refreshed on
    // brain_switched events. Distinct from the soul: same Pilot
    // soul, different brain. Brain dropdown next to the agent
    // picker drives POST /api/brain to swap live without changing
    // soul/skills.
    @State private var coworkActiveProvider: String = ""
    @State private var coworkActiveModel: String = ""
    @State private var coworkBrainPresets: [BrainPreset] = BrainPreset.fallbackPresets

    /// Connection error string for kinclaw's :5001 server. Nil = OK,
    /// non-nil = the green dot in agentBar flips orange and the
    /// tooltip shows the reason. Refreshed on appear, on stream
    /// errors, and after a brain switch.
    @State private var coworkConnectError: String?

    /// Chat-tab "browse vs chat" state. True = show the agent
    /// gallery (discovery surface). False = show welcomeCard /
    /// messages for the selected agent. Default true so first-time
    /// users land on discovery; flips false when they tap a card,
    /// flips back true on "← agents" / ⌘B / explicit nil out.
    /// Independent of selectedAgent so a returning user with
    /// chatLastAgentSlug auto-restored STILL sees the gallery as
    /// the empty-state entry.
    @State private var chatBrowsing: Bool = true

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
    private var coreAgents: [Agent] {
        cloudAgents.filter { $0.domain == "core" }
    }
    private var spiritualAgents: [Agent] {
        cloudAgents.filter { $0.domain == "spiritual" }
    }
    private var tcmAgents: [Agent] {
        cloudAgents.filter { $0.domain == "tcm" }
    }
    private var otherCloudAgents: [Agent] {
        cloudAgents.filter {
            $0.domain != "core"
                && $0.domain != "spiritual"
                && $0.domain != "tcm"
        }
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
        // Two layers via ZStack:
        //   - Main content in a VStack starting at y=0 BELOW the
        //     titlebar (28pt reserved Color.clear placeholder so
        //     chat messages don't slide UP under the traffic
        //     lights).
        //   - Header overlay (.ignoresSafeArea(.top)) floating
        //     INTO the titlebar row, sharing the row with the
        //     traffic lights NSWindow draws there.
        // The .ignoresSafeArea is scoped to JUST the header (not
        // the whole body) — putting it on the parent in r10 was
        // what pushed the messages up under the titlebar.
        ZStack(alignment: .top) {
            mainStack
            titlebarHeaderOverlay
        }
        .frame(minWidth: 320, minHeight: 380)
    }

    /// Main column. Layout hierarchy (top → bottom):
    ///
    ///   1. titlebar (28pt reserve) — ModeBar lives in the overlay
    ///      that floats here, so the FIRST thing the eye lands on is
    ///      "what am I trying to do" (Chat / Cowork / Code).
    ///   2. agentBar (Chat/Cowork only) — secondary row with the
    ///      mode-scoped agent picker + history / clear / tts. Code
    ///      mode skips this row; CodePane's own repoBar serves the
    ///      same secondary role for that surface.
    ///   3. mode body — chat / cowork / code, each consuming the
    ///      remaining vertical space.
    ///
    /// The reorder (mode primary, agent secondary) reflects the
    /// conceptual hierarchy: the user's first decision is what kind
    /// of work they're doing; only after that does "with whom" matter.
    private var mainStack: some View {
        VStack(spacing: 0) {
            // 22pt reservation for the titlebar row. macOS standard
            // traffic-light height is ~22pt; the previous 28pt left
            // ~6pt of dead space below the ModeBar pills before the
            // divider, which read as a noticeable gap on the glass
            // background. Match the actual visible chrome height.
            Color.clear.frame(height: 22)

            Divider().opacity(0.15)

            // Secondary row — agent picker and utility buttons. Code
            // mode has CodePane's own repoBar acting as its secondary
            // row, so we skip ours there to avoid double bars.
            if mode != .code {
                agentBar
                Divider().opacity(0.15)
            }

            Group {
                switch mode {
                case .chat, .cowork:
                    // Chat and Cowork share the same chat surface —
                    // the only difference is the agent pool (cloud vs
                    // KinClaw souls), enforced by the mode-scoped
                    // agentMenu in agentBar above. The screen / input
                    // claws are tools the AGENT uses when invoked;
                    // the user's actual desktop is right there, no
                    // need to embed a preview.
                    chatBody
                case .code:
                    CodePane()
                }
            }
        }
        .preferredColorScheme(.dark)
        .background(Color.clear) // SpotlightWindow's blur shows through
        // Drag any file in from Finder / desktop / mail — becomes a
        // pending attachment. Local kinclaw souls (Pilot etc.) get
        // the file path baked into the message so the agent can
        // read it directly. Cloud agents get a path mention but
        // can't access the file (Phase 2: vision-model upload).
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            Task { await loadAgents() }
            // Auto-populate the Cowork brain dropdown from the user's
            // actual Ollama install — same UX Code mode has. Without
            // this the dropdown shows only fallback presets until the
            // user manually clicks "Reload from Ollama".
            Task { await reloadCoworkBrainPresets() }
            // Probe kinclaw's :5001 once on appear so the green dot
            // reflects truth from the start (vs waiting for the next
            // hello/error event to arrive).
            Task { await refreshCoworkConnection() }
        }
        .onChange(of: selectedAgent?.slug) { _, slug in
            handleAgentChange()
            persistAgentForCurrentMode(slug: slug)
        }
        .onChange(of: mode) { _, newMode in
            // Save the outgoing session and clear the surface
            // SYNCHRONOUSLY before the agent-swap chain fires.
            // Without this clear-first step there's a 1-frame
            // flash where the new mode's view (chatBody) still
            // shows the previous tab's messages because the
            // selectedAgent change → handleAgentChange path
            // runs on the *next* layout cycle. Tab switching
            // should feel instant.
            saveCurrentSession()
            messages = []
            currentSessionID = UUID()
            sessionTitle = "New chat"
            // Re-enter browse mode whenever we land back in Chat
            // tab — the gallery is the entry surface, not the
            // last welcomeCard. Tab-switch behavior matches "open
            // app fresh" behavior.
            if newMode == .chat {
                chatBrowsing = true
            }
            applyAgentForMode(newMode)
        }
        .onDisappear {
            sseClient?.cancel()
            localStreamTask?.cancel()
            speaker.stop()
        }
    }

    /// Chat surface — the original spotlight content (messages +
    /// pending attachments + input bar). Extracted from mainStack
    /// in Stage 2 so the same VStack can switch between chat /
    /// cowork / code based on the active ModeBar selection.
    private var chatBody: some View {
        VStack(spacing: 0) {
            // messagesView is the primary, flexible child.
            // The hover-zone + recent-agents row sit as OVERLAYS so
            // they don't compete with the ScrollView for layout
            // priority — the previous ZStack arrangement collapsed
            // the chat to a near-zero height after sending the
            // first message because the 12pt hover hit zone was
            // dominating intrinsic sizing.
            messagesView
                .overlay(alignment: .top) {
                    if showingRecentRow {
                        RecentAgentsRow(
                            allAgents: allAgents,
                            currentSlug: selectedAgent?.slug,
                            onSelect: { agent in
                                selectedAgent = agent
                                scheduleRecentRowHide(after: 0.15)
                            }
                        )
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .top)
                                     .combined(with: .opacity))
                        .onHover { hovering in
                            if hovering { cancelRecentRowHide() }
                            else { scheduleRecentRowHide(after: 0.6) }
                        }
                    }
                }
                .overlay(alignment: .top) {
                    // 12pt invisible hover trigger floating ON TOP
                    // of the messages — only intercepts hover, not
                    // clicks (allowsHitTesting elsewhere).
                    Color.clear
                        .frame(height: 12)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                cancelRecentRowHide()
                                withAnimation(.easeOut(duration: 0.18)) {
                                    showingRecentRow = true
                                }
                            } else {
                                scheduleRecentRowHide(after: 0.6)
                            }
                        }
                }

            Divider().opacity(0.15)

            pendingAttachmentsBar

            inputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isDropTarget
                                ? Color.green.opacity(0.6)
                                : Color.clear,
                                lineWidth: 1.5)
                        .padding(.horizontal, 8)
                )
        }
    }

    /// Titlebar overlay — sits in the 28pt row alongside the macOS
    /// traffic-light buttons. Hosts the **ModeBar** (Chat / Cowork /
    /// Code) as the primary identity of the panel: what the user is
    /// trying to do is the highest-level question. Settings (⚙) is
    /// the only other titlebar resident — it's truly global, not
    /// mode-scoped.
    ///
    /// Pinned via .ignoresSafeArea(.top) — without it SwiftUI inserts
    /// a safe-area inset and the bar drops below the traffic lights.
    private var titlebarHeaderOverlay: some View {
        HStack(spacing: 10) {
            ModeBar(mode: $mode)
                .frame(maxWidth: .infinity, alignment: .leading)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 72)   // clear the traffic-light buttons
        .padding(.trailing, 14)
        .padding(.vertical, 1)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Secondary row (Chat/Cowork only): mode-scoped agent picker on
    /// the left, utility buttons (history / clear / tts) on the right.
    /// Code mode skips this — CodePane's own repoBar is the secondary
    /// row for that surface, with a different identity (the repo
    /// path, not an agent).
    private var agentBar: some View {
        HStack(spacing: 10) {
            agentMenu
                .frame(maxWidth: .infinity, alignment: .leading)

            // Cowork-only: brain dropdown next to the soul picker.
            // Soul (Pilot/Coder/...) and brain (kimi/claude/qwen) are
            // independent — pick Pilot then swap brain without
            // reloading. Mirrors Code mode's brainMenu but hits
            // kinclaw on :5001 instead of kincode on :5002.
            if mode == .cowork {
                coworkBrainMenu
            }

            // Session history (📚) — popover with all saved chats
            // for the active agent + "+ New chat" + delete.
            Button {
                showingHistoryPopover.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Session history (\u{2318}H)")
            .keyboardShortcut("h", modifiers: .command)
            .popover(isPresented: $showingHistoryPopover,
                     arrowEdge: .top) {
                if let agent = selectedAgent {
                    SessionHistoryPopover(
                        agentSlug: agent.slug,
                        activeSessionID: currentSessionID,
                        onPick: { session in
                            loadSession(session)
                            showingHistoryPopover = false
                        },
                        onNew: {
                            startNewSession()
                            showingHistoryPopover = false
                        },
                        onDelete: { session in
                            ChatSessionStore.delete(id: session.id,
                                                     agentSlug: agent.slug)
                            if session.id == currentSessionID {
                                startNewSession()
                            }
                        }
                    )
                }
            }

            // Connection dot — Cowork-only since the :5001 server
            // is what makes Cowork tick. Green = kinclaw responding,
            // orange = unreachable (helper crashed, supervisor
            // recovering, port collision). Replaces the loud
            // "kinclaw not reachable" inline error text that used
            // to compete with the agent name for visual weight.
            if mode == .cowork {
                Circle()
                    .fill(coworkConnectError == nil
                          ? Color.green.opacity(0.7)
                          : Color.orange.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .help(coworkConnectError ?? "kinclaw :5001 connected")
            }

            // Stop button — interrupts the in-flight turn via
            // DELETE /api/chat (kinclaw) or task cancel (cloud SSE
            // through SSEClient). Only visible while a turn is
            // streaming. Mirrors Code mode's Stop in CodePane —
            // same icon, same Cmd+. shortcut. Critical for Cowork:
            // a misbehaving Pilot trying 5-7 GUI clicks needs an
            // emergency stop, not "wait for the next AX timeout".
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

            // New session — saves current to disk + starts a fresh
            // session id. For Cowork, this also re-loads the active
            // soul on the server side so kinclaw's history buffer
            // resets (otherwise a stuck error message survives).
            // Same icon Code uses; dimmed when the chat is empty
            // to discourage the redundant click.
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
            .help("New session (saves current + clears agent memory)")

            if !messages.isEmpty {
                Button {
                    clearChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear chat (\u{2318}\u{232B})")
                .keyboardShortcut(.delete, modifiers: .command)
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Agent picker (Chat / Cowork only)
    // (The old monolithic `header` was split into agentBar + the new
    //  ModeBar-driven titlebarHeaderOverlay. agentMenu is still the
    //  picker — see below.)


    private var agentMenu: some View {
        Menu {
            // Mode-scoped dropdown — Chat shows ONLY cloud groups
            // (Selah / Heal / Core / Faith); Cowork shows ONLY KinClaw
            // computer-use souls. This is the conceptual heart of the
            // three-tab split: each tab has a distinct purpose, so its
            // agent pool is distinct too. Code mode never reaches this
            // menu (kincode is fixed; the picker is replaced upstream
            // with a static label).

            switch mode {
            case .cowork:
                // ── KinClaw computer-use souls (7 today) ──
                if !kinClawSouls.isEmpty {
                    Menu("🦞  KinClaw  (\(kinClawSouls.count))") {
                        ForEach(kinClawSouls) { agentMenuRow($0) }
                    }
                } else if !isLoadingAgents {
                    Text("🦞  No KinClaw souls — is kinclaw running on :5001?")
                        .foregroundColor(.secondary)
                }

            case .chat:
                // ── Core — `localkin/scripts/serve.sh` AGENTS array,
                //     17 publicly tunneled agents at *.localkin.dev. ──
                if !coreAgents.isEmpty {
                    Menu("⭐  Core  (\(coreAgents.count))") {
                        ForEach(coreAgents) { agentMenuRow($0) }
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

                // ── Cloud agents in unrecognized domains ──
                if !otherCloudAgents.isEmpty {
                    Menu("☁️  Other cloud  (\(otherCloudAgents.count))") {
                        ForEach(otherCloudAgents.prefix(80)) { agentMenuRow($0) }
                    }
                }

            case .code:
                // Unreachable — header swaps the picker for a static
                // "🦞 kincode" label when mode == .code. Defensive
                // empty case.
                EmptyView()
            }

            // ── No groups at all → empty / loading ──
            if mode == .chat && cloudAgents.isEmpty {
                if isLoadingAgents {
                    Text("Loading cloud agents…").foregroundColor(.secondary)
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

    /// Cowork brain dropdown. Compact label "🧠 <model>" with a
    /// chevron; clicking opens a list of presets pulled from the
    /// user's local Ollama plus a fallback static list. Selection
    /// POSTs /api/brain to kinclaw on :5001 — same soul (Pilot etc.
    /// stays Pilot), different brain. State updates come back via
    /// SSE hello / brain_switched events.
    private var coworkBrainMenu: some View {
        Menu {
            if coworkBrainPresets.isEmpty {
                Text("Ollama not reachable on :11434")
                    .foregroundColor(.secondary)
            } else {
                ForEach(coworkBrainPresets) { preset in
                    Button {
                        switchCoworkBrain(to: preset)
                    } label: {
                        let isCurrent = (preset.provider == coworkActiveProvider
                                         && preset.model == coworkActiveModel)
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
                Task { await reloadCoworkBrainPresets() }
            }
            Text("Soul stays the same; only brain swaps")
                .foregroundColor(.secondary)
        } label: {
            HStack(spacing: 4) {
                Text("🧠")
                    .font(.system(size: 12))
                Text(coworkBrainLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(coworkActiveModel.isEmpty
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
        .help("Switch brain for Cowork (soul stays the same)")
    }

    private var coworkBrainLabel: String {
        if coworkActiveModel.isEmpty { return "loading…" }
        if let preset = BrainPreset.find(provider: coworkActiveProvider,
                                          model: coworkActiveModel,
                                          in: coworkBrainPresets) {
            return preset.label
        }
        return coworkActiveModel
    }

    /// POST /api/brain to kinclaw (port 5001). Optimistic — the
    /// dropdown stays on the new label; if the server refuses (turn
    /// in flight, missing API key) we surface the error and the
    /// next SSE hello will reset us back to truth.
    private func switchCoworkBrain(to preset: BrainPreset) {
        Task {
            do {
                try await KinClawAPIClient.default.switchBrain(
                    provider: preset.provider,
                    model: preset.model)
                // Optimistic local update — SSE brain_switched will
                // confirm authoritatively in ~10ms.
                await MainActor.run {
                    coworkActiveProvider = preset.provider
                    coworkActiveModel = preset.model
                }
            } catch {
                // Surface to chat as an error bubble — same path
                // sendLocal uses for kinclaw connectivity errors.
                await MainActor.run {
                    let err = ChatMessage.assistant("brain switch failed — \(error.localizedDescription)")
                    messages.append(err)
                }
            }
        }
    }

    private func reloadCoworkBrainPresets() async {
        let fresh = await OllamaCatalog.loadPresets()
        if !fresh.isEmpty {
            await MainActor.run { coworkBrainPresets = fresh }
        }
    }

    /// Probe kinclaw's :5001 server. Two outputs:
    ///
    ///   1. coworkConnectError → nil/string drives the green/orange
    ///      dot in agentBar.
    ///   2. coworkActiveProvider/coworkActiveModel → populated from
    ///      the souls list's `active` row. SSE hello/brain_switched
    ///      events ALSO populate these, but those only fire mid-
    ///      turn; on a fresh app open we need this poll to seed
    ///      the brain dropdown's "current" mark before the user
    ///      sends anything.
    fileprivate func refreshCoworkConnection() async {
        do {
            let souls = try await KinClawAPIClient.default.fetchSouls()
            await MainActor.run {
                coworkConnectError = nil
                if let active = souls.first(where: { $0.active == true }) {
                    let parts = active.brain
                        .split(separator: "/", maxSplits: 1)
                        .map(String.init)
                    if parts.count == 2 {
                        coworkActiveProvider = parts[0]
                        coworkActiveModel = parts[1]
                    }
                }
            }
        } catch {
            await MainActor.run {
                coworkConnectError = "kinclaw :5001 unreachable — is the helper running?"
            }
        }
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
                // LazyVStack — cells render only when scrolled into
                // view. Critical for input-field responsiveness:
                // every keystroke re-evaluates the parent struct,
                // and a non-lazy VStack would force MarkdownParser
                // to re-parse every visible+invisible message every
                // tick. LazyVStack scopes that work to visible cells
                // only, restoring instant typing feel.
                //
                // (The earlier "几秒钟空白" bug attributed to LazyVStack
                // turned out to be a scroll-anchor issue, not lazy
                // materialization — fix is below in the .onChange
                // scroll handler, which now anchors the last-message
                // at .bottom rather than a 1pt invisible spacer at
                // .bottom.)
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && loadError != nil {
                        errorState
                    } else if messages.isEmpty && mode == .chat && chatBrowsing {
                        // Empty Chat tab + browse mode = gallery.
                        // chatBrowsing starts true on every cold
                        // app open AND on ⌘B / "← agents", so the
                        // discovery surface is the entry point even
                        // when chatLastAgentSlug auto-restored a
                        // selectedAgent. Tapping a card flips
                        // chatBrowsing to false → welcomeCard fires
                        // for that agent.
                        chatGallery
                    } else if messages.isEmpty && selectedAgent != nil {
                        // Cowork (and future modes that aren't
                        // gallery-driven) keep the per-agent
                        // welcomeCard.
                        welcomeCard
                            .padding(.top, 40)
                    } else {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    // The 1pt invisible streaming-indicator spacer
                    // was here before — turned out auto-scrolling
                    // to it with anchor: .bottom would push the
                    // small empty assistant bubble flush against
                    // the bottom edge with EVERYTHING ELSE pushed
                    // OFF the top of the viewport on short content,
                    // producing the "几秒钟空白" effect. Removed —
                    // the .onChange handler below now scrolls to
                    // messages.last?.id with anchor: .bottom which
                    // does the right thing without the spacer.
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // Soft fade for the welcome → messages transition.
                // Ties together the welcome-card removal + first
                // bubble append so they animate as one event.
                .animation(.easeInOut(duration: 0.18), value: messages.count)
            }
            // Two scroll triggers, two distinct strategies:
            //
            // 1. messages.count changes (user sent + assistant stub
            //    appended). Scroll target = the just-sent USER
            //    message, anchored bottom. The empty assistant bubble
            //    above it is too small + still being laid out for
            //    scrollTo to land correctly — using messages.last?.id
            //    here was producing a "blank screen, scroll up to find
            //    your message" bug because ScrollView resolved the
            //    target to a not-yet-rendered cell.
            //
            //    DispatchQueue.main.async defers the scroll to the
            //    next runloop tick, after LazyVStack has materialized
            //    the new cells.
            //
            // 2. scrollTrigger bumps (text deltas / tool calls land in
            //    the streaming bubble). Scroll target = LAST message
            //    (the assistant being filled in), anchored bottom.
            //    The bubble is now real with measurable height; this
            //    follows the streaming tail correctly.
            .onChange(of: messages.count) { _, _ in
                let target = messages.last(where: { $0.isUser })?.id
                    ?? messages.last?.id
                DispatchQueue.main.async {
                    if isStreaming {
                        proxy.scrollTo(target, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(target, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: scrollTrigger) { _, _ in
                if isStreaming {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Gallery / "agent shop" — Chat tab's discovery surface. When
    /// no agent is selected and the panel is empty, show the user
    /// what they can talk with instead of leaving them staring at
    /// blank space + dropdown they may not notice.
    ///
    /// Order matches user request: Core first (the LocalKin family
    /// flagship), then spiritual (44 Selah masters), then TCM
    /// (岐黄), then any other cloud agents. Local KinClaw souls are
    /// Cowork's territory and don't appear here.
    ///
    /// Tapping an agent card sets selectedAgent → triggers the
    /// existing welcomeCard for that agent (suggestion chips +
    /// quick-start) → user can dive into chat.
    private var chatGallery: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hero — keep tight; the panel is 380pt wide and we
            // need most of the vertical for the actual grid.
            VStack(alignment: .leading, spacing: 4) {
                Text("👋 选个对象聊")
                    .font(.system(size: 20, weight: .semibold))
                Text("Pick someone to talk with")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if isLoadingAgents {
                    Text("loading agents…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 2)
                } else if let reason = cloudErrorReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)

            // Sections — Core first per user request, then Faith
            // (most agents in this group, 44+), then TCM, then
            // anything else cloud-side that doesn't fit a known
            // category. Empty groups don't render.
            if !coreAgents.isEmpty {
                gallerySection(
                    title: "⭐  Core",
                    subtitle: "LocalKin flagship agents",
                    agents: coreAgents)
            }
            if !spiritualAgents.isEmpty {
                gallerySection(
                    title: "📜  Faith / Selah",
                    subtitle: "44 spiritual masters · 1900 years",
                    agents: spiritualAgents)
            }
            if !tcmAgents.isEmpty {
                gallerySection(
                    title: "🌿  Heal / 岐黄",
                    subtitle: "Traditional Chinese medicine masters",
                    agents: tcmAgents)
            }
            if !otherCloudAgents.isEmpty {
                gallerySection(
                    title: "🌐  Other",
                    subtitle: "Cloud agents",
                    agents: otherCloudAgents)
            }

            Spacer(minLength: 12)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One category band: title row + scrollable horizontal list of
    /// agent cards. Horizontal scroll keeps the section vertically
    /// short so all 4 categories fit on one screen — vertical lists
    /// of 44 items would push later sections off the bottom.
    @ViewBuilder
    private func gallerySection(title: String, subtitle: String,
                                 agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("(\(agents.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(agents) { agent in
                        galleryCard(agent)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// One agent card. Tap → set selectedAgent + flip chatBrowsing
    /// false → empty-state transitions from gallery to welcomeCard
    /// (single-agent quick-start chips). Auto-restored "your usual"
    /// agent gets a green ring so the user can see at a glance which
    /// one would have been picked by default.
    @ViewBuilder
    private func galleryCard(_ agent: Agent) -> some View {
        let isCurrent = (agent.slug == selectedAgent?.slug)
        Button {
            selectedAgent = agent
            chatBrowsing = false
            inputFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(AgentDecor.emoji(for: agent))
                        .font(.system(size: 22))
                    if let master = CloudAgentCatalog.master(for: agent.slug) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(master.nameZh)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(master.nameEn)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text(agent.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                if let caption = AgentDecor.caption(for: agent) {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 160, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCurrent
                          ? Color.green.opacity(0.10)
                          : Color.platformSecondaryBackground.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent
                            ? Color.green.opacity(0.55)
                            : Color.secondary.opacity(0.15),
                            lineWidth: isCurrent ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var welcomeCard: some View {
        VStack(spacing: 8) {
            // ← Back to gallery — only shown in Chat mode (Cowork
            // doesn't have a gallery yet so the button would dead-
            // end there). Sets chatBrowsing = true → empty-state
            // flips back to chatGallery on next render. Keeps
            // selectedAgent intact so the previously-tapped card
            // still gets the green "your usual" ring.
            if mode == .chat {
                HStack {
                    Button {
                        chatBrowsing = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .semibold))
                            Text("agents")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("b", modifiers: .command)
                    .help("Back to agent gallery (\u{2318}B)")
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }

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

                // ── Suggestion chips ──
                // Click to fill the input. Same affordance ChatGPT /
                // Claude / Perplexity use to onboard users into a
                // blank text field. Per-agent / per-domain prompts
                // live in AgentSuggestions.
                let suggestions = AgentSuggestions.suggestions(for: agent)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(suggestions.enumerated()),
                            id: \.offset) { _, prompt in
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

                Text(agent.isLocal
                     ? "or type below — ⌘⏎ to send."
                     : "or type below — ⌘⏎ to send. Bilingual; mix freely.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.55))
                    .padding(.top, 12)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
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
        return HStack(alignment: .top, spacing: 6) {
            if msg.isUser {
                Spacer(minLength: 24)
                BubbleWithCopy(content: msg.content, timestamp: msg.timestamp) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if !msg.content.isEmpty {
                            Text(msg.content)
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity,
                                       alignment: .trailing)
                        }
                        ForEach(msg.attachments) { attachment in
                            AttachmentView(attachment: attachment)
                        }
                    }
                }
            } else {
                // Agent emoji avatar in front of assistant bubbles —
                // visual continuity through a long conversation,
                // especially when the user has switched agents and
                // both agents' replies sit in the scrollback.
                if let agent = selectedAgent {
                    Text(AgentDecor.emoji(for: agent))
                        .font(.system(size: 16))
                        .frame(width: 22, height: 22, alignment: .top)
                        .padding(.top, 4)
                }
                BubbleWithCopy(content: msg.content, timestamp: msg.timestamp) {
                    assistantBubble(msg, showCursor: isLastAssistantWhileStreaming)
                }
                Spacer(minLength: 24)
            }
        }
    }

    private func assistantBubble(_ msg: ChatMessage,
                                 showCursor: Bool) -> some View {
        // Renders Markdown body + tool-call widgets + attachments.
        // While streaming with NO content yet, dots inside bubble
        // (ChatGPT-style); once first delta lands, dots vanish.
        VStack(alignment: .leading, spacing: 6) {
            if msg.content.isEmpty && showCursor && msg.toolCalls.isEmpty {
                StreamingDots(color: .secondary, size: 5, spacing: 5)
                    .padding(.vertical, 2)
            } else if !msg.content.isEmpty || showCursor {
                streamingMarkdownText(msg, showCursor: showCursor)
            }
            ForEach(msg.toolCalls) { call in
                ToolCallView(call: call)
            }
            ForEach(msg.attachments) { attachment in
                AttachmentView(attachment: attachment)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // maxWidth .infinity (was 320 fixed!) so the bubble grows
        // with the panel width; Spacer(minLength: 24) on the right
        // in the parent HStack keeps it from running edge-to-edge.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.platformSecondaryBackground.opacity(0.6))
        .foregroundColor(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // textSelection on the bubble propagates down to every Text
        // view inside MarkdownView (paragraphs, headings, list items,
        // code blocks). Was lost when r5 introduced MarkdownView —
        // each block-level Text view doesn't carry it itself, but
        // SwiftUI inherits this modifier from the enclosing scope.
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func streamingMarkdownText(_ msg: ChatMessage,
                                        showCursor: Bool) -> some View {
        // The MarkdownView stays OUTSIDE any TimelineView so the
        // markdown parse runs only when content actually changes —
        // not every 0.5s on the cursor blink. Earlier version put
        // both inside the timeline; the resulting re-parse + re-
        // layout on every tick (combined with auto-scroll trying
        // to chase the changing height) showed up as page-shake
        // during tool calls.
        VStack(alignment: .leading, spacing: 4) {
            MarkdownView(text: msg.content)
            if showCursor {
                BlinkingCursor()
            }
        }
    }

    // MARK: - Input bar

    /// Pending attachment chips above the input bar (only when
    /// the user has dragged something in but not yet sent).
    @ViewBuilder
    private var pendingAttachmentsBar: some View {
        if !pendingAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(pendingAttachments) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: chipIcon(attachment))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(attachment.displayName)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                pendingAttachments.removeAll {
                                    $0.id == attachment.id
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.platformSecondaryBackground.opacity(0.65))
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 32)
        }
    }

    private func chipIcon(_ a: Attachment) -> String {
        switch a.kind {
        case .image: return "photo"
        case .video: return "video"
        case .file:  return "doc"
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Paperclip — opens file picker. Same destination as
            // drag-drop (pendingAttachments). Visible affordance so
            // users know "you can attach files here" without first
            // discovering drag-drop.
            Button {
                openFilePicker()
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Attach files (or drag & drop anywhere on this panel)")

            // Mic + (when recording) live audio level meter. Click
            // toggles record/cancel.
            Button {
                if recorder.isRecording {
                    recorder.cancelRecording()
                } else {
                    recorder.startRecording(hostname: hostname)
                }
            } label: {
                if recorder.isRecording {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                        AudioLevelMeter(level: recorder.audioLevel)
                    }
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(recorder.isRecording ? "Stop recording" : "Voice input")

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

    private func scheduleRecentRowHide(after seconds: TimeInterval) {
        recentRowHideTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) {
                showingRecentRow = false
            }
        }
        recentRowHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    private func cancelRecentRowHide() {
        recentRowHideTask?.cancel()
        recentRowHideTask = nil
    }

    /// NSOpenPanel-based file picker for the paperclip button. Same
    /// landing as drag-drop — selected URLs append to
    /// pendingAttachments. Multiple selection allowed.
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose files to attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                pendingAttachments.append(Attachment(localURL: url))
            }
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Cancel the in-flight turn. Both transports get the kill
    /// signal — sseClient for cloud chat, localStreamTask + DELETE
    /// /api/chat for kinclaw. Optimistic: we flip isStreaming
    /// false locally before the server confirms (cancellation can
    /// take a beat to propagate through the brain HTTP timeout)
    /// so the input bar unlocks immediately.
    private func interruptTurn() {
        // Cloud: SSEClient cancels the URLSession data task.
        sseClient?.cancel()
        sseClient = nil
        // Local kinclaw: cancel the Swift Task driving the SSE
        // stream + DELETE the server's in-flight turn so kinclaw
        // stops feeding tokens.
        localStreamTask?.cancel()
        localStreamTask = nil
        Task {
            try? await KinClawAPIClient.default.cancelTurn()
        }
        isStreaming = false
    }

    private func clearChat() {
        guard let agent = selectedAgent else { return }
        // Drop the in-flight session entirely — delete it from
        // disk if it was saved + reset to a fresh empty session.
        ChatSessionStore.delete(id: currentSessionID, agentSlug: agent.slug)
        startNewSession()

        // Local kinclaw: also reset server-side conversation memory
        // by re-loading the soul (server reads from disk on switch).
        // Cloud agents are stateless per-message so no reset needed.
        if let soulPath = agent.localSoulPath {
            Task {
                try? await KinClawAPIClient.default.switchSoul(path: soulPath)
            }
        }
    }

    /// Start a new chat session. Saves the current one if it has
    /// content, then resets messages + currentSessionID.
    private func startNewSession() {
        guard let agent = selectedAgent else { return }
        saveCurrentSession()
        messages = []
        currentSessionID = UUID()
        sessionTitle = "New chat"
    }

    /// Load a saved session into the active chat surface.
    private func loadSession(_ session: ChatSession) {
        saveCurrentSession()
        currentSessionID = session.id
        sessionTitle = session.title
        messages = session.messages.map { $0.toMessage() }
    }

    /// Persist whatever's currently on screen as a session JSON.
    /// Idempotent — safe to call on every meaningful state change
    /// (after each turn, before switching, on disappear).
    private func saveCurrentSession() {
        guard let agent = selectedAgent else { return }
        guard !messages.isEmpty else {
            // Empty session — nothing to save. (We DON'T persist
            // empty placeholder sessions; new-chat is implicit.)
            return
        }

        // Title = first user message, capped to 60 chars. Falls
        // back to existing title (set when loading a saved session)
        // if no user message yet.
        let derived = messages.first(where: { $0.isUser })?.content
            ?? sessionTitle
        let title = String(derived.prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let now = Date()
        let session = ChatSession(
            id: currentSessionID,
            agentSlug: agent.slug,
            title: title,
            createdAt: messages.first?.timestamp ?? now,
            updatedAt: now,
            messages: messages.map(PersistedMessage.init(from:))
        )
        ChatSessionStore.save(session)
        sessionTitle = title
    }

    private func handleAgentChange() {
        // Always save the outgoing session first — otherwise the
        // messages we just had get dropped on the floor when the
        // user swaps agents (or modes, since mode-swap auto-swaps
        // selectedAgent under the hood).
        saveCurrentSession()

        guard let agent = selectedAgent else {
            // No agent — typical when switching to Cowork before the
            // kinclaw souls have loaded, or to Code mode (which has
            // no agent selection). Clear the surface to a fresh
            // state so we don't show stale Chat content under a
            // Cowork tab while the catalog catches up.
            currentSessionID = UUID()
            sessionTitle = "New chat"
            messages = []
            return
        }

        // Load the most-recent session for the new agent (or empty
        // if they've never chatted with this one).
        let recent = ChatSessionStore.list(for: agent.slug).first
        if let last = recent {
            currentSessionID = last.id
            sessionTitle = last.title
            messages = last.messages.map { $0.toMessage() }
        } else {
            currentSessionID = UUID()
            sessionTitle = "New chat"
            messages = []
        }

        // Persist last-used selection so the next launch lands on
        // the same agent.
        UserDefaults.standard.set(agent.slug, forKey: "kinclaw.lastAgent")

        // Push to recent-agents stack (UserDefaults-backed; the
        // RecentAgentsRow watches this via @AppStorage and re-renders
        // automatically).
        RecentAgentsRow.touch(slug: agent.slug)

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
                // Drop the generic "LocalKin Claude / Cloud / default"
                // souls under ~/.localkin/souls/ — they're not the
                // dock's audience. Only show KinClaw branded souls
                // here. Per Jacky 2026-05-03.
                return souls
                    .filter { $0.name.hasPrefix("KinClaw") }
                    .map(\.asAgent)
            } catch { return [] }
        }()

        let (cloud, cloudReason) = await cloudTask
        let local = await localTask
        let merged = local + cloud
        allAgents = merged
        cloudErrorReason = cloud.isEmpty ? cloudReason : nil

        if merged.isEmpty {
            loadError = "No agents available — start kinclaw locally or check your internet."
        } else if selectedAgent == nil
                  || (selectedAgent.map { !agentBelongsToMode($0, mode: mode) } ?? false) {
            // Re-validate after every catalog refresh — handles the
            // race where the user switched to Cowork before kinclaw
            // souls were loaded (selectedAgent stayed in cloud-land
            // from Chat). Once souls land, swap to the right default.
            selectedAgent = pickDefaultAgent(for: mode)
        }
        isLoadingAgents = false
    }

    /// Pick the default agent surfaced when KinClaw Mac launches OR
    /// when the user switches modes.
    ///
    /// Per-mode logic:
    ///   .chat   → last-used cloud agent (kinclaw.chat.lastAgent),
    ///             else first Core, else first Faith, else first cloud
    ///   .cowork → last-used KinClaw soul (kinclaw.cowork.lastSoul),
    ///             else KinClaw Pilot, else first KinClaw soul
    ///   .code   → no agent (kincode is fixed)
    private func pickDefaultAgent(for mode: ChatMode) -> Agent? {
        switch mode {
        case .code:
            return nil
        case .chat:
            if !chatLastAgentSlug.isEmpty,
               let agent = cloudAgents.first(where: { $0.slug == chatLastAgentSlug }) {
                return agent
            }
            return coreAgents.first
                ?? spiritualAgents.first
                ?? tcmAgents.first
                ?? otherCloudAgents.first
        case .cowork:
            if !coworkLastSoulSlug.isEmpty,
               let soul = kinClawSouls.first(where: { $0.slug == coworkLastSoulSlug }) {
                return soul
            }
            return kinClawSouls.first(where: { $0.name == "KinClaw Pilot" })
                ?? kinClawSouls.first
        }
    }

    /// Switch the active agent to whatever's appropriate for the
    /// given mode. Called from onChange(mode). Code mode is a no-op
    /// — its UI doesn't consume selectedAgent.
    private func applyAgentForMode(_ newMode: ChatMode) {
        if newMode == .code {
            return
        }
        // If the currently-selected agent is already valid for the
        // new mode (defensive — pools are mutually exclusive today,
        // so this branch rarely fires, but it's correct).
        if let cur = selectedAgent, agentBelongsToMode(cur, mode: newMode) {
            return
        }
        // Always assign — even nil. Leaving a stale cross-mode agent
        // (e.g. Selah from Chat) selected while showing Cowork's
        // KinClaw-only menu is the bug we're fixing here. nil shows
        // "Choose an agent" / loading state until catalog refreshes.
        selectedAgent = pickDefaultAgent(for: newMode)
    }

    /// True if `agent` belongs to the agent pool of `mode`.
    private func agentBelongsToMode(_ agent: Agent, mode: ChatMode) -> Bool {
        switch mode {
        case .chat:   return !agent.isLocal     // cloud only
        case .cowork: return agent.name.hasPrefix("KinClaw")
        case .code:   return false              // never matches
        }
    }

    /// Write the current agent slug under the per-mode key so it
    /// survives a relaunch + restoration on next mode switch.
    private func persistAgentForCurrentMode(slug: String?) {
        guard let s = slug else { return }
        switch mode {
        case .chat:   chatLastAgentSlug = s
        case .cowork: coworkLastSoulSlug = s
        case .code:   break
        }
    }

    // MARK: - Send (router → cloud / local)

    private func send() {
        guard let agent = selectedAgent else { return }
        let typed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow sending with attachments only — typed text optional
        // when there's at least one file attached (e.g. "drag image
        // → click send" without typing anything implies "look at
        // this").
        guard !typed.isEmpty || !pendingAttachments.isEmpty else { return }

        // Wrap message-list mutations in a SwiftUI animation block
        // so the welcome-card → bubbles transition + bubble append
        // animates as one continuous fade rather than instant pop
        // (which on macOS visibly snapped the layout and contributed
        // to the brief blank flash).
        // We can't put `withAnimation` around the actual mutation
        // because it spans multiple async branches — instead we set
        // a top-level animation modifier on the messagesView VStack.

        // Compose final user message: typed text + path mentions
        // for each attachment. Local kinclaw souls can read paths
        // directly; cloud agents see the path as a string mention
        // (won't actually open the file but knows you're referring
        // to one).
        var composed = typed
        if !pendingAttachments.isEmpty {
            let pathLines = pendingAttachments.compactMap { att -> String? in
                guard let p = att.localURL?.path else { return nil }
                return "[file: \(p)]"
            }
            if !pathLines.isEmpty {
                if !composed.isEmpty { composed += "\n\n" }
                composed += pathLines.joined(separator: "\n")
            }
        }

        var userMsg = ChatMessage.user(composed)
        userMsg.attachments = pendingAttachments
        let attachmentsToCarry = pendingAttachments

        inputText = ""
        pendingAttachments = []
        messages.append(userMsg)
        messages.append(.assistant())
        let assistantIndex = messages.count - 1
        isStreaming = true
        inputFocused = true
        // Keep `text` in scope for the legacy send paths below.
        let text = composed
        _ = attachmentsToCarry  // explicitly reserved for future use

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

        // SSE callbacks fire async on the main queue. Between send
        // and delivery, the user can clear the chat, switch agents,
        // or trigger any other path that mutates `messages`. When
        // that happens, `assistantIndex` is stale and a raw access
        // would crash with "Index out of range" (we hit this in
        // production — see KinClawMac-2026-05-05-003035.ips). Every
        // SSE callback that touches messages[] guards bounds first.
        client.onToken = { token in
            guard messages.indices.contains(assistantIndex) else { return }
            messages[assistantIndex].content += token
            scrollTrigger += 1
        }
        client.onComplete = {
            isStreaming = false
            sseClient = nil
            guard messages.indices.contains(assistantIndex) else { return }
            if !messages[assistantIndex].content.isEmpty {
                appState.recordMessage()
                if ttsEnabled {
                    speaker.speak(messages[assistantIndex].content,
                                  hostname: hostname) {}
                }
                saveCurrentSession()
            }
        }
        client.onError = { _ in
            isStreaming = false
            sseClient = nil
            guard messages.indices.contains(assistantIndex) else { return }
            if messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content = "Connection error."
            }
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
                // Successful POST = supervisor + kinclaw both alive.
                // Clear any stale connection-error so the green dot
                // updates without waiting for the next probe.
                coworkConnectError = nil
            } catch {
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].content =
                        "kinclaw error: \(error.localizedDescription)"
                }
                // Surface to the dot too — orange + descriptive
                // tooltip beats the user re-reading the bubble.
                coworkConnectError = error.localizedDescription
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
                if messages.indices.contains(assistantIndex),
                   messages[assistantIndex].content.isEmpty
                {
                    messages[assistantIndex].content =
                        "stream error: \(error.localizedDescription)"
                }
            }
            isStreaming = false
            ChatHistory.save(messages: messages, for: agent.slug)
            if ttsEnabled,
               messages.indices.contains(assistantIndex),
               !messages[assistantIndex].content.isEmpty
            {
                speaker.speak(messages[assistantIndex].content,
                              hostname: hostname) {}
            }
        }
        localStreamTask = task
    }

    /// NSItemProvider drop handler — accepts file URLs from Finder,
    /// desktop, mail attachments, anywhere. Async because each
    /// provider unwraps via `loadObject(ofClass:)`.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error = error {
                    print("[Drop] loadObject error: \(error)")
                }
                guard let url = url else {
                    print("[Drop] no URL")
                    return
                }
                let resolved = url.standardizedFileURL
                let exists = FileManager.default.fileExists(atPath: resolved.path)
                print("[Drop] got URL: \(resolved.path) (exists=\(exists))")
                DispatchQueue.main.async {
                    pendingAttachments.append(Attachment(localURL: resolved))
                }
            }
        }
        // Don't block; let the async loadObjects fire-and-forget. The
        // .onDrop return value just signals "we accept it" — actual
        // append happens when the provider resolves.
        return true
    }

    private func handleLocalEvent(_ event: KinClawEvent, assistantIndex: Int) {
        // Stale-index guard. SSE events arrive async, so by the time
        // a chunk lands the user might have cleared / switched chats
        // and `assistantIndex` no longer points at a real row. A raw
        // `messages[assistantIndex]` access in that state crashes
        // with "Index out of range" (caught by the bug report at
        // KinClawMac-2026-05-05-003035.ips). Drop the event quietly
        // — there's no bubble to write to anyway.
        guard messages.indices.contains(assistantIndex) else { return }

        switch event.kind {
        case .textDelta:
            if let t = event.text, !t.isEmpty {
                messages[assistantIndex].content += t
                scrollTrigger += 1
            }
        case .toolCall:
            // Append a new ToolCall to the message — output stays
            // nil until the matching tool_result lands. The
            // ToolCallView renders "running…" while output == nil.
            guard let name = event.name else { break }
            let id = event.id ?? UUID().uuidString
            messages[assistantIndex].toolCalls.append(ToolCall(
                id: id,
                name: name,
                params: event.params ?? [:],
                output: nil
            ))
            scrollTrigger += 1
        case .toolResult:
            // Match by id (when the server provides one) or by the
            // most-recent uncompleted call. handles the common case
            // where IDs round-trip cleanly + falls back gracefully
            // when the server omits the id field on results.
            guard let output = event.output else { break }
            if let evID = event.id,
               let idx = messages[assistantIndex].toolCalls
                   .firstIndex(where: { $0.id == evID }) {
                messages[assistantIndex].toolCalls[idx].output = output
            } else if let idx = messages[assistantIndex].toolCalls
                   .lastIndex(where: { $0.output == nil }) {
                messages[assistantIndex].toolCalls[idx].output = output
            } else {
                // Tool result with no matching call — render it as a
                // synthetic one so the user still sees the output
                // rather than us silently swallowing it.
                messages[assistantIndex].toolCalls.append(ToolCall(
                    id: UUID().uuidString,
                    name: event.name ?? "result",
                    params: [:],
                    output: output
                ))
            }
            scrollTrigger += 1
        case .error:
            let m = event.message ?? "kinclaw reported an error"
            if !messages[assistantIndex].content.isEmpty {
                messages[assistantIndex].content += "\n\n"
            }
            messages[assistantIndex].content += "**Error:** \(m)"
            scrollTrigger += 1
        case .screenFrame, .recordDone:
            // Agent emitted a screenshot or video recording —
            // attach to the assistant bubble so the user sees it
            // inline. event.images carries absolute paths;
            // event.urls carries kinclaw `/file/...` URLs.
            for path in event.images ?? [] {
                let url = URL(fileURLWithPath: path)
                messages[assistantIndex].attachments.append(
                    Attachment(localURL: url))
                scrollTrigger += 1
            }
            for s in event.urls ?? [] {
                if let url = URL(string: s) {
                    messages[assistantIndex].attachments.append(
                        Attachment(remoteURL: url))
                    scrollTrigger += 1
                }
            }
            // Single `path` field — record_done usually emits this.
            if let path = event.path, !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                messages[assistantIndex].attachments.append(
                    Attachment(localURL: url))
                scrollTrigger += 1
            }
            if let url = event.url, let parsed = URL(string: url) {
                messages[assistantIndex].attachments.append(
                    Attachment(remoteURL: parsed))
                scrollTrigger += 1
            }
        case .hello, .brainSwitched, .soulSwitched:
            // kinclaw publishes the active brain in params.brain as
            // "<provider>/<model>" on every hello (sent on connect)
            // and on brain_switched / soul_switched events. Pull
            // it into local state so the Cowork brain dropdown
            // shows the truth without needing to poll.
            if let brain = event.params?["brain"] {
                let parts = brain.split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    coworkActiveProvider = parts[0]
                    coworkActiveModel = parts[1]
                }
            }
        case .userMessage, .turnDone, .planMode, .none:
            // plan_mode is Code-mode-only; Spotlight ignores it.
            break
        }
    }
}

// MARK: - Blinking cursor
//
// Only this view re-renders on the timeline tick. Surrounding
// markdown / bubble layout is unaffected.

private struct BlinkingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text("█")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.green.opacity(0.7))
                .opacity(on ? 1 : 0)
                .frame(height: 14, alignment: .leading)
        }
    }
}

// File-private singleton — Swift forbids `static let` on generic
// types (BubbleWithCopy is generic), so the formatter lives here
// at file scope. Reused across every bubble; cheap.
private let relativeTimestampFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

// MARK: - Hover-to-copy bubble wrapper

/// Wraps any chat bubble view in an overlay that surfaces a copy
/// button + relative timestamp on hover. Click → content goes to
/// NSPasteboard.general; the icon flashes to a checkmark for 1.2s
/// as confirmation. The timestamp ("3 min ago") sits below the
/// bubble at low opacity so it doesn't compete with the message.
private struct BubbleWithCopy<Content: View>: View {
    let content: String
    let timestamp: Date?
    /// Renamed from `body` to avoid colliding with View.body.
    @ViewBuilder let bubbleContent: () -> Content

    init(content: String,
         timestamp: Date? = nil,
         @ViewBuilder bubbleContent: @escaping () -> Content) {
        self.content = content
        self.timestamp = timestamp
        self.bubbleContent = bubbleContent
    }

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack(alignment: .topTrailing) {
                bubbleContent()
                if hovering {
                    Button {
                        copy()
                    } label: {
                        Image(systemName: copied
                              ? "checkmark.circle.fill"
                              : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(copied ? .green : .secondary)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                            )
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .transition(.opacity)
                }
            }
            // Relative timestamp on hover. Lives outside the bubble
            // so a long markdown body doesn't push it around when
            // re-flowing during streaming.
            if hovering, let ts = timestamp {
                Text(relativeTimestampFormatter.localizedString(
                    for: ts, relativeTo: Date()))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.55))
                    .padding(.leading, 4)
                    .transition(.opacity)
            }
        }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hovering = isHovering
            }
        }
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}

import SwiftUI
import UserNotifications

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

    // Cowork kernel state mirrored from kinclaw (≥ 1.18): the pending
    // approval card, the plan-mode gate, and prompt size vs context
    // window for the meter. Fed by SSE mid-turn and by GET /api/state
    // between turns.
    @State private var pendingPermission: PermissionRequest?
    @State private var pendingQuestion: PendingQuestion?
    @State private var coworkPlanMode = false
    @State private var contextUsed: Int = 0
    @State private var contextLength: Int = 0
    @State private var coworkWorkspace: String = ""
    @StateObject private var searchStatus = SearchStatusStore()
    /// Companion mode: the panel becomes a picture and a voice.
    @State private var companionMode = false
    @State private var showingArtPicker = false
    @StateObject private var companionArt = CompanionArt()
    /// Left folder pane in Cowork (⌘⇧L). Persisted; on by default.
    @AppStorage("kinclaw.cowork.sidebar") private var showWorkspaceSidebar = true
    /// Bumped after each turn / workspace change so the pane reloads.
    @State private var sidebarRefresh = 0

    /// Chat-tab "browse vs chat" state. True = show the agent
    /// gallery (discovery surface). False = show welcomeCard /
    /// messages for the selected agent. Default true so first-time
    /// users land on discovery; flips false when they tap a card,
    /// flips back true on "← agents" / ⌘B / explicit nil out.
    /// Independent of selectedAgent so a returning user with
    /// chatLastAgentSlug auto-restored STILL sees the gallery as
    /// the empty-state entry.
    @State private var chatBrowsing: Bool = true

    /// Which gallery sections are expanded. Core is open by default
    /// (the LocalKin flagship — most users start here); Faith / Heal
    /// / Other start collapsed so an 80+ master gallery doesn't
    /// dump everything at once. Tap a section header to toggle.
    /// Persisted in-session only — defaults reset every cold open
    /// to keep the gallery scannable.
    ///
    /// Side benefit: collapsing trims the LazyVGrid cell count from
    /// ~80 cards to ~10 (Core only), which cuts mode-switch flicker
    /// — Chat ↔ Cowork transition was reflowing all sections every
    /// re-render.
    @State private var expandedGallerySections: Set<String> = ["core"]

    /// Live search filter for the gallery. Matches against zh name,
    /// en name, slug, era, and notable tagline so the user can find
    /// Augustine by typing "augustine" / "奥古斯丁" / "354" /
    /// "patristic" — every visible signal is a query target.
    /// Case-insensitive substring match. Empty = show everything.
    /// Auto-expands all sections when search is active so matching
    /// cards in collapsed groups become visible without manual
    /// expansion.
    @State private var gallerySearch: String = ""

    // Transports.
    @State private var sseClient: SSEClient?
    @State private var localStreamTask: Task<Void, Never>?

    // Voice.
    @StateObject private var speaker = SpeechSynthesizer()
    @StateObject private var recorder = VoiceRecorder()
    // AppStorage, not State: a spoken-reply preference that forgets itself
    // every time the panel reopens is indistinguishable from a broken toggle.
    @AppStorage("kinclaw.voice.ttsEnabled") private var ttsEnabled = false
    /// Empty = off, and that stays the default: a wake word the user hasn't
    /// been told about looks identical to voice mode being broken.
    @AppStorage("kinclaw.voice.wakeWord") private var wakeWord = ""
    /// How long a conversation stays open after the last exchange. The wake
    /// word gets you in; it should not be required for every following
    /// sentence, or a five-turn conversation means saying the name five times.
    @AppStorage("kinclaw.voice.wakeSessionSeconds") private var wakeSessionSeconds: Double = 45
    /// When the current conversation lapses back to needing the wake word.
    /// nil = not in a conversation, so the next utterance must start with it.
    @State private var wakeSessionExpiry: Date?
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

    /// Souls that exist in the kinclaw repo but have no business being offered
    /// in a macOS picker.
    ///
    /// The prefix test alone is too loose: kinclaw ships every soul it owns,
    /// including a benchmark harness and the pilots for other operating
    /// systems. Picking `KinClaw Linux Pilot` on a Mac produces an agent that
    /// reaches for tools this machine does not have, and `KinClaw macbench` is
    /// a 369-slot test rig — neither is something a person means to summon with
    /// ⌘⌥K.
    ///
    /// Matched on the soul slug rather than the display name, because display
    /// names get reworded and slugs do not.
    private static let hiddenSoulSlugs: Set<String> = [
        "macbench",        // benchmark harness (`make bench`), not an assistant
        "pilot_linux",     // wrong OS — its tools do not exist here
        "pilot_windows",   // wrong OS
    ]

    private var kinClawSouls: [Agent] {
        // Names emitted by kinclaw's soul list start with "KinClaw ".
        localAgents.filter {
            $0.name.hasPrefix("KinClaw")
                && !Self.hiddenSoulSlugs.contains($0.slug)
        }
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

    /// Private souls scanned from a sibling localkin checkout at
    /// `souls/private/`. Surfaced as a second group in the Cowork
    /// agent menu (🛡️ Private). Empty unless the user has the
    /// sibling repo on disk — public clones see only the 🦞 KinClaw
    /// group as before, no hidden behaviour. Each PrivateSoul is
    /// bridged into Agent shape via `PrivateSoul.asAgent` (carries
    /// `domain == "kinclaw-private"` + `localSoulPath = <abs path>`,
    /// which routes through the same chatBody / KinClawSupervisor
    /// spawn flow as public KinClaw souls.
    @StateObject private var privateLoader = PrivateSoulLoader()

    private var kinClawPrivateSouls: [Agent] {
        privateLoader.souls.map { $0.asAgent }
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
            if companionMode {
                CompanionView(art: companionArt,
                              isListening: recorder.isRecording,
                              isThinking: recorder.isTranscribing || isStreaming,
                              isSpeaking: speaker.isSpeaking,
                              audioLevel: recorder.audioLevel,
                              caption: companionCaption,
                              problem: companionProblem,
                              onExit: { exitCompanionMode() },
                              onFetchArt: { showingArtPicker = true })
                    .transition(.opacity)
                    .popover(isPresented: $showingArtPicker, arrowEdge: .top) {
                        CompanionArtPicker(art: companionArt) { showingArtPicker = false }
                    }
            }
        }
        .frame(minWidth: 320, minHeight: 380)
        .onReceive(NotificationCenter.default.publisher(for: .kinclawEnterCompanion)) { _ in
            if !companionMode { enterCompanionMode() }
        }
    }

    /// What is stopping the voice loop, if anything. A silent halo with
    /// no explanation is the worst failure mode for a view with no other
    /// controls, so anything that would keep speech from working gets
    /// said out loud here.
    private var companionProblem: String? {
        if let e = recorder.error, !e.isEmpty { return e }
        if selectedAgent == nil { return "先在面板里选一个 agent" }
        if !voiceMode { return "语音没打开" }
        return nil
    }

    /// The last assistant line, shown under the halo while it is fresh.
    /// Trimmed hard: this is a glance, not a transcript.
    private var companionCaption: String {
        guard let last = messages.last, !last.isUser else { return "" }
        let t = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : String(t.prefix(160))
    }

    /// Enter companion mode: grow the window, start the voice loop.
    /// Voice is the whole point here, so it turns itself on rather than
    /// leaving the user to find the mic button in a view that has none.
    private func enterCompanionMode() {
        companionArt.reload()
        withAnimation(.easeOut(duration: 0.25)) { companionMode = true }
        (NSApp.delegate as? AppDelegate)?.spotlightWindow.enterCompanion()
        extendWakeSession()
        if !voiceMode { voiceMode = true }
        if companionArt.isEmpty { showingArtPicker = true }
    }

    private func exitCompanionMode() {
        withAnimation(.easeOut(duration: 0.2)) { companionMode = false }
        showingArtPicker = false
        (NSApp.delegate as? AppDelegate)?.spotlightWindow.exitCompanion()
        voiceMode = false
        if recorder.isRecording { recorder.cancelRecording() }
        speaker.stop()
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
                    // KinClaw souls + private souls), enforced by
                    // the mode-scoped agentMenu in agentBar above.
                    // The screen / input claws are tools the AGENT
                    // uses when invoked; the user's actual desktop is
                    // right there, no need to embed a preview.
                    // Cowork adds the folder pane on the left: the
                    // workspace, what the agent touched this session,
                    // and the folder's files — Claude Desktop's layout.
                    HStack(spacing: 0) {
                        if mode == .cowork {
                            if showWorkspaceSidebar {
                                CoworkSidebar(activeWorkspace: coworkWorkspace,
                                              activeSessionID: currentSessionID,
                                              activeAgentSlug: selectedAgent?.slug ?? "",
                                              localAgentSlugs: localSoulSlugs,
                                              touched: touchedFiles,
                                              refreshToken: sidebarRefresh,
                                              onOpenSession: openCoworkSession,
                                              onNewSession: newCoworkSession(in:),
                                              onOpenFolder: applyWorkspace,
                                              onPickFolder: pickWorkspace,
                                              onDeleteSession: deleteCoworkSession,
                                              onCollapse: { toggleWorkspaceSidebar() })
                                    .frame(width: 210)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                Divider().opacity(0.15)
                            } else {
                                WorkspaceSidebarHandle { toggleWorkspaceSidebar() }
                                    .transition(.opacity)
                            }
                        }
                        chatBody
                    }
                    .animation(.easeOut(duration: 0.18), value: showWorkspaceSidebar)
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
            // Hands-free is driven by `transcript` changing, so a recording
            // that yields nothing — silence, or a rejected hallucination —
            // leaves the loop with nothing to react to and the mic stays
            // closed. This is the only path that reopens it in that case.
            //
            // Deliberately not extending the wake session: hearing nothing is
            // not an exchange, and letting it count would keep a conversation
            // open indefinitely in an empty room.
            recorder.onSilentRecording = {
                resumeListeningIfConversing(extendSession: false)
            }
            Task { await loadAgents() }
            // Scan the sibling localkin checkout for private souls.
            // Cheap (one .git + one souls/private/ existence check
            // per candidate path), runs main-thread synchronously.
            // Re-scans on every panel appearance so dropping a new
            // *.soul.md into the dir shows up next time the user
            // opens the panel.
            privateLoader.rescan()
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
        // Transcribed speech had nowhere to go: VoiceRecorder published the
        // text and nothing observed it, so recording, VAD and transcription all
        // worked while the words silently evaporated. This is the wire.
        .onChange(of: recorder.transcript) { _, text in
            var spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return }

            // Wake-word gating applies only to hands-free mode. Push-to-talk
            // is already an explicit act — demanding a wake word there would
            // mean saying the name every single time for no benefit.
            //
            // The wake word opens a conversation, it doesn't guard every
            // sentence. Once you're in, speech goes straight through until
            // the room has been quiet long enough for the session to lapse;
            // then the name is required again. Requiring it per-utterance
            // would make a five-turn exchange mean saying "小美" five times.
            // Companion mode is the wake. The word exists so background
            // chatter can't trigger the agent while you are doing
            // something else; when you have deliberately turned the
            // panel into a face and are talking to it, demanding a name
            // first just makes it look broken — which is exactly how it
            // looked.
            if voiceMode, !wakeWord.isEmpty, !companionMode {
                if isWakeSessionOpen {
                    // Already conversing — take it as-is and push the lapse
                    // further out.
                    extendWakeSession()
                } else {
                    switch WakeWord.test(spoken, wake: wakeWord) {
                    case .disabled:
                        break
                    case .woken(let rest):
                        extendWakeSession()
                        // Wake word alone with nothing after it: the user has
                        // the floor but hasn't said the request yet. Keep
                        // listening rather than sending an empty turn — the
                        // session is open now, so what follows needs no name.
                        guard !rest.isEmpty else {
                            resumeListeningIfConversing()
                            return
                        }
                        spoken = rest
                    case .ignored:
                        // Not addressed to us — drop it and keep listening. No
                        // UI change on purpose: showing every discarded
                        // utterance would defeat the point of filtering them.
                        resumeListeningIfConversing(extendSession: false)
                        return
                    }
                }
            }

            // Append rather than replace: the user may have typed something
            // first and then dictated the rest.
            inputText = inputText.isEmpty
                ? spoken
                : inputText.trimmingCharacters(in: .whitespaces) + " " + spoken

            // In a hands-free conversation the whole point is not touching the
            // keyboard, so speaking is the send.
            if voiceMode { send() }
        }
        // Leaving voice mode must stop the loop immediately — otherwise an
        // in-flight recording would fire one more round after the user opted
        // out, which feels like the app ignoring them.
        .onChange(of: voiceMode) { _, on in
            if on {
                // Hearing the reply is half of a conversation.
                ttsEnabled = true
                // Entering voice mode starts *armed*, not conversing: the
                // wake word is what opens the session. Clearing here matters
                // because the expiry survives leaving voice mode otherwise,
                // and re-entering within the window would skip the gate.
                closeWakeSession()
                if !isStreaming && !recorder.isRecording {
                    recorder.startRecording(hostname: hostname)
                }
            } else {
                if recorder.isRecording { recorder.cancelRecording() }
                speaker.stop()
                closeWakeSession()
            }
        }
        // `isWakeSessionOpen` is a time comparison, and SwiftUI has no reason
        // to re-render when a Date silently passes. Without this tick the
        // button would keep claiming the conversation is open until the next
        // unrelated state change happened to redraw it.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard let expiry = wakeSessionExpiry, expiry <= Date() else { return }
            wakeSessionExpiry = nil
        }
        .onChange(of: mode) { _, newMode in
            // Entering Cowork: prime the header (context meter, plan
            // mode) from the kernel so it's right before the first turn.
            if newMode == .cowork { refreshCoworkState() }
            // Save the outgoing session and clear the surface
            // SYNCHRONOUSLY before the agent-swap chain fires.
            // Without this clear-first step there's a 1-frame
            // flash where the new mode's view (chatBody) still
            // shows the previous tab's messages because the
            // selectedAgent change → handleAgentChange path
            // runs on the *next* layout cycle. Tab switching
            // should feel instant.
            //
            // Wrap the cascade in a no-animation transaction so
            // the chained state changes (messages, sessionID,
            // selectedAgent, brain dropdown showing/hiding) all
            // commit in a single frame. Without this, each state
            // change triggers the chatBody's `.animation(value:
            // messages.count)` independently — producing the
            // "不停的跳动" flicker as gallery → empty welcomeCard →
            // agent's saved messages animate in three separate
            // frames.
            withTransaction(Transaction(animation: nil)) {
                saveCurrentSession()
                messages = []
                currentSessionID = UUID()
                sessionTitle = "New chat"
                if newMode == .chat {
                    chatBrowsing = true
                }
                applyAgentForMode(newMode)
            }
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

            // Approval card — the kernel's permission gate parked the
            // turn on a call it wants a human to okay. Sits right above
            // the composer, where the user is already looking.
            // Cards sit bottom-left, capped in width, so they read as
            // a prompt attached to the composer rather than a banner.
            if mode == .cowork, let req = pendingPermission {
                HStack(alignment: .top, spacing: 0) {
                    PermissionCardView(request: req) { decision in
                        respondPermission(req, decision: decision)
                    }
                    .frame(maxWidth: 480)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if mode == .cowork, let q = pendingQuestion {
                HStack(alignment: .top, spacing: 0) {
                    QuestionCardView(question: q) { answer in
                        answerQuestion(q, text: answer)
                    }
                    .frame(maxWidth: 480)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if mode == .cowork && coworkPlanMode {
                PlanModeBannerView { toggleCoworkPlanMode() }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

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
            // (The brain picker moved to the composer's bottom-right
            // corner — the agent bar is about who and where, the
            // composer footer about what brain, as in Claude Desktop.)

            // Companion mode — picture + voice, no text. Outside the
            // Cowork-only block on purpose: a shortcut that exists only
            // on one tab is a shortcut nobody remembers.
            Button {
                enterCompanionMode()
            } label: {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("陪伴模式：只有声音和一张图 (⇧⌘M)")
            .keyboardShortcut("m", modifiers: [.command, .shift])

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

                // Search health — the last web_search's engines, and a
                // probe on demand.
                SearchStatusButton(store: searchStatus)

                // Context meter — how full the model's window is, from
                // the kernel's `usage` events. Same information Claude
                // Code shows as "% of context"; here it also explains
                // the automatic compaction dividers in the transcript.
                if contextLength > 0 {
                    ContextMeterView(used: contextUsed, total: contextLength)
                }

                // Plan mode — read-only gate on the kernel. The agent
                // investigates and proposes; clicks / typing / shell /
                // writes are refused until the user flips it back.
                Button {
                    toggleCoworkPlanMode()
                } label: {
                    Image(systemName: coworkPlanMode
                          ? "list.clipboard.fill" : "list.clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(coworkPlanMode ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(coworkPlanMode
                      ? "Plan mode ON — the agent can look but not act (⇧⌘P to exit)"
                      : "Plan mode — investigate and propose before acting (⇧⌘P)")
                .keyboardShortcut("p", modifiers: [.command, .shift])

                // Folder pane toggle (⌘⇧L).
                Button {
                    toggleWorkspaceSidebar()
                } label: {
                    Image(systemName: showWorkspaceSidebar ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 12))
                        .foregroundColor(showWorkspaceSidebar ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(showWorkspaceSidebar ? "Hide the folder pane (⇧⌘L)" : "Show the folder pane (⇧⌘L)")
                .keyboardShortcut("l", modifiers: [.command, .shift])

                // Workspace — the folder relative paths and shell commands
                // live in; writes outside it ask first. Cowork's version
                // of Claude Desktop's "working folder".
                Button {
                    pickWorkspace()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                        if !coworkWorkspace.isEmpty {
                            Text(URL(fileURLWithPath: coworkWorkspace).lastPathComponent)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Workspace: \(coworkWorkspace.isEmpty ? "(not set)" : coworkWorkspace)\nRelative paths and shell commands live here; writing elsewhere asks first. Click to change.")
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
        // Disable implicit animation on mode change. Without this,
        // the conditional items (coworkBrainMenu / coworkConnectError
        // dot — Cowork-only; Stop button — streaming-only; clear —
        // messages-only) animate their appearance / removal between
        // Chat ↔ Cowork, producing the agentBar's items "搜索什么"
        // shifting around. Identity-transition + nil-animation makes
        // mode switch feel instant in the bar.
        .animation(nil, value: mode)
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

                // ── 🛡️ Private souls from sibling localkin checkout ──
                // Source: PrivateSoulLoader scans souls/private/*.soul.md
                // in any of the LOCALKIN_REPO candidate paths. Only
                // surfaces when the sibling repo is on disk — public
                // clones don't see this section at all (zero hint that
                // it exists, which is the point: feature is by
                // self-host opt-in, not flag-gated).
                if !kinClawPrivateSouls.isEmpty {
                    Menu("🛡️  Private  (\(kinClawPrivateSouls.count))") {
                        ForEach(kinClawPrivateSouls) { agentMenuRow($0) }
                    }
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
            // Source — which Ollama the models below come from. One
            // click flips between this Mac and the LAN box; the model
            // list reloads and the current model is re-pointed at the
            // new host when it exists there.
            Section("Source") {
                ForEach(OllamaCatalog.knownHosts, id: \.self) { host in
                    Button {
                        switchOllamaSource(to: host)
                    } label: {
                        HStack {
                            Image(systemName: host == OllamaCatalog.defaultBaseURL ? "laptopcomputer" : "network")
                            Text(OllamaCatalog.hostLabel(host))
                            Spacer()
                            if host == OllamaCatalog.baseURL { Image(systemName: "checkmark") }
                        }
                    }
                }
                Button("Add a host in Settings…") { openSettings() }
            }
            Divider()
            if coworkBrainPresets.isEmpty {
                Text("Ollama not reachable at \(OllamaCatalog.hostLabel(OllamaCatalog.baseURL))")
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
                Image(systemName: OllamaCatalog.isRemote ? "network" : "laptopcomputer")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(coworkBrainLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(coworkActiveModel.isEmpty
                                     ? .secondary
                                     : .primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(OllamaCatalog.sourceBadge)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch brain or source for Cowork (soul stays the same)")
    }

    /// Flip the Ollama source. Reloads the model list from the new host
    /// and, if the current model exists there, re-points the running
    /// brain at it so the switch is complete in one click; otherwise
    /// the list is refreshed and the user picks.
    private func switchOllamaSource(to host: String) {
        OllamaCatalog.setHost(host)
        Task {
            await reloadCoworkBrainPresets()
            guard coworkActiveProvider == "ollama" else { return }
            if let same = coworkBrainPresets.first(where: { $0.model == coworkActiveModel }) {
                switchCoworkBrain(to: same)
            } else {
                await MainActor.run {
                    messages.append(ChatMessage.assistant(
                        "Source is now \(OllamaCatalog.hostLabel(OllamaCatalog.baseURL)); \(coworkActiveModel) isn't there — pick a model from the brain menu."))
                }
            }
        }
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
                // Ollama presets carry the configured host (kinclaw
                // takes the base URL and adds the path itself).
                try await KinClawAPIClient.default.switchBrain(
                    provider: preset.provider,
                    model: preset.model,
                    endpoint: preset.provider == "ollama" ? OllamaCatalog.baseURL : nil)
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

    /// Decode the `todos` JSON string from a kinclaw `todo_write`
    /// tool_call's params into structured TodoItem rows. Returns
    /// nil on missing/malformed payload — caller falls back to the
    /// generic ToolCallView so a bad message doesn't break the
    /// chat surface. Mirrors CodePane.parseTodos.
    private func parseCoworkTodos(from params: [String: String])
        -> [TodoItem]?
    {
        guard let json = params["todos"],
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([TodoItem].self, from: data)
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
                    if mode == .chat && chatBrowsing {
                        // Gallery wins regardless of messages state.
                        // Why not gate on messages.isEmpty: cold app
                        // open auto-restores the last saved session
                        // (handleAgentChange line ~1591), so by the
                        // time the view renders, `messages` is non-
                        // empty and any "isEmpty" gate would never
                        // fire. The user's saved conversation isn't
                        // lost — it's preserved in `messages` state;
                        // tapping the green-ringed "your usual" card
                        // flips chatBrowsing → false and the same
                        // messages render in `ForEach` below.
                        chatGallery
                    } else if messages.isEmpty && loadError != nil {
                        errorState
                    } else if messages.isEmpty && selectedAgent != nil {
                        // Cowork (and future non-gallery modes)
                        // keep the per-agent welcomeCard.
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
                //
                // Suppress this fade during mode switches —
                // `messages = []` runs every time the user goes
                // Chat ↔ Cowork, which without this guard fires
                // the fade-out as part of the tab transition,
                // producing the visible "page is searching" jump.
                .animation(.easeInOut(duration: 0.18), value: messages.count)
                .animation(nil, value: mode)
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

                // Search box — single-line filter across name (zh +
                // en), slug, era, and notable tagline. Empty = show
                // all. Active query auto-expands every section so
                // matches in collapsed groups (Faith, Heal) surface
                // without manual expansion. Magnifier glyph + clear
                // button when text present.
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Search 80+ agents — name, era, tagline",
                              text: $gallerySearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !gallerySearch.isEmpty {
                        Button {
                            gallerySearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.platformSecondaryBackground.opacity(0.5))
                )
                .padding(.top, 6)
            }
            .padding(.horizontal, 4)

            // Sections — Core first per user request, then Faith
            // (most agents in this group, 44+), then TCM, then
            // anything else cloud-side that doesn't fit a known
            // category. Empty groups don't render. Each section
            // pre-filters its agent list against the search query
            // — empty post-filter sections also don't render.
            let coreFiltered = filteredAgents(coreAgents)
            let spiritualFiltered = filteredAgents(spiritualAgents)
            let tcmFiltered = filteredAgents(tcmAgents)
            let otherFiltered = filteredAgents(otherCloudAgents)

            if !coreFiltered.isEmpty {
                gallerySection(
                    key: "core",
                    title: "⭐  Core",
                    subtitle: "LocalKin flagship agents",
                    agents: coreFiltered)
            }
            if !spiritualFiltered.isEmpty {
                gallerySection(
                    key: "spiritual",
                    title: "📜  Faith / Selah",
                    subtitle: "44 spiritual masters · 1900 years",
                    agents: spiritualFiltered)
            }
            if !tcmFiltered.isEmpty {
                gallerySection(
                    key: "tcm",
                    title: "🌿  Heal / 岐黄",
                    subtitle: "Traditional Chinese medicine masters",
                    agents: tcmFiltered)
            }
            if !otherFiltered.isEmpty {
                gallerySection(
                    key: "other",
                    title: "🌐  Other",
                    subtitle: "Cloud agents",
                    agents: otherFiltered)
            }

            // Empty-result feedback when the user's query matches
            // nothing across all sections.
            if !gallerySearch.isEmpty
                && coreFiltered.isEmpty && spiritualFiltered.isEmpty
                && tcmFiltered.isEmpty && otherFiltered.isEmpty
            {
                Text("No agents match \"\(gallerySearch)\"")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }

            Spacer(minLength: 12)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Filter helper. Empty query = pass-through; non-empty does a
    /// case-insensitive substring match against every visible
    /// signal (zh name, en name, slug, era, tagline). All matched
    /// in one pass so a query like "patristic" surfaces every
    /// auto-derived "Patristic · ..." caption.
    private func filteredAgents(_ agents: [Agent]) -> [Agent] {
        let q = gallerySearch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if q.isEmpty { return agents }
        return agents.filter { agent in
            let master = CloudAgentCatalog.master(for: agent.slug)
            let haystacks: [String?] = [
                agent.slug,
                agent.displayName,
                agent.name,
                master?.nameZh,
                master?.nameEn,
                master?.era,
                master?.tagline,
                AgentDecor.caption(for: agent),
            ]
            for s in haystacks {
                if let s = s?.lowercased(), s.contains(q) {
                    return true
                }
            }
            return false
        }
    }

    /// One category band: collapsible title row + 2-column vertical
    /// grid of agent cards. Header is always visible (chevron +
    /// title + count + subtitle); body (the grid) renders only when
    /// `expandedGallerySections` contains the key.
    ///
    /// Why collapsible: an 80-master flat dump is overwhelming AND
    /// expensive to render (each Chat ↔ Cowork mode-switch reflows
    /// all 80 cards, producing the "页面不停跳动" flicker). Default-
    /// open Core (~10 cards) gets the user started; they expand
    /// Faith / Heal / Other on demand.
    @ViewBuilder
    private func gallerySection(key: String, title: String,
                                 subtitle: String,
                                 agents: [Agent]) -> some View {
        // When search is active, auto-expand every section that has
        // surviving matches — otherwise users typing "calvin" would
        // see "Faith / Selah (1)" still collapsed and wonder where
        // the result went. Manual toggle still works post-clear.
        let searchActive = !gallerySearch
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isExpanded = searchActive
            || expandedGallerySections.contains(key)
        VStack(alignment: .leading, spacing: 8) {
            // Header is the toggle. Whole row tappable so users
            // don't have to aim at a tiny chevron — same Disclosure
            // ergonomics as macOS list sections.
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isExpanded {
                        expandedGallerySections.remove(key)
                    } else {
                        expandedGallerySections.insert(key)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: isExpanded
                          ? "chevron.down"
                          : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
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
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                // 2-column LazyVGrid keeps the panel wide enough
                // for bilingual names + 1-line caption per card
                // while halving the scroll distance vs single-
                // column. Only renders when the section is
                // expanded — collapsed sections cost ~0.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
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
                // Prefer master.tagline (hardcoded notable line OR
                // auto-derived "Period · era") so spiritual + TCM
                // cards show context-rich captions like
                // "Patristic · 354-430" or "Doctor of grace · City
                // of God" instead of bare year ranges. Fall back to
                // AgentDecor.caption for non-catalog agents (e.g.
                // local kinclaw souls).
                let cloudTagline = CloudAgentCatalog.master(for: agent.slug)?.tagline
                let caption = cloudTagline ?? AgentDecor.caption(for: agent)
                if let caption = caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
            }
            // .frame(maxWidth: .infinity) lets the LazyVGrid
            // size the card to the available column width (~172pt
            // in the 380pt panel). Was a fixed 160pt width when
            // the layout was horizontal scroll.
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        if msg.role == .system {
            systemDivider(msg)
        } else {
            messageBubbleBody(msg)
        }
    }

    /// Kernel-originated transcript markers (a context compaction, a
    /// session boundary) render as a centered dim divider, not as a
    /// speech bubble from either party.
    private func systemDivider(_ msg: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(msg.content)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 24)
    }

    private func messageBubbleBody(_ msg: ChatMessage) -> some View {
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
            // todo_write is its own surface — the LATEST list renders as
            // an inline checklist (each call replaces the whole list, so
            // older ones are stale). Cowork is where this matters most:
            // Pilot's multi-step plan is invisible without it.
            if let latestTodo = msg.toolCalls.last(where: { $0.name == "todo_write" }),
               let todos = parseCoworkTodos(from: latestTodo.params) {
                TodoChecklistView(items: todos)
            }
            // Everything else folds into one "Ran N tools ›" row once a
            // turn has three or more calls; the call in flight stays
            // visible while streaming.
            let toolCalls = msg.toolCalls.filter { $0.name != "todo_write" }
            if !toolCalls.isEmpty {
                ToolCallGroupView(calls: toolCalls, streaming: showCursor)
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
        VStack(spacing: 6) {
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

            // One voice control, not two.
            //
            // There used to be a separate dictation button beside this one, but
            // two near-identical mic glyphs sitting together only raised the
            // question of which one to press. Talking to the assistant is the
            // job; turning speech into text you then have to send by hand is a
            // strictly smaller version of it. So: one button, one meaning.
            //
            // The icon doubles as a status readout, because in a hands-free
            // loop the user cannot see whether the machine is listening,
            // thinking, or talking — and guessing wrong means speaking over it.
            Button {
                voiceMode.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: voiceIconName)
                        .font(.system(size: 14))
                        .foregroundColor(voiceIconColor)
                    // Only while actually capturing: a meter that lingers
                    // through the reply would suggest it is still hearing you.
                    if voiceMode && recorder.isRecording {
                        AudioLevelMeter(level: recorder.audioLevel)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(voiceHelpText)

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
        }

        // Composer footer — the model picker sits bottom-right next to
        // send, where Claude Desktop keeps it.
        HStack(spacing: 10) {
            Spacer()
            if mode == .cowork {
                coworkBrainMenu
            }
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
        // The kernel cancels any parked approval / question when the
        // turn dies; drop the cards now rather than waiting for the echo.
        pendingPermission = nil
        pendingQuestion = nil
    }

    /// Answer the agent's ask_user question. Optimistic: the card goes
    /// away immediately; 404 from the server means it already resolved.
    private func answerQuestion(_ q: PendingQuestion, text: String) {
        pendingQuestion = nil
        Task {
            do {
                try await KinClawAPIClient.default.answerQuestion(id: q.id, text: text)
            } catch {
                FileHandle.standardError.write(
                    "kinclaw answerQuestion failed: \(error.localizedDescription)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
    }

    /// Files the agent read or changed this session, newest first, from
    /// the file_* tool calls in the transcript. Relative paths resolve
    /// against the workspace the same way the kernel resolves them.
    private var touchedFiles: [TouchedFile] {
        var byPath: [String: TouchedFile] = [:]
        var order: [String] = []
        for msg in messages {
            for call in msg.toolCalls {
                let action: String
                switch call.name {
                case "file_read":  action = "read"
                case "file_write": action = "write"
                case "file_edit":  action = "edit"
                default: continue
                }
                guard var p = call.params["path"], !p.isEmpty else { continue }
                if p.hasPrefix("~") { p = NSString(string: p).expandingTildeInPath }
                if !p.hasPrefix("/") {
                    p = (coworkWorkspace as NSString).appendingPathComponent(p)
                }
                p = URL(fileURLWithPath: p).standardizedFileURL.path
                if let prev = byPath[p] {
                    // A file both read and written counts as written.
                    if prev.action == "read" && action != "read" {
                        byPath[p] = TouchedFile(path: p, action: action)
                    }
                    order.removeAll { $0 == p }
                } else {
                    byPath[p] = TouchedFile(path: p, action: action)
                }
                order.append(p)
            }
        }
        return order.reversed().compactMap { byPath[$0] }
    }

    private func toggleWorkspaceSidebar() {
        withAnimation(.easeOut(duration: 0.18)) { showWorkspaceSidebar.toggle() }
    }

    /// Slugs of the KinClaw souls (public + private) — what separates a
    /// Cowork conversation from a Chat one for sessions saved before the
    /// workspace field existed.
    private var localSoulSlugs: Set<String> {
        Set(allAgents.filter { $0.isLocal }.map { $0.slug })
    }

    /// Open a stored Cowork conversation from the sidebar: restore its
    /// folder, its agent, and its transcript, and clear the kernel's own
    /// history so the model isn't answering from a conversation the user
    /// just navigated away from.
    private func openCoworkSession(_ session: ChatSession) {
        saveCurrentSession()
        if let ws = session.workspace, !ws.isEmpty, ws != coworkWorkspace {
            applyWorkspace(ws)
        }
        if session.agentSlug != selectedAgent?.slug,
           let agent = allAgents.first(where: { $0.slug == session.agentSlug }) {
            selectedAgent = agent
        }
        currentSessionID = session.id
        sessionTitle = session.title
        messages = session.messages.map { $0.toMessage() }
        isStreaming = false
        pendingPermission = nil
        pendingQuestion = nil
        localStreamTask?.cancel()
        Task { try? await KinClawAPIClient.default.resetSession() }
        scrollTrigger += 1
        sidebarRefresh += 1
    }

    /// Start an empty conversation in a folder (a folder row's "New
    /// session"), switching the workspace if it isn't the active one.
    private func newCoworkSession(in workspace: String) {
        saveCurrentSession()
        if !workspace.isEmpty && workspace != coworkWorkspace {
            applyWorkspace(workspace)
        }
        messages = []
        currentSessionID = UUID()
        sessionTitle = "New chat"
        pendingPermission = nil
        pendingQuestion = nil
        contextUsed = 0
        isStreaming = false
        localStreamTask?.cancel()
        Task { try? await KinClawAPIClient.default.resetSession() }
        sidebarRefresh += 1
        inputFocused = true
    }

    private func deleteCoworkSession(_ session: ChatSession) {
        ChatSessionStore.delete(id: session.id, agentSlug: session.agentSlug)
        if session.id == currentSessionID {
            messages = []
            currentSessionID = UUID()
            sessionTitle = "New chat"
        }
        sidebarRefresh += 1
    }

    /// Point the kernel at a folder without opening a picker — used by
    /// the sidebar's folder rows.
    private func applyWorkspace(_ path: String) {
        Task {
            do {
                coworkWorkspace = try await KinClawAPIClient.default.setWorkspace(path: path)
                sidebarRefresh += 1
            } catch {
                FileHandle.standardError.write(
                    "kinclaw setWorkspace failed: \(error.localizedDescription)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
    }

    /// Folder picker for the Cowork workspace → POST /api/workspace.
    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder Pilot works in"
        if !coworkWorkspace.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: coworkWorkspace)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                coworkWorkspace = try await KinClawAPIClient.default.setWorkspace(path: url.path)
            } catch {
                FileHandle.standardError.write(
                    "kinclaw setWorkspace failed: \(error.localizedDescription)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
    }

    /// Local notification when the panel is hidden — the agent finished,
    /// needs approval, or has a question — so a task the user started
    /// and walked away from still reaches them. Clicking it shows the
    /// panel (AppDelegate is the notification delegate).
    private func notifyIfHidden(title: String, body: String) {
        guard let delegate = NSApp.delegate as? AppDelegate,
              !delegate.spotlightWindow.isVisible else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Answer the kernel's approval request. Optimistic: the card goes
    /// away immediately; a 404 from the server means the request had
    /// already resolved (timeout / stop) and there is nothing to show.
    private func respondPermission(_ req: PermissionRequest, decision: String) {
        pendingPermission = nil
        Task {
            do {
                try await KinClawAPIClient.default.respondPermission(id: req.id, decision: decision)
            } catch {
                FileHandle.standardError.write(
                    "kinclaw respondPermission failed: \(error.localizedDescription)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
    }

    /// Flip the kernel's plan-mode gate. Optimistic, reconciled by the
    /// server's reply (it may refuse) and by later plan_mode events.
    private func toggleCoworkPlanMode() {
        let target = !coworkPlanMode
        coworkPlanMode = target
        Task {
            do {
                coworkPlanMode = try await KinClawAPIClient.default.setPlanMode(target)
            } catch {
                coworkPlanMode = !target
                FileHandle.standardError.write(
                    "kinclaw setPlanMode failed: \(error.localizedDescription)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
    }

    /// Pull GET /api/state to prime the header (meter, plan mode) —
    /// on entering Cowork and after every turn. Silent on failure:
    /// the connection dot already reports an unreachable kernel.
    private func refreshCoworkState() {
        Task {
            guard let st = try? await KinClawAPIClient.default.fetchKinClawState() else { return }
            if let n = st.input_tokens { contextUsed = n }
            if let c = st.context_length, c > 0 { contextLength = c }
            if let p = st.plan_mode { coworkPlanMode = p }
            if let w = st.workspace { coworkWorkspace = w }
        }
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
    ///
    /// Cowork mode also POSTs `/api/session/reset` to the kernel —
    /// otherwise the server's history buffer survives, and the next
    /// "你好" gets answered as if it were a follow-up to whatever
    /// half-finished task the previous turn left dangling. Chat mode
    /// has no kernel-side history (cloud SSE is stateless per turn)
    /// so the local clear is enough there.
    ///
    /// If the kernel reset fails (turn in flight → 409, helper not
    /// running → network error, older binary → 501) we do NOT block
    /// the local clear — the user clicked "New session" and expects
    /// the UI to be empty regardless. The kernel-side bleed risk is
    /// surfaced as a warning in the next turn's response space (or
    /// silently for 501 — already client-only on those builds).
    private func startNewSession() {
        guard let agent = selectedAgent else { return }
        saveCurrentSession()
        messages = []
        currentSessionID = UUID()
        sessionTitle = "New chat"
        pendingPermission = nil
        pendingQuestion = nil
        contextUsed = 0

        if mode == .cowork {
            Task {
                do {
                    try await KinClawAPIClient.default.resetSession()
                } catch {
                    // Best-effort; don't pop a modal. Log to stderr
                    // for the make-run console where Jacky watches.
                    FileHandle.standardError.write(
                        "kinclaw resetSession failed: \(error.localizedDescription)\n"
                            .data(using: .utf8) ?? Data())
                }
            }
        }
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
            messages: messages.map(PersistedMessage.init(from:)),
            // Only Cowork has a working folder; a Chat-tab conversation
            // did not happen anywhere in particular.
            workspace: mode == .cowork && !coworkWorkspace.isEmpty ? coworkWorkspace : nil
        )
        ChatSessionStore.save(session)
        sessionTitle = title
        sidebarRefresh += 1
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
        case .cowork:
            // Public KinClaw souls (registered via :5001 /api/souls)
            // are name-prefixed; private souls come from the sibling
            // localkin repo and carry `domain == "kinclaw-private"`.
            // Both flavours route through the same chatBody surface.
            return agent.name.hasPrefix("KinClaw") || agent.domain == "kinclaw-private"
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

    // MARK: - Voice button state
    //
    // In a hands-free loop the microphone is open some of the time and closed
    // the rest, with no keyboard interaction to mark the boundary. Without a
    // visible cue the user talks over the reply, or waits in silence while the
    // machine is already listening. These three properties are that cue.

    private var voiceIconName: String {
        guard voiceMode else { return "mic" }
        if recorder.isTranscribing { return "waveform.badge.magnifyingglass" }
        if recorder.isRecording { return "mic.fill" }
        if speaker.isSpeaking { return "speaker.wave.2.fill" }
        if isStreaming { return "ellipsis.circle" }
        return "waveform.circle.fill"
    }

    private var voiceIconColor: Color {
        guard voiceMode else { return .secondary }
        // Waiting for the wake word is a distinct state from conversing, and
        // it must look distinct: both have the mic open, but only one of them
        // will do anything with what it hears. Without this the user says a
        // whole sentence into what looks like an active mic and gets silence.
        if recorder.isRecording && !isWakeSessionOpen { return .orange }
        // Red only while capturing — the one state where what you say is
        // being recorded.
        return recorder.isRecording ? .red : .accentColor
    }

    private var voiceHelpText: String {
        guard voiceMode else {
            return "Hands-free conversation: speak, it replies aloud, repeat"
        }
        if recorder.isTranscribing { return "Transcribing…" }
        if recorder.isRecording {
            return isWakeSessionOpen
                ? "Listening — just talk, it sends when you stop"
                : "Waiting for “\(wakeWord)” — say it to start talking"
        }
        if speaker.isSpeaking { return "Speaking — it will listen again when done" }
        if isStreaming { return "Thinking…" }
        if !isWakeSessionOpen {
            return "Conversation mode on — say “\(wakeWord)” to begin"
        }
        return "Conversation mode on — click to stop"
    }

    /// Hands the conversational turn back to the microphone.
    ///
    /// Called after the assistant finishes speaking. Guarded rather than
    /// unconditional because three things can race here: the user may have
    /// switched voice mode off while the reply was playing, another response may
    /// already be streaming, and the recorder may still be running from a
    /// previous turn. Starting a second recording in any of those cases produces
    /// overlapping audio and a garbled transcript.
    /// True while the wake word has already been said and the conversation is
    /// still open. Always true when no wake word is configured — there is no
    /// gate to be on the far side of.
    private var isWakeSessionOpen: Bool {
        guard !wakeWord.isEmpty else { return true }
        guard let expiry = wakeSessionExpiry else { return false }
        return expiry > Date()
    }

    /// Push the lapse further out. Called when the user speaks and again when
    /// a reply finishes — the second one matters: a two-minute answer would
    /// otherwise expire the session while the user is still listening to it,
    /// and they'd have to say the wake word to respond to what they just
    /// heard.
    private func extendWakeSession() {
        guard !wakeWord.isEmpty else { return }
        wakeSessionExpiry = Date().addingTimeInterval(max(5, wakeSessionSeconds))
    }

    private func closeWakeSession() {
        wakeSessionExpiry = nil
    }

    private func resumeListeningIfConversing(extendSession: Bool = true) {
        // A finished reply keeps the conversation alive; a discarded utterance
        // must not, or background chatter would hold the session open forever
        // and the wake word would stop meaning anything.
        if extendSession { extendWakeSession() }
        guard voiceMode, !isStreaming, !recorder.isRecording else { return }
        // A beat of silence between the reply ending and the mic opening, so the
        // tail of the spoken audio never bleeds into the next recording.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard voiceMode, !isStreaming, !recorder.isRecording else { return }
            recorder.startRecording(hostname: hostname)
        }
    }

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
                                  hostname: hostname) {
                        // Closing the loop: the reply has finished playing, so
                        // start listening again. Without this the user would
                        // have to reach for the mic every single turn, which is
                        // exactly what hands-free mode exists to avoid.
                        resumeListeningIfConversing()
                    }
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
            pendingPermission = nil
            pendingQuestion = nil
            refreshCoworkState()
            sidebarRefresh += 1
            if messages.indices.contains(assistantIndex) {
                let reply = messages[assistantIndex].content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    notifyIfHidden(title: "\(agent.displayName) finished", body: reply)
                }
            }
            ChatHistory.save(messages: messages, for: agent.slug)
            if ttsEnabled,
               messages.indices.contains(assistantIndex),
               !messages[assistantIndex].content.isEmpty
            {
                speaker.speak(messages[assistantIndex].content,
                              hostname: hostname) {
                    resumeListeningIfConversing()
                }
            } else {
                // TTS off (or an empty reply): there is nothing to wait for, so
                // hand the turn straight back to the microphone.
                resumeListeningIfConversing()
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
        // spawn_done is a STANDALONE bubble that arrives long after the
        // turn that dispatched the spawn has ended (researcher running
        // 3-5 minutes detached). It does NOT need an active
        // `assistantIndex` to write to — it appends a fresh bubble. So
        // handle it BEFORE the stale-index guard, otherwise the
        // guard's early-return silently drops the user's whole
        // research deliverable. Real bug observed: 2026-05-06 19:55,
        // researcher finished after 1m52s but no bubble ever appeared
        // because pilot's turn was long over and `assistantIndex` no
        // longer pointed at any row.
        if event.kind == .spawnDone {
            let soulName = event.name ?? "agent"
            let jobID = event.id ?? "?"
            let dur = event.params?["duration_s"] ?? "?"
            let body = event.output ?? "(no output)"
            let header = "🔬 \(soulName) (job \(jobID)) finished in \(dur)s"
            messages.append(ChatMessage.assistant("**\(header)**\n\n\(body)"))
            notifyIfHidden(title: "\(soulName) finished", body: body)
            scrollTrigger += 1
            return
        }

        // Kernel-level events that aren't bound to the streaming
        // bubble either: the permission gate, context accounting, plan
        // mode. Handled before the stale-index guard for the same
        // reason spawn_done is.
        switch event.kind {
        case .permissionRequest:
            guard let id = event.id else { return }
            let req = PermissionRequest(
                id: id,
                skill: event.name ?? "?",
                summary: event.summary ?? (event.name ?? "?"),
                reason: event.reason ?? "",
                params: event.params ?? [:])
            pendingPermission = req
            notifyIfHidden(title: "Pilot needs approval", body: req.summary)
            scrollTrigger += 1
            return
        case .permissionResolved:
            if pendingPermission?.id == event.id { pendingPermission = nil }
            return
        case .question:
            guard let id = event.id else { return }
            let q = PendingQuestion(id: id, text: event.message ?? "?", options: event.options ?? [])
            pendingQuestion = q
            notifyIfHidden(title: "Pilot asks", body: q.text)
            scrollTrigger += 1
            return
        case .questionResolved:
            if pendingQuestion?.id == event.id { pendingQuestion = nil }
            return
        case .workspace:
            if let w = event.workspace { coworkWorkspace = w }
            sidebarRefresh += 1
            return
        case .usage:
            if let n = event.input_tokens { contextUsed = n }
            if let c = event.context_length, c > 0 { contextLength = c }
            return
        case .compacted:
            // Appended after the streaming bubble on purpose: inserting
            // before it would shift assistantIndex under the deltas
            // still arriving for this turn.
            let m = event.message ?? "Older conversation compacted into a summary"
            messages.append(ChatMessage(id: UUID(), role: .system,
                                        content: "🗜 \(m)", timestamp: Date()))
            scrollTrigger += 1
            return
        case .planMode:
            if let p = event.plan_mode { coworkPlanMode = p }
            return
        default:
            break
        }

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
        case .notice:
            // Kernel commentary mid-turn (circuit breaker replan, hook
            // block, denied permission). The turn goes on — render as
            // a quiet blockquote inside the bubble, not as an error.
            if let m = event.message, !m.isEmpty {
                messages[assistantIndex].content += "\n\n> ⚠︎ \(m)\n"
                scrollTrigger += 1
            }
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
        case .sessionReset:
            // Server confirmed it cleared its history tape. We've
            // already wiped the UI client-side via startNewSession;
            // this event is for any *other* connected SSE client to
            // refresh. No-op here.
            break
        case .spawnDone:
            // Already handled above the stale-index guard — this case
            // is unreachable but kept exhaustive for the compiler.
            break
        case .userMessage, .turnDone, .planMode,
             .permissionRequest, .permissionResolved, .usage, .compacted,
             .question, .questionResolved, .workspace, .none:
            // plan_mode / permission / question / usage / compacted /
            // workspace are handled above the stale-index guard.
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

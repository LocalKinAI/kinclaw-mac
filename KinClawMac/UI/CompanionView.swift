import SwiftUI
import AppKit

/// Companion mode: the panel becomes a picture and a voice. No
/// transcript, no buttons, no typing — you speak, it listens, it
/// answers out loud, and the halo around the character shows which of
/// those is happening. Esc leaves.
///
/// It drives the same voice loop the panel already uses (VoiceRecorder,
/// SpeechSynthesizer, the kinclaw turn); this view only decides what
/// you look at while it runs.
struct CompanionView: View {
    @ObservedObject var art: CompanionArt
    /// The 3D companion, when there is a model for her. Reached directly
    /// rather than passed in: this view already takes twenty parameters, and
    /// the stage is a singleton because she has to outlive the view.
    @ObservedObject private var vrm = VRMStage.shared
    @ObservedObject private var vrmServer = VRMServerBox.shared
    @ObservedObject private var overlay = CompanionOverlay.shared
    @ObservedObject private var lookMaker = RealLookMaker.shared

    /// Live inputs from the panel's existing voice objects.
    let isListening: Bool
    let isThinking: Bool
    let isSpeaking: Bool
    let audioLevel: Double
    /// The recorder has heard a voice in the current recording, as opposed to
    /// the microphone merely being open.
    var isHearingSpeech: Bool = false
    /// Last thing said, shown small and briefly — useful when the room
    /// is loud enough that you missed it, invisible the rest of the time.
    let caption: String
    /// Non-nil when something is stopping the voice loop; shown instead
    /// of the state label, because "说话就好" over a dead mic is a lie.
    let problem: String?
    /// How the companion feels — from the reply's opening tag, or from
    /// how the user sounded. Picks the art alongside `state`.
    let mood: CompanionMood?
    /// What the current reply is about, in one English keyword, or "".
    /// Matched against the art's own filenames and credits.
    let subject: String
    /// What it is doing right now — "在看屏幕", "在跑命令". Companion
    /// mode shows no tool calls, so without this a task that takes six
    /// rounds is forty seconds of a face saying nothing.
    let activity: String?
    /// True when talking over the agent will stop it (headphones, or
    /// forced on). Otherwise the halo is the way to cut in.
    let canBargeIn: Bool
    /// Stop the reply and open the microphone.
    let onInterrupt: () -> Void
    /// A parked turn waiting on the human — the permission gate or an
    /// `ask_user` question. Read out loud AND shown here: the voice is
    /// the fast path, the card is what you come back to.
    let prompt: CompanionPromptView.Prompt?
    let onPromptDecision: (String) -> Void
    let onPromptAnswer: (String) -> Void

    let onExit: () -> Void
    let onFetchArt: () -> Void
    /// Speak the sample line in the voice just chosen.
    let onPreviewVoice: () -> Void
    /// Where the avatar's local server is serving from, or nil when the
    /// digital human is off or unavailable — then it is a picture and a
    /// halo, as before.
    let avatarBase: URL?
    /// Turn the digital human on or off, and pick who it is.
    let onAvatarToggle: (Bool) -> Void
    let onAvatarCharacter: (AvatarStage.Character) -> Void
    /// Handed the web view once it exists, so audio can reach it.
    let onAvatarReady: (AvatarWebView) -> Void

    // The voice is a global preference, not a companion one: the panel's
    // voice mode uses the same speaker. It is offered here because this
    // is the one view where you are listening to it.
    @AppStorage("kinclaw.voice.tts.speaker") private var voice = "auto"
    @ObservedObject private var ttsVoices = TTSVoices.shared
    @AppStorage("kinclaw.voice.tts.speed") private var speed: Double = 1.0

    @State private var current: URL?
    @State private var previous: URL?
    @State private var currentImage: NSImage?
    @State private var previousImage: NSImage?
    @State private var showPrevious = false
    @State private var rotate: Timer?
    /// When the picture last changed — the floor under how often it can.
    @State private var lastPick: Date?
    /// The pending "nobody needs you, go and play" after an exchange ends.
    @State private var wander: DispatchWorkItem?
    @State private var lastPickState = ""
    @State private var lastPickScene: String?
    /// A still gets a slow push-in and drift over its time on screen,
    /// alternating direction picture to picture, so the background is
    /// never quite static even before there are clips.
    @State private var kenZoom: CGFloat = 1.03
    @State private var kenShift: CGSize = .zero
    @State private var kenSign: CGFloat = 1
    /// The joints of the animal in the current still, when macOS could
    /// find them. Non-nil means the picture can be puppeteered — it
    /// breathes, blinks and looks at you — rather than merely drifting.
    @State private var puppetRig: PuppetRig?

    private var state: String {
        if isSpeaking { return "speaking" }
        if isThinking { return "thinking" }
        if isListening { return "listening" }
        return "idle"
    }

    private var accent: Color {
        if problem != nil { return .orange }
        switch state {
        case "listening": return .green
        case "thinking":  return .yellow
        case "speaking":  return .cyan
        default:          return .white.opacity(0.5)
        }
    }

    private var stateLabel: String {
        if let p = problem { return p }
        if let a = activity, isThinking { return a + "…" }
        switch state {
        case "listening": return "在听"
        case "thinking":  return "在想"
        case "speaking":  return canBargeIn ? "在说 · 想插话就直接说" : "在说 · 点一下光晕打断"
        default:          return "说话就好"
        }
    }

    var body: some View {
        ZStack {
            // The art is behind her either way now. It used to be a dark
            // ground whenever a face was on screen, because a green-screened
            // stranger over a picture of somebody's dog reads as a collage
            // rather than as a person in a room. That stopped being true when
            // the figure and the pictures became the same woman: her cut-out
            // over her own kitchen is one scene, not two subjects competing.
            background
            LinearGradient(colors: avatarBase == nil
                           ? [.black.opacity(0.15), .black.opacity(0.55)]
                           // A little more scrim behind a figure, so the halo
                           // and the caption stay readable against her.
                           : [.black.opacity(0.25), .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The living face, between the background and the controls.
            // Its own background is chroma-keyed away, so what shows
            // behind it is the picture that follows the conversation.
            if let base = avatarBase {
                AvatarView(base: base, onReady: onAvatarReady)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            // The 3D companion. Above the picture, hit-testing on: her eyes
            // follow the pointer, which is the one interaction that makes a
            // character feel present rather than played back.
            // Not while she is on the desktop: one web view for the
            // character, or two copies of the model animating in parallel.
            if let base = vrmServer.base, !overlay.isOn {
                VRMStageView(base: base, onReady: { vrm.attach($0) })
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            VStack {
                topBar
                Spacer()
                // With a face on screen the halo becomes a second
                // thing claiming to be the agent. Tap-to-interrupt
                // moves onto the face itself, which is where anyone
                // would reach for it anyway.
                if avatarBase == nil {
                    halo
                        .contentShape(Circle().scale(1.3))
                        .onTapGesture {
                            if isSpeaking || isThinking { onInterrupt() }
                        }
                        .help(isSpeaking ? "打断" : "")
                } else {
                    Color.clear
                        .frame(height: 200)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSpeaking || isThinking { onInterrupt() }
                        }
                        .help(isSpeaking ? "打断" : "")
                }
                Text(stateLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(problem == nil ? .white.opacity(0.9) : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .padding(.top, 14)
                Spacer()

                // The last thing said, as a subtitle rather than as
                // text floating in the middle of the picture. It was
                // 13pt translucent white with nothing behind it, which
                // is legible over a dark scrim and not over a face or a
                // snowfield. Now: bigger, opaque, on its own dark
                // backing, and along the bottom where a subtitle goes —
                // out of the way of whoever is talking.
                if !caption.isEmpty, prompt == nil {
                    Text(caption)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.black.opacity(0.62))
                        )
                        .padding(.horizontal, 22)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
                if let p = prompt {
                    CompanionPromptView(prompt: p,
                                        onDecision: onPromptDecision,
                                        onAnswer: onPromptAnswer)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
            }
            .animation(.easeOut(duration: 0.2), value: prompt)
        }
        .background(Color.black)
        .onAppear {
            art.reload()
            enterStage(stage3D)
            let later = DispatchWorkItem { vrm.attend(false) }
            wander = later
            DispatchQueue.main.asyncAfter(deadline: .now() + 9, execute: later)
            rotate = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
                Task { @MainActor in pick() }
            }
        }
        .onDisappear { rotate?.invalidate(); rotate = nil }
        // Somebody is talking to her, or she is about to answer: she comes up
        // to the lens. A few seconds after the exchange ends she is free to
        // wander off again — the same rhythm as the filmed companion's wait
        // and talk clips, walked instead of cut.
        .onChange(of: wanted) { _, now in
            // Which of the three called her, for the diagnostics: a companion
            // who never wanders off is being called by something.
            let why = [isThinking ? "在想" : nil, isSpeaking ? "在说" : nil,
                       isListening && isHearingSpeech ? "听见人声" : nil].compactMap { $0 }.joined(separator: "+")
            CompanionPresence.shared.noteWanted(now ? "叫她：\(why)" : "放她走")
            wander?.cancel()
            if now {
                vrm.attend(true)
            } else {
                let later = DispatchWorkItem { vrm.attend(false) }
                wander = later
                DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: later)
            }
        }
        .onChange(of: state) { _, _ in
            // Per-state art swaps immediately; a pool-only setup keeps
            // the same picture and just changes the halo. Scenes are per-state
            // art too: wait and talk are the two halves of one place.
            if art.hasGroups || !art.scenes.isEmpty { pick() }
        }
        // She moved — the user named a place, or a reply did. The picker only
        // runs on these hooks, so without this one the decision is made and
        // the old room stays on screen.
        // The whole scene rather than its name: the same place gains a talk
        // clip a minute after its wait clip, and a plate when the 3D
        // companion first needs one, and each of those is a new picture.
        .onChange(of: art.scene) { _, _ in pick() }
        // Which companion is on screen decides what a place is made of.
        .onChange(of: stage3D) { _, on in enterStage(on) }

        .onChange(of: mood) { _, new in
            if art.hasGroups { pick() }
            vrm.express(new)
        }
        // Her mouth follows the voice's level while a reply is being spoken;
        // the stage decays it on its own, so a dropped update closes it.
        .onChange(of: audioLevel) { _, level in
            vrm.voice(level: level * 1.4, speaking: isSpeaking)
        }
        .onChange(of: isSpeaking) { _, speaking in
            vrm.voice(level: speaking ? audioLevel * 1.4 : 0, speaking: speaking)
        }
        .onAppear {
            CompanionPresence.shared.onScreen = true
            vrmServer.startIfWanted()
        }
        .onDisappear { CompanionPresence.shared.onScreen = false }
        // A look that just finished is one she should be wearing: the point of
        // making it was to see it.
        .onChange(of: lookMaker.made?.id) { _, id in
            guard id != nil, let made = lookMaker.made else { return }
            if vrmServer.base != nil {
                VRMWardrobe.isEnabled = false
                vrmServer.stop()
            }
            onAvatarCharacter(made)
        }
        // The subject changing is the strongest reason to change the
        // picture — and the only one that makes the background about
        // the conversation rather than about the voice.
        .onChange(of: subject) { _, new in
            guard !new.isEmpty else { return }
            pick()
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var background: some View {
        GeometryReader { geo in
            ZStack {
                if let p = previous, showPrevious {
                    media(p, image: previousImage, size: geo.size, live: false)
                }
                if let c = current {
                    media(c, image: currentImage, size: geo.size, live: true)
                        .transition(.opacity)
                        .id(c)
                } else {
                    emptyState
                }
            }
        }
        .ignoresSafeArea()
    }

    /// One piece of art filling the window: a looping clip as it is, a
    /// still with the slow camera move and a breath that follows the
    /// microphone while someone is talking.
    @ViewBuilder
    private func media(_ url: URL, image: NSImage?, size: CGSize, live: Bool) -> some View {
        if CompanionArt.isVideo(url) {
            LoopingVideoView(url: url)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else if let img = image, live, let rig = puppetRig {
            // A photograph that can look back. See AnimalPuppetView:
            // no lip sync, because a dog does not lip sync — what
            // reads as alive is attention.
            AnimalPuppetView(image: img, rig: rig,
                             isListening: isListening,
                             isThinking: isThinking,
                             isSpeaking: isSpeaking,
                             audioLevel: audioLevel)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else if let img = image {
            let level = (isListening || isSpeaking) ? CGFloat(min(1, audioLevel * 1.4)) : 0
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect((live ? kenZoom : 1.03) + level * 0.02)
                .offset(live ? kenShift : .zero)
                .animation(.easeOut(duration: 0.15), value: level)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🦞").font(.system(size: 60))
            Text("还没有背景图")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            Text("放几张图片到 ~/.kinclaw/companion/，\n或者让我去网上取几张。")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("去取几张…") { onFetchArt() }
                .controlSize(.small)
                .tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            voiceMenu
            themeMenu
            avatarMenu
            wardrobeMenu
            Spacer()
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(7)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("离开陪伴模式 (Esc)")
        }
        .padding(12)
    }

    /// Ask for a video and make a look out of it. A minute of someone talking
    /// to the camera is what the scripts want; the name is the folder it lands
    /// in and what the menu calls her.
    private func pickLookVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "挑一段她说话的视频（正脸、一分钟左右就够）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        lookMaker.make(from: url, name: url.deletingPathExtension().lastPathComponent)
    }

    /// The 3D companion and her clothes: a folder of VRM models, and which one
    /// she is wearing. Desktop Mate's outfit switch and Grok's "switch to a
    /// summer dress" are the same move underneath — a VRM carries its clothes
    /// baked in, so an outfit is a file.
    private var wardrobeMenu: some View {
        let outfits = VRMWardrobe.outfits
        let wearing = VRMWardrobe.chosen
        return Menu {
            Toggle(isOn: Binding(
                get: { vrmServer.base != nil },
                set: { on in
                    VRMWardrobe.isEnabled = on
                    if on {
                        if avatarBase != nil { onAvatarToggle(false) }
                        vrmServer.startIfWanted()
                    } else {
                        vrmServer.stop()
                    }
                }
            )) {
                Label("3D 形象", systemImage: "person.crop.square.badge.video")
            }
            .disabled(outfits.isEmpty)
            if !outfits.isEmpty {
                Divider()
                ForEach(outfits) { outfit in
                    Button {
                        vrm.wear(outfit)
                        if vrmServer.base == nil {
                            if avatarBase != nil { onAvatarToggle(false) }
                            VRMWardrobe.isEnabled = true
                            vrmServer.startIfWanted()
                        }
                    } label: {
                        if outfit.id == wearing?.id {
                            Label(outfit.name, systemImage: "checkmark")
                        } else {
                            Text(outfit.name)
                        }
                    }
                }
            }
            Divider()
            // The panel is a window you summon; the desktop is where she can
            // just be. Same character, same web view, moved.
            Button(overlay.isOn ? "从桌面收回面板" : "放到桌面上（浮在最前面）") {
                if !overlay.isOn, vrmServer.base == nil {
                    if avatarBase != nil { onAvatarToggle(false) }
                    VRMWardrobe.isEnabled = true
                    vrmServer.startIfWanted()
                }
                overlay.toggle()
            }
            if overlay.isOn {
                Button(overlay.clickThrough ? "让她接收点击" : "鼠标穿透（她只是画面）") {
                    overlay.setClickThrough(!overlay.clickThrough)
                }
            }
            Divider()
            Button("打开模型文件夹…") {
                NSWorkspace.shared.open(VRMWardrobe.ensureFolder())
            }
            Button("去 VRoid Hub 找模型…") {
                NSWorkspace.shared.open(VRMWardrobe.sourceURL)
            }
            if outfits.isEmpty {
                Text("把 .vrm 放进 ~/.kinclaw/avatars/ 就能选了")
                    .foregroundColor(.secondary)
            }
            if let note = vrm.note {
                Divider()
                Text(note).foregroundColor(.secondary)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: vrmServer.base != nil ? "figure.stand" : "figure.stand.dress")
                    .font(.system(size: 10))
                Text(vrmServer.base != nil ? (wearing?.name ?? "3D") : "3D 形象")
                    .font(.system(size: 11))
            }
            .foregroundColor(vrmServer.base != nil ? .pink.opacity(0.9) : .white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("她的形象和衣服：~/.kinclaw/avatars/ 里的 VRM 模型")
    }

    /// Pick a voice by ear: every change speaks the sample line, so
    /// finding the one you like is a few clicks, not a trip to Settings
    /// and back for each candidate.
    private var voiceMenu: some View {
        Menu {
            Picker("声音", selection: $voice) {
                Text(ttsVoices.autoLabel).tag("auto")
                ForEach(ttsVoices.groups) { group in
                    Section(group.title) {
                        ForEach(group.voices, id: \.id) { v in Text(v.label).tag(v.id) }
                    }
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("语速", selection: $speed) {
                ForEach(KokoroVoice.speeds, id: \.self) { sp in
                    Text(String(format: "%.1fx", sp)).tag(sp)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("再听一遍") { onPreviewVoice() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                Text(voiceLabel)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("换个声音 · 每次换都会念一句给你听")
        .onChange(of: voice) { _, _ in onPreviewVoice() }
        .onChange(of: speed) { _, _ in onPreviewVoice() }
    }

    /// Which set of pictures is behind you: the default folder or any
    /// `companion-<name>` sibling. Switching re-reads the folder and
    /// swaps the picture on the spot.
    /// The digital human, when the avatar service is on disk. Off by
    /// default: it is a web view running a WASM model, which is a lot
    /// to start for someone who wanted a picture and a voice.
    @ViewBuilder
    private var avatarMenu: some View {
        if AvatarStage.source != nil {
            Menu {
                Toggle(isOn: Binding(
                    get: { avatarBase != nil },
                    set: { on in
                        // One or the other: the 3D canvas covers the panel, so
                        // both on means a cartoon standing in front of her.
                        if on, vrmServer.base != nil {
                            VRMWardrobe.isEnabled = false
                            vrmServer.stop()
                        }
                        onAvatarToggle(on)
                    }
                )) {
                    Label("会说话的人", systemImage: "person.wave.2")
                }
                if avatarBase != nil {
                    Divider()
                    ForEach(AvatarStage.characters) { c in
                        Button {
                            onAvatarCharacter(c)
                        } label: {
                            if c.id == AvatarStage.chosen?.id {
                                Label(c.name, systemImage: "checkmark")
                            } else {
                                Text(c.name)
                            }
                        }
                    }
                }
                Divider()
                Button(lookMaker.busy ? "正在做新形象…" : "用一段视频做新形象…") {
                    pickLookVideo()
                }
                .disabled(lookMaker.busy)
                Button("打开形象文件夹…") {
                    try? FileManager.default.createDirectory(at: AvatarStage.madeFolder,
                                                             withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AvatarStage.madeFolder)
                }
                if let note = lookMaker.note {
                    Divider()
                    Text(note).foregroundColor(.secondary)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: avatarBase != nil ? "person.wave.2.fill" : "person.wave.2")
                    Text(avatarBase != nil ? (AvatarStage.chosen?.name ?? "数字人") : "数字人")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(avatarBase != nil ? .cyan.opacity(0.9) : .white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("嘴型跟着 Kokoro 的声音动。背景还是上面那套，人站在前面。")
        }
    }

    private var themeMenu: some View {
        Menu {
            ForEach(CompanionArt.themes()) { th in
                Button {
                    art.useTheme(th)
                    pick()
                } label: {
                    if th.url.path == CompanionArt.folder.path {
                        Label(th.name, systemImage: "checkmark")
                    } else {
                        Text(th.name)
                    }
                }
            }
            Divider()
            Button("去取几张…") { onFetchArt() }
            Button("打开文件夹") { art.revealFolder() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle")
                Text(CompanionArt.themes().first { $0.url.path == CompanionArt.folder.path }?.name ?? "背景")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.35)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("换一套背景：~/.kinclaw/companion-<名字>/ 都是一套")
    }

    private var voiceLabel: String {
        let name = ttsVoices.label(for: voice) ?? "自动"
        let rate = abs(speed - 1.0) < 0.01 ? "" : String(format: " · %.1fx", speed)
        return name + rate
    }

    /// The one moving thing: a ring that breathes on idle and tracks
    /// your voice while the mic is open, so "is it hearing me" is
    /// answerable from across the room.
    private var halo: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.04 * sin(t * 1.6)
            let level = isListening ? min(1, audioLevel * 1.6) : 0
            let pulse = isSpeaking ? 1 + 0.06 * sin(t * 5) : 1
            let scale = breathe * pulse * (1 + level * 0.35)
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.30), lineWidth: 2)
                    .frame(width: 150, height: 150)
                    .scaleEffect(scale * 1.12)
                    .blur(radius: 6)
                Circle()
                    .stroke(accent.opacity(0.85), lineWidth: 2.5)
                    .frame(width: 130, height: 130)
                    .scaleEffect(scale)
                if isThinking {
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(t * 220))
                }
            }
        }
        .frame(height: 190)
    }

    /// Somebody is actually talking to her, or she is working on an answer.
    /// Not "the microphone is open": in a voice conversation it is open all
    /// evening, and a companion pinned to the lens by an open microphone
    /// never gets to wander off at all. A voice in it is what counts.
    private var wanted: Bool { isThinking || isSpeaking || (isListening && isHearingSpeech) }

    /// The 3D companion is the one in the panel — not the filmed one, and
    /// not while she is out on the desktop, where there is no room behind her.
    private var stage3D: Bool { vrmServer.base != nil && !overlay.isOn }

    /// Places are clips of her for the filmed companion and empty plates for
    /// the 3D one. Coming on stage in 3D also has the plates made for every
    /// place that predates her — once, eleven seconds apiece.
    private func enterStage(_ in3D: Bool) {
        art.stage3D = in3D
        if in3D, !art.scenes.isEmpty { CompanionCharacter.shared.makePlates() }
        // Not subject to the hold: the stage comes up a fraction of a second
        // after the view appears, and a pick held back then leaves the filmed
        // clip on screen behind the 3D companion — two of her — until
        // something else happens to change.
        lastPick = nil
        pick()
    }

    private func pick() {
        // Hold a picture for a few seconds whatever happens. Mood,
        // state and subject can all move within one reply, and a
        // background that crossfades three times in five seconds is a
        // slideshow, which is the failure mode this whole feature is
        // one step away from.
        // The hold is about pictures: three crossfades in five seconds is a
        // slideshow. It is *not* about her state — in a scene, "she looks up
        // and starts talking" is the one transition that has to be immediate,
        // and holding it for four seconds is why the background looked stuck.
        let stateChanged = state != lastPickState
        lastPickState = state
        // Nor is it about where she is: a scene change is the user's own
        // request arriving, and is shown at once.
        let moved = art.scene?.name != lastPickScene
        lastPickScene = art.scene?.name
        if !stateChanged, !moved, let last = lastPick, Date().timeIntervalSince(last) < 4 { return }
        let next = art.art(for: state, mood: mood, subject: subject,
                           fallback: art.pool.randomElement())
        // She is framed and lit by what is behind her: waist up and in the
        // place's light when that is one of her plates, full length under
        // studio lights otherwise. Said here rather than from a change hook —
        // the first pick happens before any hook is listening, and she stood
        // full length in her own kitchen until something else moved.
        // With a wide plate she has the whole place: the stage draws it and
        // she walks around in it.
        if stage3D, next != nil, next == art.scene?.plate {
            vrm.place(in: art.scene)
        } else {
            vrm.place(plate: nil)
        }
        guard next != current else { return }
        lastPick = Date()
        previous = current
        previousImage = currentImage
        showPrevious = current != nil
        // Decoded once here, not on every frame of the camera move.
        currentImage = next.flatMap { CompanionArt.isVideo($0) ? nil : NSImage(contentsOf: $0) }
        // Vision costs a couple hundred milliseconds the first time it
        // sees a photo and nothing after — the answer is cached beside
        // the file. Off the main thread either way: a crossfade must
        // not wait for a pose model.
        puppetRig = nil
        if let u = next, !CompanionArt.isVideo(u) {
            Task { @MainActor in
                let r = AnimalPuppet.rig(for: u)
                if current == u { puppetRig = r }
            }
        }
        kenSign = -kenSign
        kenZoom = 1.03
        kenShift = .zero
        withAnimation(.easeInOut(duration: 0.8)) {
            current = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showPrevious = false }
        // Start the push-in after the crossfade has begun, so the new
        // picture arrives already moving rather than snapping into motion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard current == next else { return }
            withAnimation(.linear(duration: 45)) {
                kenZoom = 1.10
                kenShift = CGSize(width: kenSign * 14, height: -10)
            }
        }
    }
}

/// "Go get a few" — type what you want behind you, see what came back,
/// keep the ones you like. Wikimedia Commons needs no account, so this
/// works on a fresh machine; a free Pexels key in Settings swaps in a
/// better-looking source.
struct CompanionArtPicker: View {
    @ObservedObject var art: CompanionArt
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [CompanionArt.Candidate] = []
    @State private var searching = false
    @State private var kept: Set<UUID> = []
    @State private var kind: CompanionArt.MediaKind = .photo
    /// Which folder the next downloads land in: "" is the rotating
    /// pool, otherwise a state or mood.
    @State private var group = ""
    @AppStorage(CompanionArt.pexelsKeyKey) private var pexelsKey = ""
    /// Making a picture rather than finding one.
    @ObservedObject private var diffuser = DiffuserClient.shared
    @State private var drawPrompt = ""
    /// Her: the description, and what to put her in next.
    @ObservedObject private var her = CompanionCharacter.shared
    @State private var lookText = ""
    @State private var sceneText = ""
    @State private var drawNote: String?
    @State private var drawn: URL?
    @AppStorage(DiffuserClient.hostKey) private var diffuserHost = DiffuserClient.defaultHost

    private let suggestions = ["柴犬 puppy", "kitten", "golden retriever", "portrait", "cat sleeping", "landscape"]

    private var groupChoices: [(key: String, label: String)] {
        [("", "轮换")]
            + CompanionArt.stateKeys.map { ($0, $0) }
            + CompanionMood.allCases.map { ($0.rawValue, $0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("背景图").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("完成") { onClose() }.controlSize(.small)
            }
            HStack(spacing: 6) {
                Picker("", selection: $kind) {
                    ForEach(CompanionArt.MediaKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                TextField("小狗 / kitten / portrait…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button(searching ? "搜索中…" : "搜索") { runSearch() }
                    .controlSize(.small)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                Text("存到").font(.system(size: 10)).foregroundColor(.secondary)
                Picker("", selection: $group) {
                    ForEach(groupChoices, id: \.key) { Text($0.label).tag($0.key) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 120)
                Spacer()
                if kind == .video && pexelsKey.isEmpty {
                    Text("视频要 Pexels key（免费）— 设置 → 陪伴模式")
                        .font(.system(size: 10)).foregroundColor(.orange)
                }
            }
            HStack(spacing: 5) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { query = s; runSearch() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                Spacer()
            }

            if !results.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                        ForEach(results) { c in
                            thumb(c)
                        }
                    }
                }
                .frame(height: 260)
                Text("点一张就存到 \(CompanionArt.folder.path)")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Divider().opacity(0.2)
            herRow

            Divider().opacity(0.2)
            makeRow

            Divider().opacity(0.2)
            HStack {
                Text("已有 \(art.count) 个")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("打开文件夹") { art.revealFolder() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.green)
            }
            Text("子文件夹按状态或情绪取名：idle / listening / thinking / speaking，开心 / 温柔 / 好奇 / 困 / 担心。小美每句话带情绪，说话时就换成那个文件夹里的图或视频；顶层的按时间轮换。mp4 / mov 循环播放。")
                .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { art.reload() }
        // The library grows in the background, a picture a minute; the picker
        // should show that happening rather than a count from when it opened.
        .onReceive(NotificationCenter.default.publisher(for: .kinclawCompanionArtGrew)) { _ in
            art.reload()
        }
    }

    private func thumb(_ c: CompanionArt.Candidate) -> some View {
        Button {
            kept.insert(c.id)
            Task { await art.download([c], theme: query, group: group) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: c.preview) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                if c.isVideo {
                    Label("\(c.seconds ?? 0)s", systemImage: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if kept.contains(c.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(4)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .help("\(c.title)\n\(c.credit)")
    }

    /// One woman, kept the same across every picture.
    ///
    /// Candidates are cheap (15s each) and the choice is permanent-ish, so
    /// the strip is the important part of this panel: it is the only moment
    /// anybody decides what she looks like. Everything after it is an edit of
    /// the one picture that gets adopted.
    @ViewBuilder
    private var herRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.square.badge.camera")
                    .font(.system(size: 10)).foregroundColor(.pink)
                Text("她是谁").font(.system(size: 11, weight: .medium))
                if let anchor = her.anchorURL,
                   let image = NSImage(contentsOf: anchor) {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .help("锚图：\(anchor.path)")
                }
                Spacer()
                TextField("名字", text: Binding(
                    get: { her.sheet.name },
                    set: { her.rename($0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(width: 70)
            }
            HStack(spacing: 6) {
                TextField("长什么样（英文）：mid-20s, long dark hair, soft features…",
                          text: $lookText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                Button(her.busy ? "忙…" : "画候选") {
                    her.makeCandidates(look: lookText.isEmpty ? her.sheet.look : lookText)
                }
                .controlSize(.small)
                .disabled(her.busy || (lookText.isEmpty && her.sheet.look.isEmpty))
            }
            if !her.candidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(her.candidates, id: \.path) { url in
                            if let image = NSImage(contentsOf: url) {
                                Button { her.adopt(url) } label: {
                                    Image(nsImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5)
                                            .stroke(her.anchorURL?.lastPathComponent == url.lastPathComponent
                                                    ? Color.pink : Color.clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .disabled(her.busy)
                                .help("点它定妆：过一次编辑，之后每张都是这张脸")
                            }
                        }
                    }
                }
                .frame(height: 58)
            }
            if her.sheet.isReady {
                HStack(spacing: 6) {
                    TextField("换个场景（英文指令）：she is in a sunny kitchen…", text: $sceneText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .onSubmit { putHer() }
                    Button("出场景") { putHer() }
                        .controlSize(.small)
                        .disabled(sceneText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("长一天") { her.growLibrary() }
                        .controlSize(.small)
                        .disabled(her.busy)
                        .help("按八个生活场景各出一张，填进对应情绪的文件夹（一张一分钟上下）")
                }
            }
            if let note = her.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundColor(note.contains("失败") || note.contains("先") ? .orange : .secondary)
                    .lineLimit(2).truncationMode(.middle)
            }
        }
    }

    private func putHer() {
        let instruction = sceneText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        let mood = group
        Task { _ = await her.scene(instruction, mood: mood.isEmpty ? nil : mood) }
    }

    /// Make one instead of finding one.
    ///
    /// Stock search answers "a photograph of a cafe"; a diffuser answers "her,
    /// in that cafe, in the afternoon". Same destination folder as the
    /// downloads, so the companion picks it up by mood the same way.
    @ViewBuilder
    private var makeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
                TextField("画一张：a quiet cafe in afternoon light…", text: $drawPrompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { draw() }
                Button(diffuser.busy ? "画中…" : "生成") { draw() }
                    .controlSize(.small)
                    .disabled(diffuser.busy || drawPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                // An mp4 in her folder is already a moving background, so a
                // clip needs nothing here that a picture does not.
                Button("拍 4 秒") { film() }
                    .controlSize(.small)
                    .disabled(drawPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("在视频服务上拍一段 4 秒的背景（\(DiffuserClient.videoHost)），几分钟")
            }
            if let job = diffuser.videoJobs.first {
                Text(job.line)
                    .font(.system(size: 10))
                    .foregroundColor(job.error != nil ? .orange : (job.done ? .green : .secondary))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                if let drawn {
                    // Straight to the picture, because the first thing anyone
                    // wants after "生成" is to look at it.
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([drawn])
                    } label: {
                        Label(drawn.lastPathComponent, systemImage: "photo")
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }
                if let drawNote {
                    Text(drawNote)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                Spacer()
                TextField("出图服务地址", text: $diffuserHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(width: 170)
                    .help("OllamaDiffuser 的地址，默认是盒子：\(DiffuserClient.defaultHost)")
            }
        }
    }

    /// Film one. The job announces itself in the row above; nothing here
    /// waits, because minutes.
    private func film() {
        let prompt = drawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let folder = group.isEmpty ? CompanionArt.folder
                                   : CompanionArt.folder.appendingPathComponent(group)
        _ = diffuser.startVideo(prompt: prompt, into: folder)
    }

    private func draw() {
        let prompt = drawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        drawNote = nil
        let folder = group.isEmpty ? CompanionArt.folder
                                   : CompanionArt.folder.appendingPathComponent(group)
        Task {
            do {
                let file = try await diffuser.generate(prompt: prompt, into: folder)
                drawn = file
                drawPrompt = ""
                art.reload()
            } catch {
                drawn = nil
                drawNote = error.localizedDescription
            }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            let r = await art.search(q, kind: kind)
            await MainActor.run {
                results = r
                searching = false
            }
        }
    }
}

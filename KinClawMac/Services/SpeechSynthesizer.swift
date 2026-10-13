import AVFoundation
import Speech

/// TTS: Server Kokoro first, fallback to iOS AVSpeechSynthesizer
class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var completion: (() -> Void)?
    /// Remaining clips for a multi-language reply, played back to back.
    /// Decoded and `prepareToPlay`ed the moment the audio arrives, so
    /// the handoff between two sentences is a `play()` call rather than
    /// a decode — and paired with the bytes they came from, because the
    /// lip sync needs the waveform at the moment playback starts, not
    /// at the moment synthesis finished. A clip can wait seconds in
    /// this queue behind the one before it.
    private var playQueue: [(player: AVAudioPlayer, clip: Data)] = []
    @Published var isSpeaking = false

    // MARK: Streaming state
    //
    // Waiting for a whole reply before saying a word is most of the gap
    // between this and a realtime voice assistant: the model streams
    // tokens for several seconds while the speaker sits silent, then
    // synthesis and playback start from zero. Streaming mode speaks each
    // sentence as it completes, so the first words land about a second
    // after the model starts writing instead of after it stops.
    //
    // Synthesis is serialized rather than parallel. Kokoro renders a
    // sentence in ~1s and a sentence takes ~3-6s to say, so one worker
    // stays comfortably ahead of playback, and serial order is the order
    // the sentences are spoken in — no reassembly, no clip arriving
    // before the one it follows.
    private var isStreamingReply = false
    private var streamHostname = ""
    private var pendingSentences: [String] = []
    private var synthesizing = false
    /// Bumped by every `stop()`, `speak()` and `beginStream()`. Synthesis
    /// awaits a network round-trip, and a reply can be stopped and a new
    /// one started while that is in flight; a result that comes back
    /// for an older generation is dropped rather than played into the
    /// reply that replaced it — which is how two answers ended up
    /// interleaved on the speaker.
    private var generation = 0
    /// A reply's opening sentence, played while the box is still making it
    /// (see `SentenceStream`). Only ever plays while no clip does.
    private let sentenceStream = SentenceStream()

    /// Handed every clip just before it plays, for anything that needs
    /// the audio itself rather than the fact of it — the digital
    /// human's lip sync reads the waveform to know what the mouth is
    /// doing. Called on the main actor with the same bytes that go to
    /// the speaker, at the same moment, so the two stay in step.
    var onClip: ((Data) -> Void)?
    /// Called when speech is cut off, so a mouth does not finish a
    /// sentence nobody is hearing.
    var onStopped: (() -> Void)?

    // MARK: Delayed playback (a face made from the voice, LiveFace)
    //
    // Her face on the box is made from each clip as it is handed over and
    // arrives a moment later, so the sound waits for it: every clip goes to
    // `onClip` when its turn on the push timeline comes and plays
    // `playbackDelay` later. The next clip is handed over when the last one's
    // push slot ends — not when it has finished playing, which would leave a
    // `playbackDelay` gap between sentences. Zero (the default) is the old
    // path, untouched.
    var playbackDelay: TimeInterval = 0
    /// Delayed playback: the push timeline ran out with nothing queued — the
    /// face can render the tail of what it has.
    var onDrained: (() -> Void)?
    private var scheduled: [AVAudioPlayer] = []
    private var pushUntil = Date.distantPast
    private var pushTimer: Timer?
    private var pushing: Bool { Date() < pushUntil }

    override init() {
        super.init()
        // Learn what the TTS server can do before the first reply needs it:
        // whether its voices are multilingual decides how text is split.
        Task { @MainActor in await TTSVoices.shared.refresh() }
        synthesizer.delegate = self
        // A streamed sentence reaches the lip sync piece by piece, each as
        // it starts playing, the way a clip does.
        sentenceStream.onPiece = { [weak self] wav in self?.onClip?(wav) }
        sentenceStream.onFinished = { [weak self] in self?.streamedSentenceDidFinish() }
    }

    /// Open a streaming reply: sentences enqueued with `stream(_:)` are
    /// spoken as they arrive, and `endStream()` closes it. `onComplete`
    /// fires once the last clip has played, matching `speak`.
    func beginStream(hostname: String, onComplete: @escaping () -> Void) {
        stop()
        completion = onComplete
        isStreamingReply = true
        streamHostname = hostname
        isSpeaking = true
        generation += 1
    }

    /// Hand one finished sentence to the speaker; they queue in order.
    func stream(_ sentence: String) {
        let t = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isStreamingReply, !t.isEmpty else { return }
        pendingSentences.append(t)
        pumpStream()
    }

    /// No more sentences are coming. Completion fires when the queue
    /// drains; if nothing was ever spoken it fires now.
    func endStream() {
        guard isStreamingReply else { return }
        isStreamingReply = false
        finishStreamIfDrained()
    }

    /// True while a streamed reply is still accepting sentences.
    var isStreamOpen: Bool { isStreamingReply }

    /// Synthesize the next sentence, one at a time, appending to the play
    /// queue and starting playback if nothing is playing.
    private func pumpStream() {
        guard !synthesizing, !pendingSentences.isEmpty else { return }
        synthesizing = true
        let sentence = pendingSentences.removeFirst()
        let hostname = streamHostname
        let gen = generation
        Task { @MainActor in
            defer {
                self.synthesizing = false
                self.pumpStream()
                self.finishStreamIfDrained()
            }
            let isLocal = hostname == "localhost-kinclaw" || hostname.hasPrefix("localhost")
            let pref = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
            let preferred = (pref == "auto" || pref.isEmpty) ? "" : pref
            let segments: [TextSegmenter.Segment]
            if isLocal {
                segments = Self.localSegments(sentence, preferredVoice: preferred)
            } else {
                let cleaned = TextSegmenter.stripNonSpeakable(sentence)
                segments = cleaned.isEmpty ? []
                    : [TextSegmenter.Segment(text: cleaned, voice: self.pickServerVoice(forText: sentence))]
            }
            for seg in segments {
                // A sentence dropped mid-flight (the user barged in, or the
                // turn was cancelled) must not resurface as audio — not
                // even inside the next reply, which is what checking
                // `isSpeaking` alone allowed.
                guard self.isSpeaking, self.generation == gen else { return }
                if let streamed = self.streamRequest(seg, isLocal: isLocal),
                   await self.sentenceStream.play(streamed.request, base: streamed.base) {
                    continue
                }
                if let data = await self.synthesizeSegment(seg, isLocal: isLocal, hostname: hostname),
                   self.generation == gen,
                   let player = self.preparedPlayer(data) {
                    self.playQueue.append((player, data))
                    let free = self.playbackDelay > 0 ? !self.pushing
                        : self.audioPlayer?.isPlaying != true && !self.sentenceStream.isActive
                    if free {
                        _ = self.playNextClip()
                    }
                }
            }
        }
    }

    /// Completion fires only when the stream is closed AND nothing is left
    /// to synthesize or play. An empty queue mid-generation just means the
    /// model is still writing.
    private func finishStreamIfDrained() {
        guard !isStreamingReply, !synthesizing,
              pendingSentences.isEmpty, playQueue.isEmpty,
              audioPlayer?.isPlaying != true, scheduled.isEmpty, !pushing,
              !sentenceStream.isActive else { return }
        isSpeaking = false
        let done = completion
        completion = nil
        done?()
    }

    /// The request that streams `segment`, or nil to make it whole.
    ///
    /// Only while nothing is playing: that is the reply's first sentence (or
    /// one the model was slow to write), the one someone is waiting on.
    /// Later sentences are made while earlier ones play, so streaming them
    /// gains nothing. Only from a server with one voice for every language —
    /// the box's Qwen3-TTS — at normal speed, and never for a face made from
    /// the voice: LiveFace works on whole clips.
    private func streamRequest(_ segment: TextSegmenter.Segment, isLocal: Bool) -> (request: URLRequest, base: String)? {
        guard isLocal, TTSVoices.multilingual, playbackDelay == 0,
              playQueue.isEmpty, audioPlayer?.isPlaying != true, !sentenceStream.isActive,
              !MediaPlacement.place(.voice).isCloud else { return nil }
        let speed = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")
        guard speed <= 0 || speed == 1 else { return nil }
        let base = Self.localTTSBase
        guard SentenceStream.supported(base),
              let url = URL(string: "\(base)/v1/audio/speech") else { return nil }

        // OpenAI's speech request; `pcm` is 16-bit mono at 24 kHz.
        struct SpeechRequest: Codable {
            let input: String
            let voice: String
            let response_format: String
            let stream_format: String
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(SpeechRequest(
            input: segment.text, voice: segment.voice,
            response_format: "pcm", stream_format: "audio"))
        return (request, base)
    }

    /// A streamed sentence has been heard to the end: on to the next clip,
    /// as when a clip's player finishes.
    private func streamedSentenceDidFinish() {
        if !playQueue.isEmpty, playNextClip() { return }
        finishStreamIfDrained()
    }

    /// The local TTS server (Settings → Backend → TTS).
    private static var localTTSBase: String {
        let pref = UserDefaults.standard.string(forKey: "kinclaw.backend.tts") ?? ""
        return pref.isEmpty
            ? "http://localhost:8001"
            : pref.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Speak text: try server TTS first, fallback to iOS native
    func speak(_ text: String, hostname: String = "", onComplete: @escaping () -> Void) {
        stop()
        completion = onComplete
        isSpeaking = true
        generation += 1

        // Configure audio session (iOS only — macOS routes audio without it)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        // Try server TTS first if hostname available
        if !hostname.isEmpty {
            let gen = generation
            Task { @MainActor in
                let success = await self.serverTTS(text: text, hostname: hostname, gen: gen)
                // Stopped while synthesizing: nothing to fall back to.
                guard self.generation == gen else { return }
                if !success {
                    self.localTTS(text: text)
                }
            }
        } else {
            localTTS(text: text)
        }
    }

    /// Server TTS — local agents hit Kokoro directly, cloud agents
    /// go through the LocalKin gateway. We're a native Mac app, so
    /// we don't need the CORS proxy that the browser-served
    /// kinclaw web UI uses (kinclaw kernel's /api/voice/tts just
    /// forwards to TTS_ENDPOINT/synthesize anyway). Direct = one
    /// fewer hop, simpler config.
    private func serverTTS(text: String, hostname: String, gen: Int) async -> Bool {
        let isLocal = hostname == "localhost-kinclaw"
            || hostname.hasPrefix("localhost")

        // Split mixed-language replies so each run is spoken by a voice that
        // can actually pronounce it. Local Kokoro needs this done client-side
        // — one request carries one speaker. The cloud gateway does its own
        // handling, so it still gets the whole text in a single call (just
        // cleaned of markdown and emoji, which it does not strip).
        let pref = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        let preferred = (pref == "auto" || pref.isEmpty) ? "" : pref
        let segments: [TextSegmenter.Segment]
        if isLocal {
            segments = Self.localSegments(text, preferredVoice: preferred)
        } else {
            let cleaned = TextSegmenter.stripNonSpeakable(text)
            segments = cleaned.isEmpty
                ? []
                : [TextSegmenter.Segment(text: cleaned, voice: pickServerVoice(forText: text))]
        }
        guard !segments.isEmpty else { return false }

        // Synthesize concurrently but keep order — Kokoro handles parallel
        // requests fine, and a reply that alternates languages several times
        // would otherwise pay the full round-trip once per run.
        var clips = [Data?](repeating: nil, count: segments.count)
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (i, seg) in segments.enumerated() {
                group.addTask {
                    (i, await self.synthesizeSegment(seg, isLocal: isLocal, hostname: hostname))
                }
            }
            for await (i, data) in group { clips[i] = data }
        }

        // Stopped while the clips were being made: they belong to a reply
        // nobody wants any more. Report success so the caller does not
        // read it out with the system voice instead.
        guard generation == gen, isSpeaking else { return true }

        // All-or-nothing: a half-spoken reply is worse than falling back to
        // the system voice, which at least reads the whole thing.
        let ordered = clips.compactMap { $0 }
        guard ordered.count == segments.count else { return false }

        let prepared = ordered.compactMap { data -> (AVAudioPlayer, Data)? in
            guard let p = preparedPlayer(data) else { return nil }
            return (p, data)
        }
        guard prepared.count == ordered.count else { return false }
        playQueue = prepared
        return playNextClip()
    }

    /// Decode one clip and get it ready to start on the next `play()`.
    private func preparedPlayer(_ data: Data) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        player.prepareToPlay()
        return player
    }

    /// Warm the synthesis path before the first reply needs it.
    ///
    /// Kokoro loads each language's G2P and each voice's embedding on
    /// first use: measured here, the first Chinese sentence after idle
    /// took 3.4s and the first English one 2.4s, against 0.5s once warm.
    /// In a conversation that is the opening line arriving late, every
    /// time. Two tiny throwaway requests on entering voice mode move
    /// that cost to before anyone is waiting on it.
    func prewarm(hostname: String) {
        let isLocal = hostname == "localhost-kinclaw" || hostname.hasPrefix("localhost")
        guard isLocal, !isSpeaking else { return }
        let pref = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        let preferred = (pref == "auto" || pref.isEmpty) ? "" : pref
        Task { @MainActor in await TTSVoices.shared.refresh() }
        // One voice reads everything on a multilingual server; Kokoro needs
        // both its Chinese and English voice warm.
        let warm = TTSVoices.multilingual
            ? Self.localSegments("嗯。", preferredVoice: preferred)
            : Self.localSegments("嗯。", preferredVoice: preferred) + Self.localSegments("Hi.", preferredVoice: preferred)
        for seg in warm {
            Task.detached(priority: .utility) {
                _ = await self.synthesizeSegment(seg, isLocal: true, hostname: hostname)
            }
        }
    }

    /// A short line in the voice replies are spoken in, as a WAV, without
    /// playing it — the companion's 嗯 while the user talks, played on its own
    /// so that it is not a reply: nothing waits for it and nothing arms the
    /// barge-in. Nil when it cannot be made.
    func clip(_ text: String, hostname: String) async -> Data? {
        let isLocal = hostname == "localhost-kinclaw" || hostname.hasPrefix("localhost")
        let pref = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        let preferred = (pref == "auto" || pref.isEmpty) ? "" : pref
        let segments = isLocal
            ? Self.localSegments(text, preferredVoice: preferred)
            : [TextSegmenter.Segment(text: text, voice: pickServerVoice(forText: text))]
        guard let first = segments.first else { return nil }
        return await synthesizeSegment(first, isLocal: isLocal, hostname: hostname)
    }

    /// One segment → one WAV. Returns nil on any failure so the caller can
    /// fall back wholesale.
    private func synthesizeSegment(
        _ segment: TextSegmenter.Segment,
        isLocal: Bool,
        hostname: String
    ) async -> Data? {
        // 声音 placed on a cloud API (Settings → 画·改·拍·声音): a local
        // soul's words go there, in the voice chosen for that provider — the
        // box's speaker names mean nothing to it. A failure falls back like
        // any other.
        let voicePlace = MediaPlacement.place(.voice)
        if isLocal, voicePlace.isCloud {
            guard let data = try? await MediaCloud.speak(segment.text, on: voicePlace) else { return nil }
            return WAVTrim.trim(data)
        }
        do {
            // Route to Kokoro directly when the agent is a local
            // soul (hostname marker is "localhost-kinclaw" — see
            // Soul.asAgent). User can override the Kokoro endpoint
            // via Settings → Backend → TTS (defaults to
            // http://localhost:8001).
            let url: URL
            if isLocal {
                url = URL(string: "\(Self.localTTSBase)/synthesize")!
            } else {
                url = URL(string: "https://\(hostname)/v1/tts")!
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            // Cloud path needs Bearer auth; local Kokoro on loopback
            // doesn't (no auth layer).
            if !isLocal {
                let token = await TokenManager.shared.token(for: hostname)
                request.setValue("Bearer \(token)",
                                 forHTTPHeaderField: "Authorization")
            }

            // Field names are not interchangeable between the two backends,
            // and getting them wrong fails silently — the server answers 200
            // and returns audio, just in the wrong voice.
            //
            // Local Kokoro (`/synthesize`) reads `speaker` and `language`.
            // Sending `voice` meant it never saw a speaker at all and fell
            // back to an English default, which pronounces Chinese by naming
            // the characters: 「施舍是信仰的试金石」came back as "Chinese
            // letter, Chinese letter, Chinese letter…" (verified by feeding
            // the audio back through SenseVoice). The same request with
            // `speaker`+`language` transcribes cleanly — and is a third of the
            // size, because it stops narrating every glyph.
            //
            // The cloud gateway (`/v1/tts`) keeps the `voice`/`speed` shape.
            struct KokoroRequest: Codable {
                let text: String
                let speaker: String
                let language: String
                let speed: Double
            }
            struct GatewayTTSRequest: Codable {
                let text: String
                let voice: String?
                let speed: Double?
            }
            // The voice comes from the segmenter, which already accounted for
            // the user's speaker preference and the language of this
            // particular run — so a Chinese reply quoting an English term
            // gets two requests with two speakers, not one compromise voice.
            let voice = segment.voice
            let speed = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")

            if isLocal {
                // Kokoro wants a bare language tag, not a locale: "zh", not
                // "zh-CN". Derive it from the voice prefix so it can never
                // disagree with the speaker being sent alongside it.
                // A multilingual server gets no language: its voices aren't
                // named by language ("vivian"), and deriving one from the
                // prefix would read Chinese as English. It detects from the text.
                request.httpBody = try JSONEncoder().encode(KokoroRequest(
                    text: segment.text,
                    speaker: voice,
                    language: TTSVoices.multilingual ? "" : TextSegmenter.language(forVoice: voice),
                    speed: speed > 0 ? speed : 1.0
                ))
            } else {
                request.httpBody = try JSONEncoder().encode(GatewayTTSRequest(
                    text: segment.text,
                    voice: voice,
                    speed: speed > 0 ? speed : nil
                ))
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 44 else {  // WAV header is 44 bytes minimum
                return nil
            }
            // Kokoro pads ~0.4s in front and ~0.7s behind every clip.
            // Between streamed sentences that is a hole, not a pause.
            return WAVTrim.trim(data)
        } catch {
            return nil
        }
    }

    /// Pop the next clip off the queue and play it. Returns false if the clip
    /// can't be decoded, so the caller can fall back to the system voice.
    @discardableResult
    private func playNextClip() -> Bool {
        guard !playQueue.isEmpty else { return false }
        if playbackDelay > 0 { return pushNextClip() }
        let (player, clip) = playQueue.removeFirst()
        player.delegate = self
        audioPlayer = player
        // The mouth is told at the same instant the speaker starts.
        onClip?(clip)
        guard player.play() else {
            playQueue.removeAll()
            return false
        }
        return true
    }

    /// Delayed playback: hand the clip over now, play it `playbackDelay` later,
    /// and hand the next one over when this one's slot ends.
    private func pushNextClip() -> Bool {
        let (player, clip) = playQueue.removeFirst()
        player.delegate = self
        audioPlayer = player
        onClip?(clip)
        guard player.play(atTime: player.deviceCurrentTime + playbackDelay) else {
            playQueue.removeAll()
            return false
        }
        scheduled.append(player)
        let slot = player.duration
        pushUntil = Date().addingTimeInterval(slot)
        pushTimer?.invalidate()
        pushTimer = Timer.scheduledTimer(withTimeInterval: slot, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.playQueue.isEmpty {
                _ = self.pushNextClip()
            } else {
                self.onDrained?()
                self.finishStreamIfDrained()
            }
        }
        return true
    }

    /// Local iOS TTS fallback
    private func localTTS(text: String) {
        // Same cleaning as the server path. The old inline version handled
        // four markdown markers and nothing else, so emoji reached the system
        // voice and got announced by name ("sparkles", "check mark").
        let cleaned = TextSegmenter.stripNonSpeakable(text)

        let utterance = AVSpeechUtterance(string: cleaned)

        // Pick voice — honor user's lang pref, else majority detection.
        let langCode = detectLanguage(cleaned)
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)

        // Apply user's speed pref (Settings → Voice).
        let speedPref = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")
        let multiplier = speedPref > 0 ? speedPref : 0.9
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(multiplier)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        scheduled.forEach { $0.stop() }
        scheduled.removeAll()
        pushTimer?.invalidate()
        pushTimer = nil
        pushUntil = .distantPast
        playQueue.removeAll()   // else a barged-in reply resumes mid-sentence
        sentenceStream.stop()
        onStopped?()
        isStreamingReply = false
        pendingSentences.removeAll()
        isSpeaking = false
        completion = nil
        generation += 1
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.completion?()
            self?.completion = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.completion?()
            self?.completion = nil
        }
    }

    // MARK: - Language Detection

    /// Decide what BCP-47 language code to feed AVSpeechSynthesizer.
    ///
    /// Priority:
    ///   1. User's explicit Settings → General → Language pref
    ///      ("zh" / "en" / "auto"). Wins over text-content guess.
    ///   2. Majority CJK vs Latin character count. Was previously
    ///      "ANY CJK char → all-Chinese voice", which mangled
    ///      English replies that happened to mention a single
    ///      Chinese brand name or punctuation mark.
    private func detectLanguage(_ text: String) -> String {
        let pref = UserDefaults.standard.string(forKey: "kinclaw.lang") ?? "auto"
        if pref == "zh" { return "zh-CN" }
        if pref == "en" { return "en-US" }

        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // CJK Unified Ideographs main block
            if (0x4E00...0x9FFF).contains(v)
                || (0x3040...0x30FF).contains(v)   // hiragana / katakana
                || (0xAC00...0xD7AF).contains(v) { // hangul
                cjk += 1
            } else if (0x0041...0x005A).contains(v)
                   || (0x0061...0x007A).contains(v) {
                latin += 1
            }
        }
        if cjk == 0 { return "en-US" }
        if latin == 0 { return "zh-CN" }
        // Mixed — pick the majority. CJK chars carry more "weight"
        // per unit since each is a full word, not a letter; bias
        // toward CJK at 0.5x ratio.
        return Double(cjk) >= Double(latin) * 0.3 ? "zh-CN" : "en-US"
    }

    /// Text for the local TTS server as (text, voice) runs. Kokoro voices speak
    /// one language, so mixed text is split between voices; a multilingual
    /// server (Qwen3-TTS) reads the whole sentence in one voice — splitting it
    /// there switched voice mid-sentence and broke the intonation.
    static func localSegments(_ text: String, preferredVoice: String) -> [TextSegmenter.Segment] {
        guard TTSVoices.multilingual else {
            return TextSegmenter.splitByLang(text, preferredVoice: preferredVoice)
        }
        let cleaned = TextSegmenter.stripNonSpeakable(text)
        return cleaned.isEmpty ? [] : [TextSegmenter.Segment(text: cleaned, voice: preferredVoice)]
    }

    /// Pick a Kokoro / server TTS voice based on detected language
    /// and the user's preferred speaker (Settings → Voice → Voice).
    /// "auto" → use language-appropriate default; explicit speaker
    /// → use it as-is regardless of language.
    private func pickServerVoice(forText text: String) -> String {
        let pref = UserDefaults.standard.string(forKey: "kinclaw.voice.tts.speaker") ?? "auto"
        if pref != "auto" && !pref.isEmpty {
            return pref
        }
        let lang = detectLanguage(text)
        if lang.hasPrefix("zh") {
            return "zf_xiaoxiao"   // Chinese female default
        }
        return "af_bella"          // English female default
    }
}

// MARK: - AVAudioPlayerDelegate
extension SpeechSynthesizer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Delayed playback: the push timeline starts the next clips; done
            // is when the last scheduled one has played and nothing is coming.
            if self.playbackDelay > 0 {
                self.scheduled.removeAll { $0 === player }
                guard self.scheduled.isEmpty, self.playQueue.isEmpty, !self.pushing else { return }
                self.audioPlayer = nil
                if self.isStreamingReply || self.synthesizing || !self.pendingSentences.isEmpty {
                    self.finishStreamIfDrained()
                    return
                }
                self.isSpeaking = false
                self.completion?()
                self.completion = nil
                return
            }
            // A mixed-language reply is several clips; only report "done"
            // after the last one, or voice mode would start listening again
            // while the English half is still queued.
            if !self.playQueue.isEmpty, self.playNextClip() { return }
            self.audioPlayer = nil
            // While a stream is open an empty queue means "the model is
            // still writing", not "the reply is over". Reporting done here
            // would reopen the mic in the middle of an answer.
            if self.isStreamingReply || self.synthesizing || !self.pendingSentences.isEmpty {
                self.finishStreamIfDrained()
                return
            }
            self.isSpeaking = false
            self.completion?()
            self.completion = nil
        }
    }
}

// MARK: - A sentence played while it is made

/// Plays one sentence while the TTS server is still making it.
///
/// `/synthesize` answers once the whole sentence exists: measured on the box
/// (Qwen3-TTS 0.6B, a 3-4 s sentence), 0.7-0.8 s of silence at the start of
/// every reply. `/v1/audio/speech` with `stream_format: audio` sends the same
/// speech as 16-bit 24 kHz PCM while it is made, the first half second after
/// 0.13-0.2 s. The pieces go to an AVAudioPlayerNode, which plays buffers back
/// to back without a gap; an AVAudioPlayer per piece would leave a hole at
/// every join.
///
/// The lip sync still gets clips: each piece goes to `onPiece` as a WAV the
/// moment it starts playing. Silence is trimmed as `WAVTrim` trims a clip (the
/// box pads 0.25-0.45 s at each end) by holding back trailing silence until
/// sound follows it or the sentence ends. Sound itself is never held back.
///
/// Main thread, apart from the download loop in `play`.
final class SentenceStream {
    static let rate = 24_000
    private static let leadKeep = rate * 60 / 1000      // as WAVTrim keeps
    private static let trailKeep = rate * 160 / 1000
    private static let pieceBytes = rate                // half a second at 16 bits
    private static let threshold = Int16(0.01 * 32767)
    /// Servers that turned `/v1/audio/speech` streaming down (an older
    /// LocalKin, another TTS server): not asked again this run.
    private static var unsupported = Set<String>()

    var onPiece: ((Data) -> Void)?
    var onFinished: (() -> Void)?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(SentenceStream.rate), channels: 1)!
    private var session = 0
    private var task: URLSessionDataTask?
    private var downloading = false
    private var playing = 0             // buffers scheduled and not yet heard
    private var waiting: [Data] = []    // their WAVs, after the one playing
    private var heardSound = false      // past the leading silence
    private var lead: [Int16] = []      // the end of the leading silence
    private var held: [Int16] = []      // silence that may be the closing one
    private var endsAt = Date.distantPast
    private var watchdog: Timer?
    private var observer: NSObjectProtocol?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        // A change of output device stops the engine, and with it the
        // callbacks that say a buffer was heard: end the sentence rather
        // than wait on them.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.abandon() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Downloading, or still playing what it downloaded.
    var isActive: Bool { downloading || playing > 0 }

    static func supported(_ base: String) -> Bool { !unsupported.contains(base) }

    /// Play the answer to `request` as it arrives. True when the sentence was
    /// dealt with, heard or stopped on purpose; false when nothing could be
    /// played and the caller should make it whole instead.
    func play(_ request: URLRequest, base: String) async -> Bool {
        guard let mine = await MainActor.run(body: { self.begin() }) else { return false }
        var completed = false
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let dataTask = bytes.task
            guard await MainActor.run(body: { self.attach(dataTask, mine) }) else { return true }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
            if status == 200, type.hasPrefix("audio/pcm") {
                var chunk = Data()
                chunk.reserveCapacity(Self.pieceBytes)
                for try await byte in bytes {
                    chunk.append(byte)
                    guard chunk.count >= Self.pieceBytes else { continue }
                    let piece = chunk
                    chunk.removeAll(keepingCapacity: true)
                    guard await MainActor.run(body: { self.take(piece, mine) }) else { return true }
                }
                let rest = chunk
                completed = await MainActor.run { self.take(rest, mine) }
            } else if status == 200 || (400..<500).contains(status) {
                // Answered, but not with a stream: it doesn't do this one.
                await MainActor.run { _ = Self.unsupported.insert(base) }
            }
        } catch {}
        let done = completed
        return await MainActor.run { self.end(mine, completed: done) }
    }

    /// Stop now: drop what is scheduled and cancel the download.
    func stop() {
        session += 1
        task?.cancel()
        task = nil
        watchdog?.invalidate()
        watchdog = nil
        node.stop()
        if engine.isRunning { engine.stop() }
        downloading = false
        playing = 0
        waiting.removeAll()
        lead.removeAll()
        held.removeAll()
    }

    private func begin() -> Int? {
        stop()
        do {
            try engine.start()
        } catch {
            return nil
        }
        node.play()
        heardSound = false
        endsAt = .distantPast
        downloading = true
        return session
    }

    private func attach(_ task: URLSessionDataTask, _ mine: Int) -> Bool {
        guard mine == session else {
            task.cancel()
            return false
        }
        self.task = task
        return true
    }

    /// Audio from the download: schedule what is sound, hold what may be the
    /// closing silence. False once the sentence has been stopped.
    private func take(_ data: Data, _ mine: Int) -> Bool {
        guard mine == session else { return false }
        var samples = Self.samples(data)
        if !heardSound {
            guard let first = samples.firstIndex(where: Self.loud) else {
                lead = Array((lead + samples).suffix(Self.leadKeep))
                return true
            }
            samples = Array((lead + samples[..<first]).suffix(Self.leadKeep)) + samples[first...]
            lead.removeAll()
            heardSound = true
        }
        let all = held + samples
        if let last = all.lastIndex(where: Self.loud) {
            schedule(Array(all[...last]), mine)
            held = Array(all[(last + 1)...])
        } else {
            held = all
        }
        return true
    }

    private func end(_ mine: Int, completed: Bool) -> Bool {
        guard mine == session else { return true }
        task = nil
        downloading = false
        // Nothing was ever heard: a failure to fall back from, or silence.
        guard heardSound else {
            stop()
            return completed
        }
        if completed {
            schedule(Array(held.prefix(Self.trailKeep)), mine)
        }
        held.removeAll()
        // The callbacks that say a buffer was heard stop if the engine does;
        // don't let a reply wait on them past the end of its audio.
        watchdog = Timer.scheduledTimer(
            withTimeInterval: max(0, endsAt.timeIntervalSinceNow) + 1.5, repeats: false
        ) { [weak self] _ in
            guard let self, mine == self.session, self.playing > 0 else { return }
            self.abandon()
        }
        finishIfDone(mine)
        return true
    }

    private func schedule(_ samples: [Int16], _ mine: Int) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let out = buffer.floatChannelData![0]
        for i in samples.indices { out[i] = Float(samples[i]) / 32768 }
        let wav = Self.wav(samples)
        // An idle node plays a buffer the moment it is scheduled.
        if playing == 0 { onPiece?(wav) } else { waiting.append(wav) }
        playing += 1
        endsAt = max(endsAt, Date()).addingTimeInterval(Double(samples.count) / Double(Self.rate))
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.heard(mine) }
        }
    }

    /// A buffer has been heard, so the next one is starting.
    private func heard(_ mine: Int) {
        guard mine == session, playing > 0 else { return }
        playing -= 1
        if !waiting.isEmpty { onPiece?(waiting.removeFirst()) }
        finishIfDone(mine)
    }

    private func finishIfDone(_ mine: Int) {
        guard mine == session, !downloading, playing == 0 else { return }
        stop()
        onFinished?()
    }

    /// Playback stopped under the sentence: call it over.
    private func abandon() {
        guard isActive else { return }
        stop()
        onFinished?()
    }

    private static func loud(_ sample: Int16) -> Bool {
        sample > threshold || sample < -threshold
    }

    private static func samples(_ data: Data) -> [Int16] {
        data.withUnsafeBytes { raw in
            (0..<raw.count / 2).map {
                Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self))
            }
        }
    }

    /// 16-bit mono WAV, the shape the lip sync reads.
    static func wav(_ samples: [Int16]) -> Data {
        var out = Data(capacity: 44 + samples.count * 2)
        func text(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { out.append(contentsOf: $0) } }
        text("RIFF"); u32(36 + samples.count * 2); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        text("data"); u32(samples.count * 2)
        for s in samples { u16(Int(UInt16(bitPattern: s))) }
        return out
    }
}

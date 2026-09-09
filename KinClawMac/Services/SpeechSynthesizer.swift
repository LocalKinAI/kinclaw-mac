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

    /// Handed every clip just before it plays, for anything that needs
    /// the audio itself rather than the fact of it — the digital
    /// human's lip sync reads the waveform to know what the mouth is
    /// doing. Called on the main actor with the same bytes that go to
    /// the speaker, at the same moment, so the two stay in step.
    var onClip: ((Data) -> Void)?
    /// Called when speech is cut off, so a mouth does not finish a
    /// sentence nobody is hearing.
    var onStopped: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
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
                segments = TextSegmenter.splitByLang(sentence, preferredVoice: preferred)
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
                if let data = await self.synthesizeSegment(seg, isLocal: isLocal, hostname: hostname),
                   self.generation == gen,
                   let player = self.preparedPlayer(data) {
                    self.playQueue.append((player, data))
                    if self.audioPlayer?.isPlaying != true {
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
              audioPlayer?.isPlaying != true else { return }
        isSpeaking = false
        let done = completion
        completion = nil
        done?()
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
            segments = TextSegmenter.splitByLang(text, preferredVoice: preferred)
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
        let zh = TextSegmenter.splitByLang("嗯。", preferredVoice: preferred)
        let en = TextSegmenter.splitByLang("Hi.", preferredVoice: preferred)
        for seg in zh + en {
            Task.detached(priority: .utility) {
                _ = await self.synthesizeSegment(seg, isLocal: true, hostname: hostname)
            }
        }
    }

    /// One segment → one WAV. Returns nil on any failure so the caller can
    /// fall back wholesale.
    private func synthesizeSegment(
        _ segment: TextSegmenter.Segment,
        isLocal: Bool,
        hostname: String
    ) async -> Data? {
        do {
            // Route to Kokoro directly when the agent is a local
            // soul (hostname marker is "localhost-kinclaw" — see
            // Soul.asAgent). User can override the Kokoro endpoint
            // via Settings → Backend → TTS (defaults to
            // http://localhost:8001).
            let url: URL
            if isLocal {
                let prefBase = UserDefaults.standard.string(
                    forKey: "kinclaw.backend.tts") ?? ""
                let base = prefBase.isEmpty
                    ? "http://localhost:8001"
                    : prefBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                url = URL(string: "\(base)/synthesize")!
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
                request.httpBody = try JSONEncoder().encode(KokoroRequest(
                    text: segment.text,
                    speaker: voice,
                    language: TextSegmenter.language(forVoice: voice),
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
        playQueue.removeAll()   // else a barged-in reply resumes mid-sentence
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

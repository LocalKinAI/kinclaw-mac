import AVFoundation
import Speech

/// STT: Record audio → server SenseVoice first, fallback to iOS SFSpeechRecognizer
class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var error: String?
    /// Normalized audio level 0...1 — UI binds to this for the
    /// recording waveform / level bar. Updated at 10Hz from the
    /// silence-detection timer; smoothed via a small EMA so the
    /// bars don't jitter on tiny mic noise.
    @Published var audioLevel: Double = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var silenceTimer: Timer?
    private var maxTimer: Timer?
    private var storedHostname: String = ""
    private var hasSpeechStarted = false

    var onTranscript: ((String) -> Void)?
    var onNoSpeech: (() -> Void)?  // Called when no speech detected, for voice mode loop

    /// Start recording audio
    func startRecording(hostname: String = "") {
        error = nil
        transcript = ""
        storedHostname = hostname
        hasSpeechStarted = false

        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.beginRecording()
                } else {
                    self?.error = "Microphone permission denied"
                    self?.onNoSpeech?()
                }
            }
        }
        #elseif os(macOS)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.beginRecording()
                } else {
                    self?.error = "Microphone permission denied"
                    self?.onNoSpeech?()
                }
            }
        }
        #endif
    }

    /// Stop recording and transcribe
    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxTimer?.invalidate()
        maxTimer = nil
        audioRecorder?.stop()

        guard isRecording else { return }
        isRecording = false
        audioLevel = 0

        guard let url = recordingURL else {
            onNoSpeech?()
            return
        }

        // Don't transcribe silence.
        //
        // The detector already knows whether anything crossed the speech
        // threshold, and that answer was being thrown away — every recording
        // went to STT, including the ones that stopped precisely *because*
        // nobody spoke. Speech models don't return empty for empty input; they
        // return their most likely utterance, so two seconds of room tone came
        // back as "I." and got sent to the agent as if the user had said it.
        //
        // In hands-free mode this is not a cosmetic problem: the mic reopens
        // after every reply, so an empty room can hold a conversation with
        // itself indefinitely.
        guard hasSpeechStarted else {
            onNoSpeech?()
            return
        }

        isTranscribing = true

        Task { @MainActor in
            let text = await self.transcribe(audioURL: url, hostname: self.storedHostname)
            self.isTranscribing = false
            if let text = text,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !Self.isLikelyHallucination(text) {
                self.transcript = text
                self.onTranscript?(text)
            } else {
                // No speech detected — notify so voice mode can restart
                self.onNoSpeech?()
            }
        }
    }

    /// Phrases speech models emit when handed something that isn't speech.
    ///
    /// Backstop behind the `hasSpeechStarted` gate, for audio that does cross
    /// the threshold without being speech — a door, a cough, a chair. Trained
    /// on subtitle corpora, these models fall back to what those corpora are
    /// full of: sign-offs and channel outros.
    ///
    /// Kept deliberately small and exact-match-only. Anything broader starts
    /// eating real utterances, and dropping something the user actually said
    /// is worse than letting one stray "I." through — they can see the
    /// mistake and repeat themselves, but silently discarded speech just looks
    /// like the mic is broken. "ok" / "okay" / "嗯" are excluded for that
    /// reason despite being common hallucinations: they're also common replies.
    private static let hallucinationPhrases: Set<String> = [
        "i", "you", "the", "bye",
        "thank you", "thanks", "thank you very much",
        "thanks for watching", "thank you for watching",
        "谢谢观看", "谢谢大家", "请不吝点赞订阅",
        "字幕由amara.org社区提供", "字幕志愿者",
    ]

    static func isLikelyHallucination(_ text: String) -> Bool {
        let stripped = text.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !stripped.isEmpty else { return true }
        return hallucinationPhrases.contains(where: {
            $0.filter { $0.isLetter || $0.isNumber } == stripped
        })
    }

    func cancelRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxTimer?.invalidate()
        maxTimer = nil
        audioRecorder?.stop()
        isRecording = false
        isTranscribing = false
        audioLevel = 0
    }

    // MARK: - Private

    private func beginRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            self.error = "Audio session error"
            onNoSpeech?()
            return
        }
        #endif
        // macOS: AVAudioRecorder works without an explicit AVAudioSession.

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("stt_recording_\(Int(Date().timeIntervalSince1970)).wav")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            startSilenceDetection()
        } catch {
            self.error = "Failed to start recording"
            onNoSpeech?()
        }
    }

    private func startSilenceDetection() {
        var silenceCount = 0

        // Recording used to overrun to the 15s safety timer instead of
        // stopping 0.5s after the user finished talking. Measured on this
        // machine rather than guessed: room tone averages -40.5 dBFS but
        // *peaks* at -32.0. The old test was `avgPower > -35` against a
        // hardcoded constant, and a hit reset `silenceCount` to zero. So the
        // average sat safely below the line while stray peaks crossed it every
        // few ticks — each one wiping the counter before it could reach 5.
        // Silence was detected constantly and never accumulated.
        //
        // Two fixes, because either alone is fragile:
        //
        //   1. Put the line where the room is, not where a constant guessed.
        //      Sample the first 0.4s (user hasn't started talking yet) and set
        //      the threshold 12 dB above it — here that's ≈-28, clear of the
        //      -32 peaks. Clamped both ways: a silent room shouldn't make a
        //      keyboard tap read as speech, a loud one shouldn't need
        //      shouting.
        //   2. Decay the counter instead of resetting it (below), so one
        //      stray peak can't undo half a second of accumulated silence.
        var calibration: [Float] = []
        var speechThreshold: Float = -35
        let calibrationTicks = 5

        // Settings → Voice exposes this as a slider. It used to write to
        // `kinclaw.voice.silenceThresholdDB`, which nothing ever read — the
        // detector had -35 hardcoded, so dragging it did nothing at all. Now
        // it sets how far above the measured room noise a sound has to be
        // before it counts as speech, which is the knob that actually helps in
        // a room the default doesn't suit.
        let marginPref = UserDefaults.standard.double(forKey: "kinclaw.voice.silenceMarginDB")
        let margin = Float(marginPref > 0 ? marginPref : 12)

        // 3 ticks = 300ms above the threshold before this counts as speech.
        // Short enough not to clip a real word, long enough that a keystroke
        // or a chair doesn't mark the recording as worth transcribing.
        var speechFrames = 0
        let framesForSpeech = 3

        // Safety: max 15 seconds recording
        maxTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let recorder = self.audioRecorder,
                  recorder.isRecording else { return }

            recorder.updateMeters()
            let avgPower = recorder.averagePower(forChannel: 0)

            // averagePower is dB (typically -160 silence → 0 max).
            // Map to 0...1 for UI binding. -60 dB feels like a
            // useful noise floor; clamp to that. Then EMA smooth
            // (alpha 0.5) so the level meter doesn't jitter.
            let normalized = max(0, min(1, (Double(avgPower) + 60) / 60))
            DispatchQueue.main.async {
                self.audioLevel = self.audioLevel * 0.5 + normalized * 0.5
            }

            // Calibrate against this room before judging anything. The level
            // meter above keeps updating throughout, so the waveform still
            // moves during these 0.4s — only the stop decision waits.
            if calibration.count < calibrationTicks {
                calibration.append(avgPower)
                if calibration.count == calibrationTicks {
                    // Median, not mean. Calibration runs while the mic is
                    // already hot, so a door closing or an early "呃" lands in
                    // the sample — and with a mean, one such tick drags the
                    // whole threshold up and makes the rest of the recording
                    // deaf. A median of 5 shrugs off up to two bad ticks.
                    let floor = calibration.sorted()[calibration.count / 2]
                    // Upper clamp is -30, not -25. Calibration runs on the
                    // first 0.5s of the recording, so a user who starts
                    // talking immediately has their own voice measured as the
                    // room floor. At a -25 ceiling, someone speaking softly
                    // (around -28) would set a threshold above their own
                    // speech and never be heard again for the rest of the
                    // recording. -30 keeps that case working while still
                    // sitting clear of the -32 noise peaks measured here.
                    speechThreshold = min(-30, max(-45, floor + margin))
                }
                return
            }

            // Detect if user has started speaking.
            //
            // Requires a sustained run, not a single tick. `hasSpeechStarted`
            // decides whether the recording is worth transcribing at all, and
            // a lone spike — a cough, a door, a key — used to be enough to
            // mark the whole recording as speech. What then reached STT was
            // effectively silence, and speech models do not answer "nothing"
            // for that; they answer with their most likely utterance. Feeding
            // this build 2s of digital silence returns 「그.」— an invented
            // Korean syllable, from a model being used for Chinese and
            // English. That unpredictability is why the phrase list below is
            // only a backstop: the fix has to be not sending silence at all.
            if avgPower > speechThreshold {
                speechFrames += 1
                if speechFrames >= framesForSpeech { self.hasSpeechStarted = true }
                // Decay, don't reset. A single loud tick is as likely to be a
                // keystroke or a chair creak as it is speech; letting one
                // erase 0.5s of accumulated silence is what kept recording
                // alive until the safety timer. Sustained speech still drives
                // this to 0 within a few ticks, since it subtracts twice as
                // fast as silence adds.
                silenceCount = max(0, silenceCount - 2)
            } else {
                // Decay rather than reset. Requiring three *strictly
                // consecutive* ticks made short words unrecognisable: speech
                // level fluctuates, and a single dip below the line — normal
                // between two syllables — sent the count back to zero, so a
                // two-syllable wake word could never accumulate enough. With
                // decay, a lone transient still falls back to zero on the next
                // quiet tick, but real speech keeps climbing through its
                // natural gaps.
                speechFrames = max(0, speechFrames - 1)
                silenceCount += 1
            }

            // 0.5s silence after speech → stop
            // 2s pure silence (no speech at all) → stop and retry
            let silenceThreshold = self.hasSpeechStarted ? 5 : 20
            if silenceCount >= silenceThreshold {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
    }

    /// Try server STT first, fallback to iOS Speech
    private func transcribe(audioURL: URL, hostname: String) async -> String? {
        if !hostname.isEmpty {
            if let text = await serverSTT(audioURL: audioURL, hostname: hostname) {
                return text
            }
        }
        return await localSTT(audioURL: audioURL)
    }

    /// Server STT — local agents hit SenseVoice directly, cloud
    /// agents go through the LocalKin gateway. Mirrors the TTS fix
    /// in SpeechSynthesizer: the `localhost-kinclaw` marker means
    /// route to the local SenseVoice server (default :8000), not
    /// the cloud gateway.
    private func serverSTT(audioURL: URL, hostname: String) async -> String? {
        do {
            let isLocal = hostname == "localhost-kinclaw"
                || hostname.hasPrefix("localhost")
            let url: URL
            if isLocal {
                let prefBase = UserDefaults.standard.string(
                    forKey: "kinclaw.backend.stt") ?? ""
                let base = prefBase.isEmpty
                    ? "http://localhost:8000"
                    : prefBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                url = URL(string: "\(base)/transcribe")!
            } else {
                url = URL(string: "https://\(hostname)/v1/stt")!
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30

            // Cloud needs Bearer auth; local SenseVoice on loopback
            // doesn't (no auth layer).
            if !isLocal {
                let token = await TokenManager.shared.token(for: hostname)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            let audioData = try Data(contentsOf: audioURL)

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("sensevoice:small\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            struct STTResponse: Codable { let text: String }
            let sttResponse = try JSONDecoder().decode(STTResponse.self, from: data)
            return sttResponse.text
        } catch {
            return nil
        }
    }

    /// iOS native Speech Recognition fallback
    private func localSTT(audioURL: URL) async -> String? {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return nil
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

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

        isTranscribing = true

        Task { @MainActor in
            let text = await self.transcribe(audioURL: url, hostname: self.storedHostname)
            self.isTranscribing = false
            if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.transcript = text
                self.onTranscript?(text)
            } else {
                // No speech detected — notify so voice mode can restart
                self.onNoSpeech?()
            }
        }
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

            // Detect if user has started speaking
            if avgPower > -35 {
                self.hasSpeechStarted = true
                silenceCount = 0
            } else {
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

    /// Server STT via SenseVoice
    private func serverSTT(audioURL: URL, hostname: String) async -> String? {
        do {
            let url = URL(string: "https://\(hostname)/v1/stt")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30

            let token = await TokenManager.shared.token(for: hostname)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

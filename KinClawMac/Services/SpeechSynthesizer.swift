import AVFoundation
import Speech

/// TTS: Server Kokoro first, fallback to iOS AVSpeechSynthesizer
class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var completion: (() -> Void)?
    @Published var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak text: try server TTS first, fallback to iOS native
    func speak(_ text: String, hostname: String = "", onComplete: @escaping () -> Void) {
        stop()
        completion = onComplete
        isSpeaking = true

        // Configure audio session (iOS only — macOS routes audio without it)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        // Try server TTS first if hostname available
        if !hostname.isEmpty {
            Task { @MainActor in
                let success = await self.serverTTS(text: text, hostname: hostname)
                if !success {
                    self.localTTS(text: text)
                }
            }
        } else {
            localTTS(text: text)
        }
    }

    /// Server TTS via Kokoro (POST /v1/tts → WAV audio)
    private func serverTTS(text: String, hostname: String) async -> Bool {
        do {
            let url = URL(string: "https://\(hostname)/v1/tts")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            // Auth token
            let token = await TokenManager.shared.token(for: hostname)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            struct TTSRequest: Codable {
                let text: String
                let voice: String?
                let speed: Double?
            }
            // Pick voice based on user's TTS speaker pref (Settings →
            // Voice) + detected language. nil voice was making the
            // server pick its own default (zf_xiaoxiao zh-CN female),
            // which read English text in mangled Chinese phonetics.
            let voice = pickServerVoice(forText: text)
            let speed = UserDefaults.standard.double(forKey: "kinclaw.voice.tts.speed")
            request.httpBody = try JSONEncoder().encode(TTSRequest(
                text: text,
                voice: voice,
                speed: speed > 0 ? speed : nil
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 44 else {  // WAV header is 44 bytes minimum
                return false
            }

            // Play WAV audio
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            return true
        } catch {
            return false
        }
    }

    /// Local iOS TTS fallback
    private func localTTS(text: String) {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "- ", with: "")

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
        isSpeaking = false
        completion = nil
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
        return "af_heart"          // English female default
    }
}

// MARK: - AVAudioPlayerDelegate
extension SpeechSynthesizer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.completion?()
            self?.completion = nil
        }
    }
}

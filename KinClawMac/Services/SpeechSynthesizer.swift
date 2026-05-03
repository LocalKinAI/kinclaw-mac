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
            }
            request.httpBody = try JSONEncoder().encode(TTSRequest(text: text, voice: nil))

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

        // Auto-detect language
        if containsChinese(cleaned) {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        } else if containsSpanish(cleaned) {
            utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
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

    private func containsChinese(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private func containsSpanish(_ text: String) -> Bool {
        let indicators = ["hola", "gracias", "buenos", "buenas", "usted"]
        let lower = text.lowercased()
        return indicators.contains { lower.contains($0) }
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

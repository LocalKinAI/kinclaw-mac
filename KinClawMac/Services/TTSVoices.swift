import Foundation

/// The voices the TTS server actually has, for the voice pickers.
///
/// The pickers used to list Kokoro's voices from `KokoroVoice.all`, which
/// stopped matching the server once it ran Qwen3-TTS: sixteen Kokoro names
/// folded onto a handful of Qwen3 speakers, so four different "女" choices all
/// came back as the same voice. The server now answers `GET /voices`; this
/// asks it and falls back to the Kokoro list when it can't (an older server,
/// or none reachable yet).
///
/// `multilingual` is the other half: Kokoro voices speak one language, so
/// mixed replies are split between voices (`TextSegmenter`), but a Qwen3
/// voice reads "我用 iPhone 发了 email" in one breath, and splitting it switched
/// voice twice mid-sentence. It is kept in UserDefaults so SpeechSynthesizer,
/// off the main actor, can read it without a hop.
@MainActor
final class TTSVoices: ObservableObject {
    static let shared = TTSVoices()

    struct Voice: Identifiable, Hashable, Codable {
        let id: String
        let name: String
        let language: String
        let gender: String?
    }

    struct Group: Identifiable {
        let title: String
        let voices: [(id: String, label: String)]
        var id: String { title }
    }

    @Published private(set) var serverVoices: [Voice] = []
    @Published private(set) var defaultVoice: String?

    private static let voicesKey = "kinclaw.voice.tts.serverVoices"
    private static let multilingualKey = "kinclaw.voice.tts.multilingual"
    private static let defaultKey = "kinclaw.voice.tts.serverDefault"
    private static let sourceKey = "kinclaw.voice.tts.serverSource"

    /// True when the server's voices each read every language, so text
    /// should not be split between voices. Safe to read from any thread.
    nonisolated static var multilingual: Bool {
        UserDefaults.standard.bool(forKey: multilingualKey)
    }

    /// Native language of a server voice ("vivian" -> "zh"), from the
    /// cached list. Safe to read from any thread.
    nonisolated static func language(ofServerVoice id: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: voicesKey),
              let voices = try? JSONDecoder().decode([Voice].self, from: data) else { return nil }
        return voices.first { $0.id == id }?.language
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.voicesKey),
           let voices = try? JSONDecoder().decode([Voice].self, from: data) {
            serverVoices = voices
        }
        defaultVoice = UserDefaults.standard.string(forKey: Self.defaultKey)
    }

    private static var endpoint: String {
        let pref = UserDefaults.standard.string(forKey: "kinclaw.backend.tts")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (pref.isEmpty ? "http://localhost:8001" : pref)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Ask the server for its voices. Keeps the cached list on failure;
    /// clears it when the server answered but has no `/voices` (a Kokoro
    /// server from before 2.1), so the pickers fall back to Kokoro's.
    func refresh() async {
        let base = Self.endpoint
        guard let url = URL(string: base + "/voices") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        struct Reply: Decodable {
            let multilingual: Bool?
            let default_voice: String?
            let voices: [Voice]
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                store(voices: [], multilingual: false, defaultVoice: nil, source: base)
                return
            }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            store(voices: reply.voices, multilingual: reply.multilingual ?? false,
                  defaultVoice: reply.default_voice, source: base)
        } catch {
            // Unreachable: keep what we had, unless it came from another server.
            if UserDefaults.standard.string(forKey: Self.sourceKey) != base {
                store(voices: [], multilingual: false, defaultVoice: nil, source: base)
            }
        }
    }

    private func store(voices: [Voice], multilingual: Bool, defaultVoice: String?, source: String) {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(voices), forKey: Self.voicesKey)
        defaults.set(multilingual, forKey: Self.multilingualKey)
        defaults.set(defaultVoice, forKey: Self.defaultKey)
        defaults.set(source, forKey: Self.sourceKey)
        serverVoices = voices
        self.defaultVoice = defaultVoice
    }

    // MARK: - Picker helpers

    /// Voices grouped by native language: the server's when known, else Kokoro's.
    var groups: [Group] {
        guard !serverVoices.isEmpty else {
            return [
                Group(title: "中文", voices: KokoroVoice.chinese.map { ($0.id, $0.label) }),
                Group(title: "English", voices: KokoroVoice.english.map { ($0.id, $0.label) }),
            ]
        }
        let titles = ["zh": "中文", "en": "English"]
        var order: [String] = []
        var byLang: [String: [(id: String, label: String)]] = [:]
        for v in serverVoices {
            let key = titles[v.language] == nil ? "other" : v.language
            if byLang[key] == nil { order.append(key) }
            byLang[key, default: []].append((v.id, v.name))
        }
        return order.map { Group(title: titles[$0] ?? "其他", voices: byLang[$0] ?? []) }
    }

    /// What "auto" means with the current server.
    var autoLabel: String {
        if !serverVoices.isEmpty {
            let name = serverVoices.first { $0.id == defaultVoice }?.name ?? defaultVoice ?? "server default"
            return "自动（\(name)）"
        }
        return "自动（中文晓晓 · 英文 Bella）"
    }

    func label(for id: String) -> String? {
        serverVoices.first { $0.id == id }?.name ?? KokoroVoice.all.first { $0.id == id }?.label
    }
}

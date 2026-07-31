import Foundation

/// Mixed-language TTS segmentation, ported from localkin's `pkg/tts/split.go`.
///
/// Kokoro voices are single-language: `zf_xiaoxiao` narrating English produces
/// mangled phonetics, and `af_bella` narrating Chinese produces the "Chinese
/// letter, Chinese letter…" recital. A reply that mixes both — which most of
/// them do, since technical terms stay in English — needs to be split and
/// spoken by the matching voice per run.
///
/// This is a port rather than a reimplementation on purpose: the Go version is
/// already in production behind `kin_speak` and carries fixes this would
/// otherwise have to rediscover (neutral punctuation attaching to the *next*
/// language, short English labels being absorbed rather than voiced alone).
/// `TextSegmenterTests` checks the two stay in agreement.
enum TextSegmenter {

    struct Segment: Equatable {
        let text: String
        let voice: String
    }

    // Kokoro voice ID prefix → language.
    private static let prefixToLang: [Character: String] = [
        "a": "en", "b": "en", "z": "zh", "j": "ja", "h": "hi",
        "e": "es", "f": "fr", "i": "it", "p": "pt",
    ]

    private static let defaultVoices: [String: String] = [
        "zh": "zf_xiaoxiao", "ja": "jf_alpha", "hi": "hf_alpha",
        "en": "af_bella", "es": "ef_dora", "fr": "ff_siwis",
        "it": "if_sara", "pt": "pf_dora",
    ]

    /// Classify a scalar into a language bucket. Empty = neutral: digits and
    /// punctuation take on whatever language surrounds them, so "3 个" doesn't
    /// break into an English "3" and a Chinese "个".
    private static func charLang(_ s: Unicode.Scalar) -> String {
        let v = s.value
        switch v {
        case 0x3040...0x309F, 0x30A0...0x30FF:
            return "ja"
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3000...0x303F, 0xFF00...0xFFEF:
            return "zh"
        case 0x0900...0x097F:
            return "hi"
        default:
            if CharacterSet.decimalDigits.contains(s) { return "" }
            if CharacterSet.letters.contains(s) { return "en" }
            return ""
        }
    }

    /// Characters TTS engines can't pronounce and would otherwise read out
    /// literally ("black medium star", "trade mark sign").
    private static func isNonSpeakable(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x1F000...0x1FAFF,   // emojis, pictographs
             0x2600...0x27BF,      // misc symbols, dingbats
             0xFE00...0xFE0F,      // variation selectors
             0xE0020...0xE007F,    // tags
             0x2300...0x23FF,      // misc technical ⌚⏰
             0x2B00...0x2BFF:      // symbols and arrows
            return true
        case 0x200D, 0x200B, 0x200C, 0x200E, 0x200F,  // ZWJ / ZWNBSP
             0x20E3,                                   // enclosing keycap
             0x2764, 0x2763,                           // hearts
             0x00A9, 0x00AE,                           // ©®
             0x2122:                                   // ™
            return true
        default:
            return false
        }
    }

    /// Strip markdown syntax and non-speakable characters.
    static func stripNonSpeakable(_ text: String) -> String {
        var s = text
        for pattern in ["```", "`", "**", "__"] {
            s = s.replacingOccurrences(of: pattern, with: "")
        }

        s = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                t = String(t.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            }
            if t.count >= 2 {
                let chars = Array(t)
                if (chars[0] == "-" || chars[0] == "+") && chars[1] == " " {
                    t = String(chars[2...]).trimmingCharacters(in: .whitespaces)
                }
            }
            return t
        }.joined(separator: "\n")

        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !isNonSpeakable($0) }))

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split mixed-language text into runs, each tagged with the voice that
    /// should speak it. `preferredVoice` overrides the default for its own
    /// language only — picking `zm_yunxi` still leaves English on `af_bella`.
    static func splitByLang(_ text: String, preferredVoice: String = "") -> [Segment] {
        let cleaned = stripNonSpeakable(text)
        if cleaned.isEmpty { return [] }

        var voiceFor = defaultVoices
        if preferredVoice.count >= 2, let first = preferredVoice.first,
           let lang = prefixToLang[first] {
            voiceFor[lang] = preferredVoice
        }

        let scalars = Array(cleaned.unicodeScalars)
        var tags = scalars.map { charLang($0) }

        // Neutral runs attach to the language that FOLLOWS them, so a comma
        // between a Chinese clause and an English one goes with the English.
        var nextLang = ""
        for i in stride(from: tags.count - 1, through: 0, by: -1) {
            if !tags[i].isEmpty { nextLang = tags[i] } else { tags[i] = nextLang }
        }
        if nextLang.isEmpty { return [] }   // nothing pronounceable

        var segments: [Segment] = []
        var segStart = 0
        for i in 1...scalars.count {
            if i < scalars.count && tags[i] == tags[segStart] { continue }
            let voice = voiceFor[tags[segStart]] ?? voiceFor["en"]!
            let piece = String(String.UnicodeScalarView(scalars[segStart..<i]))
            if let last = segments.last, last.voice == voice {
                segments[segments.count - 1] = Segment(text: last.text + piece, voice: voice)
            } else {
                segments.append(Segment(text: piece, voice: voice))
            }
            segStart = i
        }

        // A one- or two-letter English run is almost always a label (option
        // "A", a variable name) rather than English prose. Voicing it on its
        // own costs a whole extra synthesis round-trip and sounds like a
        // stutter, so fold it into the neighbouring segment.
        let enVoice = voiceFor["en"]!
        var merged: [Segment] = []
        for seg in segments {
            if seg.voice == enVoice, letterCount(seg.text) <= 2,
               let last = merged.last, last.voice != enVoice {
                merged[merged.count - 1] = Segment(text: last.text + seg.text, voice: last.voice)
            } else if let last = merged.last, last.voice == seg.voice {
                merged[merged.count - 1] = Segment(text: last.text + seg.text, voice: last.voice)
            } else {
                merged.append(seg)
            }
        }
        if merged.count >= 2, merged[0].voice == enVoice,
           letterCount(merged[0].text) <= 2, merged[1].voice != enVoice {
            merged[1] = Segment(text: merged[0].text + merged[1].text, voice: merged[1].voice)
            merged.removeFirst()
        }

        // Fold punctuation-only runs into the segment before them.
        //
        // This step has no counterpart in the Go original, which is fine — it
        // changes cost, not pronunciation. CJK punctuation carries a "zh" tag
        // (U+3000–303F), so "…zero。 Let me explain" ends up with a lone "。"
        // between two other runs. Spoken that's silent, but structurally it is
        // a whole extra HTTP round-trip and an extra AVAudioPlayer handoff,
        // which is audible as a hitch. Attaching it to the preceding run keeps
        // the trailing pause where it belongs.
        var compacted: [Segment] = []
        for seg in merged {
            let speakable = seg.text.unicodeScalars.contains {
                CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }
            if !speakable, let last = compacted.last {
                compacted[compacted.count - 1] = Segment(text: last.text + seg.text,
                                                         voice: last.voice)
            } else if let last = compacted.last, last.voice == seg.voice {
                // Absorbing a punctuation run can leave two same-voice
                // segments adjacent ("zero" + "。" then " Let me explain"),
                // which the earlier merge pass has already gone by. Without
                // this they stay split and cost an extra synthesis call for
                // no audible difference.
                compacted[compacted.count - 1] = Segment(text: last.text + seg.text,
                                                         voice: last.voice)
            } else {
                compacted.append(seg)
            }
        }

        return compacted
    }

    private static func letterCount(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { CharacterSet.letters.contains($1) ? $0 + 1 : $0 }
    }

    /// Kokoro wants a bare language tag ("zh"), derived from the voice prefix.
    static func language(forVoice voice: String) -> String {
        guard let first = voice.first, let lang = prefixToLang[first] else { return "en" }
        return lang
    }
}

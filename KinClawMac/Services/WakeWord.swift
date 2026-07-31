import Foundation

/// Wake-word gating for hands-free voice mode.
///
/// Without this, voice mode sends every transcription it produces — including
/// a phone call in the same room, a colleague's question, or the recogniser's
/// best guess at an air conditioner. The wake word turns "always listening"
/// into "always listening, rarely acting".
///
/// Matching is deliberately loose. STT output for a short name is unstable:
/// "小 Kin" comes back as 「小金」, 「小巾」, 「小kin」, sometimes with a
/// trailing comma, sometimes with the recogniser's own spacing. Comparing raw
/// strings would mean the user repeats themselves while a correct match sits
/// one punctuation mark away, which is a worse failure than the occasional
/// false accept it prevents.
enum WakeWord {

    /// Result of testing a transcription against the configured wake word.
    enum Match {
        /// Wake word found; payload is the remaining command (may be empty if
        /// the user only said the wake word).
        case woken(String)
        /// No wake word — the utterance should be dropped.
        case ignored
        /// Gating is off; take the utterance as-is.
        case disabled
    }

    /// Fold away everything the recogniser is inconsistent about: case,
    /// spacing, and punctuation. Keeps letters, digits, and CJK.
    private static func normalize(_ s: String) -> [Character] {
        Array(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Test `text` against `wake`. An empty wake word disables gating.
    ///
    /// The wake word must appear at the *start* of the utterance — not
    /// anywhere in it. Matching mid-sentence would fire on the agent's own
    /// name being discussed ("我在问 Kin 的事"), which is exactly the noise
    /// this is meant to filter.
    static func test(_ text: String, wake: String) -> Match {
        let wakeChars = normalize(wake)
        guard !wakeChars.isEmpty else { return .disabled }

        let chars = Array(text)
        var wakeIndex = 0
        var cut = chars.startIndex

        // Walk the original text, consuming normalized wake characters as
        // they match. Tracking the original index in parallel is what lets us
        // strip the wake word from text that had punctuation inside it.
        for (i, ch) in chars.enumerated() {
            // `Character(ch.lowercased())` would trap here: lowercasing is not
            // 1:1 (ß → "ss"), and the Character(String) initializer requires
            // exactly one grapheme. Take the first scalar instead.
            guard let folded = ch.lowercased().first else { continue }
            if !folded.isLetter && !folded.isNumber {
                // Skip punctuation/space, but only before the match completes
                // — leading noise like "嗯，" shouldn't break the match.
                if wakeIndex == 0 { continue }
                if wakeIndex < wakeChars.count { continue }
            }
            if wakeIndex < wakeChars.count, folded == wakeChars[wakeIndex] {
                wakeIndex += 1
                cut = chars.index(after: i)
                if wakeIndex == wakeChars.count { break }
                continue
            }
            // A non-matching speakable character before the wake word is
            // complete means this utterance doesn't start with it.
            if wakeIndex < wakeChars.count { return .ignored }
        }

        guard wakeIndex == wakeChars.count else { return .ignored }

        // Strip the punctuation that separated the wake word from the command
        // ("小金，今天…"), but only at the front. Trimming both ends would eat
        // the sentence's own terminator and turn "小金，下雨了吗？" into a
        // statement.
        let separators = Set(" \t\n,，.。!！?？、:：")
        let rest = String(chars[cut...].drop { separators.contains($0) })
        return .woken(rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

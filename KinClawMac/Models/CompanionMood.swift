import Foundation

/// What the companion is feeling, as far as a picture can show it.
///
/// Two sources feed it. The companion soul opens every reply with a
/// bracketed tag — `[开心]你是说那只橘猫吗？` — which the panel strips
/// before speaking and uses to pick the art. And SenseVoice labels the
/// emotion in the user's voice, which sets a mood while the reply is
/// still being written, so the face reacts to how you sounded before
/// the words come back.
enum CompanionMood: String, CaseIterable {
    case happy, gentle, curious, sleepy, worried

    /// Folder name and tag word, the way the soul is told to write it.
    var label: String {
        switch self {
        case .happy:   return "开心"
        case .gentle:  return "温柔"
        case .curious: return "好奇"
        case .sleepy:  return "困"
        case .worried: return "担心"
        }
    }

    /// Accepts the tag word, the folder name, and the near-synonyms a
    /// model reaches for when it does not copy the list exactly.
    static func parse(_ raw: String) -> CompanionMood? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let m = CompanionMood(rawValue: t) { return m }
        switch t {
        case "开心", "高兴", "快乐", "兴奋", "笑", "joy", "excited":  return .happy
        case "温柔", "平静", "温暖", "安慰", "calm", "warm", "soft":  return .gentle
        case "好奇", "疑问", "惊讶", "surprised", "interested":       return .curious
        case "困", "累", "疲惫", "想睡", "tired", "sleep":            return .sleepy
        case "担心", "难过", "心疼", "着急", "sad", "concerned":      return .worried
        default: return nil
        }
    }

    /// SenseVoice's label for the user's voice → how the companion
    /// should look while it listens. Neutral is no signal.
    static func fromVoice(_ emotion: String) -> CompanionMood? {
        switch emotion.lowercased() {
        case "happy":              return .happy
        case "sad":                return .gentle
        case "angry", "fearful":   return .worried
        case "surprised":          return .curious
        default:                   return nil
        }
    }

    /// One line for the model, appended to what the user said. Hedged
    /// on purpose: SenseVoice small mislabels a flat voice as sad often
    /// enough that the soul is told to soften its tone, not to comment.
    static func cue(forVoice emotion: String) -> String? {
        let how: String
        switch emotion.lowercased() {
        case "happy":     how = "听起来挺开心"
        case "sad":       how = "听起来有点低落"
        case "angry":     how = "听起来有点烦躁"
        case "fearful":   how = "听起来有点紧张"
        case "surprised": how = "听起来有点意外"
        default:          return nil
        }
        return "(语气线索:\(how),不一定准)"
    }
}

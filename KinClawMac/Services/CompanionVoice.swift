import Foundation

/// Turning the panel's two modal cards — the permission gate and
/// `ask_user` — into something a face with no buttons can handle.
///
/// Companion mode has no approval card, which is why the soul used to
/// run with `mode: auto` and a handful of harmless skills. With the
/// skills come the questions, and the only channel that exists here is
/// the one already open: it says what it wants to do, you say yes or no.
enum CompanionVoice {

    // MARK: Reading a request out loud

    /// Skill name → what to call it when speaking. The tool name means
    /// nothing to a listener, and reading "cerebellum" aloud is worse
    /// than saying nothing.
    private static let verbs: [String: String] = [
        "shell": "跑一条命令",
        "file_write": "写一个文件",
        "file_edit": "改一个文件",
        "forge": "造一个新技能",
        "imsg_send": "发一条信息",
        "input": "动一下键盘鼠标",
        "ui": "点一下界面",
        "spawn": "叫一个帮手来做",
        "record": "录一段屏幕",
        "cerebellum": "操作一个 app",
        "screen": "看一眼屏幕",
    ]

    /// The gist of a call, short enough to say. Long arguments are cut:
    /// nobody listens to a 200-character path, and the point of the
    /// question is whether you trust the action, not the exact bytes.
    static func spoken(_ request: PermissionRequest) -> String {
        let verb = verbs[request.skill]
            ?? verbs[request.skill.components(separatedBy: "(").first ?? ""]
            ?? "用 \(request.skill)"
        // The summary reads "shell: rm -rf ./build" — the half after the
        // colon is the part worth hearing.
        var detail = request.summary
        if let colon = detail.firstIndex(of: ":") {
            detail = String(detail[detail.index(after: colon)...])
        }
        detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        // A summary that is only the skill name adds nothing to the verb.
        if detail == request.skill { detail = "" }
        // A path read out in full is unlistenable and tells you nothing
        // the file's own name doesn't. Keep the last two components.
        if detail.hasPrefix("/") || detail.hasPrefix("~") {
            let parts = detail.split(separator: "/")
            if parts.count > 2 { detail = "…/" + parts.suffix(2).joined(separator: "/") }
        }
        if detail.count > 60 { detail = String(detail.prefix(60)) + "……" }
        return detail.isEmpty
            ? "我想\(verb)，可以吗？"
            : "我想\(verb)：\(detail)。可以吗？"
    }

    /// Spoken form of an `ask_user` question. Options are read as a
    /// list so answering by repeating one is natural.
    static func spoken(_ question: PendingQuestion) -> String {
        guard !question.options.isEmpty else { return question.text }
        return question.text + " " + question.options.joined(separator: "，还是 ") + "？"
    }

    // MARK: Hearing the answer

    /// Yes / no / "stop asking" out of one spoken line, or nil when it
    /// is neither — in which case the caller asks again rather than
    /// guessing, since guessing wrong means running something the user
    /// did not agree to.
    ///
    /// Deliberately narrow. "把那个文件删了" is an instruction, not an
    /// approval, and must not read as one; only short affirmations
    /// count, and a sentence long enough to be a new request is
    /// rejected outright.
    static func decision(from spoken: String) -> String? {
        let t = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[。，、！？.,!?\\s]", with: "",
                                  options: .regularExpression)
            .lowercased()
        guard !t.isEmpty else { return nil }

        // "以后都不用问了" — approve and stop asking for this skill.
        let always = ["一直可以", "都可以", "以后不用问", "以后别问", "不用再问",
                      "always", "别问了", "不用问了"]
        if always.contains(where: { t.contains($0) }) { return "allow_session" }

        let no = ["不要", "不用", "别", "算了", "停", "取消", "不行", "不可以",
                  "no", "stop", "cancel", "don't", "dont"]
        if no.contains(where: { t.contains($0) }) { return "deny" }

        // Short affirmations only. A long sentence containing "可以"
        // ("这个可以等一下再说") is not an approval.
        guard t.count <= 12 else { return nil }
        let yes = ["可以", "好", "行", "嗯", "对", "去吧", "干吧", "没问题", "同意",
                   "ok", "okay", "yes", "yep", "sure", "go", "yeah", "确认"]
        if yes.contains(where: { t.contains($0) }) { return "allow" }
        return nil
    }

    /// Match a spoken answer to one of the offered options, so saying
    /// "第二个" or part of an option's text picks it.
    static func pick(_ spoken: String, from options: [String]) -> String? {
        let t = spoken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty, !options.isEmpty else { return nil }
        for (i, opt) in options.enumerated() {
            let ordinals = ["第一个", "第一", "one", "1"]
            let map = [["第一个", "第一"], ["第二个", "第二"], ["第三个", "第三"],
                       ["第四个", "第四"], ["第五个", "第五"]]
            _ = ordinals
            if i < map.count, map[i].contains(where: { t.contains($0) }) { return opt }
            let o = opt.lowercased()
            if !o.isEmpty, t.contains(o) || o.contains(t) { return opt }
        }
        return nil
    }

    /// What the face is busy with, for the line under the halo. nil
    /// when there is nothing worth saying.
    static func activity(forSkill name: String) -> String? {
        let base = name.components(separatedBy: "(").first ?? name
        switch base {
        case "screen":                    return "在看屏幕"
        case "weather":                   return "在查天气"
        case "web_search", "web_fetch",
             "kinbrowser", "web",
             "web_scrape", "browser_session": return "在查资料"
        case "memory", "kinbrain", "learn": return "在想以前的事"
        case "music_play", "music_pause": return "在放音乐"
        case "shell":                     return "在跑命令"
        case "file_read":                 return "在读文件"
        case "file_write", "file_edit":   return "在写文件"
        case "ui", "input", "cerebellum",
             "app_open_clean":            return "在操作电脑"
        case "spawn":                     return "在叫帮手"
        case "tool_search":               return "在找工具"
        case "location":                  return "在定位"
        case "todo_write":                return "在列步骤"
        default:                          return "在忙"
        }
    }
}

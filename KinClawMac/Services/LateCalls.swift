import Foundation

/// Tool calls that run past what their caller can wait for. The kernel's relay gives a call 55
/// seconds, a studio agent's fifteen minutes; a call still working past that used to come back
/// from the relay as 「连不上 LocalKin 的面板：…timed out」 while the work went on unseen — a
/// failure that wasn't (lyric_video, image_generate, a long social step). Now such a call answers
/// in time that it is still going, with an id, and its result is kept for `panel_result`.
@MainActor
enum LateCalls {
    private struct Late {
        let name: String
        let started: Date
        var result: (text: String, isError: Bool)?
    }

    private static var kept: [String: Late] = [:]

    /// The call's own answer when it comes within `seconds`; else "still going" with an id.
    static func answer(_ name: String, _ args: [String: Any], within seconds: Double) async -> (String, Bool) {
        // An unstructured task keeps the caller's patience and place (task-locals are inherited).
        let work = Task { @MainActor in await PanelTools.call(name, args) }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        return await withCheckedContinuation { (done: CheckedContinuation<(String, Bool), Never>) in
            var answered = false
            Task { @MainActor in
                let result = await work.value
                if answered {
                    kept[id]?.result = result
                } else {
                    answered = true
                    done.resume(returning: result)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
                guard !answered else { return }
                answered = true
                prune()
                kept[id] = Late(name: name, started: Date().addingTimeInterval(-seconds))
                done.resume(returning: ("「\(name)」还在做（已经 \(Int(seconds)) 秒，比这次调用能等的久）。它没有停，做完的结果会留着："
                                        + "用 panel_result（id: \"\(id)\"）取，可以先做别的。", false))
            }
        }
    }

    /// panel_result: a late call's answer once it has come, waiting up to `wait` seconds for it.
    static func result(_ id: String, wait: Double) async -> (String, Bool) {
        let until = Date().addingTimeInterval(max(0, min(wait, PanelTools.patience - 4)))
        while true {
            guard let late = kept[id] else { return ("没有这个 id 的结果：\(id)（早取走了，或 app 重启过）", true) }
            if let result = late.result {
                kept[id] = nil
                return result
            }
            if Date() >= until {
                let minutes = Int(Date().timeIntervalSince(late.started) / 60)
                return ("「\(late.name)」还在做（\(minutes) 分钟了）。等会儿再用 panel_result（id: \"\(id)\"）取", false)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Results nobody came for in a day are let go.
    private static func prune() {
        let old = Date().addingTimeInterval(-86_400)
        kept = kept.filter { $0.value.started > old }
    }
}

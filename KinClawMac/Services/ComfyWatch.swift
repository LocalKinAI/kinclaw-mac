import Foundation

/// Where jobs stand on the box's ComfyUI — every tab's and every tool's — read
/// from KinClaw's progress desk on the box (scripts/comfy/kinclaw_nodes/progress.py).
///
/// The Studio tabs and OpenMontage all queue on that one ComfyUI, and each
/// could see only its own job, and only that it was "running": a score waited
/// 58 minutes behind another session's H3 test without knowing it, a picture
/// ran twenty minutes with no way to tell slow from stuck, and a score was cut
/// off halfway twice in one day with no word of who or why (the Studio agents'
/// notebooks, 2026-09-28). Now a job says where it is in the queue and behind
/// what, which node and step it is on and for how long, and an interruption
/// says who and why.
@MainActor
final class ComfyWatch: ObservableObject {
    static let shared = ComfyWatch()

    struct Job: Decodable {
        let prompt_id: String
        let tab: String?
        let what: String?
        let program: String?
        let from: String?
        let node: String?
        let node_class: String?
        let value: Double?
        let max: Double?
        let for_s: Double?
        let node_s: Double?
        let step_s: Double?
        let waiting_s: Double?

        /// "Montage 的 MiniMax 配乐".
        var title: String {
            let kind = what ?? "一个工作流"
            return tab.map { "\($0) 的\(kind)" } ?? kind
        }

        /// "KSampler 第 3/20 步（这一步 0:41），已 7:12".
        var doing: String {
            var out = node_class ?? "准备中"
            if let value, let max, max > 1 {
                out += " 第 \(Int(value))/\(Int(max)) 步" + (step_s.map { "（这一步 \(ComfyWatch.clock($0))）" } ?? "")
                // Its steps so far, at the pace they went: how long the rest of this node has to go.
                if value >= 1, max > value, let node_s, node_s > 0 {
                    out += "，这个节点还要约 \(ComfyWatch.clock((max - value) * node_s / value))"
                }
            } else if let node_s {
                out += "（这个节点 \(ComfyWatch.clock(node_s))）"
            }
            return out + (for_s.map { "，已 \(ComfyWatch.clock($0))" } ?? "")
        }
    }

    struct Ended: Decodable {
        let prompt_id: String
        let end: String?
        let at: Double?
        let tab: String?
        let what: String?
        let program: String?
        let from: String?
        let took_s: Double?
        let by: String?
        let why: String?
        let stop_program: String?
        let stop_from: String?
        let error: String?

        var title: String {
            let kind = what ?? "一个工作流"
            return tab.map { "\($0) 的\(kind)" } ?? kind
        }
    }

    struct Mine: Decodable {
        let state: String
        let ahead: Int?
        let end: String?
        let by: String?
        let why: String?
        let stop_program: String?
        let stop_from: String?
        let error: String?
    }

    struct Snapshot: Decodable {
        let now: Double?
        let running: [Job]
        let pending: [Job]
        let ended: [Ended]
        let mine: Mine?
    }

    /// The line for each job of ours being waited on, by prompt id; `now` is the latest.
    @Published private(set) var lines: [String: String] = [:]
    @Published private(set) var now: String?
    private var active: [String: (what: String, base: String)] = [:]
    private var order: [String] = []
    private var poller: Task<Void, Never>?
    /// Each line as last read, and when: a read that gets no answer keeps the old line, saying how old.
    private var read: [String: (line: String, at: Date)] = [:]

    /// A job of ours is on the box: keep its line fresh until `ended`.
    func began(_ id: String, what: String, base: String) {
        active[id] = (what, base)
        order.append(id)
        guard poller == nil else { return }
        poller = Task { @MainActor in
            while !active.isEmpty, !Task.isCancelled {
                for (id, job) in active {
                    let line = await Self.line(for: id, what: job.what, base: job.base)
                    guard active[id] != nil else { continue }
                    if let line {
                        read[id] = (line, Date())
                        lines[id] = line
                    } else if let last = read[id], Date().timeIntervalSince(last.at) > 12 {
                        lines[id] = last.line + "（\(Int(Date().timeIntervalSince(last.at))) 秒前读到的；盒子这会儿没答）"
                    }
                }
                now = order.last.flatMap { lines[$0] }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            poller = nil
        }
    }

    func ended(_ id: String) {
        active[id] = nil
        read[id] = nil
        lines[id] = nil
        order.removeAll { $0 == id }
        now = order.last.flatMap { lines[$0] }
    }

    /// The line for the job of ours that is on the box now, if any.
    var current: String? { now }

    // MARK: The whole box, for the Studio's status chip

    /// The box's ComfyUI as last read, while something on screen shows it (`watchBox`).
    @Published private(set) var box: Snapshot?
    /// When it was last read; nil when the last read failed.
    @Published private(set) var boxAt: Date?
    private var boxWatchers = 0
    private var boxPoller: Task<Void, Never>?

    /// Keep `box` fresh — every 3 s while the box is busy, every 8 when it is not — for as long
    /// as some view that shows it is on screen.
    func watchBox() {
        boxWatchers += 1
        guard boxPoller == nil else { return }
        boxPoller = Task { @MainActor in
            while boxWatchers > 0, !Task.isCancelled {
                if let read = await Self.snapshot(base: ComfyStudio.base) {
                    box = read
                    boxAt = Date()
                } else {
                    boxAt = nil
                }
                let busy = !(box?.running.isEmpty ?? true) || !(box?.pending.isEmpty ?? true)
                try? await Task.sleep(nanoseconds: (busy ? 3 : 8) * 1_000_000_000)
            }
            boxPoller = nil
        }
    }

    func unwatchBox() { boxWatchers = max(0, boxWatchers - 1) }

    // MARK: Asking the box

    static func snapshot(base: String, prompt: String? = nil) async -> Snapshot? {
        var parts = URLComponents(string: base + "/kinclaw/progress")
        if let prompt { parts?.queryItems = [URLQueryItem(name: "prompt_id", value: prompt)] }
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Where one job stands: "排在第 2 个，前面：Montage 的 MiniMax 配乐（在跑，KSampler 第 3/20 步…）" or
    /// "在跑：KSampler 第 3/4 步（这一步 0:21），已 2:40". Nil when the box has no desk.
    static func line(for id: String, what: String, base: String) async -> String? {
        guard let box = await snapshot(base: base, prompt: id), let mine = box.mine else { return nil }
        switch mine.state {
        case "running":
            guard let job = box.running.first(where: { $0.prompt_id == id }) else { return "\(what)在跑" }
            return "\(what)在跑：\(job.doing)"
        case "pending":
            let ahead = box.running + box.pending.prefix(while: { $0.prompt_id != id })
            let names = ahead.prefix(3).map { job in
                job.title + (box.running.contains { $0.prompt_id == job.prompt_id } ? "（在跑，\(job.doing)）" : "（排队）")
            }
            return "\(what)在排队：第 \(ahead.count + 1) 个，前面是 " + names.joined(separator: "、") + (ahead.count > 3 ? " 等" : "")
        case "ended":
            return stopped(mine, what: what)
        default:
            return nil
        }
    }

    /// How a job that ended badly ended, in words: who stopped it and why when it was said.
    static func stopped(_ mine: Mine, what: String) -> String? {
        switch mine.end {
        case "interrupted":
            if let by = mine.by {
                return "\(what)被\(by)打断了" + (mine.why.map { "：\($0)" } ?? "")
            }
            let source = [mine.stop_program, mine.stop_from].compactMap { $0 }.joined(separator: "，")
            return "\(what)在盒子上被打断了" + (source.isEmpty ? "（没人留话；可能是 ComfyUI 页面上点的停）" : "（\(source)，没留原因）")
        case "error":
            return "\(what)出错：" + (mine.error ?? "看盒子上的 comfy.log")
        default:
            return nil
        }
    }

    /// For a job whose history says it did not finish: the reason, from the desk.
    static func reason(_ id: String, what: String, base: String) async -> String? {
        guard let mine = await snapshot(base: base, prompt: id)?.mine, mine.state == "ended" else { return nil }
        return stopped(mine, what: what)
    }

    /// The whole box in a line or three: what runs, for whom, at which step; what waits;
    /// the last interruption. Falls back to ComfyUI's own queue when the desk is not there.
    static func summary(base: String) async -> String {
        guard let box = await snapshot(base: base) else { return await plainQueue(base: base) }
        var lines: [String] = []
        if box.running.isEmpty, box.pending.isEmpty {
            lines.append("盒子的 ComfyUI（几个标签共用）：空着")
        } else {
            let running = box.running.map { "\($0.title)：\($0.doing)" }.joined(separator: "；")
            lines.append("盒子的 ComfyUI（几个标签共用）：" + (running.isEmpty ? "没在跑" : "在跑 \(running)"))
            if !box.pending.isEmpty {
                lines.append("排队 \(box.pending.count) 个：" + box.pending.prefix(4).map {
                    $0.title + ($0.waiting_s.map { "（等了 \(clock($0))）" } ?? "")
                }.joined(separator: "、"))
            }
        }
        // An interruption in the last half hour: older ones are not news.
        if let stop = box.ended.last(where: { $0.end == "interrupted" && (box.now ?? 0) - ($0.at ?? 0) < 1800 }) {
            let who = stop.by ?? [stop.stop_program, stop.stop_from].compactMap { $0 }.joined(separator: "，")
            lines.append("半小时内有任务被打断：" + (who.isEmpty ? "没人留话" : who) + (stop.why.map { "（\($0)）" } ?? ""))
        }
        return lines.joined(separator: "\n")
    }

    /// The queue as ComfyUI itself tells it, when the box has no desk yet.
    static func plainQueue(base: String) async -> String {
        guard let url = URL(string: base + "/queue") else { return "盒子的 ComfyUI：地址不对" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let queue = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "盒子的 ComfyUI：连不上"
        }
        let running = queue["queue_running"] as? [[Any]] ?? []
        let pending = queue["queue_pending"] as? [[Any]] ?? []
        return "盒子的 ComfyUI（几个标签共用）：在跑 \(running.count)，排队 \(pending.count)"
    }

    /// Stop one job, saying who and why: a running one is interrupted, a waiting one taken
    /// out of the queue — never somebody else's job that happens to be running. Through the
    /// desk when the box has it, plain ComfyUI otherwise.
    static func interrupt(_ id: String, base: String, by: String, why: String) async {
        let state = await snapshot(base: base, prompt: id)?.mine?.state
        if state == "pending", let url = URL(string: base + "/queue") {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["delete": [id]])
            _ = try? await URLSession.shared.data(for: request)
            return
        }
        let desk = state != nil
        guard let url = URL(string: base + (desk ? "/kinclaw/interrupt" : "/interrupt")) else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: desk ? ["prompt_id": id, "by": by, "why": why] : ["prompt_id": id])
        _ = try? await URLSession.shared.data(for: request)
    }

    nonisolated static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

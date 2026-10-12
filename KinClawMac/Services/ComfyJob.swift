import CryptoKit
import Foundation

/// One graph on the box's ComfyUI, from queueing it to the files it saved — the one way every tab
/// runs one: Film's shots, pictures and music, Motion's takes and clay, talking videos, a drawing's
/// music, the Comfy tab's templates.
///
/// What it is careful about (the agents' notebooks, 2026-09-26 … 10-10, and 「先做1和2」):
///   - a graph is queued once. Each carries a tag made from what it is, and before it is queued —
///     again after a relaunch, or after a POST whose answer was lost on the way — the box's queue
///     and recent history are searched for it: a shot rendering there is taken up again instead of
///     rendered twice while the first one finishes for nobody;
///   - the time limit counts from when it starts running, not from when it was queued behind another
///     tab's hour of work; and when it runs out, the job is stopped on the box;
///   - a look that gets no answer is not a failure — only ComfyUI's own word is (an error, an
///     interruption). Half an hour without any answer is "the box can't be reached", which a resume
///     takes up again; a graph neither queued nor in the history has vanished, and is said so;
///   - a file is fetched again when the fetch fails on the way.
@MainActor
enum ComfyJob {
    enum Trouble: LocalizedError {
        /// ComfyUI's own word: it would not take the graph (with its answer, which names the nodes),
        /// the graph failed, it was stopped.
        case refused(String, answer: [String: Any] = [:])
        case failed(String)
        /// No answer from the box for long: the job may be running on; a resume takes it up.
        case unreachable(String)
        /// Neither queued nor in the history: ComfyUI restarted, or it was deleted.
        case vanished(String)

        var errorDescription: String? {
            switch self {
            case .refused(let text, _), .failed(let text), .unreachable(let text), .vanished(let text): return text
            }
        }
    }

    /// What ComfyUI said when the job ended.
    struct Done {
        let id: String
        let outputs: [String: Any]
        let failed: Bool
        let interrupted: Bool
        /// Its exception message, when it failed.
        let error: String?
    }

    /// The tag that says which graph a queued job is: the same graph, the same tag.
    nonisolated static func tag(_ graph: [String: Any], client: String) -> String {
        var data = (try? JSONSerialization.data(withJSONObject: graph, options: [.sortedKeys])) ?? Data()
        data.append(Data(client.utf8))
        return SHA256.hash(data: data).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Running one

    /// Queue `graph` (or take up the one already queued), wait for it, and say ComfyUI's error as a
    /// failure. `deadline` counts from when it starts running; nil waits as long as it takes.
    static func run(_ graph: [String: Any], base: String, what: String, client: String,
                    deadline: TimeInterval?) async throws -> Done {
        let id = try await submit(graph, base: base, what: what, client: client)
        // Where it stands on the shared box — queue, node, step — for the tabs and the agents.
        ComfyWatch.shared.began(id, what: what, base: base)
        defer { ComfyWatch.shared.ended(id) }
        let done = try await finish(id, base: base, what: what, deadline: deadline, by: "KinClaw（\(what)）")
        if done.interrupted {
            throw Trouble.failed(await ComfyWatch.reason(id, what: what, base: base) ?? "\(what)在盒子上被打断了")
        }
        if done.failed { throw Trouble.failed("\(what)出错：" + (done.error ?? "看盒子上的 comfy.log").prefix(300)) }
        return done
    }

    /// Queue `graph` — or find it queued, running, or (with `reuseDone`) done well by an earlier try.
    /// Its prompt id.
    static func submit(_ graph: [String: Any], base: String, what: String, client: String,
                       reuseDone: Bool = true) async throws -> String {
        let tag = Self.tag(graph, client: client)
        if let found = await find(tag, base: base, reuseDone: reuseDone) { return found }
        guard let url = URL(string: base + "/prompt") else { throw Trouble.refused("ComfyUI 地址不对") }
        var last: Error?
        for attempt in 0..<3 {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": graph, "client_id": client,
                                                                           "extra_data": ["kinclaw_tag": tag]])
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                guard (response as? HTTPURLResponse)?.statusCode == 200, let id = answer["prompt_id"] as? String else {
                    throw Trouble.refused("ComfyUI 不接这个\(what)：\(String(data: data, encoding: .utf8)?.prefix(300) ?? "")", answer: answer)
                }
                return id
            } catch let trouble as Trouble {
                throw trouble
            } catch {
                last = error
                guard BoxTrouble.isTransient(error), !Task.isCancelled else { throw error }
                // The answer was lost on the way: it may have been queued all the same.
                try? await Task.sleep(nanoseconds: UInt64(2 + attempt * 3) * 1_000_000_000)
                if let found = await find(tag, base: base, reuseDone: reuseDone) { return found }
            }
        }
        throw last ?? Trouble.unreachable("ComfyUI 没应答")
    }

    /// A job with this tag on the box: queued or running — or done well and still in the recent
    /// history, when `reuseDone`. A failed one is not taken up: it is queued again.
    static func find(_ tag: String, base: String, reuseDone: Bool = true) async -> String? {
        if case .answer(let value) = await get(base + "/queue"), let queue = value as? [String: Any] {
            for key in ["queue_running", "queue_pending"] {
                for item in queue[key] as? [[Any]] ?? [] where item.count > 3 {
                    if (item[3] as? [String: Any])?["kinclaw_tag"] as? String == tag, let id = item[1] as? String { return id }
                }
            }
        }
        guard reuseDone, case .answer(let value) = await get(base + "/history?max_items=32"),
              let history = value as? [String: Any] else { return nil }
        for (id, value) in history {
            guard let entry = value as? [String: Any], let prompt = entry["prompt"] as? [Any], prompt.count > 3,
                  (prompt[3] as? [String: Any])?["kinclaw_tag"] as? String == tag else { continue }
            let status = entry["status"] as? [String: Any]
            if status?["status_str"] as? String == "success", status?["completed"] as? Bool == true { return id }
        }
        return nil
    }

    /// Wait for job `id` until ComfyUI says it ended — done, failed or interrupted. `deadline` counts
    /// from when it is first seen running; past it, the job is stopped on the box. Stopped here
    /// (cancelled), it is stopped there too: the box would render for nobody for minutes.
    static func finish(_ id: String, base: String, what: String, deadline seconds: TimeInterval?, by: String) async throws -> Done {
        var started: Date?
        var missing: Date?
        var answered = Date()
        var looks = 0
        do {
            while true {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                looks += 1
                switch await get(base + "/history/\(id)") {
                case .answer(let value):
                    answered = Date()
                    if let entry = (value as? [String: Any])?[id] as? [String: Any], let done = ended(id, entry) { return done }
                case .noAnswer:
                    break
                }
                // Every twenty seconds: queued, running, or gone?
                if looks % 5 == 0 {
                    switch await place(id, base: base) {
                    case .running:
                        answered = Date()
                        missing = nil
                        if started == nil { started = Date() }
                    case .pending:
                        answered = Date()
                        missing = nil
                    case .absent:
                        answered = Date()
                        // Not queued: just finished (the history has it at the next look), or gone.
                        let since = missing ?? Date()
                        missing = since
                        if Date().timeIntervalSince(since) > 90 {
                            throw Trouble.vanished("\(what)在盒子上不见了：不在 ComfyUI 的队列里，也不在它的记录里（ComfyUI 重启过，或被删了）")
                        }
                    case .noAnswer:
                        break
                    }
                }
                if Date().timeIntervalSince(answered) > 1800 {
                    throw Trouble.unreachable("\(what)：盒子的 ComfyUI 半小时连不上了；任务也许还在那边跑，接着做会接上它")
                }
                if let seconds, let started, Date().timeIntervalSince(started) > seconds {
                    await ComfyWatch.interrupt(id, base: base, by: by, why: "跑了 \(Int(seconds / 60)) 分钟还没好")
                    throw Trouble.failed("\(what)跑了 \(Int(seconds / 60)) 分钟还没好，已在盒子上停下")
                }
            }
        } catch {
            if Task.isCancelled { await ComfyWatch.interrupt(id, base: base, by: by, why: "在 app 里停下了") }
            throw error
        }
    }

    /// ComfyUI's history entry when it says the job ended; nil while it runs.
    private static func ended(_ id: String, _ entry: [String: Any]) -> Done? {
        let status = entry["status"] as? [String: Any]
        let outputs = entry["outputs"] as? [String: Any] ?? [:]
        if status?["status_str"] as? String == "error" {
            let raw = status?["messages"] as? [[Any]] ?? []
            let interrupted = raw.contains { $0.first as? String == "execution_interrupted" }
            let messages = raw.compactMap { $0.count > 1 ? $0[1] as? [String: Any] : nil }
            return Done(id: id, outputs: outputs, failed: true, interrupted: interrupted,
                        error: messages.compactMap { $0["exception_message"] as? String }.first)
        }
        guard status?["completed"] as? Bool == true else { return nil }
        return Done(id: id, outputs: outputs, failed: false, interrupted: false, error: nil)
    }

    // MARK: - Its files

    /// The first file `node` saved — pictures, video or sound — fetched; nil when it saved none.
    static func file(_ done: Done, node: String, base: String, what: String) async throws -> Data? {
        let saved = done.outputs[node] as? [String: Any] ?? [:]
        let files = saved["images"] as? [[String: Any]] ?? saved["audio"] as? [[String: Any]] ?? saved["gifs"] as? [[String: Any]] ?? []
        guard let first = files.first else { return nil }
        return try await fetch(first, base: base, what: what)
    }

    /// One saved file from ComfyUI's /view, fetched again when the fetch fails on the way: the
    /// file is on the box, finished.
    static func fetch(_ item: [String: Any], base: String, what: String) async throws -> Data {
        guard let name = item["filename"] as? String else { throw Trouble.failed("\(what)跑完了但没存下来") }
        var parts = URLComponents(string: base + "/view")
        parts?.queryItems = [URLQueryItem(name: "filename", value: name),
                             URLQueryItem(name: "subfolder", value: item["subfolder"] as? String ?? ""),
                             URLQueryItem(name: "type", value: item["type"] as? String ?? "output")]
        guard let url = parts?.url else { throw Trouble.failed("取不回\(what)") }
        var last: Error?
        for attempt in 0..<4 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 120
                let (bytes, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                if code == 200 { return bytes }
                if code < 500 { throw Trouble.failed("取不回\(what)：盒子答 HTTP \(code)") }
                last = Trouble.unreachable("取\(what)时盒子答 HTTP \(code)")
            } catch let trouble as Trouble {
                throw trouble
            } catch {
                last = error
                guard BoxTrouble.isTransient(error), !Task.isCancelled else { throw error }
            }
            try? await Task.sleep(nanoseconds: UInt64(2 + attempt * 4) * 1_000_000_000)
        }
        throw last ?? Trouble.unreachable("取不回\(what)")
    }

    // MARK: - Asking the box

    enum Reply {
        case answer(Any)
        case noAnswer
    }

    enum Place { case running, pending, absent, noAnswer }

    /// Where job `id` is in ComfyUI's queue.
    static func place(_ id: String, base: String) async -> Place {
        guard case .answer(let value) = await get(base + "/queue"), let queue = value as? [String: Any] else { return .noAnswer }
        func has(_ key: String) -> Bool { (queue[key] as? [[Any]] ?? []).contains { $0.count > 1 && $0[1] as? String == id } }
        return has("queue_running") ? .running : has("queue_pending") ? .pending : .absent
    }

    /// JSON from the box, or no answer (a transport error, or something that is not JSON).
    static func get(_ address: String) async -> Reply {
        guard let url = URL(string: address) else { return .noAnswer }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try? JSONSerialization.jsonObject(with: data) else { return .noAnswer }
        return .answer(value)
    }
}

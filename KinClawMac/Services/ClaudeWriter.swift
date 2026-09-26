import Foundation
import Network

/// Claude on this Mac's subscription, as the Studio's writer ("film 里的分镜
/// 选不了本地 claude 订阅的").
///
/// Whatever in the Studio needs words — a storyboard, the words for a first
/// frame, a verdict on a take, a music brief, a workflow's values — asks "the
/// writer" over Ollama's /api/chat, in a dozen places. A subscription has no
/// API to call: it lives in Claude Code, signed in here. So this is an Ollama
/// with Claude underneath — loopback only, an ephemeral port, a secret in the
/// path — and each /api/chat is one `claude -p`: no tools, no settings, no
/// session kept, the caller's system prompt instead of Claude Code's own, the
/// pictures passed as pictures. Measured: a picture and a question answered
/// by claude-opus-5-5 in 2.7 s.
final class ClaudeWriter: @unchecked Sendable {
    /// What `kinclaw.film.writer.host` holds when it is the one picked.
    static let pick = "claude-subscription"
    /// The name it answers to, as a model.
    static let model = "claude"
    static let title = "Claude（这台 Mac 的订阅）"

    /// Claude Code on this Mac, if it is installed.
    static var binary: String? { AgentHarness.claude.binary }

    private static let lock = NSLock()
    private static var running: ClaudeWriter?

    /// The address to ask, as an Ollama's; nil without Claude Code.
    static func host() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let running { return running.base }
        guard let binary, let started = ClaudeWriter(binary: binary) else { return nil }
        running = started
        return started.base
    }

    private(set) var base = ""
    private let listener: NWListener
    private let binary: String
    private let secret = UUID().uuidString.lowercased()
    /// A folder of its own to run in: no CLAUDE.md above it to pick up.
    private let room = FileManager.default.temporaryDirectory.appendingPathComponent("kinclaw-claude-writer")
    private let work = DispatchQueue(label: "kinclaw.claude-writer", qos: .userInitiated, attributes: .concurrent)
    /// At most three at once: a film asks for a verdict on every take.
    private let seats = DispatchSemaphore(value: 3)

    private init?(binary: String) {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: params, on: .any) else { return nil }
        self.listener = listener
        self.binary = binary
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        _ = ready.wait(timeout: .now() + 3)
        guard let port = listener.port?.rawValue, port != 0 else { listener.cancel(); return nil }
        base = "http://127.0.0.1:\(port)/\(secret)"
    }

    // MARK: HTTP, as much of it as Ollama's clients use

    private func accept(_ conn: NWConnection) {
        conn.start(queue: work)
        read(conn, Data())
    }

    private func read(_ conn: NWConnection, _ got: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { conn.cancel(); return }
            var got = got
            if let data { got.append(data) }
            if let request = Request(got) {
                self.serve(request, on: conn)
            } else if done || error != nil || got.count > 64 << 20 {
                conn.cancel()
            } else {
                self.read(conn, got)
            }
        }
    }

    private struct Request {
        let path: String
        let body: Data

        /// A whole request, or nil while its body is still arriving.
        init?(_ data: Data) {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = lines.first?.split(separator: " ") ?? []
            let length = lines.dropFirst().compactMap { line -> Int? in
                let pair = line.split(separator: ":", maxSplits: 1)
                guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
                return Int(pair[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0
            let body = data[end.upperBound...]
            guard body.count >= length else { return nil }
            path = first.count >= 2 ? String(first[1]) : ""
            self.body = Data(body.prefix(length))
        }
    }

    private func serve(_ request: Request, on conn: NWConnection) {
        let prefix = "/" + secret
        guard request.path.hasPrefix(prefix + "/") else { return send(conn, status: "404 Not Found", json: ["error": "not found"]) }
        switch String(request.path.dropFirst(prefix.count)) {
        case "/api/tags": send(conn, json: ["models": [["name": Self.model, "model": Self.model]]])
        case "/api/show": send(conn, json: ["capabilities": ["completion", "vision"]])
        case "/api/chat": chat(request.body, on: conn)
        default: send(conn, status: "404 Not Found", json: ["error": "not found"])
        }
    }

    private func send(_ conn: NWConnection, status: String = "200 OK", json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// One /api/chat. The headers go at once and a space every ten seconds
    /// after them until the answer: a caller's timeout counts silence, Claude
    /// can take a minute over a storyboard, and whitespace before a JSON
    /// value is still JSON. The answer is Ollama's shape, one line of it when
    /// streamed; a failure is its `error`.
    private func chat(_ body: Data, on conn: NWConnection) {
        guard let asked = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let messages = asked["messages"] as? [[String: Any]] else {
            return send(conn, status: "400 Bad Request", json: ["error": "no messages"])
        }
        let streamed = asked["stream"] as? Bool ?? true            // Ollama's default
        let format = asked["format"]
        let type = streamed ? "application/x-ndjson" : "application/json"
        conn.send(content: Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8),
                  completion: .contentProcessed { _ in })
        let beat = DispatchSource.makeTimerSource(queue: work)
        beat.schedule(deadline: .now() + 10, repeating: 10)
        beat.setEventHandler { conn.send(content: Data(" ".utf8), completion: .contentProcessed { _ in }) }
        beat.resume()
        work.async {
            self.seats.wait()
            let answer = self.ask(messages, format: format)
            self.seats.signal()
            beat.cancel()
            var reply: [String: Any] = ["model": Self.model, "done": true,
                                        "created_at": ISO8601DateFormatter().string(from: Date())]
            switch answer {
            case .success(let text):
                reply["message"] = ["role": "assistant", "content": text]
                reply["done_reason"] = "stop"
            case .failure(let why):
                reply["error"] = why.text
            }
            var data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
            if streamed { data.append(0x0a) }
            conn.send(content: data, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    // MARK: Claude

    private struct Trouble: Error { let text: String }

    /// Ollama's messages as one turn for `claude -p`: the system messages its
    /// system prompt, what came before the last quoted, the pictures first.
    private func ask(_ messages: [[String: Any]], format: Any?) -> Result<String, Trouble> {
        var system = messages.filter { $0["role"] as? String == "system" }
            .compactMap { $0["content"] as? String }.joined(separator: "\n\n")
        if format != nil {
            system += "\n\nReply with JSON only — no words before or after it, no code fence."
            if let schema = format as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: schema) {
                system += " It must fit this JSON Schema: " + String(decoding: data, as: UTF8.self)
            }
        }
        if system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            system = "Answer exactly what is asked, in the shape it is asked for."
        }
        let talk = messages.filter { $0["role"] as? String != "system" }
        var text = ""
        for message in talk.dropLast() {
            text += "[\(message["role"] as? String ?? "user")]\n\(message["content"] as? String ?? "")\n\n"
        }
        text += talk.last?["content"] as? String ?? ""
        var content: [[String: Any]] = talk.flatMap { ($0["images"] as? [String]) ?? [] }.map { picture in
            ["type": "image", "source": ["type": "base64", "media_type": Self.kind(of: picture), "data": picture]]
        }
        content.append(["type": "text", "text": text])
        let line = ["type": "user", "message": ["role": "user", "content": content]] as [String: Any]

        try? FileManager.default.createDirectory(at: room, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--system-prompt", system, "--tools", "", "--strict-mcp-config", "--setting-sources", "",
                             "--no-session-persistence", "--disable-slash-commands"]
        process.currentDirectoryURL = room
        // Its own sign-in: nothing of an agent's aiming it at a host.
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE") && !$0.key.hasPrefix("ANTHROPIC") }
        env["PATH"] = AgentLauncher.childPath(for: binary)
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(Trouble(text: "Claude Code 起不来：\(error.localizedDescription)")) }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        work.asyncAfter(deadline: .now() + 300, execute: deadline)
        if let data = try? JSONSerialization.data(withJSONObject: line) {
            input.fileHandleForWriting.write(data + Data("\n".utf8))
        }
        try? input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        // The answer is the line of the kind "result".
        for raw in String(decoding: out, as: UTF8.self).split(separator: "\n").reversed() {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                  event["type"] as? String == "result" else { continue }
            let said = event["result"] as? String ?? ""
            if event["is_error"] as? Bool == true || (event["subtype"] as? String ?? "success") != "success" {
                return .failure(Trouble(text: "Claude：" + (said.isEmpty ? (event["subtype"] as? String ?? "出错了") : said)))
            }
            return .success(format == nil ? said : Self.json(in: said))
        }
        return .failure(Trouble(text: process.terminationReason == .uncaughtSignal
                                ? "Claude 五分钟没答完" : "Claude Code 没有回答（退出码 \(process.terminationStatus)）"))
    }

    /// What a base64 picture is, by its first bytes.
    private static func kind(of picture: String) -> String {
        if picture.hasPrefix("/9j/") { return "image/jpeg" }
        if picture.hasPrefix("R0lGOD") { return "image/gif" }
        if picture.hasPrefix("UklGR") { return "image/webp" }
        return "image/png"
    }

    /// The JSON in a reply asked for JSON only, without the fence or the
    /// sentence a model still sometimes puts around it.
    private static func json(in text: String) -> String {
        guard let open = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return text }
        let closer: Character = text[open] == "{" ? "}" : "]"
        guard let close = text.lastIndex(of: closer), open < close else { return text }
        return String(text[open...close])
    }
}

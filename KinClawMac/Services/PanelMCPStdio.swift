import Foundation

/// `KinClawMac --mcp-stdio`: the MCP server the kernel spawns, which is this
/// same binary doing nothing but carrying JSON-RPC lines to the running app.
///
/// It exists because the two ends cannot meet any other way. The kernel's MCP
/// client speaks stdio to a process it spawned; the browser and the terminals
/// the tools describe are inside an app it did not spawn. So: one line of JSON
/// in on stdin, one POST to the app's loopback port, one line of JSON out. No
/// AppKit, no window — main.swift sends this path off before the app starts.
///
/// When the app is not running — or is a different app, with a token this one
/// does not know — every call answers with an error saying so. Which is the
/// honest answer: the panel's tools are the panel's, and without it there is
/// nothing to read.
enum PanelMCPStdio {
    /// `--tools a,b,c`: the only tools this relay lets through — listed, and
    /// callable. A studio agent is given its tab's tools this way; a deny list
    /// in the agent itself stops the calls but leaves every other tool the
    /// panel has (the signed-in browser, the terminals) in its list. nil is
    /// all of them, for the kernel.
    private static let only: Set<String>? = {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--tools"), at + 1 < args.count else { return nil }
        return Set(args[at + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }()

    /// `--timeout <seconds>`: how long one call may take. The kernel gives up
    /// at sixty, hence fifty-five for it. A studio agent waits as long as the
    /// work takes — a download, a render — and was told "连不上面板" at 55 s
    /// while the app went on doing it.
    private static let timeout: TimeInterval = {
        let args = CommandLine.arguments
        guard let at = args.firstIndex(of: "--timeout"), at + 1 < args.count,
              let seconds = TimeInterval(args[at + 1]), seconds > 0 else { return 55 }
        return seconds
    }()

    /// `--images`: the pictures a tool names in `image://` lines come back as
    /// pictures too, for an agent that takes them in a tool's answer (Claude
    /// Code). The kernel attaches them itself, from the lines.
    private static let images = CommandLine.arguments.contains("--images")

    static func run() -> Never {
        // Unbuffered: the kernel reads a line and waits, and a reply sitting
        // in a buffer looks exactly like a server that has hung.
        setvbuf(stdout, nil, _IONBF, 0)

        // Each call on its own thread: one that takes minutes does not hold up
        // a status read behind it. Replies go out whole, a line each, in the
        // order they finish — JSON-RPC matches them by id. (The kernel asks
        // one at a time, so for it nothing changes.)
        let calls = DispatchQueue(label: "panel-relay", attributes: .concurrent)
        let out = NSLock()
        let open = DispatchGroup()
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            open.enter()
            calls.async {
                defer { open.leave() }
                guard let reply = forward(trimmed) else { return }
                out.lock()
                print(reply)
                out.unlock()
            }
        }
        open.wait()     // answer what was asked before the other end closed
        exit(0)
    }

    /// POST one JSON-RPC message to the app. nil when there is nothing to say
    /// back — a notification, which has no id and wants no reply.
    private static func forward(_ line: String) -> String? {
        let id = Self.id(in: line)
        let method = Self.method(in: line)
        if let only, method == "tools/call", let name = Self.toolName(in: line), !only.contains(name) {
            return id.map { error(id: $0, "\(name) 不在这个 agent 能用的工具里") }
        }
        guard let handshake = Handshake.read() else {
            return id.map { error(id: $0, "KinClaw Mac 没在运行 —— 面板的浏览器和终端工具要等它起来") }
        }
        guard let url = URL(string: "http://127.0.0.1:\(handshake.port)/mcp") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(handshake.token, forHTTPHeaderField: "X-KinClaw-Panel-Token")
        if images { request.setValue("1", forHTTPHeaderField: "X-KinClaw-Images") }
        // How long a tool may wait for its work before it answers.
        if timeout > 60 { request.setValue(String(Int(timeout - 30)), forHTTPHeaderField: "X-KinClaw-Patience") }
        request.httpBody = Data(line.utf8)

        var body: Data?
        var status = 0
        var failure: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, err in
            body = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            failure = err?.localizedDescription
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 3)

        if let failure {
            return id.map { error(id: $0, "连不上 KinClaw Mac 的面板：\(failure)") }
        }
        if status == 204 { return nil }
        guard status == 200, let body, !body.isEmpty else {
            return id.map { error(id: $0, "面板回了 HTTP \(status)") }
        }
        // The list, cut down to what this relay lets through.
        if let only, method == "tools/list",
           var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           var result = object["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            result["tools"] = tools.filter { ($0["name"] as? String).map(only.contains) ?? false }
            object["result"] = result
            if let data = try? JSONSerialization.data(withJSONObject: object) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        // One line: the kernel's reader is line-based, and the app answers
        // with compact JSON, but a stray newline would desynchronise it.
        return String(decoding: body, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The request's id, as JSON, so the error carries the same one back. The
    /// id may be a number or a string; both are copied through verbatim rather
    /// than parsed and re-rendered.
    private static func id(in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"], !(id is NSNull) else { return nil }
        if let number = id as? NSNumber { return number.stringValue }
        if let text = id as? String,
           let encoded = try? JSONSerialization.data(withJSONObject: [text], options: []),
           let wrapped = String(data: encoded, encoding: .utf8) {
            return String(wrapped.dropFirst().dropLast()) // ["x"] → "x"
        }
        return nil
    }

    private static func method(in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["method"] as? String
    }

    private static func toolName(in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any] else { return nil }
        return params["name"] as? String
    }

    private static func error(id: String, _ message: String) -> String {
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32001,"message":"\#(escaped)"}}"#
    }

    /// The port and token the app published, re-read on every call: the app may
    /// have restarted since the last one, and then both have changed.
    private struct Handshake {
        let port: Int
        let token: String

        static func read() -> Handshake? {
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".localkin/panel.json")
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let port = object["port"] as? Int, port > 0,
                  let token = object["token"] as? String, !token.isEmpty else { return nil }
            return Handshake(port: port, token: token)
        }
    }
}

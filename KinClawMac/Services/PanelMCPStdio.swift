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

    static func run() -> Never {
        // Unbuffered: the kernel reads a line and waits, and a reply sitting
        // in a buffer looks exactly like a server that has hung.
        setvbuf(stdout, nil, _IONBF, 0)

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let reply = forward(trimmed) else { continue }
            print(reply)
        }
        exit(0)
    }

    /// POST one JSON-RPC message to the app. nil when there is nothing to say
    /// back — a notification, which has no id and wants no reply.
    private static func forward(_ line: String) -> String? {
        let id = Self.id(in: line)
        guard let handshake = Handshake.read() else {
            return id.map { error(id: $0, "KinClaw Mac 没在运行 —— 面板的浏览器和终端工具要等它起来") }
        }
        guard let url = URL(string: "http://127.0.0.1:\(handshake.port)/mcp") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 55 // the kernel gives up at 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(handshake.token, forHTTPHeaderField: "X-KinClaw-Panel-Token")
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
        _ = done.wait(timeout: .now() + 58)

        if let failure {
            return id.map { error(id: $0, "连不上 KinClaw Mac 的面板：\(failure)") }
        }
        if status == 204 { return nil }
        guard status == 200, let body, !body.isEmpty else {
            return id.map { error(id: $0, "面板回了 HTTP \(status)") }
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

import Foundation
import Network

/// The panel's own MCP server: the browser tab and the terminals, as tools the
/// kernel's agent can call.
///
/// Why the panel and not the kernel's own fetch: the kernel has `kinbrowser`,
/// which fetches a URL from nowhere in particular. This browser is the one you
/// are signed into, with your cookies and whatever the page's JavaScript put on
/// the screen — and the terminals are the ones you are watching. An agent that
/// can read those is in the same room as you; one that can only fetch is not.
///
/// Shape of it, and why:
///
///   - The kernel's MCP client speaks stdio only (see kinclaw pkg/mcp), and the
///     state these tools need — live web views, running terminals — is inside
///     this app. So the server registered with the kernel is this app's own
///     binary with `--mcp-stdio`, a process that does nothing but relay
///     JSON-RPC lines to the app over loopback. See PanelMCPStdio.
///   - Loopback, and a token. Any process on this Mac can reach a loopback
///     port, and "open a URL in the user's signed-in browser" is not a thing to
///     hand out. The port and a per-launch token go in ~/.localkin/panel.json,
///     mode 0600, and a request without the token gets a 403.
///   - Read mostly. The agent can open a page, read a page, and read what a
///     terminal is showing. It cannot type into your shell: that is the one
///     that needs a conversation first.
@MainActor
final class PanelBridge {
    static let shared = PanelBridge()

    /// After 5001 (kinclaw) and 5002 (kincode). Fixed rather than ephemeral so
    /// a stale panel.json cannot point the relay at somebody else's port.
    static let preferredPort: UInt16 = 5003

    /// Where the relay looks for the port and the token.
    static let handshakePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".localkin/panel.json")

    private(set) var port: UInt16 = 0
    private var token = ""
    private var listener: NWListener?

    // MARK: - Lifecycle

    /// Start listening, publish the handshake file, and make sure the kernel's
    /// mcp.json names this app. Safe to call twice.
    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let endpoint = NWEndpoint.Port(rawValue: Self.preferredPort),
              let l = try? NWListener(using: params, on: endpoint) else {
            NSLog("panel bridge: port \(Self.preferredPort) is taken — the agent's browser and terminal tools are off this launch")
            return
        }
        token = UUID().uuidString
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            self?.receive(on: conn, so_far: Data())
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
        port = Self.preferredPort
        publishHandshake()
        registerWithKernel()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        try? FileManager.default.removeItem(at: Self.handshakePath)
    }

    /// The port and the token, for the relay to read. 0600: it is a capability.
    private func publishHandshake() {
        let body: [String: Any] = ["port": Int(port), "token": token,
                                   "pid": ProcessInfo.processInfo.processIdentifier]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let url = Self.handshakePath
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Put this app in ~/.localkin/mcp.json as the "panel" server, or update the
    /// command when the app has moved — a Debug build's path changes with
    /// DerivedData. Other servers in the file are left alone.
    ///
    /// The kernel starts its MCP servers when it starts, so a kernel that was
    /// already running when this was written does not see it until it restarts.
    /// That is what MCPConfigStore.needsRestart is for; here it is only logged.
    private func registerWithKernel() {
        let url = MCPConfigStore.configPath
        let command = Bundle.main.executableURL?.standardizedFileURL.path ?? ""
        guard !command.isEmpty else { return }

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let existing = servers["panel"] as? [String: Any]
        let entry: [String: Any] = ["command": command, "args": ["--mcp-stdio"]]
        if let existing, existing["command"] as? String == command,
           (existing["args"] as? [String]) == ["--mcp-stdio"] {
            return // already right
        }
        servers["panel"] = entry
        root["mcpServers"] = servers
        guard let out = try? JSONSerialization.data(withJSONObject: root,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try out.write(to: url, options: .atomic)
            NSLog("panel bridge: registered in %@ — the kernel picks it up when it next starts",
                  url.path)
        } catch {
            NSLog("panel bridge: could not write %@: %@", url.path, error.localizedDescription)
        }
    }

    // MARK: - HTTP

    /// One request per connection, `Connection: close`. The relay sends a line
    /// of JSON and waits for a line of JSON; nothing here needs keep-alive.
    private nonisolated func receive(on conn: NWConnection, so_far: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, _ in
            guard let self else { conn.cancel(); return }
            var buffer = so_far
            if let data { buffer.append(data) }
            guard let request = HTTPRequest(buffer) else {
                if done || buffer.count > 4 << 20 { conn.cancel(); return }
                self.receive(on: conn, so_far: buffer)
                return
            }
            Task { @MainActor in
                let response = await self.answer(request)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private func answer(_ request: HTTPRequest) async -> Data {
        guard request.path == "/mcp" else {
            return Self.http(status: "404 Not Found", body: Data("not found".utf8), type: "text/plain")
        }
        guard request.header("x-kinclaw-panel-token") == token, !token.isEmpty else {
            return Self.http(status: "403 Forbidden", body: Data("bad token".utf8), type: "text/plain")
        }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return Self.jsonrpc(["jsonrpc": "2.0", "id": NSNull(),
                                 "error": ["code": -32700, "message": "parse error"]])
        }
        guard let reply = await handle(message) else {
            // A notification: nothing to answer with.
            return Self.http(status: "204 No Content", body: Data(), type: "text/plain")
        }
        return Self.jsonrpc(reply)
    }

    private static func jsonrpc(_ reply: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{}".utf8)
        return http(status: "200 OK", body: body, type: "application/json")
    }

    private static func http(status: String, body: Data, type: String) -> Data {
        var head = Data("""
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r\n
        """.utf8)
        head.append(body)
        return head
    }

    // MARK: - JSON-RPC

    /// The three methods an MCP client needs, and the call. nil means the
    /// message was a notification and wants no reply.
    func handle(_ message: [String: Any]) async -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        func result(_ value: Any) -> [String: Any]? {
            guard let id, !(id is NSNull) else { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": value]
        }
        func failure(_ code: Int, _ text: String) -> [String: Any]? {
            guard let id, !(id is NSNull) else { return nil }
            return ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
        }

        switch method {
        case "initialize":
            // Echo the client's version: the kernel asks for 2024-11-05, and a
            // server that answers with a different one is a server it may not
            // talk to.
            let version = params["protocolVersion"] as? String ?? "2024-11-05"
            return result([
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "kinclaw-panel", "version": "1"],
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return result([String: Any]())
        case "tools/list":
            return result(["tools": PanelTools.definitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = await PanelTools.call(name, args)
            return result(["content": [["type": "text", "text": text]], "isError": isError])
        default:
            return failure(-32601, "unknown method \(method)")
        }
    }
}

// MARK: - A request, parsed far enough

/// Method, path, headers and body of one HTTP/1.1 request. Returns nil while
/// the bytes so far are not a whole request yet.
struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
    private let headers: [String: String]

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    init?(_ data: Data) {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<split.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard let request = lines.first else { return nil }
        lines.removeFirst()
        let parts = request.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        var p = String(parts[1])
        if let q = p.firstIndex(of: "?") { p = String(p[p.startIndex..<q]) }
        path = p

        var collected: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            collected[key] = value
        }
        headers = collected

        let length = Int(collected["content-length"] ?? "0") ?? 0
        let rest = data[split.upperBound...]
        guard rest.count >= length else { return nil }
        body = Data(rest.prefix(length))
    }
}

import Foundation
import Network

/// A local static file server for the avatar page.
///
/// The digital human runs entirely in a web view — its inference is a
/// WASM module — and WASM will not instantiate from `file://`: the
/// browser refuses the fetch, and it refuses quietly, so the page just
/// never finishes loading. It needs an origin. This is the smallest
/// thing that is one: loopback only, an ephemeral port, and it serves
/// exactly one directory.
///
/// The MIME type matters more than it looks. `.wasm` served as
/// anything but `application/wasm` fails `instantiateStreaming` with an
/// error most pages swallow, which is a long afternoon if you do not
/// know to check it first.
@MainActor
final class AvatarServer {

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let root: URL

    init(root: URL) { self.root = root }

    /// Start on an ephemeral port. Returns the base URL, or nil when
    /// the listener could not start — the caller shows the still
    /// picture instead, which is what it would have shown anyway.
    @discardableResult
    func start() -> URL? {
        if let p = listener != nil ? port : nil, p != 0 {
            return URL(string: "http://127.0.0.1:\(p)/")
        }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let l = try? NWListener(using: params, on: .any) else { return nil }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            self?.receive(on: conn)
        }
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        l.start(queue: .global(qos: .userInitiated))
        _ = ready.wait(timeout: .now() + 3)
        guard let p = l.port?.rawValue, p != 0 else { l.cancel(); return nil }
        listener = l
        port = p
        return URL(string: "http://127.0.0.1:\(p)/")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: Serving

    private nonisolated func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, _ in
            guard let self, let data, !data.isEmpty else {
                if done { conn.cancel() }
                return
            }
            let head = String(decoding: data, as: UTF8.self)
            let path = Self.requestedPath(head)
            Task { @MainActor in
                let response = self.response(for: path)
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private nonisolated static func requestedPath(_ head: String) -> String {
        guard let line = head.split(separator: "\r\n", maxSplits: 1).first else { return "/" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        var p = String(parts[1])
        if let q = p.firstIndex(of: "?") { p = String(p[p.startIndex..<q]) }
        return p.removingPercentEncoding ?? p
    }

    private func response(for path: String) -> Data {
        var rel = path == "/" ? "MiniLive.html" : String(path.dropFirst())
        // Loopback and one directory, but a path is still user input:
        // resolve it and refuse anything that climbed out.
        rel = rel.replacingOccurrences(of: "\\", with: "/")
        let file = root.appendingPathComponent(rel).standardizedFileURL
        let base = root.standardizedFileURL.path
        guard file.path == base || file.path.hasPrefix(base + "/"),
              let body = try? Data(contentsOf: file) else {
            return Self.head(status: "404 Not Found", type: "text/plain", length: 9) + Data("not found".utf8)
        }
        return Self.head(status: "200 OK", type: Self.mime(file.pathExtension), length: body.count) + body
    }

    private static func head(status: String, type: String, length: Int) -> Data {
        Data("""
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(length)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r\n
        """.utf8)
    }

    private static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "text/javascript; charset=utf-8"
        case "wasm":        return "application/wasm"   // see the note above
        case "json":        return "application/json"
        case "gz":          return "application/gzip"
        case "css":         return "text/css; charset=utf-8"
        case "mp4", "m4v":  return "video/mp4"
        case "wav":         return "audio/wav"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico":         return "image/x-icon"
        case "woff2":       return "font/woff2"
        case "woff":        return "font/woff"
        case "ttf":         return "font/ttf"
        default:            return "application/octet-stream"
        }
    }
}

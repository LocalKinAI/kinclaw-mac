import Foundation

// MARK: - Events
//
// Mirror of `pkg/server/server.go : Event`. All fields are optional
// because the server only sets the ones relevant to the event type
// (e.g. text_delta has Text, tool_call has Name+Params, error has
// Message). Callers switch on `type` and read the right fields.

/// SSE event from `GET /api/events`. The kinclaw server publishes
/// `user_message`, `text_delta`, `tool_call`, `tool_result`,
/// `screen_frame`, `record_done`, `soul_switched`, `turn_done`,
/// `error`, and a `hello` event for late subscribers.
struct KinClawEvent: Codable {
    let type: String

    // text deltas (assistant streaming reply)
    let text: String?
    let thinking: Bool?

    // tool_call invocations
    let id: String?
    let name: String?
    let params: [String: String]?
    /// Pre-computed display string for tool_call ("ls -la /tmp",
    /// "src/main.go"). Emitted by kincode; kinclaw events leave this
    /// nil and the UI derives a label from `params`. For kinclaw
    /// `permission_request` events it is the one-line call summary.
    let summary: String?
    /// permission_request: why the gate stopped (rule / dangerous).
    let reason: String?

    // tool_result / screen_frame / record_done payloads
    let output: String?
    let images: [String]?
    let urls: [String]?
    let path: String?
    let url: String?

    // usage stats — kincode emits at end of turn; kinclaw emits a
    // `usage` event after every model call with context_length so the
    // UI can draw a meter.
    let input_tokens: Int?
    let output_tokens: Int?
    let context_length: Int?

    // compacted: what the fold removed.
    let before_tokens: Int?
    let after_tokens: Int?

    // question: choices offered with the question (message = the question).
    let options: [String]?

    // workspace: the folder relative paths resolve against.
    let workspace: String?

    // user_message: image-attachment count (kincode plan mode).
    let image_count: Int?

    // plan_mode broadcast: true = entered plan mode, false = exited.
    let plan_mode: Bool?

    // error
    let message: String?
}

extension KinClawEvent {
    /// Convenience type tags so call sites switch on a Swift-side enum
    /// rather than raw strings everywhere.
    enum Kind: String {
        case hello
        case userMessage   = "user_message"
        case textDelta     = "text_delta"
        case toolCall      = "tool_call"
        case toolResult    = "tool_result"
        case screenFrame   = "screen_frame"
        case recordDone    = "record_done"
        case soulSwitched  = "soul_switched"
        case brainSwitched = "brain_switched"
        case sessionReset  = "session_reset"
        case spawnDone     = "spawn_done"
        case turnDone      = "turn_done"
        case planMode      = "plan_mode"
        /// kinclaw ≥ 1.18: the kernel's permission gate wants a human
        /// decision; answer via POST /api/permission with the same id.
        case permissionRequest  = "permission_request"
        /// Someone answered (or the wait was cancelled) — drop the card.
        case permissionResolved = "permission_resolved"
        case permissionMode     = "permission_mode"
        /// Token accounting after each model call.
        case usage
        /// Older turns were folded into a summary.
        case compacted
        /// Kernel-originated text mid-turn (circuit breaker, hook block,
        /// permission denial). NOT an error: the turn continues.
        case notice
        /// ask_user: the agent has a question; answer via POST /api/answer.
        case question
        case questionResolved = "question_resolved"
        /// The session's working folder changed.
        case workspace
        case error
    }

    var kind: Kind? { Kind(rawValue: type) }
}

// MARK: - Errors

enum KinClawAPIError: LocalizedError {
    case unreachable(URL)
    case invalidResponse
    case server(status: Int, body: String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            return "kinclaw not reachable at \(url.absoluteString)"
        case .invalidResponse:
            return "kinclaw returned an unparseable response"
        case .server(let status, let body):
            return "kinclaw HTTP \(status): \(body)"
        case .stream(let msg):
            return "kinclaw event stream: \(msg)"
        }
    }
}

// MARK: - Client

/// Talks to a local `kinclaw serve` instance — by default at
/// `http://localhost:5001` (per Jacky 2026-05-03; previously :8020).
///
/// kinclaw exposes a two-channel chat protocol:
///
///   - `POST /api/chat {message}` to *kick* a turn (echoes via SSE
///     immediately, then the assistant reply streams as deltas).
///   - `GET /api/events` (SSE) to *receive* — text deltas, tool
///     calls, tool results, soul switches, turn_done.
///
/// Caller is expected to keep one event-stream subscription open for
/// the lifetime of the chat view, and POST messages independently.
/// History is server-side; clients send only the new user message.
final class KinClawAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// Default singleton pointing at `http://localhost:5001`.
    static let `default` = KinClawAPIClient()

    init(baseURL: URL = URL(string: "http://localhost:5001")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // SSE streams stay open indefinitely — never time out the
        // underlying resource. Per-request timeout still bounds
        // non-streaming calls.
        config.timeoutIntervalForResource = .infinity
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health

    /// True if `GET /api/souls` returns 200. Used by the supervisor
    /// (M4) to decide when the spawned kinclaw subprocess is ready,
    /// and by the source switcher to gray out "Local" when offline.
    func ping() async -> Bool {
        do {
            _ = try await fetchSouls()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Souls

    /// `GET /api/souls` — list available souls (active flag marks
    /// the one currently loaded). Returns empty array (not error)
    /// if soul listing isn't wired (501) — same shape as "no souls
    /// found" so the UI handles both the same way.
    func fetchSouls() async throws -> [Soul] {
        let url = baseURL.appendingPathComponent("api/souls")
        let (data, response) = try await sessionData(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw KinClawAPIError.invalidResponse
        }
        if http.statusCode == 501 { return [] }
        try checkOK(http, body: data)
        return try decoder.decode([Soul].self, from: data)
    }

    /// `POST /api/soul {path}` — switch the running session over.
    /// Server returns 202 on success, 4xx with the error message if
    /// the swap is refused (turn in flight, soul fails to load).
    func switchSoul(path: String) async throws {
        let url = baseURL.appendingPathComponent("api/soul")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["path": path])
        let (data, response) = try await sessionDataFor(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw KinClawAPIError.invalidResponse
        }
        // 202 Accepted is the documented success code, but accept any
        // 2xx defensively.
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw KinClawAPIError.server(status: http.statusCode, body: body)
        }
    }

    // MARK: - Chat

    /// `POST /api/chat {message, images?}` — kick a turn. Reply
    /// streams over the events channel; this call returns once the
    /// server has accepted the message (typically immediately).
    /// Server tracks conversation history per-soul so we send only
    /// the new user message.
    ///
    /// `images` is non-nil when the user attached pictures. kincode
    /// translates these into Anthropic vision blocks / OpenAI
    /// image_url parts at the provider level — non-vision models
    /// will reject the turn at API time.
    func sendChat(_ message: String,
                  images: [ImageAttachment] = []) async throws {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            let message: String
            let images: [ImageAttachment]?
        }
        let body = Body(message: message,
                        images: images.isEmpty ? nil : images)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// One image attached to a chat turn. mediaType ∈ {image/png,
    /// image/jpeg, image/gif, image/webp}. data is the raw base64
    /// (no data: URL prefix — kincode provider layer adds prefix
    /// when calling OpenAI; Anthropic uses raw base64 directly).
    struct ImageAttachment: Encodable, Identifiable, Hashable {
        let id: UUID
        let mediaType: String
        let data: String

        init(mediaType: String, data: String, id: UUID = UUID()) {
            self.id = id
            self.mediaType = mediaType
            self.data = data
        }

        // ID is a client-side handle for SwiftUI ForEach; not sent.
        enum CodingKeys: String, CodingKey {
            case mediaType = "media_type"
            case data
        }
    }

    /// `POST /api/plan_mode {enabled}` — flip kincode's plan-mode
    /// gate. While on, the agent denies write/exec/spawn tools and
    /// prepends a directive teaching the model to emit a markdown
    /// plan instead. Returns the post-toggle state (server may
    /// refuse e.g. mid-turn).
    /// `POST /api/permission_mode {mode}` — switch the approval gate
    /// between "ask" and "auto" mid-session. Returns the mode actually
    /// in force, which is not always the one requested.
    func setPermissionMode(_ mode: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/permission_mode")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["mode": mode])
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        struct Reply: Decodable { let mode: String }
        return try JSONDecoder().decode(Reply.self, from: data).mode
    }

    func setPlanMode(_ enabled: Bool) async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/plan_mode")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["enabled": enabled])
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        struct Reply: Decodable { let enabled: Bool }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return reply.enabled
    }

    /// `DELETE /api/chat` — cancel the in-flight turn via the
    /// server's interrupt handler. No-op if no turn is running.
    func cancelTurn() async throws {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    // MARK: - Permission gate / context (kinclaw ≥ 1.18)

    /// `POST /api/permission {id, decision}` — answer a
    /// `permission_request`. decision ∈ allow | allow_session | deny.
    /// 404 means the request already resolved (timed out, or the turn
    /// was stopped) — callers treat that as "card is stale", not error.
    func respondPermission(id: String, decision: String) async throws {
        let url = baseURL.appendingPathComponent("api/permission")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": id, "decision": decision])
        let (data, response) = try await sessionDataFor(request: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return }
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// `POST /api/answer {id, text}` — answer an `ask_user` question.
    /// 404 means it already resolved (timeout / stop); treated as stale.
    func answerQuestion(id: String, text: String) async throws {
        let url = baseURL.appendingPathComponent("api/answer")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": id, "text": text])
        let (data, response) = try await sessionDataFor(request: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return }
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// `POST /api/workspace {path}` — change the folder relative paths and
    /// shell commands use; writes outside it ask first. Returns the
    /// cleaned path the kernel settled on.
    func setWorkspace(path: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/workspace")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["path": path])
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        struct Reply: Decodable { let workspace: String }
        return try decoder.decode(Reply.self, from: data).workspace
    }

    /// `POST /api/compact` — fold older conversation into a summary
    /// now. Returns the kernel's one-line outcome. 409 while a turn is
    /// running.
    func compact() async throws -> String {
        let url = baseURL.appendingPathComponent("api/compact")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        struct Reply: Decodable { let message: String? }
        return (try? decoder.decode(Reply.self, from: data))?.message ?? "compacted"
    }

    /// `GET /api/state` on kinclaw — soul, brain, gate mode, plan mode,
    /// prompt size vs context window. Used to prime the Cowork header
    /// on connect and refresh it after each turn.
    struct KinClawState: Decodable {
        let soul: String?
        let brain: String?
        let permission_mode: String?
        let plan_mode: Bool?
        let session_allowed: [String]?
        let messages: Int?
        let input_tokens: Int?
        let context_length: Int?
        let total_input_tokens: Int?
        let total_output_tokens: Int?
        let workspace: String?
        let deferred: [String]?
        let loaded: [String]?
    }
    func fetchKinClawState() async throws -> KinClawState {
        let url = baseURL.appendingPathComponent("api/state")
        let (data, response) = try await sessionData(from: url)
        try checkOK(response as? HTTPURLResponse, body: data)
        return try decoder.decode(KinClawState.self, from: data)
    }

    // MARK: - Voice

    /// `POST /api/voice/transcribe` — proxies upstream STT (default
    /// SenseVoice on :8000). Multipart form data with a "file" field.
    /// Returns the recognized text (`{"text": "..."}`).
    func transcribe(audio: Data, mimeType: String = "audio/wav",
                    filename: String = "rec.wav") async throws -> String {
        let url = baseURL.appendingPathComponent("api/voice/transcribe")
        let boundary = "kinclaw-mac-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".utf8Data)
        request.httpBody = body

        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        struct R: Codable { let text: String }
        return try decoder.decode(R.self, from: data).text
    }

    /// `POST /api/voice/tts {text, speaker?}` — returns audio/wav
    /// bytes synthesized by the upstream TTS server (default Kokoro
    /// on :8001).
    func synthesize(text: String, speaker: String? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent("api/voice/tts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct B: Codable { let text: String; let speaker: String? }
        request.httpBody = try JSONEncoder().encode(B(text: text, speaker: speaker))
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
        return data
    }

    // MARK: - SSE event stream

    /// Subscribe to `GET /api/events`. The returned async sequence
    /// yields one `KinClawEvent` per `data:` line; consumer cancels
    /// by breaking out of the for-await loop or invalidating the
    /// session.
    ///
    /// Late-joining subscribers receive a synthetic `hello` event
    /// with the active soul info, then live events from there. No
    /// historical replay.
    func eventStream() -> AsyncThrowingStream<KinClawEvent, Error> {
        let url = baseURL.appendingPathComponent("api/events")
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // Strong reference captured in the Task; if the consumer drops
        // the stream the onTermination handler cancels the URLSession
        // task which unblocks the byte iteration.
        let session = self.session
        let decoder = self.decoder

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: KinClawAPIError.invalidResponse)
                        return
                    }
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: KinClawAPIError.server(
                            status: http.statusCode, body: ""))
                        return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        // SSE: only `data: ...` lines carry JSON. Skip
                        // comments (`: connected`), empty lines (record
                        // separators), and unknown frame types.
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let event = try? decoder.decode(KinClawEvent.self, from: data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private func sessionData(from url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            // Wrap "connection refused" / "host not found" into the
            // unreachable case so the UI can render "kinclaw not
            // running" instead of a raw URLError.
            if (error as NSError).domain == NSURLErrorDomain {
                throw KinClawAPIError.unreachable(url)
            }
            throw error
        }
    }

    private func sessionDataFor(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain,
               let url = request.url {
                throw KinClawAPIError.unreachable(url)
            }
            throw error
        }
    }

    private func checkOK(_ http: HTTPURLResponse?, body: Data) throws {
        guard let http = http else { throw KinClawAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: body, encoding: .utf8) ?? ""
            throw KinClawAPIError.server(status: http.statusCode, body: msg)
        }
    }
}

// MARK: - Kincode flavor (Code mode)

/// kincode (Code mode) shares the kinclaw transport shape — same
/// POST /api/chat, GET /api/events, DELETE /api/chat — so we reuse
/// KinClawAPIClient with a different baseURL. The kincode-specific
/// surface (`/api/repo` to chdir the agent, `/api/state` for status)
/// is added here as an extension.
extension KinClawAPIClient {

    /// Singleton pointing at the local kincode server (default :5002).
    /// Used by Code mode (CodePane) for chat and repo control.
    static let kincode = KinClawAPIClient(
        baseURL: URL(string: "http://localhost:5002")!
    )

    /// `POST /api/repo {"path": "..."}` — chdir the kincode subprocess
    /// into the user's chosen repo. All subsequent bash / file_* tool
    /// calls operate relative to this dir.
    func setRepo(_ path: String) async throws {
        let url = baseURL.appendingPathComponent("api/repo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["path": path])
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// `GET /api/state` — current repo / model / provider / message
    /// count. Used by CodePane to label the repo header.
    struct ServerState: Codable {
        let repo: String?
        let model: String?
        let provider: String?
        let message_count: Int?
        let plan_mode: Bool?
        /// "ask" or "auto" — what kincode's approval gate is doing, so
        /// the footer shows the truth after a reconnect rather than its
        /// own last guess.
        let permission_mode: String?
    }
    func fetchState() async throws -> ServerState {
        let url = baseURL.appendingPathComponent("api/state")
        let (data, response) = try await sessionData(from: url)
        try checkOK(response as? HTTPURLResponse, body: data)
        return try decoder.decode(ServerState.self, from: data)
    }

    /// `POST /api/clear` — wipe the agent's conversation memory back
    /// to system-prompt-only state. Cancels any in-flight turn first.
    /// Used by Code mode's "new session" button to recover from
    /// stuck error states (e.g. a malformed history that 400s on
    /// every retry) without restarting the kincode subprocess.
    func clearConversation() async throws {
        let url = baseURL.appendingPathComponent("api/clear")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// `POST /api/brain` — switch the running agent's provider/model
    /// at runtime. Cancels any in-flight turn first server-side.
    /// `apiKey` and `endpoint` are optional; when omitted the server
    /// reads from env (ANTHROPIC_API_KEY / OPENAI_API_KEY) and uses
    /// per-provider defaults.
    func switchBrain(provider: String, model: String,
                     apiKey: String? = nil,
                     endpoint: String? = nil) async throws {
        let url = baseURL.appendingPathComponent("api/brain")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Codable {
            let provider: String
            let model: String
            let api_key: String?
            let endpoint: String?
        }
        request.httpBody = try JSONEncoder().encode(Body(
            provider: provider, model: model,
            api_key: apiKey, endpoint: endpoint
        ))
        let (data, response) = try await sessionDataFor(request: request)
        try checkOK(response as? HTTPURLResponse, body: data)
    }

    /// `POST /api/session/reset` — wipe the kernel's conversation tape
    /// without changing the soul/brain/skills. The "New session" button
    /// in Cowork hits this so a stuck mid-task tool-call loop from a
    /// prior conversation can't bleed into the next user message. The
    /// kernel responds 409 Conflict if a turn is in flight — caller
    /// should DELETE /api/chat first (the same Stop button machinery)
    /// then retry. Older kinclaw builds without the endpoint return
    /// 501; we silently swallow that so the Mac UI degrades gracefully
    /// to client-only reset on outdated kernels.
    func resetSession() async throws {
        let url = baseURL.appendingPathComponent("api/session/reset")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, response) = try await sessionDataFor(request: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 501 {
            // Endpoint not wired on this kernel build — the client
            // already cleared local state; nothing more to do.
            return
        }
        try checkOK(http, body: data)
    }
}

// MARK: - Tiny helpers

private extension String {
    /// Forced UTF-8 conversion — only used for fixed ASCII multipart
    /// preambles, so the force-unwrap is safe.
    var utf8Data: Data { data(using: .utf8)! }
}

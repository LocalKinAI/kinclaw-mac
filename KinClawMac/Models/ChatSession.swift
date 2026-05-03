import Foundation

/// A single chat conversation — one back-and-forth thread with a
/// specific agent. Multiple sessions per agent: history list, click
/// to switch, delete one without losing others, "new" to start
/// fresh.
///
/// Stored as one JSON file per session at:
///   ~/.kinclaw/sessions/<agentSlug>/<id>.json
///
/// Why ~/.kinclaw/ and not ~/.localkin/:
///   ~/.localkin/ is the **shared** LocalKin family runtime data —
///   memory.db / souls / serve-sessions are written by the kinclaw
///   kernel itself and consumed by any LocalKin product. Sessions
///   are KinClaw Mac UI state — they belong with the *product*, not
///   the *runtime*. Splitting them keeps each home single-purpose
///   and lets users back up / nuke either half independently.
///
/// JSON layout (human-readable so users can grep / inspect / copy):
/// ```json
/// {
///   "id": "uuid",
///   "agentSlug": "KinClaw Pilot",
///   "title": "Trader Joe 导航",
///   "createdAt": "2026-05-03T18:30:00Z",
///   "updatedAt": "2026-05-03T18:34:22Z",
///   "messages": [...]
/// }
/// ```
struct ChatSession: Codable, Identifiable, Equatable {
    let id: UUID
    let agentSlug: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [PersistedMessage]

    init(id: UUID = UUID(),
         agentSlug: String,
         title: String = "New chat",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         messages: [PersistedMessage] = []) {
        self.id = id
        self.agentSlug = agentSlug
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// Display title — falls back to "Untitled" + short timestamp
    /// when the user hasn't said anything yet.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "New chat" {
            return "Untitled · \(Self.shortTime.string(from: createdAt))"
        }
        return trimmed
    }

    private static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f
    }()
}

/// Storage shape for a single chat message inside a session JSON.
/// Slimmer than the in-memory ChatMessage — drops UUID id (regenerated
/// on load), keeps role / content / timestamp / toolCalls /
/// attachments. Codable round-trips cleanly.
struct PersistedMessage: Codable, Equatable {
    let role: String
    let content: String
    let timestamp: Date
    var toolCalls: [PersistedToolCall] = []
    var attachments: [PersistedAttachment] = []

    init(from msg: ChatMessage) {
        self.role = msg.role.rawValue
        self.content = msg.content
        self.timestamp = msg.timestamp
        self.toolCalls = msg.toolCalls.map(PersistedToolCall.init(from:))
        self.attachments = msg.attachments.map(PersistedAttachment.init(from:))
    }

    func toMessage() -> ChatMessage {
        var m = ChatMessage(
            id: UUID(),
            role: ChatMessage.Role(rawValue: role) ?? .assistant,
            content: content,
            timestamp: timestamp
        )
        m.toolCalls = toolCalls.map { $0.toToolCall() }
        m.attachments = attachments.compactMap { $0.toAttachment() }
        return m
    }
}

struct PersistedToolCall: Codable, Equatable {
    let id: String
    let name: String
    let params: [String: String]
    var output: String?

    init(from tc: ToolCall) {
        self.id = tc.id
        self.name = tc.name
        self.params = tc.params
        self.output = tc.output
    }

    func toToolCall() -> ToolCall {
        ToolCall(id: id, name: name, params: params, output: output)
    }
}

struct PersistedAttachment: Codable, Equatable {
    let kindRaw: String
    let localPath: String?
    let remoteURL: String?
    let displayName: String

    init(from a: Attachment) {
        self.kindRaw = a.kind.rawValue
        self.localPath = a.localURL?.path
        self.remoteURL = a.remoteURL?.absoluteString
        self.displayName = a.displayName
    }

    func toAttachment() -> Attachment? {
        if let path = localPath {
            return Attachment(localURL: URL(fileURLWithPath: path))
        }
        if let s = remoteURL, let url = URL(string: s) {
            return Attachment(remoteURL: url, displayName: displayName)
        }
        return nil
    }
}

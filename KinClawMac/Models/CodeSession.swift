import Foundation

/// One persisted Code-mode conversation. Keyed by repo path —
/// switching repos in CodePane swaps sessions, so going back to a
/// repo restores the last conversation about it.
///
/// Stored as JSON at `~/.kinclaw/code-sessions/<repoHash>/<id>.json`.
/// We currently keep only one active session per repo (the most
/// recently updated); the schema leaves room for multi-session per
/// repo if the UI gains a session picker later.
struct CodeSession: Codable, Identifiable {
    let id: UUID
    /// Absolute path of the repo this session is scoped to.
    let repoPath: String
    var messages: [PersistedCodeMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         repoPath: String,
         messages: [PersistedCodeMessage] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.repoPath = repoPath
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Codable mirror of CodeMessage. Lives in Models/ rather than UI/
/// because UI types should stay free of disk-layer concerns. The
/// CodePane translates CodeMessage ↔ PersistedCodeMessage at the
/// store boundary.
struct PersistedCodeMessage: Codable {
    enum Role: String, Codable {
        case user, assistant, toolCall = "tool_call",
             toolResult = "tool_result", error
    }

    let id: UUID
    let role: Role
    var text: String
    let toolName: String?
    let toolError: String?
}

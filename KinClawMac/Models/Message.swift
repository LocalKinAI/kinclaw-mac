import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    /// Tool invocations attached to this message — populated by the
    /// local kinclaw transport from `tool_call` / `tool_result`
    /// SSE events. Cloud agents don't emit these; the array stays
    /// empty for cloud bubbles. Renderered as collapsible sections
    /// below the assistant text.
    var toolCalls: [ToolCall] = []

    enum Role: String {
        case user
        case assistant
        case system
    }

    var isUser: Bool { role == .user }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, timestamp: Date())
    }

    static func assistant(_ text: String = "") -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, timestamp: Date())
    }
}

/// One tool invocation emitted by a local kinclaw turn. Stored on
/// the assistant `ChatMessage` it belongs to, displayed inline as
/// an expandable widget.
struct ToolCall: Identifiable, Equatable {
    let id: String   // server-issued tool_call id; falls back to UUID
    let name: String
    let params: [String: String]
    /// Output filled in once the matching tool_result event arrives.
    /// Stays nil until then — UI renders as "running…" while nil.
    var output: String?
}

// MARK: - API Request / Response

struct ChatRequest: Codable {
    let messages: [APIMessage]
    let stream: Bool
    let noHistory: Bool?

    enum CodingKeys: String, CodingKey {
        case messages, stream
        case noHistory = "no_history"
    }
}

struct APIMessage: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Codable {
    let id: String?
    let choices: [Choice]?

    struct Choice: Codable {
        let index: Int?
        let message: ResponseMessage?
        let delta: ResponseDelta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message, delta
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String?
        let content: String?
    }

    struct ResponseDelta: Codable {
        let role: String?
        let content: String?
    }
}

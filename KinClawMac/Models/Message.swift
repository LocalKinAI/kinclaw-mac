import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

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

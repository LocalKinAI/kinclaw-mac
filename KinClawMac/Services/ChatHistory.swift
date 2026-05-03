import Foundation

/// Persists chat messages per agent using UserDefaults
enum ChatHistory {
    private static let maxMessages = 100  // Keep last 100 messages per agent

    private struct StoredMessage: Codable {
        let role: String
        let content: String
        let timestamp: Double  // TimeInterval
    }

    static func save(messages: [ChatMessage], for agentSlug: String) {
        let stored = messages.suffix(maxMessages).map { msg in
            StoredMessage(
                role: msg.role.rawValue,
                content: msg.content,
                timestamp: msg.timestamp.timeIntervalSince1970
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: "chat_\(agentSlug)")
        }
    }

    static func load(for agentSlug: String) -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: "chat_\(agentSlug)"),
              let stored = try? JSONDecoder().decode([StoredMessage].self, from: data) else {
            return []
        }
        return stored.map { s in
            ChatMessage(
                id: UUID(),
                role: ChatMessage.Role(rawValue: s.role) ?? .assistant,
                content: s.content,
                timestamp: Date(timeIntervalSince1970: s.timestamp)
            )
        }
    }

    static func clear(for agentSlug: String) {
        UserDefaults.standard.removeObject(forKey: "chat_\(agentSlug)")
    }

    /// Get list of agents with saved history
    static func agentsWithHistory() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("chat_") }
            .map { String($0.dropFirst(5)) }
    }
}

import Foundation

struct Agent: Codable, Identifiable, Hashable {
    let name: String
    let slug: String
    let port: Int?
    let model: String?
    let online: Bool
    let hostname: String?
    let domain: String?

    /// Absolute filesystem path to a local kinclaw soul, set when
    /// this Agent is bridged from a `Soul`. nil for cloud agents
    /// (api.localkin.dev /v1/agents never includes this key).
    /// Codable synthesis decodes-if-present on optionals, so cloud
    /// JSON parses unchanged.
    let localSoulPath: String?

    var id: String { slug }

    /// True when this Agent is a bridged local kinclaw soul rather
    /// than a cloud agent. ChatView branches on this to pick the
    /// right transport.
    var isLocal: Bool { localSoulPath != nil }

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var emoji: String {
        // Slug-specific overrides first
        switch slug {
        case let s where s.contains("conductor"): return "🎯"
        case let s where s.contains("english"): return "🇬🇧"
        case let s where s.contains("spanish"): return "🇪🇸"
        case "trader": return "💹"
        case "oracle": return "🔮"
        case "ceo": return "👨‍💼"
        case "cfo": return "💵"
        case "cto": return "👨‍💻"
        default: break
        }
        // Then domain-based
        switch domain {
        case "core": return "🧠"
        case "board": return "🏛️"
        case "bible": return "📖"
        case "csuite": return "👔"
        case "design": return "🎨"
        case "engineering": return "⚙️"
        case "game_dev": return "🎮"
        case "integration": return "🔗"
        case "marketing": return "📢"
        case "paid_media": return "💰"
        case "prediction": return "🔮"
        case "product": return "📦"
        case "project_management": return "📋"
        case "qa": return "🧪"
        case "quant": return "📈"
        case "spatial_computing": return "🥽"
        case "specialist": return "🔬"
        case "spiritual": return "✝️"
        case "support": return "🛟"
        case "tcm": return "🏥"
        default: return "🤖"
        }
    }

    var chatURL: String {
        if let hostname = hostname {
            return "https://\(hostname)"
        }
        return "https://api.localkin.dev"
    }
}

struct AgentHealthResponse: Codable {
    let status: String
    let soul: String?
    let slug: String?
    let model: String?
    let provider: String?
    let domain: String?
}

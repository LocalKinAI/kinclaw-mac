import Foundation

/// Visual decoration for an `Agent` — emoji avatar, bilingual name,
/// era / tagline. Looks up cloud masters in `CloudAgentCatalog`,
/// hardcodes a small map for local KinClaw souls, and provides a
/// generic fallback for everything else.
///
/// Kept as a side-table (not fields on Agent) because the decoration
/// is platform-specific UI metadata — Agent itself is the wire-shape
/// data model used across views and the API client. Mixing them
/// would couple Agent to display concerns it shouldn't know about.
enum AgentDecor {

    // MARK: - Local KinClaw souls (7)
    //
    // The kinclaw soul list returns names like "KinClaw Pilot" /
    // "KinClaw Coder" — we strip the prefix and map per-soul to an
    // emoji that matches what each one is for. Any new KinClaw soul
    // added server-side without an entry here falls through to the
    // 🦞 default, which still reads correctly.

    private static let kinClawEmoji: [String: String] = [
        "pilot":      "🦞",   // master / 5-claw operator
        "coder":      "💻",   // writes code
        "critic":     "🔍",   // reviews / critiques
        "curator":    "📚",   // organizes / archives
        "eye":        "👁",    // visual perception
        "marketer":   "📢",   // copy / distribution
        "researcher": "🔬",   // deep research
    ]

    // MARK: - Local LocalKin generic souls (3)

    private static let localKinEmoji: [String: String] = [
        "default": "⚙️",
        "claude":  "🧠",
        "cloud":   "☁️",
    ]

    // MARK: - Public lookups

    /// One-character emoji for the agent. Always returns something
    /// printable — never nil — so call sites can drop it inline
    /// without optional dance.
    static func emoji(for agent: Agent) -> String {
        // Cloud master? Look up the catalog.
        if !agent.isLocal,
           let master = CloudAgentCatalog.master(for: agent.slug) {
            return master.avatar
        }
        // Local KinClaw soul? Strip "KinClaw " prefix and look up
        // by the lowercased remainder.
        let kinClawKey = agent.name
            .replacingOccurrences(of: "KinClaw ", with: "")
            .lowercased()
        if let emoji = kinClawEmoji[kinClawKey] {
            return emoji
        }
        // Local LocalKin soul? slug is already the key (e.g.
        // "default" / "claude" / "cloud").
        if let emoji = localKinEmoji[agent.slug] {
            return emoji
        }
        // Generic fallback — local agents lean lobster, cloud lean
        // sparkle, matches the bullet color in the dropdown.
        return agent.isLocal ? "🦞" : "✨"
    }

    /// Bilingual display label. Cloud masters render as "📜 爱任纽
    /// Irenaeus"; local souls render with their plain name. Returns
    /// already-formatted; no SwiftUI styling baked in so call sites
    /// can format further.
    static func displayLabel(for agent: Agent) -> String {
        let avatar = emoji(for: agent)
        if let master = CloudAgentCatalog.master(for: agent.slug) {
            return "\(avatar)  \(master.nameZh) · \(master.nameEn)"
        }
        return "\(avatar)  \(agent.displayName)"
    }

    /// Era / role caption. Master era for cloud agents; descriptive
    /// role line for local. nil if nothing meaningful to show.
    static func caption(for agent: Agent) -> String? {
        if let master = CloudAgentCatalog.master(for: agent.slug) {
            return master.era
        }
        if agent.isLocal {
            // Local souls' "era" is just what they DO. Match the
            // emoji map roles.
            let kinClawKey = agent.name
                .replacingOccurrences(of: "KinClaw ", with: "")
                .lowercased()
            switch kinClawKey {
            case "pilot":       return "operates your Mac (5 claws)"
            case "coder":       return "writes & refactors code"
            case "critic":      return "reviews & critiques"
            case "curator":     return "organizes & archives"
            case "eye":         return "sees & describes"
            case "marketer":    return "copy & distribution"
            case "researcher":  return "deep research"
            default:            break
            }
            switch agent.slug {
            case "default":     return "default LocalKin chat"
            case "claude":      return "Claude-backed local soul"
            case "cloud":       return "cloud-brain local soul"
            default:            return "local soul"
            }
        }
        return nil
    }
}

import Foundation

/// Top-level surface picker for the spotlight panel. The same window
/// hosts three different agent UX shapes — switching is a one-click
/// thing, not a window swap.
///
///   .chat   → conversation surface (Local KinClaw + Cloud LocalKin)
///   .cowork → chat + inline live screen feed ("agent's eyes" mode,
///             driven by the kinclaw kernel's screen claw). The agent
///             picker splits Cowork souls into two source groups:
///               🦞 KinClaw — public souls from the kinclaw kernel
///                            (`./souls/`, `~/.localkin/souls/`)
///               🛡️ Private — souls from a sibling localkin checkout
///                            at `souls/private/` (file-system scanned
///                            via PrivateSoulLoader, never network-
///                            registered, never uploaded)
///   .code   → repo picker + file tree + diff viewer + chat,
///             driven by kincode kernel running on :5002
///
/// This mirrors Claude Code Desktop's three-mode top bar, but plugged
/// into the LocalKin kernel family (kinclaw + kincode) instead of
/// Anthropic-only. Mode persists across launches so the user doesn't
/// have to re-pick on every summon.
enum ChatMode: String, CaseIterable, Identifiable {
    case chat
    case cowork
    case code

    var id: String { rawValue }

    /// Short label shown in the ModeBar pill.
    var title: String {
        switch self {
        case .chat:   return "Chat"
        case .cowork: return "Cowork"
        case .code:   return "Code"
        }
    }

    /// SF Symbol name for the pill icon. Picked to read at 11pt: a
    /// plain bubble for chat, an eye for cowork (we're showing the
    /// agent the screen), a chevron for code.
    var symbol: String {
        switch self {
        case .chat:   return "bubble.left.and.bubble.right"
        case .cowork: return "eye"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// One-line tooltip for hover.
    var help: String {
        switch self {
        case .chat:
            return "Chat with any agent (Local KinClaw or Cloud LocalKin)"
        case .cowork:
            return "Cowork — agent watches your screen (KinClaw souls, public + private)"
        case .code:
            return "Code — repo-aware coding agent (kincode on :5002)"
        }
    }
}

extension ChatMode {
    /// UserDefaults key for the persisted last-used mode.
    static let storageKey = "kinclaw.mode"

    /// Read the persisted mode, falling back to .chat for first run
    /// and for any unknown value (handles forward-compat — older
    /// builds reading a future mode string just default to chat).
    static func loadPersisted() -> ChatMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return ChatMode(rawValue: raw) ?? .chat
    }

    /// Persist this mode as the user's last-used surface.
    func persist() {
        UserDefaults.standard.set(rawValue, forKey: ChatMode.storageKey)
    }
}

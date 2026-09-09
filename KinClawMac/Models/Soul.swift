import Foundation

/// One entry in `GET /api/souls` from a local kinclaw server.
///
/// Wire shape comes from `pkg/server/server.go : SoulInfo`:
/// ```
/// {"path": "/abs/path/to/x.soul.md", "name": "pilot", "brain": "kimi", "active": true}
/// ```
///
/// `path` is the canonical id — the user can have two souls with the
/// same `name` in different directories (./souls/pilot.soul.md vs
/// ~/.localkin/souls/pilot.soul.md), and switching is by absolute path.
struct Soul: Codable, Identifiable, Hashable {
    let path: String
    let name: String
    let brain: String
    /// Who opens this soul — "primary" (a door a person picks),
    /// "worker" (dispatched by another agent), "bench", "platform".
    /// Absent on older kernels and on souls that say nothing, which
    /// both mean primary.
    var role: String?
    /// True for the soul currently loaded in the kinclaw session.
    /// Optional because handleSouls omits it for inactive souls.
    var active: Bool?

    var id: String { path }

    /// A door: what belongs in a picker. Souls are the developer's
    /// unit, not the user's — eleven ship in the repo and only three
    /// are doors; the rest are hands the pilot dispatches, benchmarks,
    /// and ports for another OS. Putting all eleven in a menu asks the
    /// user to choose a capability boundary, which is not a question
    /// they have any basis to answer.
    var isPrimary: Bool { (role ?? "primary") == "primary" }

    /// "pilot" → "Pilot", "kitchen_helper" → "Kitchen Helper".
    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension Soul {
    /// Render as the `Agent` shape so existing views (AgentListView /
    /// ChatView / MessageBubble) can show local souls without being
    /// rewritten.
    ///
    /// This is M1's transitional bridge — once the AgentSource protocol
    /// lands (~M2 / M3 onwards) ChatView will switch on the source
    /// directly and this glue can shrink.
    var asAgent: Agent {
        Agent(
            name: name,
            slug: name,
            port: nil,
            model: brain,
            online: true,
            // Marker so other code can spot a local soul.
            // No https:// — just the host:port we'll talk to.
            hostname: "localhost-kinclaw",
            domain: "kinclaw",
            // Carry the absolute path so ChatView can switch the
            // server-side active soul before sending.
            localSoulPath: path,
            soulRole: role
        )
    }
}

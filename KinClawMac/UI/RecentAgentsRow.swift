import SwiftUI

/// Horizontal row of recently-used agent emojis at the top of the
/// chat surface. One-click switch — tap any avatar → that agent
/// becomes selected.
///
/// Persisted in UserDefaults under "kinclaw.recentAgents" as an
/// ordered list of slugs (most-recent first, capped at 6). The
/// active agent is highlighted with a small green dot.
struct RecentAgentsRow: View {
    let allAgents: [Agent]
    let currentSlug: String?
    let onSelect: (Agent) -> Void

    private static let storageKey = "kinclaw.recentAgents"
    private static let maxRecent = 6

    @AppStorage(storageKey) private var recentSlugsCSV: String = ""

    private var recentAgents: [Agent] {
        let slugs = recentSlugsCSV.split(separator: ",").map(String.init)
        // Resolve slugs to Agents in current catalog. Drop any whose
        // catalog entry has gone away (e.g. a soul that was renamed).
        return slugs.compactMap { slug in
            allAgents.first(where: { $0.slug == slug })
        }
    }

    var body: some View {
        if recentAgents.count >= 1 {
            HStack(spacing: 8) {
                ForEach(recentAgents) { agent in
                    Button {
                        onSelect(agent)
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Text(AgentDecor.emoji(for: agent))
                                .font(.system(size: 16))
                                .frame(width: 26, height: 26)
                                .background(
                                    Circle()
                                        .fill(currentSlug == agent.slug
                                              ? Color.green.opacity(0.18)
                                              : Color.platformSecondaryBackground.opacity(0.5))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(currentSlug == agent.slug
                                                ? Color.green.opacity(0.6)
                                                : Color.clear,
                                                lineWidth: 1)
                                )
                            if currentSlug == agent.slug {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 1, y: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(agent.displayName)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    /// Push a slug to the front of the recent list. Call when the
    /// user picks an agent. De-dupes (existing entry moves to head)
    /// and caps to maxRecent.
    static func touch(slug: String) {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        var slugs = raw.split(separator: ",").map(String.init)
        slugs.removeAll(where: { $0 == slug })
        slugs.insert(slug, at: 0)
        if slugs.count > maxRecent {
            slugs = Array(slugs.prefix(maxRecent))
        }
        UserDefaults.standard.set(slugs.joined(separator: ","),
                                  forKey: storageKey)
    }
}

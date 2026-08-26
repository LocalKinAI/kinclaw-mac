import Foundation

/// Backs the Skills settings tab: what the currently active soul can actually
/// use, out of everything the kernel has loaded.
///
/// The distinction this exists to show: a skill being *registered* means the
/// kernel loaded it successfully; being *exposed* means the active soul's
/// `skills.enable` list lets the model see it. Those numbers differ a lot —
/// 189 registered vs 25 exposed for pilot — and "the skill is installed but my
/// agent says it can't do that" is the confusion that follows from conflating
/// them.
@MainActor
final class SkillStore: ObservableObject {

    struct Entry: Codable, Identifiable, Equatable {
        var name: String
        var description: String
        var exposed: Bool
        var source: String   // "builtin" | "mcp"

        var id: String { name }
        var isMCP: Bool { source == "mcp" }
    }

    struct Counts: Codable, Equatable {
        var registered: Int
        var exposed: Int
    }

    struct Status: Codable, Equatable {
        var soul: String
        var enablePatterns: [String]
        var skills: [Entry]
        var missing: [String]?
        /// Patterns added from this UI, on top of the soul's own list.
        var extras: [String]?
        var counts: Counts
    }

    @Published private(set) var status: Status?
    @Published private(set) var fetchFailed = false
    @Published var query = ""
    @Published var exposedOnly = true

    var soulName: String { status?.soul ?? "—" }
    var registeredCount: Int { status?.counts.registered ?? 0 }
    var exposedCount: Int { status?.counts.exposed ?? 0 }

    /// Enable entries that match nothing registered.
    ///
    /// Surfaced prominently because it is silent otherwise: the soul claims a
    /// capability, the kernel logs one line at startup, and the agent simply
    /// never has it. A typo here looks identical to the feature not existing.
    var missing: [String] { status?.missing ?? [] }

    /// Extras this UI added, as opposed to what the soul grants.
    var extras: Set<String> { Set(status?.extras ?? []) }

    /// Whether a skill is exposed because of an extra rather than the soul.
    ///
    /// Shown differently in the UI: one is the user's own toggle and can be
    /// taken back here, the other lives in the soul file and can't.
    func isExtra(_ name: String) -> Bool { extras.contains(name) }

    /// Whether the soul itself grants this skill, ignoring extras.
    ///
    /// Determines whether the checkbox is editable: un-ticking a
    /// soul-granted skill would have to remove it from the soul file, and
    /// this overlay is deliberately additive-only.
    func grantedBySoul(_ name: String) -> Bool {
        guard let patterns = status?.enablePatterns else { return false }
        let extras = self.extras
        for p in patterns where !extras.contains(p) {
            if p.hasSuffix("*") {
                if name.hasPrefix(String(p.dropLast())) { return true }
            } else if p == name {
                return true
            }
        }
        return false
    }

    var filtered: [Entry] {
        let all = status?.skills ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { entry in
            if exposedOnly && !entry.exposed { return false }
            if q.isEmpty { return true }
            return entry.name.lowercased().contains(q)
                || entry.description.lowercased().contains(q)
        }
    }

    func refresh(port: Int = 5001) async {
        guard let url = URL(string: "http://localhost:\(port)/api/skills") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                fetchFailed = true
                return
            }
            status = try JSONDecoder().decode(Status.self, from: data)
            fetchFailed = false
        } catch {
            fetchFailed = true
        }
    }
}

// MARK: - Toggling extras

extension SkillStore {

    /// Grant or revoke one skill for the active soul.
    ///
    /// Writes an overlay file (`~/.localkin/skill_extras.json`), never the soul
    /// itself. Souls are hand-authored — pilot's enable list is interleaved
    /// with comments explaining each entry — and a checkbox that rewrote that
    /// file would eventually mangle the reasoning to save one text edit.
    ///
    /// Additive only: skills the soul grants can't be un-ticked here, because
    /// doing so would leave a soul file that no longer describes the running
    /// agent. Removing stays an edit to the soul, where git can see it.
    func setExtra(_ name: String, enabled: Bool, port: Int = 5001) async {
        guard let url = URL(string: "http://localhost:\(port)/api/skills/extras") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["pattern": name, "enable": enabled])

        _ = try? await URLSession.shared.data(for: request)
        // Re-read rather than mutating locally: the kernel recomputes exposure
        // on write, and its answer is the one that matters.
        await refresh(port: port)
    }
}

import Foundation

/// File-system store for `ChatSession`. One JSON file per session at
///   ~/.kinclaw/sessions/<sanitized-agentSlug>/<id>.json
///
/// Public API surface mirrors what the UI needs:
///
///   list(for: agentSlug)             → [ChatSession] (most-recent first)
///   load(id: agentSlug:)             → ChatSession?
///   save(_ session: ChatSession)     → write atomically
///   delete(id: agentSlug:)           → remove file
///
/// First-run migration:
///   `migrateFromUserDefaults()` reads any legacy
///   `chat_<agentSlug>` UserDefaults blobs (the pre-multi-session
///   storage) and rewrites them as session JSONs, then clears those
///   keys. Idempotent — safe to call on every launch.
enum ChatSessionStore {

    // MARK: - Public

    /// Lists sessions for an agent, newest-updated first. Returns
    /// `[]` if the agent's directory doesn't exist yet.
    static func list(for agentSlug: String) -> [ChatSession] {
        let dir = directory(for: agentSlug)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }

            let sessions = urls.compactMap(loadSession(from:))
            return sessions.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("[ChatSessionStore] list error: \(error)")
            return []
        }
    }

    /// Loads a specific session by id within an agent's directory.
    static func load(id: UUID, agentSlug: String) -> ChatSession? {
        let url = fileURL(for: id, agentSlug: agentSlug)
        return loadSession(from: url)
    }

    /// Atomic write — writes to a tmp neighbor then renames. Avoids
    /// partial-write corruption if the app exits mid-flush.
    static func save(_ session: ChatSession) {
        let dir = directory(for: session.agentSlug)
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)

            let url = fileURL(for: session.id, agentSlug: session.agentSlug)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[ChatSessionStore] save \(session.id) error: \(error)")
        }
    }

    /// Deletes one session. No-op if file doesn't exist.
    static func delete(id: UUID, agentSlug: String) {
        let url = fileURL(for: id, agentSlug: agentSlug)
        try? FileManager.default.removeItem(at: url)
    }

    /// Total count across all agents — surfaced in About / Settings
    /// for power-user inspection.
    static func totalCount() -> Int {
        let root = sessionsRoot
        guard let agentDirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        var total = 0
        for agentDir in agentDirs where agentDir.hasDirectoryPath {
            if let files = try? FileManager.default.contentsOfDirectory(
                at: agentDir, includingPropertiesForKeys: nil
            ) {
                total += files.filter { $0.pathExtension == "json" }.count
            }
        }
        return total
    }

    // MARK: - Migration from UserDefaults legacy storage

    private static let migrationKey = "kinclaw.sessionStore.migrated"

    /// Reads any pre-multi-session `chat_<agentSlug>` UserDefaults
    /// blobs and writes them as one session each. Sets a flag so it
    /// only runs once. Safe to call on every launch.
    static func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        // Each chat_<slug> UserDefaults entry stores [StoredMessage]
        // (matching the legacy shape in Services/ChatHistory.swift).
        struct StoredMessage: Codable {
            let role: String
            let content: String
            let timestamp: Double
        }

        let allKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("chat_") }
        var migrated = 0
        for key in allKeys {
            let agentSlug = String(key.dropFirst("chat_".count))
            guard let data = defaults.data(forKey: key),
                  let stored = try? JSONDecoder()
                      .decode([StoredMessage].self, from: data),
                  !stored.isEmpty else {
                defaults.removeObject(forKey: key)
                continue
            }

            let firstUserMsg = stored.first(where: { $0.role == "user" })?.content
                ?? "Imported chat"
            let title = String(firstUserMsg.prefix(60))
            let createdAt = Date(timeIntervalSince1970:
                stored.first?.timestamp ?? Date().timeIntervalSince1970)
            let updatedAt = Date(timeIntervalSince1970:
                stored.last?.timestamp ?? createdAt.timeIntervalSince1970)

            let messages = stored.map { s in
                PersistedMessage(from: ChatMessage(
                    id: UUID(),
                    role: ChatMessage.Role(rawValue: s.role) ?? .assistant,
                    content: s.content,
                    timestamp: Date(timeIntervalSince1970: s.timestamp)
                ))
            }

            let session = ChatSession(
                agentSlug: agentSlug,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messages: messages
            )
            save(session)
            defaults.removeObject(forKey: key)
            migrated += 1
        }

        defaults.set(true, forKey: migrationKey)
        if migrated > 0 {
            print("[ChatSessionStore] migrated \(migrated) chat(s) from UserDefaults → ~/.kinclaw/sessions/")
        }
    }

    // MARK: - Internals

    /// `~/.kinclaw/sessions/`
    private static var sessionsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".kinclaw/sessions",
                                            isDirectory: true)
    }

    /// `~/.kinclaw/sessions/<sanitized-slug>/`
    private static func directory(for agentSlug: String) -> URL {
        sessionsRoot.appendingPathComponent(sanitize(agentSlug),
                                             isDirectory: true)
    }

    /// `~/.kinclaw/sessions/<slug>/<id>.json`
    private static func fileURL(for id: UUID, agentSlug: String) -> URL {
        directory(for: agentSlug)
            .appendingPathComponent("\(id.uuidString).json")
    }

    /// Slug → safe directory name. Replaces / and other delimiters
    /// with dashes; leaves spaces (so "KinClaw Pilot" still reads as
    /// "KinClaw Pilot/" in Finder).
    private static func sanitize(_ slug: String) -> String {
        slug.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    private static func loadSession(from url: URL) -> ChatSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChatSession.self, from: data)
    }
}

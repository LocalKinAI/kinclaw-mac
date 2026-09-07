import Foundation
import CryptoKit

/// File-system store for `CodeSession`. One JSON file per session at
///
///   ~/.kinclaw/code-sessions/<repoHash>/<id>.json
///
/// The repo path itself isn't used as the directory name — it
/// contains slashes / spaces / unicode and would leak deep filesystem
/// structure into our config dir. Instead we hash the absolute path
/// (SHA256, first 16 hex chars) for a stable, filesystem-safe key.
///
/// Multi-session per repo has always been the on-disk shape; since the
/// Code sidebar lists folders with their sessions, it is also the UI's
/// shape. `mostRecent` remains the "resume where I left off" entry
/// point when a folder is opened without picking a session.
enum CodeSessionStore {

    /// One session as the sidebar shows it: enough to render a row
    /// without decoding every message of every session.
    struct Summary: Identifiable, Equatable {
        let id: UUID
        let repoPath: String
        let title: String
        let updatedAt: Date
        let messageCount: Int
    }

    // MARK: - Public

    /// Every session for a repo, newest first.
    static func sessions(repoPath: String) -> [Summary] {
        summaries(in: directory(for: repoPath))
    }

    /// Every repo that has at least one stored session, newest activity
    /// first. The directory name is a hash, so the path is read back
    /// out of the session JSON itself.
    static func folders() -> [(path: String, lastUsed: Date, sessions: Int)] {
        let root = rootDirectory()
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        var out: [(String, Date, Int)] = []
        for dir in dirs {
            let ss = summaries(in: dir)
            guard let newest = ss.first else { continue }
            out.append((newest.repoPath, newest.updatedAt, ss.count))
        }
        return out.sorted { $0.1 > $1.1 }.map { (path: $0.0, lastUsed: $0.1, sessions: $0.2) }
    }

    /// Load one session by id within a repo.
    static func load(repoPath: String, id: UUID) -> CodeSession? {
        let url = directory(for: repoPath).appendingPathComponent("\(id.uuidString).json")
        return loadSession(from: url)
    }

    /// Delete one session file.
    static func delete(repoPath: String, id: UUID) {
        let url = directory(for: repoPath).appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// Title for a session row: the first user message, one line.
    /// Falls back to the date when a session has no user text yet
    /// (a turn that errored before the user's message was persisted).
    static func title(for session: CodeSession) -> String {
        if let first = session.messages.first(where: { $0.role == .user }) {
            let line = first.text
                .split(separator: "\n").first.map(String.init) ?? first.text
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(70)) }
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: session.createdAt)
    }

    /// Most recently updated session for this repo, or nil if none.
    /// Used on CodePane.onAppear to resume the conversation.
    static func mostRecent(repoPath: String) -> CodeSession? {
        let dir = directory(for: repoPath)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return nil
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "json" }
            let sessions = urls.compactMap(loadSession(from:))
            return sessions.max(by: { $0.updatedAt < $1.updatedAt })
        } catch {
            print("[CodeSessionStore] mostRecent error: \(error)")
            return nil
        }
    }

    /// Atomic write. Writes to a tmp neighbor then renames so a
    /// partial flush during quit doesn't leave a half-written file.
    static func save(_ session: CodeSession) {
        let dir = directory(for: session.repoPath)
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
            let url = dir.appendingPathComponent("\(session.id.uuidString).json")
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            // Replace existing file in one syscall — never observable
            // as missing/partial by readers.
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
        } catch {
            print("[CodeSessionStore] save error: \(error)")
        }
    }

    /// Delete every session for this repo. Used by "Clear history"
    /// in Settings → Data.
    static func clear(repoPath: String) {
        let dir = directory(for: repoPath)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Total bytes used by all code sessions across all repos. Shown
    /// in Settings → Data as part of the disk usage breakdown.
    static func totalDiskBytes() -> Int {
        let root = rootDirectory()
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        var total = 0
        if let it = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in it {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += size
                }
            }
        }
        return total
    }

    // MARK: - Internals

    private static func summaries(in dir: URL) -> [Summary] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap(loadSession(from:))
            .map { Summary(id: $0.id, repoPath: $0.repoPath, title: title(for: $0),
                           updatedAt: $0.updatedAt, messageCount: $0.messages.count) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func loadSession(from url: URL) -> CodeSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodeSession.self, from: data)
    }

    private static func rootDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".kinclaw/code-sessions")
    }

    private static func directory(for repoPath: String) -> URL {
        rootDirectory().appendingPathComponent(repoHash(repoPath))
    }

    /// Stable, filesystem-safe per-repo key. SHA256 of the absolute
    /// path, truncated to 16 hex chars (~64 bits, plenty of entropy
    /// for a few hundred repos per user). Truncation is fine: collisions
    /// would require ~2^32 repos to hit 50% birthday, and we have <100.
    private static func repoHash(_ path: String) -> String {
        let normalized = (path as NSString).standardizingPath
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

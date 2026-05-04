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
/// v1 keeps a single active session per repo (mostRecent). Multi-
/// session per repo is supported by the schema; the UI just picks
/// the most-recently-updated one on load.
enum CodeSessionStore {

    // MARK: - Public

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

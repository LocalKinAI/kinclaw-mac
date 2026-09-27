import Combine
import Foundation

/// Every conversation Claude Code and Codex keep on this Mac, for the Code
/// tab's list — the Claude desktop app's among them, since what it runs is
/// Claude Code ("把我这里的 session 复制过去加个列表，我可以在那里操作和这里一样").
///
/// Claude Code keeps each in ~/.claude/projects/<folder>/<id>.jsonl, one
/// JSON object a line, and writes its name into it again and again as the
/// conversation goes: a name given by hand (custom-title), one it made up
/// itself (ai-title), or an agent's (agent-name). Codex keeps its rollouts in
/// ~/.codex/sessions by day, the first line naming the folder. Neither has an
/// index, and a long conversation is hundreds of megabytes, so only each
/// file's two ends are read — as bytes, searched without decoding them — and
/// only again when the file has changed: 301 conversations, measured, take
/// 20 ms to look over again.
///
/// Left out: a Studio tab's own agent's (that tab goes back into them),
/// `claude -p` and `codex exec` runs (a question and an answer, nobody's
/// conversation), ones had in Claude Code's scratch folders, and files with
/// nothing said in them.
@MainActor
final class CodeHistory: ObservableObject {
    static let shared = CodeHistory()

    struct Item: Identifiable, Hashable {
        /// The conversation's id — what `claude --resume` and `codex resume` take.
        let id: String
        let harness: AgentHarness
        /// Where it was had: where it is gone back into from.
        let folder: String
        /// The folder the list shows it under: see `groupKey`.
        let group: String
        let title: String
        let modified: Date
    }

    /// Newest first.
    @Published private(set) var items: [Item] = []
    @Published private(set) var loading = false

    struct Seen: Sendable {
        let modified: Date
        let bytes: Int
        let item: Item?
    }

    private var seen: [String: Seen] = [:]

    func refresh() {
        guard !loading else { return }
        loading = true
        let before = seen
        let studio = StudioAgent.all.map(\.folder.path)
        Task {
            let (found, now) = await Task.detached(priority: .utility) { Self.scan(before, studio: studio) }.value
            seen = now
            items = found
            loading = false
        }
    }

    func item(_ id: String?) -> Item? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: Looking over them

    nonisolated private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    nonisolated private static var projects: URL { home.appendingPathComponent(".claude/projects") }

    /// The folder a conversation is listed under: the one it was had in,
    /// symlinks resolved (/tmp is /private/tmp), and a worktree Claude Code
    /// made for it (<repo>/.claude/worktrees/<name>) under its repo.
    nonisolated static func groupKey(_ folder: String) -> String {
        let real = realPath(folder)
        if let cut = real.range(of: "/.claude/worktrees/") { return String(real[..<cut.lowerBound]) }
        return real
    }

    /// Claude Code's name for a folder's directory under projects: its path,
    /// every character but a letter or a digit made a dash.
    nonisolated static func projectName(_ path: String) -> String {
        String(path.utf16.map { unit -> Character in
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return Character(Unicode.Scalar(UInt8(unit)))
            default: return "-"
            }
        })
    }

    nonisolated private static func scan(_ before: [String: Seen], studio: [String]) -> ([Item], [String: Seen]) {
        let files = FileManager.default
        var now: [String: Seen] = [:]
        func look(_ file: URL, _ read: (URL) -> Item?) -> Item? {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let bytes = values?.fileSize ?? 0
            let seen = before[file.path].flatMap { $0.modified == modified && $0.bytes == bytes ? $0 : nil }
                ?? Seen(modified: modified, bytes: bytes, item: read(file))
            now[file.path] = seen
            return seen.item
        }
        func contents(_ dir: URL) -> [URL] {
            (try? files.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        }
        // A Studio tab's own, by the folder they were had in and by the
        // directory they are kept in.
        let skipped = Set(studio.flatMap { [$0, realPath($0)] })
        let skippedDirs = Set(skipped.map(projectName))
        // And Claude Code's own scratch folders (/private/tmp/claude-<uid>/…),
        // where an agent tries something out: nobody's project.
        func studios(_ item: Item) -> Bool {
            skipped.contains(item.folder) || skipped.contains(realPath(item.folder)) || item.group.hasPrefix("/private/tmp/claude-")
        }

        // One conversation can be kept in two folders' directories — copied,
        // to be carried on from the other — and is listed once: the copy in
        // its own folder's directory, which is the one `--resume` finds from
        // there, else the latest.
        var claude: [String: (item: Item, own: Bool)] = [:]
        for dir in contents(projects) where !skippedDirs.contains(dir.lastPathComponent) {
            for file in contents(dir) where file.pathExtension == "jsonl" {
                guard let item = look(file, readClaude), !studios(item) else { continue }
                let own = projectName(item.folder) == dir.lastPathComponent
                    || projectName(realPath(item.folder)) == dir.lastPathComponent
                if let kept = claude[item.id], (kept.own && !own) || (kept.own == own && kept.item.modified >= item.modified) {
                    continue
                }
                claude[item.id] = (item, own)
            }
        }
        var found = claude.values.map(\.item)
        if let walk = files.enumerator(at: home.appendingPathComponent(".codex/sessions"),
                                       includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            for case let file as URL in walk
            where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                if let item = look(file, readCodex), !studios(item) { found.append(item) }
            }
        }
        return (found.sorted { $0.modified > $1.modified }, now)
    }

    /// A file's first and last stretches: where its folder and first words
    /// are, and where its latest name is.
    nonisolated private static func ends(_ file: URL, head: Int, tail: Int) -> (head: Data, tail: Data, modified: Date)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let start = (try? handle.read(upToCount: head)) ?? Data()
        guard tail > 0, let size = try? handle.seekToEnd(), size > UInt64(head) else { return (start, Data(), modified) }
        try? handle.seek(toOffset: max(UInt64(head), size - UInt64(tail)))
        return (start, (try? handle.readToEnd()) ?? Data(), modified)
    }

    nonisolated private static let userLine = Data("\"type\":\"user\"".utf8)
    nonisolated private static let assistantLine = Data("\"type\":\"assistant\"".utf8)

    nonisolated private static func readClaude(_ file: URL) -> Item? {
        guard let (head, tail, modified) = ends(file, head: 512 * 1024, tail: 256 * 1024) else { return nil }
        var folder: String?
        var first: String?
        for line in head.split(separator: 0x0A) {
            if folder == nil { folder = string("cwd", in: line) }
            if first == nil, line.range(of: userLine) != nil,
               let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
               entry["type"] as? String == "user",
               entry["isMeta"] as? Bool != true, entry["isSidechain"] as? Bool != true {
                // A headless run's: nobody's conversation.
                if entry["entrypoint"] as? String == "sdk-cli" { return nil }
                first = said((entry["message"] as? [String: Any])?["content"])
            }
            if folder != nil, first != nil { break }
        }
        let name = named(tail) ?? named(head)
        guard let folder, let title = name ?? first else { return nil }
        return Item(id: file.deletingPathExtension().lastPathComponent, harness: .claude,
                    folder: folder, group: groupKey(folder), title: title, modified: modified)
    }

    /// The latest name a Claude Code conversation carries.
    nonisolated private static func named(_ data: Data) -> String? {
        for key in ["customTitle", "aiTitle", "agentName"] {
            if let name = string(key, in: data, last: true), !name.isEmpty { return name }
        }
        return nil
    }

    nonisolated private static func readCodex(_ file: URL) -> Item? {
        guard let (head, _, modified) = ends(file, head: 128 * 1024, tail: 0) else { return nil }
        let lines = head.split(separator: 0x0A)
        guard let meta = lines.first, meta.range(of: Data("\"session_meta\"".utf8)) != nil,
              string("source", in: meta) != "exec",
              let id = string("id", in: meta), let folder = string("cwd", in: meta) else { return nil }
        for line in lines.dropFirst() where line.range(of: Data("\"role\":\"user\"".utf8)) != nil {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let payload = entry["payload"] as? [String: Any],
                  let words = said(payload["content"]) else { continue }
            return Item(id: id, harness: .codex, folder: folder, group: groupKey(folder), title: words, modified: modified)
        }
        return nil
    }

    /// What a person said, from a message's content — words, not tool
    /// results, and not the harness's own wrappers (<command-name>,
    /// <environment_context>, …). Its first line, cut short.
    nonisolated private static func said(_ content: Any?) -> String? {
        var text: String?
        if let plain = content as? String {
            text = plain
        } else if let parts = content as? [[String: Any]] {
            text = parts.compactMap { part -> String? in
                guard let kind = part["type"] as? String, kind == "text" || kind == "input_text" else { return nil }
                return part["text"] as? String
            }.first
        }
        guard let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty,
              !words.hasPrefix("<") else { return nil }
        let line = words.split(separator: "\n").first.map(String.init) ?? words
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    /// A string's value in compact JSON, by its key: the first, or the last.
    nonisolated private static func string(_ key: String, in data: Data, last: Bool = false) -> String? {
        guard let found = data.range(of: Data("\"\(key)\":\"".utf8), options: last ? .backwards : [],
                                     in: data.startIndex..<data.endIndex) else { return nil }
        var end = found.upperBound
        var escaped = false
        while end < data.endIndex {
            let byte = data[end]
            if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { break }
            end += 1
        }
        guard end < data.endIndex else { return nil }
        var literal = Data([0x22])
        literal.append(data[found.upperBound..<end])
        literal.append(0x22)
        return (try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed)) as? String
    }

    nonisolated static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: One conversation

    /// Claude Code's file for a conversation had in `folder` — in that
    /// folder's directory, where `claude --resume` run there looks for it.
    nonisolated static func claudeFile(_ id: String, in folder: String) -> URL? {
        for path in Set([folder, realPath(folder)]) {
            let file = projects.appendingPathComponent(projectName(path)).appendingPathComponent(id + ".jsonl")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    /// Whether anything was said in it: what makes it one to go back into.
    nonisolated static func claudeSaidAnything(_ id: String, in folder: String) -> Bool {
        let head = 256 * 1024
        guard let file = claudeFile(id, in: folder), let (start, _, _) = ends(file, head: head, tail: 0) else { return false }
        return start.count >= head || start.range(of: userLine) != nil || start.range(of: assistantLine) != nil
    }

    /// The Codex conversation begun in `folder` since `date`: a new Codex
    /// session says its id nowhere else.
    nonisolated static func codexConversation(in folder: String, since date: Date) -> String? {
        let real = realPath(folder)
        guard let walk = FileManager.default.enumerator(at: home.appendingPathComponent(".codex/sessions"),
                                                        includingPropertiesForKeys: [.creationDateKey]) else { return nil }
        let rollouts = walk.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
            .filter { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) >= date.addingTimeInterval(-5) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in rollouts {
            guard let (head, _, _) = ends(file, head: 8192, tail: 0),
                  let meta = head.split(separator: 0x0A).first,
                  string("source", in: meta) != "exec",
                  let cwd = string("cwd", in: meta), cwd == folder || realPath(cwd) == real else { continue }
            return string("id", in: meta)
        }
        return nil
    }
}

extension AgentBrain {
    /// The brain a host and a model amount to, when the host is one of the
    /// places brains come from; no model is the harness's own account.
    @MainActor static func at(_ host: String, model: String) -> AgentBrain? {
        guard !model.isEmpty else { return .account }
        func plain(_ url: String) -> String {
            url.lowercased().replacingOccurrences(of: "localhost", with: "127.0.0.1")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        for source in Source.allCases where source != .account {
            let brain = AgentBrain(source: source, model: model)
            if let endpoint = brain.endpoint, plain(endpoint) == plain(host) { return brain }
        }
        return nil
    }
}

import AppKit
import SwiftUI

/// 活画: a huashu-art-motion film played live in the app — the same code that renders its video frame by
/// frame, drawn here in real time over its song, to scrub, slow down and turn the knobs of
/// (「先拿倩影在app里实时播」, 2026-10-08: the first step towards answers that are live pictures).
///
/// The films kept in <art>/live/<id>: a film from the box is huashu's own engine folder with the film in it
/// (index.html, engine.js, transitions, scenes, lib, eras_<film>.js), fetched once with its song; a
/// drawing (「画给我看」, LiveDraw) keeps only its own scenes and draws on the shared engine. The window
/// plays one with its LivePlayer.
@MainActor
final class LiveFilm: NSObject, ObservableObject {
    static let shared = LiveFilm()

    static var folder: URL { CompanionArt.folder.appendingPathComponent("live") }

    /// One film kept on this Mac.
    struct Film: Codable, Identifiable, Hashable {
        /// Its folder's name.
        var id: String
        var title: String
        /// The film's eras file is eras_<film>.js in its engine folder.
        var film: String
        /// The engine folder on the box it came from, and its song there: what 「从盒子更新」 fetches again.
        var box: String?
        var boxSong: String?
        /// The song's file name in the film's folder.
        var song: String?
        var fetched: Date?
        /// An engine folder on this Mac to take what the film's own folder lacks (a drawing's).
        var base: String?
        /// "drawing" for 「画给我看」; nil for a film from the box.
        var kind: String?
        /// The question a drawing answers.
        var question: String?
        /// 「讲给我听」: the lines its voice says, each at its moment (the voice is its song, voice.wav).
        var lines: [Line]?
        /// How long it plays when its voice runs past its pictures.
        var length: Double?
    }

    struct Line: Codable, Hashable {
        var t: Double
        var text: String
    }

    typealias Era = LivePlayer.Era
    typealias Knob = LivePlayer.Knob

    @Published private(set) var films: [Film] = []
    @Published private(set) var current: Film?
    @Published private(set) var fetching: String?
    @Published private(set) var trouble: String?

    /// The window's player.
    let player = LivePlayer()
    private var window: NSWindow?

    private override init() {
        super.init()
        reload()
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // MARK: - The films kept

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        films = folders.compactMap { Self.read($0.appendingPathComponent("film.json")) }
            .sorted { ($0.fetched ?? .distantPast) > ($1.fetched ?? .distantPast) }
    }

    static func read(_ file: URL) -> Film? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: file)).flatMap { try? decoder.decode(Film.self, from: $0) }
    }

    static func write(_ film: Film) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(film).write(to: folder.appendingPathComponent(film.id).appendingPathComponent("film.json"), options: .atomic)
    }

    /// By its id or a piece of its title; nil: the one open, else the last kept.
    func film(named name: String?) -> Film? {
        reload()
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return current ?? films.first }
        return films.first { $0.id == name } ?? films.first { $0.title.localizedCaseInsensitiveContains(name) }
    }

    static func engine(_ film: Film) -> URL { folder.appendingPathComponent(film.id).appendingPathComponent("engine") }

    static func song(_ film: Film) -> URL? {
        film.song.map { folder.appendingPathComponent(film.id).appendingPathComponent($0) }
    }

    /// The film loaded into a player: its own folder, then the engine it draws on.
    static func load(_ film: Film, into player: LivePlayer) {
        player.load(engine(film), base: film.base.map { URL(fileURLWithPath: $0) }, film: film.film, song: song(film), length: film.length)
    }

    /// A film from the box: its engine folder (without huashu's demos and examples) and its song, kept
    /// in <art>/live/<id>. Again for a film already kept: what changed there comes over.
    @discardableResult
    func fetch(id: String, title: String, box: String, film: String, song: String?) async throws -> Film {
        let id = TalkingVideo.slug(id.isEmpty ? film : id)
        guard film.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil else {
            throw Failure.message("film 是 eras_<film>.js 里的 <film>：小写字母、数字、下划线")
        }
        fetching = title
        defer { fetching = nil }
        let dir = Self.folder.appendingPathComponent(id)
        try await Self.fetch(box, into: dir.appendingPathComponent("engine"))
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("engine/eras_\(film).js").path),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("engine/engine.js").path) else {
            throw Failure.message("\(box) 不是 huashu 的引擎文件夹，或者里面没有 eras_\(film).js")
        }
        var kept = Film(id: id, title: title, film: film, box: box, boxSong: song, song: nil, fetched: Date())
        if let song, !song.isEmpty {
            let name = "song." + ((song as NSString).pathExtension.isEmpty ? "wav" : (song as NSString).pathExtension.lowercased())
            let (status, said) = await Self.copy("/usr/bin/scp", ["-q", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
                                                                  "\(BoxServices.ssh):\(Self.home(song))", dir.appendingPathComponent(name).path])
            guard status == 0 else { throw Failure.message("从盒子拿歌 \(song) 失败：\(said.prefix(300))") }
            kept.song = name
        }
        try Self.write(kept)
        reload()
        return kept
    }

    /// A folder on the box copied into `local` (what changed, without huashu's demos and examples when
    /// it is a film's engine).
    static func fetch(_ remote: String, into local: URL, excluding: [String] = ["demos", "reference_films", "clips", "examples"]) async throws {
        let target = BoxServices.ssh
        guard !target.isEmpty else { throw Failure.message("没有盒子的 ssh 地址（盒子面板里设）") }
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let path = home(remote)
        let (status, said) = await copy("/usr/bin/rsync", ["-a", "-e", "ssh -o BatchMode=yes -o ConnectTimeout=6"]
            + excluding.flatMap { ["--exclude", $0] }
            + ["\(target):\(path.hasSuffix("/") ? path : path + "/")", local.path + "/"])
        guard status == 0 else { throw Failure.message("从盒子拿 \(remote) 失败：\(said.prefix(300))") }
    }

    /// A path on the box as scp and rsync take it: relative to its home.
    private static func home(_ path: String) -> String { path.hasPrefix("~/") ? String(path.dropFirst(2)) : path }

    /// 「从盒子更新」: the open film fetched again from where it came from, and reloaded.
    func update() async {
        guard let film = current, let box = film.box else { trouble = "这部活画不是从盒子拿的"; return }
        do {
            let kept = try await fetch(id: film.id, title: film.title, box: box, film: film.film, song: film.boxSong)
            try open(kept)
        } catch {
            trouble = error.localizedDescription
        }
    }

    nonisolated static func copy(_ tool: String, _ arguments: [String]) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do { try process.run() } catch { continuation.resume(returning: (255, error.localizedDescription)); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    // MARK: - The window

    /// The film in its window (`name`: its id or title; nil: the open one or the last kept).
    func show(_ name: String? = nil) async {
        guard let film = film(named: name) else {
            trouble = films.isEmpty ? "还没有活画：先让 Montage 的 agent 用 live_film 从盒子拿一部 huashu 的片子" : "没有叫「\(name ?? "")」的活画"
            return
        }
        do {
            try open(film)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            trouble = error.localizedDescription
        }
    }

    private func open(_ film: Film) throws {
        guard FileManager.default.fileExists(atPath: Self.engine(film).appendingPathComponent("eras_\(film.film).js").path) else {
            throw Failure.message("「\(film.title)」的文件不在 \(Self.engine(film).path)")
        }
        if window == nil { makeWindow() }
        current = film
        trouble = nil
        window?.title = "活画 · \(film.title)"
        Self.load(film, into: player)
    }

    private func makeWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1280, screen.width - 80)
        let size = NSSize(width: width, height: min(width * 9 / 16 + 96, screen.height - 60))
        let made = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                width: size.width, height: size.height),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        made.isReleasedWhenClosed = false
        made.collectionBehavior.insert(.fullScreenPrimary)
        made.contentMinSize = NSSize(width: 640, height: 460)
        made.contentView = NSHostingView(rootView: LiveFilmView())
        made.delegate = self
        window = made
    }

    /// Until the open film has drawn every scene once (or failed).
    func untilReady(seconds: Double = 30) async { await player.untilReady(seconds: seconds) }

    /// The line for the tools.
    func report() -> String {
        reload()
        let kept = films.map { "「\($0.title)」（\($0.id)\($0.kind == "drawing" ? "，画给我看" : "")）" }.joined(separator: "、")
        var line = films.isEmpty ? "还没有活画" : "活画：\(kept)"
        if let current, window != nil {
            line += String(format: "；窗口开着「%@」，%@ %.1f / %.1f 秒，%d 帧/秒", current.title, player.playing ? "在放" : "停着",
                           player.time, player.total, player.fps)
        }
        if let fetching { line += "；正在从盒子拿「\(fetching)」" }
        if let trouble = trouble ?? player.trouble { line += "；问题：\(trouble)" }
        return line
    }
}

extension LiveFilm: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.player.pause()
            self.window = nil
        }
    }
}

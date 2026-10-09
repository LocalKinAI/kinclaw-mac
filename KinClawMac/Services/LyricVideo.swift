import AppKit
import AVFoundation
import WebKit

/// 歌词视频: JIZURA (852wa/JIZURA, MIT) — a lyric video (文字PV) from a song and its timed lyrics, each line
/// with its own layout, entrance and camera move on the song's beats — in a window of the app's own:
/// 「jizura接入我的kinclaw-mac啊」 (2026-10-08).
///
/// The page (its Traditional Chinese edition, one 2.4 MB file) is fetched once from GitHub and kept in
/// <art>/tools/jizura. It runs in a WKWebView served from a scheme of our own, so a song and an LRC are handed
/// to its own file inputs and its own buttons do the rest. Three things measured on the way in:
///   - its export needs its window on screen: off screen WebKit throttles it to nothing (15 minutes, no file);
///     on screen a 60 s video came out in 9 s — so a job shows the window, small, at the bottom right;
///   - reading an LRC asks 「要用 LRC 的內容取代目前的歌詞嗎？」 — answered yes here, or it waits forever;
///   - WebKit's AAC from it is undecodable (0 channels), so the song itself is laid under the picture.
@MainActor
final class LyricVideo: NSObject, ObservableObject {
    static let shared = LyricVideo()

    static let page = URL(string: "https://raw.githubusercontent.com/852wa/JIZURA/main/zh-hant/index.html")!
    static let home = URL(string: "https://github.com/852wa/JIZURA")!
    static var folder: URL { CompanionArt.folder.appendingPathComponent("tools/jizura") }
    static var made: URL { CompanionArt.folder.appendingPathComponent("lyric-videos") }

    @Published private(set) var working: String?
    @Published private(set) var last: URL?
    @Published private(set) var trouble: String?

    private var window: NSWindow?
    /// Opened by the person (big, theirs to close) rather than for a job (small, closed after).
    private var interactive = false
    private var web: WKWebView?
    private let files = Files()
    private var loading: CheckedContinuation<Void, Error>?
    private var download: (target: URL, done: CheckedContinuation<Void, Error>)?

    private override init() {}

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // MARK: - The page

    /// The page as kept, fetched when missing (or `fresh`).
    @discardableResult
    func ensurePage(fresh: Bool = false) async throws -> URL {
        let file = Self.folder.appendingPathComponent("index.html")
        if !fresh, FileManager.default.fileExists(atPath: file.path) { return file }
        var request = URLRequest(url: Self.page, timeoutInterval: 60)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 100_000 else {
            if FileManager.default.fileExists(atPath: file.path) { return file }
            throw Failure.message("拿不到 JIZURA 的页面（GitHub）：\(Self.page.absoluteString)")
        }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return file
    }

    // MARK: - The window

    /// The page in its window, for the person to make one by hand.
    func show() async {
        do {
            try await open(interactive: true)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            trouble = error.localizedDescription
        }
    }

    private func open(interactive asked: Bool) async throws {
        files.page = try await ensurePage()
        if window == nil {
            let config = WKWebViewConfiguration()
            config.setURLSchemeHandler(files, forURLScheme: Files.scheme)
            let view = WKWebView(frame: .zero, configuration: config)
            view.navigationDelegate = self
            view.uiDelegate = self
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = asked ? NSSize(width: min(1320, screen.width - 80), height: min(860, screen.height - 80))
                             : NSSize(width: 480, height: 320)
            let origin = asked ? NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
                               : NSPoint(x: screen.maxX - size.width - 16, y: screen.minY + 16)
            let made = NSWindow(contentRect: NSRect(origin: origin, size: size),
                                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            made.title = "歌词视频 · JIZURA"
            made.isReleasedWhenClosed = false
            made.contentView = view
            made.delegate = self
            window = made
            web = view
            interactive = asked
            try await load()
        } else if asked {
            interactive = true
        }
        // On screen, or the export never finishes; a job does not take the person's focus.
        if asked { window?.makeKeyAndOrderFront(nil) } else { window?.orderFrontRegardless() }
    }

    private func load() async throws {
        guard let web else { return }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            loading = done
            web.load(URLRequest(url: URL(string: "\(Files.scheme)://app/index.html")!))
        }
    }

    // MARK: - A job

    struct Options {
        var title: String?
        var aspect = "16:9"
        var resolution = "1080"
        var fps = 30
        var quality = "high"
        /// Leave the middle free for a singer laid over it.
        var keepCentre = false
        /// A font on this Mac by name ("PingFang HK"): one that has every character of the lyrics.
        var font: String?
        /// zh-Hant, zh-Hans, ja, ko, en or auto.
        var language = "auto"
    }

    /// One lyric video: the song and its LRC in, an MP4 out with the song as its soundtrack.
    func make(song: URL, lrc: String, options: Options, out: URL?) async throws -> URL {
        guard working == nil else { throw Failure.message("正在做「\(working!)」，等它做完") }
        guard FileManager.default.fileExists(atPath: song.path) else { throw Failure.message("找不到这首歌：\(song.path)") }
        let lines = lrc.components(separatedBy: .newlines).filter { $0.range(of: #"^\[\d+:\d+(\.\d+)?\]"#, options: .regularExpression) != nil }
        guard !lines.isEmpty else { throw Failure.message("LRC 里没有带时间的歌词行（要像 [00:29.35]月光照落 古道旁 这样）") }
        let name = options.title ?? song.deletingPathExtension().lastPathComponent
        working = name
        trouble = nil
        defer { working = nil }

        try FileManager.default.createDirectory(at: Self.made, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let target = out ?? Self.made.appendingPathComponent("\(TalkingVideo.slug(name))-\(stamp).mp4")
        let lrcFile = Self.made.appendingPathComponent(".\(stamp).lrc")
        try lrc.write(to: lrcFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lrcFile) }

        let wasOpen = window != nil
        try await open(interactive: false)
        try await load()                                   // a clean page for each job
        files.set(["song": song, "lrc": lrcFile])
        guard let web else { throw Failure.message("JIZURA 的窗口没打开") }

        // Its own file inputs, then its own controls; the song first, so the beats are found.
        try await put(web, input: "audioFile", path: "song", name: song.lastPathComponent, type: "audio/*")
        try await waitFor(web, "!document.body.innerText.includes('尚未匯入歌曲')", seconds: 60, what: "歌导入")
        try await put(web, input: "fileLrc", path: "lrc", name: "lyrics.lrc", type: "text/plain")
        let settings: [String: Any] = [
            "lyricLang": options.language, "outAspect": options.aspect, "eAspect": options.aspect,
            "outRes": options.resolution, "eRes": options.resolution, "outFps": String(options.fps), "eFps": String(options.fps),
            "outQuality": options.quality,
        ]
        _ = try await web.callAsyncJavaScript("""
            for (const [id, value] of Object.entries(settings)) {
              const el = document.getElementById(id); if (!el) continue;
              if ([...el.options].some(o => (o.value || o.text) === value)) { el.value = value; el.dispatchEvent(new Event('change', { bubbles: true })); }
            }
            const c = document.getElementById('eCenter');
            if (c && c.checked !== keep) { c.checked = keep; c.dispatchEvent(new Event('change', { bubbles: true })); }
            if (font) { const f = document.getElementById('localFont'); if (f) { f.value = font; f.dispatchEvent(new Event('input', { bubbles: true })); f.dispatchEvent(new Event('change', { bubbles: true })); } }
            if (title) { for (const id of ['songTitle']) { const t = document.getElementById(id); if (t) { t.value = title; t.dispatchEvent(new Event('input', { bubbles: true })); } } }
            return true;
            """, arguments: ["settings": settings, "keep": options.keepCentre, "font": options.font ?? "", "title": options.title ?? ""],
            in: nil, contentWorld: .page)

        // Its export, caught as a download.
        let picture = Self.made.appendingPathComponent(".\(stamp)-picture.mp4")
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            download = (picture, done)
            web.evaluateJavaScript("document.getElementById('btnMP4').click()") { _, _ in }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
                if let pending = self?.download, pending.target == picture {
                    self?.download = nil
                    pending.done.resume(throwing: Failure.message("JIZURA 十分钟没导出来"))
                }
            }
        }
        defer { try? FileManager.default.removeItem(at: picture) }
        if !wasOpen, !interactive { window?.close() }

        try await Self.lay(song, under: picture, into: target)
        last = target
        return target
    }

    private func put(_ web: WKWebView, input: String, path: String, name: String, type: String) async throws {
        _ = try await web.callAsyncJavaScript("""
            const b = await (await fetch(url)).blob(); const dt = new DataTransfer();
            dt.items.add(new File([b], name, { type })); const el = document.getElementById(id);
            el.files = dt.files; el.dispatchEvent(new Event('change', { bubbles: true })); return b.size;
            """, arguments: ["id": input, "url": "\(Files.scheme)://app/\(path)", "name": name, "type": type],
            in: nil, contentWorld: .page)
    }

    private func waitFor(_ web: WKWebView, _ condition: String, seconds: Double, what: String) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw Failure.message("JIZURA 的\(what)一直没好")
    }

    /// The exported picture with the song itself as its sound.
    nonisolated private static func lay(_ song: URL, under picture: URL, into out: URL) async throws {
        let video = AVURLAsset(url: picture), sound = AVURLAsset(url: song)
        guard let pictureTrack = try await video.loadTracks(withMediaType: .video).first,
              let soundTrack = try await sound.loadTracks(withMediaType: .audio).first else {
            throw Failure.message("导出的视频或这首歌读不出来")
        }
        let length = try await video.load(.duration)
        let soundLength = try await sound.load(.duration)
        let mix = AVMutableComposition()
        guard let v = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.message("拼不起来")
        }
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: pictureTrack, at: .zero)
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, soundLength)), of: soundTrack, at: .zero)
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.message("导不出来")
        }
        export.outputURL = out
        export.outputFileType = .mp4
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in export.exportAsynchronously { done.resume() } }
        guard export.status == .completed else {
            throw Failure.message("配上原曲时失败：\(export.error?.localizedDescription ?? "不知道为什么")")
        }
    }

    /// The line for the tools.
    func report() -> String {
        if let working { return "在做歌词视频「\(working)」（JIZURA 的窗口在屏幕右下角，做完自己关）" }
        let kept = FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent("index.html").path)
        return (last.map { "最近做好的歌词视频：\($0.path)" } ?? "还没做过歌词视频")
            + (kept ? "" : "（JIZURA 的页面第一次用时从 GitHub 拿，2.4 MB）")
            + (trouble.map { "；上次的问题：\($0)" } ?? "")
    }
}

extension LyricVideo: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, NSWindowDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.loading?.resume(); self.loading = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loading?.resume(throwing: error); self.loading = nil }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                             decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let download = action.shouldPerformDownload
        Task { @MainActor in decisionHandler(download ? .download : .allow) }
    }

    nonisolated func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        Task { @MainActor in download.delegate = self }
    }

    nonisolated func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Task { @MainActor in download.delegate = self }
    }

    /// Where its export goes: the job's file, or — made by hand — the lyric videos folder.
    nonisolated func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                              completionHandler: @escaping @MainActor (URL?) -> Void) {
        Task { @MainActor in
            let target = self.download?.target
                ?? Self.made.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(suggestedFilename)")
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            if self.download == nil { self.last = target }
            completionHandler(target)
        }
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            if let pending = self.download { self.download = nil; pending.done.resume() }
            else if let last = self.last { NSWorkspace.shared.activateFileViewerSelecting([last]) }
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Task { @MainActor in
            if let pending = self.download { self.download = nil; pending.done.resume(throwing: error) }
        }
    }

    /// 「要用 LRC 的內容取代目前的歌詞嗎？」 and the like: yes.
    nonisolated func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                             initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in completionHandler(true) }
    }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                             initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        Task { @MainActor in self.trouble = message; completionHandler() }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.window = nil; self.web = nil; self.interactive = false }
    }
}

/// The page and the job's files, served from `kinclaw-jizura://app/…` — the page itself, `song` and `lrc`.
private final class Files: NSObject, WKURLSchemeHandler {
    static let scheme = "kinclaw-jizura"
    private let lock = NSLock()
    private var served: [String: URL] = [:]
    private var pageFile: URL?

    var page: URL? {
        get { lock.lock(); defer { lock.unlock() }; return pageFile }
        set { lock.lock(); pageFile = newValue; lock.unlock() }
    }

    func set(_ files: [String: URL]) { lock.lock(); served = files; lock.unlock() }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let path = String((task.request.url?.path ?? "/").dropFirst())
        lock.lock(); let file = path.isEmpty || path == "index.html" ? pageFile : served[path]; lock.unlock()
        guard let file, let data = try? Data(contentsOf: file), let url = task.request.url else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let type = file.pathExtension == "html" ? "text/html" : "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: type == "text/html" ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

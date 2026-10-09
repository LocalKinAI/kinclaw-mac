import AppKit
import WebKit

/// One huashu film drawn live in a web view — the engine's own page, served from a scheme of our own,
/// with WebKit's canvas filters switched on and the song playing in the page; `live.*` drives it.
/// 活画's window has one, a 「画给我看」 card in a conversation has one, and the drawing check keeps one
/// off screen to look at a drawing the way the person will see it.
///
/// Why each part is there (measured 2026-10-08):
///   - huashu loads its scenes by synchronous XHR: a scheme can serve them, if every file is an HTTP 200;
///   - WebKit's canvas `filter` is off by default and huashu's ink is mostly blur — without it the mist
///     of 《倩影》 came out as hard white ellipses — so it is switched on for these views only;
///   - a frame takes 4–15 ms here (60 fps), the first frame of a scene up to a quarter of a second while
///     its layers are painted once, so every scene is drawn once before anything plays;
///   - the picture keeps its own clock (smooth) and is pulled back to the song's whenever they drift
///     more than 80 ms apart.
@MainActor
final class LivePlayer: NSObject, ObservableObject {
    struct Era: Identifiable, Hashable {
        let id: String
        let t0: Double
        let t1: Double
    }

    /// A control the film gives the person (window.LIVE_KNOBS in live_<film>.js).
    struct Knob: Identifiable, Hashable {
        let id: String
        let label: String
        let min: Double
        let max: Double
        var value: Double
        let step: Double
    }

    @Published private(set) var ready = false
    @Published private(set) var playing = false
    @Published private(set) var time: Double = 0
    @Published private(set) var total: Double = 0
    @Published private(set) var eras: [Era] = []
    @Published private(set) var knobs: [Knob] = []
    @Published private(set) var fps = 0
    @Published private(set) var rate: Double = 1
    @Published private(set) var loops = true
    @Published private(set) var lettering = true
    @Published private(set) var hasSong = false
    @Published private(set) var trouble: String?
    /// Every error the page has reported since it was loaded, for the drawing check.
    private(set) var errors: [String] = []
    /// The film it has loaded, by its eras name.
    private(set) var film: String?

    let view: WKWebView
    private let files: LiveFiles
    private let messages: LiveMessages
    private var whenReady: [CheckedContinuation<Void, Never>] = []
    /// A window off screen to keep the view in when no window shows it (the drawing check).
    private var shelf: NSWindow?

    override init() {
        let files = LiveFiles(), messages = LiveMessages()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(files, forURLScheme: LiveFiles.scheme)
        config.mediaTypesRequiringUserActionForPlayback = []
        let filters = Self.enableCanvasFilters(config.preferences)
        let content = config.userContentController
        content.add(messages, name: "live")
        content.addUserScript(WKUserScript(source: Self.errorsScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: Self.playerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: config)
        view.underPageBackgroundColor = .black
        self.files = files
        self.messages = messages
        self.view = view
        super.init()
        messages.owner = self
        if !filters { trouble = "这台 Mac 的 WebKit 没有画布滤镜开关：雾和光会是硬边的" }
    }

    /// A film: its own folder first, then `base` for what it does not have (a drawing keeps only its own
    /// scenes; huashu's engine is shared), its song if it has one, and `length` when its voice runs longer
    /// than its pictures (the last shot holds).
    func load(_ folder: URL, base: URL? = nil, film: String, song: URL? = nil, length: Double? = nil) {
        files.serve([folder] + (base.map { [$0] } ?? []), song: song)
        self.film = film
        ready = false
        playing = false
        time = 0
        total = 0
        eras = []
        knobs = []
        fps = 0
        hasSong = false
        errors = []
        if trouble?.hasPrefix("这台 Mac") != true { trouble = nil }
        let longer = length.map { "&total=\(String(format: "%.2f", $0))" } ?? ""
        view.load(URLRequest(url: URL(string: "\(LiveFiles.scheme)://film/index.html?film=\(film)&render=1\(longer)&v=\(Int(Date().timeIntervalSince1970))")!))
    }

    /// Put in a window off screen when nothing shows it, so that it loads and draws.
    func shelve() {
        guard view.window == nil else { return }
        if shelf == nil {
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 960, height: 540), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            shelf = window
        }
        shelf?.contentView = view
    }

    /// Done with: the page emptied and the window off screen let go (a player made for one export).
    func discard() {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        shelf?.contentView = nil
        shelf?.close()
        shelf = nil
    }

    /// Until it has drawn every scene once, or failed, or `seconds` went by.
    func untilReady(seconds: Double = 30) async {
        if ready { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            whenReady.append(done)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard let self, !self.whenReady.isEmpty else { return }
                self.whenReady.forEach { $0.resume() }
                self.whenReady = []
            }
        }
    }

    // MARK: - Playing

    func play() { run("live.play()") }
    func pause() { run("live.pause()") }
    func toggle() { playing ? pause() : play() }

    func seek(_ seconds: Double) {
        time = max(0, min(total, seconds))
        run("live.seek(\(time))")
    }

    func setRate(_ value: Double) {
        rate = max(0.1, min(2, value))
        run("live.rate(\(rate))")
    }

    func setLoops(_ on: Bool) {
        loops = on
        run("live.loop(\(on))")
    }

    func setLettering(_ on: Bool) {
        lettering = on
        run("live.lyrics(\(on))")
    }

    func setKnob(_ id: String, _ value: Double) {
        guard let index = knobs.firstIndex(where: { $0.id == id }) else { return }
        knobs[index].value = value
        guard let data = try? JSONSerialization.data(withJSONObject: [id]), let quoted = String(data: data, encoding: .utf8) else { return }
        run("live.knob(\(quoted.dropFirst().dropLast()), \(value))")
    }

    private func run(_ js: String) {
        view.evaluateJavaScript(js) { _, _ in }
    }

    // MARK: - Looking at it

    struct Shot {
        let png: Data
        /// How much the frame varies (the spread of its brightness, 0–128): near 0 is one flat colour.
        let spread: Double
    }

    /// The frame at `t` as a PNG `width` pixels wide; it stops playing.
    func frame(at t: Double, width: Int = 960) async throws -> Shot {
        let value = try await view.callAsyncJavaScript("""
            live.pause(); live.seek(t);
            const src = window.__canvas, k = Math.min(1, w / src.width);
            const out = document.createElement('canvas'); out.width = Math.round(src.width * k); out.height = Math.round(src.height * k);
            const g = out.getContext('2d'); g.imageSmoothingQuality = 'high'; g.drawImage(src, 0, 0, out.width, out.height);
            const px = g.getImageData(0, 0, out.width, out.height).data; let n = 0, s = 0, s2 = 0;
            for (let i = 0; i < px.length; i += 16) { const y = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]; n++; s += y; s2 += y * y; }
            const mean = s / n;
            return { png: out.toDataURL('image/png').split(',')[1], spread: Math.sqrt(Math.max(0, s2 / n - mean * mean)) };
            """, arguments: ["t": t, "w": width], in: nil, contentWorld: .page)
        guard let shot = value as? [String: Any], let text = shot["png"] as? String, let png = Data(base64Encoded: text) else {
            throw LiveFilm.Failure.message("拿不到 \(t) 秒那一帧")
        }
        return Shot(png: png, spread: shot["spread"] as? Double ?? 0)
    }

    /// The full frame at `t` as a JPEG, for a video; it stops playing.
    func jpeg(at t: Double, quality: Double = 0.93) async throws -> Data {
        let value = try await view.callAsyncJavaScript("""
            live.pause(); live.seek(t);
            return window.__canvas.toDataURL('image/jpeg', q).split(',')[1];
            """, arguments: ["t": t, "q": quality], in: nil, contentWorld: .page)
        guard let text = value as? String, let data = Data(base64Encoded: text) else {
            throw LiveFilm.Failure.message("拿不到 \(t) 秒那一帧")
        }
        return data
    }

    /// How long a frame takes to draw here: the median and the slowest, in milliseconds.
    func bench(_ times: [Double]) async -> (median: Double, worst: Double)? {
        guard let value = try? await view.callAsyncJavaScript("""
            const px = window.__canvas.getContext('2d'), ms = [];
            for (const t of times) { const a = performance.now(); window.renderFrame(t); px.getImageData(0, 0, 1, 1); ms.push(performance.now() - a); }
            ms.sort((a, b) => a - b);
            return [ms[ms.length >> 1], ms[ms.length - 1]];
            """, arguments: ["times": times], in: nil, contentWorld: .page) as? [Double], value.count == 2 else { return nil }
        return (value[0], value[1])
    }

    // MARK: - The page's messages

    fileprivate func receive(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            total = body["total"] as? Double ?? 0
            eras = (body["eras"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, let t0 = $0["t0"] as? Double, let t1 = $0["t1"] as? Double else { return nil }
                return Era(id: id, t0: t0, t1: t1)
            }
            knobs = (body["knobs"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, let min = $0["min"] as? Double, let max = $0["max"] as? Double else { return nil }
                return Knob(id: id, label: $0["label"] as? String ?? id, min: min, max: max,
                            value: $0["value"] as? Double ?? min, step: $0["step"] as? Double ?? 0)
            }
            hasSong = body["song"] as? Bool ?? false
            if body["filters"] as? Bool == false { trouble = "WebKit 的画布滤镜没开：雾和光会是硬边的" }
            ready = true
            run("live.rate(\(rate)); live.loop(\(loops)); live.lyrics(\(lettering))")
            whenReady.forEach { $0.resume() }
            whenReady = []
        case "tick":
            time = body["t"] as? Double ?? time
            fps = body["fps"] as? Int ?? fps
            playing = body["playing"] as? Bool ?? playing
        case "error":
            let said = String((body["message"] as? String ?? "出错了").prefix(600))
            if !errors.contains(said), errors.count < 50 { errors.append(said) }
            trouble = String(said.prefix(300))
            if !ready, body["boot"] as? Bool == true { whenReady.forEach { $0.resume() }; whenReady = [] }
        default:
            break
        }
    }

    // MARK: - WebKit's canvas filters

    /// WebKit's own canvas `filter` (blur, brightness, contrast…) is behind a feature switch that is off
    /// in WebKit 26; it is switched on for these views only, through WebKit's list of features.
    private static func enableCanvasFilters(_ preferences: WKPreferences) -> Bool {
        let type: AnyObject = WKPreferences.self
        let list = NSSelectorFromString("_features"), set = NSSelectorFromString("_setEnabled:forFeature:")
        guard type.responds(to: list), preferences.responds(to: set),
              let features = type.perform(list)?.takeUnretainedValue() as? [NSObject],
              let feature = features.first(where: { ($0.value(forKey: "key") as? String) == "CanvasFiltersEnabled" }) else {
            return false
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, true, feature)
        return true
    }

    // MARK: - The page's side

    private static let errorsScript = """
        (() => {
          const post = m => window.webkit.messageHandlers.live.postMessage(m);
          window.addEventListener('error', e => post({ type: 'error', message: String(e.message || e) + (e.filename ? ' (' + e.filename.split('/').pop() + ':' + e.lineno + ')' : '') }));
          window.addEventListener('unhandledrejection', e => post({ type: 'error', message: String(e.reason) }));
          const said = console.error.bind(console);
          console.error = (...a) => { post({ type: 'error', message: a.map(String).join(' ') }); said(...a); };
        })();
        """

    /// huashu's page with its own preview hidden: the picture fills the view, the song plays here, and
    /// `live.*` is what the app calls. live_<film>.js, when the film has one, gives the knobs.
    private static let playerScript = #"""
        (() => {
          const post = m => window.webkit.messageHandlers.live.postMessage(m);
          const css = document.createElement('style');
          css.textContent = 'html,body{margin:0;height:100%;background:#000;overflow:hidden} #ui{display:none!important} canvas#c{display:block;width:100vw;height:100vh;max-width:none;object-fit:contain}';
          document.head.appendChild(css);
          const query = new URLSearchParams(location.search), film = query.get('film') || '', longer = +(query.get('total') || 0);
          const audio = new Audio(); audio.preservesPitch = true;
          let playing = false, rate = 1, loop = true, anchorT = 0, anchorWall = 0, frames = 0, fpsWall = 0, fps = 0, lastPost = 0, overlay = null;
          const total = () => window.__total || 0;
          const clock = () => playing ? anchorT + (performance.now() - anchorWall) / 1000 * rate : anchorT;
          const anchor = t => { anchorT = t; anchorWall = performance.now(); };
          const draw = t => { try { window.renderFrame(Math.max(0, Math.min(total() - 0.001, t))); } catch (e) { post({ type: 'error', message: String(e && e.stack || e) }); } };
          const say = () => post({ type: 'tick', t: clock(), fps: Math.round(fps), playing });
          async function boot() {
            const began = performance.now();
            while (!window.__ready) {
              if (window.__bootFailed) { post({ type: 'error', boot: true, message: window.__bootFailed }); return; }
              if (performance.now() - began > 60000) { post({ type: 'error', boot: true, message: 'huashu 的引擎一分钟没起来' }); return; }
              await new Promise(r => setTimeout(r, 50));
            }
            try { const r = await fetch('live_' + film + '.js'); if (r.ok) (0, eval)(await r.text() + '\n//# sourceURL=live_' + film + '.js'); }
            catch (e) { post({ type: 'error', message: 'live_' + film + '.js：' + e }); }
            try { const r = await fetch('__song'); if (r.ok) { const b = await r.blob(); if (b.size) audio.src = URL.createObjectURL(b); } } catch (e) {}
            if (longer > total()) window.__total = longer;                // its voice runs on: the last shot holds
            for (const e of ERAS) { draw(e.t0 + 0.02); draw(Math.min(e.t1, total()) - 0.05); }
            overlay = window.GLOBAL_OVERLAY || null;
            draw(0);
            post({ type: 'ready', total: total(), song: !!audio.src,
                   filters: 'filter' in CanvasRenderingContext2D.prototype,
                   eras: ERAS.map(e => ({ id: e.id, t0: e.t0, t1: Math.min(e.t1, total()) })),
                   knobs: (window.LIVE_KNOBS || []).map(k => ({ id: k.id, label: k.label || k.id, min: k.min, max: k.max, value: k.value, step: k.step || 0 })) });
            fpsWall = performance.now();
            requestAnimationFrame(tick);
          }
          function tick(now) {
            requestAnimationFrame(tick);
            if (!playing) return;
            let t = clock();
            if (t >= total()) {
              if (loop) { live.seek(0); t = 0; }
              else { anchor(total()); playing = false; audio.pause(); draw(total()); say(); return; }
            }
            draw(t);
            frames++;
            if (now - fpsWall > 500) { fps = frames * 1000 / (now - fpsWall); frames = 0; fpsWall = now; }
            if (now - lastPost > 100) { lastPost = now; say(); }
          }
          // The song is the clock: the picture is pulled back to it when they drift apart.
          setInterval(() => { if (playing && audio.src && !audio.paused && Math.abs(audio.currentTime - clock()) > 0.08) anchor(audio.currentTime); }, 500);
          audio.addEventListener('playing', () => { if (playing) anchor(audio.currentTime); });
          window.live = {
            async play() {
              if (playing) return;
              if (clock() >= total() - 0.05) anchor(0);
              playing = true; anchor(anchorT); frames = 0; fpsWall = performance.now();
              if (audio.src) { audio.currentTime = anchorT; audio.playbackRate = rate;
                try { await audio.play(); } catch (e) { post({ type: 'error', message: '歌放不出来：' + e }); } }
              say();
            },
            pause() { anchor(clock()); playing = false; audio.pause(); draw(anchorT); fps = 0; say(); },
            seek(t) { t = Math.max(0, Math.min(total(), t)); anchor(t); if (audio.src) audio.currentTime = t; if (!playing) draw(t); say(); },
            rate(r) { anchor(clock()); rate = r; audio.playbackRate = r; },
            loop(v) { loop = !!v; },
            lyrics(v) { window.GLOBAL_OVERLAY = v ? overlay : null; if (!playing) draw(clock()); },
            knob(id, v) { const k = (window.LIVE_KNOBS || []).find(k => k.id === id); if (!k) return; k.value = v;
              try { k.apply(v); } catch (e) { post({ type: 'error', message: String(e) }); } if (!playing) draw(clock()); },
          };
          boot();
        })();
        """#
}

/// The page's messages, without the content controller holding the player strongly.
private final class LiveMessages: NSObject, WKScriptMessageHandler {
    weak var owner: LivePlayer?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak owner] in owner?.receive(body) }
    }
}

/// A film's folders, served from `kinclaw-live://film/…` — the first folder that has the file — and its
/// song as `__song`. An HTTP 200 for every file (the engine's synchronous XHR checks the status), and
/// nothing kept: a drawing changes between two loads.
private final class LiveFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "kinclaw-live"
    private let lock = NSLock()
    private var roots: [URL] = []
    private var song: URL?

    func serve(_ folders: [URL], song file: URL?) {
        lock.lock(); roots = folders.map(\.standardizedFileURL); song = file; lock.unlock()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = String(url.path.drop(while: { $0 == "/" }))
        lock.lock(); let roots = roots, song = song; lock.unlock()
        var data: Data?, file: URL?
        if path == "__song" {
            file = song
            data = song.flatMap { try? Data(contentsOf: $0) }
        } else {
            for root in roots {
                let wanted = root.appendingPathComponent(path).standardizedFileURL
                guard wanted.path.hasPrefix(root.path + "/"), let found = try? Data(contentsOf: wanted) else { continue }
                file = wanted
                data = found
                break
            }
        }
        guard let file, let data else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "no-store"])!)
            task.didFinish()
            return
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "json": "application/json",
                     "css": "text/css", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp",
                     "svg": "image/svg+xml", "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf", "otf": "font/otf",
                     "wav": "audio/wav", "mp3": "audio/mpeg", "m4a": "audio/mp4", "flac": "audio/flac"]
        let type = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": type, "Content-Length": "\(data.count)", "Cache-Control": "no-store"])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

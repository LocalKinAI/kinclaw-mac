import AppKit
import WebKit

/// 「做成一台机器」's check: anatomy's drive.mjs, in WebKit. A figure's page is loaded out of sight in
/// the WebKit the person will use it in and driven step by step — wait, scroll, move, click, drag, key,
/// slow, until, eval, shot, sheet, lines, with drive.mjs's own arguments — and the answer is what each
/// step saw: the readout after every picture, the console's errors and exceptions, whether the page
/// scrolls sideways, the line ends that float, and the pictures.
///
/// anatomy checks its figures in headless Chrome. The person sees them here, and a Mac with this app need
/// not have Chrome. Its line check is page code (scripts/line-ends.mjs) and runs here as it is. The steps'
/// events are the page's own — PointerEvent, MouseEvent and KeyboardEvent dispatched where the point is —
/// not the system's: CSS :hover does not follow them, and pointer capture is kept by the page's side.
///
/// The page draws in a window far off screen, ordered in and kept "visible" (WebKit's occlusion check off
/// for it): out of a window, or in one hidden, WebKit sends a page no animation frames, and a figure's
/// motion is all requestAnimationFrame.
@MainActor
final class MachineCheck: NSObject {
    struct Options {
        /// The viewport, in CSS px: 1440 × 1100 as drive.mjs; 390 wide for a phone. It grows taller
        /// when a picture reaches below it.
        var width: Double = 1440
        var height: Double = 1100
        /// Every getContext("webgl"/"webgl2") answers null: the SVG without its shaders.
        var noWebGL = false
        /// matchMedia('(prefers-reduced-motion: reduce)') matches (the page's script only; CSS does not follow).
        var reduced = false
        /// As it sits in a conversation: no margins round the card (LiveMachine's inline view).
        var embedded = false
        /// JavaScript run before the page's own (drive.mjs's --preload).
        var preload: String?
    }

    struct Outcome {
        var lines: [String] = []
        var pictures: [URL] = []
        /// Floating line ends, steps that failed, errors: none when all is well.
        var problems = 0
    }

    /// What a figure's page loses when it sits in a conversation: the page's margins round its card.
    static let embeddedCSS = """
        html,body{overflow:hidden!important}.iso-page{width:100%!important;margin:0 auto!important}.iso-figure{margin:0!important}\
        .iso-legend{padding:0 14px 14px}
        """

    private let view: WKWebView
    private let window: NSWindow
    private let relay = MachineRelay()
    private var errors: [String] = []
    private var loading: CheckedContinuation<String?, Never>?
    private var pending: WKNavigation?
    /// One check at a time: the others wait their turn.
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Where the steps' pointer is, in CSS px.
    private var mouse = CGPoint(x: 4, y: 4)

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 1100)
        view = WKWebView(frame: frame, configuration: config)
        window = NSWindow(contentRect: frame.offsetBy(dx: -20000, dy: -20000), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = view
        super.init()
        Self.keepDrawing(view)
        view.navigationDelegate = relay
        config.userContentController.add(relay, name: "machine")
        relay.owner = self
    }

    /// WebKit stops a page's animation frames when it thinks its window can't be seen: told not to look.
    static func keepDrawing(_ view: WKWebView) {
        let set = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard view.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(view.method(for: set), to: Setter.self)(view, set, false)
    }

    // MARK: - A check

    /// `page` loaded with `options`, `steps` done in order (default: wait 2.5 s, a picture of the card,
    /// the line check); pictures written to `shots`. `lineEnds` is anatomy's line check (the function in
    /// scripts/line-ends.mjs).
    func run(_ page: URL, steps given: [[Any]]?, options: Options = Options(), shots: URL, lineEnds: String?) async -> Outcome {
        await take()
        defer { give() }
        var out = Outcome()
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let began = Date()
        if let trouble = await open(page, options) {
            out.lines.append("打不开 \(page.lastPathComponent)：\(trouble)")
            out.problems += 1
            window.orderOut(nil)
            return out
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let title = (await js("return document.title || ''").0 as? String) ?? ""
        out.lines.append(String(format: "「%@」加载 %.1f 秒，视口 %d × %d%@", title, Date().timeIntervalSince(began),
                                Int(options.width), Int(view.bounds.height),
                                options.noWebGL ? "，WebGL 关着" : "") + (options.reduced ? "，减少动态" : ""))
        let fallback: [[Any]] = [["wait", 2500], ["shot", "card"], ["lines"]]
        let steps = given?.isEmpty == false ? given! : fallback
        var taken = 0
        for (index, step) in steps.enumerated() {
            let (said, pictures, failed) = await perform(step, index: index, shots: shots, lineEnds: lineEnds, taken: &taken)
            if let said { out.lines.append(said) }
            out.pictures += pictures
            out.problems += failed
        }
        if let wide = await js("return [document.documentElement.scrollWidth, window.innerWidth]").0 as? [Any],
           let content = Self.number(wide.first), let viewport = Self.number(wide.last), content > viewport + 1 {
            out.lines.append("页面横着会滚：内容 \(Int(content)) px 宽，视口 \(Int(viewport)) px")
            out.problems += 1
        }
        if errors.isEmpty {
            out.lines.append("console: clean")
        } else {
            out.lines.append("console（\(errors.count)）：\n" + errors.prefix(15).joined(separator: "\n"))
            out.problems += errors.count
        }
        window.orderOut(nil)
        return out
    }

    /// The page as it sits in a conversation, `width` px wide, as a picture at twice that; its height in px.
    func poster(_ page: URL, width: Double, to file: URL) async -> Double? {
        await take()
        defer { give() }
        var options = Options()
        options.width = width
        options.height = 600
        options.embedded = true
        guard await open(page, options) == nil else { window.orderOut(nil); return nil }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let height = Self.number(await js("return Math.ceil(document.body.getBoundingClientRect().height)").0) ?? 600
        await resize(CGSize(width: width, height: min(max(height, 100), 6000)))
        defer { window.orderOut(nil) }
        guard let png = try? await snapshot(view.bounds, scale: 2) else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? png.write(to: file)) != nil else { return nil }
        return height
    }

    private func take() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func give() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    /// Loaded fresh, the scripts it asks for set before the page's own; nil, or what went wrong.
    private func open(_ page: URL, _ options: Options) async -> String? {
        let content = view.configuration.userContentController
        content.removeAllUserScripts()
        var early = [Self.driveScript]
        if options.noWebGL { early.append(Self.noWebGLScript) }
        if options.reduced { early.append(Self.reducedScript) }
        if let preload = options.preload, !preload.isEmpty { early.append(preload) }
        for source in early {
            content.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if options.embedded {
            let css = "(() => { const s = document.createElement('style'); s.textContent = \(Self.quoted(Self.embeddedCSS)); document.head.appendChild(s); })();"
            content.addUserScript(WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        errors = []
        mouse = CGPoint(x: 4, y: 4)
        await resize(CGSize(width: options.width, height: options.height))
        window.orderBack(nil)
        var parts = URLComponents(url: page, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "v", value: String(UUID().uuidString.prefix(8)))]
        loaded(nil, trouble: "又加载了一次")
        return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            loading = done
            let navigation = view.loadFileURL(parts?.url ?? page, allowingReadAccessTo: page.deletingLastPathComponent())
            pending = navigation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.pending === navigation else { return }
                self.loaded(navigation, trouble: "二十秒没加载完")
            }
        }
    }

    /// The load that `navigation` is has finished (nil: whatever is loading, given up on).
    fileprivate func loaded(_ navigation: WKNavigation?, trouble: String?) {
        guard navigation == nil || navigation === pending else { return }
        pending = nil
        loading?.resume(returning: trouble)
        loading = nil
    }

    fileprivate func receive(_ body: [String: Any]) {
        guard body["type"] as? String == "error" else { return }
        let said = String((body["message"] as? String ?? "出错了").prefix(600))
        if !errors.contains(said), errors.count < 50 { errors.append(said) }
    }

    private func resize(_ size: CGSize) async {
        guard view.bounds.size != size else { return }
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        _ = await js("await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); return 1", timeout: 2)
    }

    // MARK: - The steps

    /// One step, as drive.mjs takes it: what it saw (nil: nothing to say), its pictures, and how many
    /// problems it found.
    private func perform(_ step: [Any], index: Int, shots: URL, lineEnds: String?, taken: inout Int) async -> (String?, [URL], Int) {
        guard let kind = step.first as? String else { return ("第 \(index + 1) 步不是 [\"动作\", …]", [], 1) }
        func arg(_ i: Int) -> Any? { i < step.count && !(step[i] is NSNull) ? step[i] : nil }
        func number(_ i: Int) -> Double? { Self.number(arg(i)) }
        func text(_ i: Int) -> String? { arg(i) as? String }
        func region(_ i: Int) -> CGRect? {
            guard let values = (arg(i) as? [Any])?.compactMap({ Self.number($0) }), values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        func name(_ i: Int, _ fallback: String) -> String {
            let given = ((text(i) ?? "") as NSString).lastPathComponent
            let stem = (given as NSString).deletingPathExtension.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            taken += 1
            return stem.isEmpty ? "\(fallback)-\(taken)" : String(stem.prefix(60))
        }
        func point(_ selector: String?, _ fx: Double?, _ fy: Double?) async -> CGPoint? {
            guard let rect = await box(selector) else { return nil }
            return CGPoint(x: rect.minX + rect.width * (fx ?? 0.5), y: rect.minY + rect.height * (fy ?? 0.5))
        }
        let missing = "页面上没有 \(text(1) ?? ".iso-plate")"

        switch kind {
        case "wait":
            try? await Task.sleep(nanoseconds: UInt64(min(max(number(1) ?? 0, 0), 60_000) * 1_000_000))
            return (nil, [], 0)
        case "scroll":
            _ = await js("const el = document.querySelector(sel || '.iso-plate'); if (el) el.scrollIntoView({ block: 'center' }); return 1", ["sel": text(1) ?? ""])
            return (nil, [], 0)
        case "move":
            guard let to = await point(text(1), number(2), number(3)) else { return ("move：\(missing)", [], 1) }
            await glide(to)
            return (nil, [], 0)
        case "click":
            guard let to = await point(text(1), number(2), number(3)) else { return ("click：\(missing)", [], 1) }
            mouse = to
            _ = await js("__drive.move(x, y); __drive.down(x, y); __drive.up(x, y); return 1", ["x": to.x, "y": to.y])
            return (nil, [], 0)
        case "drag":
            guard let from = await point(text(1), number(2), number(3)),
                  let to = await point(text(1), number(4), number(5)) else { return ("drag：\(missing)", [], 1) }
            mouse = from
            _ = await js("__drive.move(x, y); __drive.down(x, y); return 1", ["x": from.x, "y": from.y])
            let count = max(1, Int(number(6) ?? 20))
            for i in 1...count {
                let at = CGPoint(x: from.x + (to.x - from.x) * Double(i) / Double(count), y: from.y + (to.y - from.y) * Double(i) / Double(count))
                _ = await js("__drive.move(x, y); return 1", ["x": at.x, "y": at.y])
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            _ = await js("__drive.up(x, y); return 1", ["x": to.x, "y": to.y])
            mouse = to
            return (nil, [], 0)
        case "key":
            let key = text(1) ?? ""
            guard !key.isEmpty else { return ("key：要一个键", [], 1) }
            let named = [" ": "Space", "-": "Minus", "=": "Equal", ",": "Comma", ".": "Period", "/": "Slash", ";": "Semicolon",
                         "'": "Quote", "[": "BracketLeft", "]": "BracketRight", "\\": "Backslash", "`": "Backquote"]
            let digit = key.count == 1 && key.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
            let code = text(3) ?? named[key] ?? (digit ? "Digit\(key)" : key.count == 1 ? "Key\(key.uppercased())" : key)
            _ = await js("const el = document.querySelector(sel); if (el) el.focus(); __drive.key(key, code); return 1",
                         ["sel": text(2) ?? "[tabindex=\"0\"]", "key": key, "code": code])
            return (nil, [], 0)
        case "slow":
            _ = await js("window.__driveSpeed = f; return 1", ["f": number(1) ?? 1])
            return (nil, [], 0)
        case "until":
            guard let expression = text(1) else { return ("until：要一个 JS 表达式", [], 1) }
            let limit = Date().addingTimeInterval(min(number(2) ?? 10_000, 60_000) / 1000)
            while Date() < limit {
                if await js("return Boolean(await (0, eval)(src))", ["src": expression]).0 as? Bool == true { return (nil, [], 0) }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return ("until: timed out waiting for \(expression.prefix(200))", [], 1)
        case "eval":
            guard let source = text(1) else { return ("eval：要一段 JS", [], 1) }
            let (value, trouble) = await js("""
                const v = await (0, eval)(src);
                if (v === undefined) return 'undefined';
                try { return JSON.stringify(v); } catch (e) { return String(v); }
                """, ["src": source])
            if let trouble { return ("eval 出错：\(trouble)", [], 1) }
            return ("eval: \(String(describing: value ?? "null").prefix(2000))", [], 0)
        case "shot":
            let file = shots.appendingPathComponent(name(1, "shot") + ".png")
            do {
                let png = try await shot(text(2), scale: number(3) ?? 1, region: region(4))
                try png.write(to: file)
            } catch {
                return ("shot \(file.lastPathComponent)：\(error.localizedDescription)", [], 1)
            }
            return ("shot \(file.lastPathComponent) · readout \"\(await readout())\"", [file], 0)
        case "sheet":
            let file = shots.appendingPathComponent(name(1, "sheet") + ".png")
            let every = max(0, number(2) ?? 200), count = min(max(1, Int(number(3) ?? 6)), 48)
            var frames: [CGImage] = [], said: [String] = []
            for i in 0..<count {
                if i > 0 { try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000)) }
                guard let png = try? await shot(text(4), scale: number(5) ?? 0.5, region: region(6)),
                      let source = CGImageSourceCreateWithData(png as CFData, nil),
                      let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                frames.append(frame)
                said.append("\(i):\"\(await readout())\"")
            }
            guard let tiled = Self.tile(frames, columns: Int(number(7) ?? Double(min(count, 6)))), (try? tiled.write(to: file)) != nil else {
                return ("sheet \(file.lastPathComponent)：拿不到画面", [], 1)
            }
            return ("sheet \(file.lastPathComponent) · \(frames.count) frames every \(Int(every)) ms · readouts \(said.joined(separator: " "))", [file], 0)
        case "lines":
            guard let lineEnds else { return ("lines：没有 anatomy 的 line-ends.mjs", [], 1) }
            let out = text(1) == nil ? nil : shots.appendingPathComponent(name(1, "lines") + ".png")
            var options = (arg(3) as? [String: Any]) ?? [:]
            options["select"] = text(2) ?? NSNull()
            options["show"] = out != nil
            let (value, trouble) = await js("return (\(lineEnds))(options)", ["options": options], timeout: 60)
            guard let result = value as? [String: Any] else { return ("lines: the check did not run\(trouble.map { "（\($0)）" } ?? "")", [], 1) }
            let problems = result["problems"] as? [[String: Any]] ?? []
            var said = ["line ends: \(problems.count) of \(Self.number(result["ends"]).map { Int($0) } ?? 0) ends on \(Self.number(result["lines"]).map { Int($0) } ?? 0) lines float"]
            for problem in problems.prefix(40) { said.append("  " + Self.describe(problem)) }
            if problems.count > 40 { said.append("  …还有 \(problems.count - 40) 处") }
            var pictures: [URL] = []
            if let out {
                if let png = try? await shot(text(2), scale: 2, region: nil), (try? png.write(to: out)) != nil {
                    pictures.append(out)
                    said.append("shot \(out.lastPathComponent)")
                }
                _ = await js("const o = document.querySelector('[data-line-ends]'); if (o) o.remove(); return 1")
            }
            return (said.joined(separator: "\n"), pictures, problems.count)
        case "turn", "orbit":
            return ("\(kind)：3D 的转动这里不做（做成一台机器只做平面的 Figure）", [], 1)
        default:
            return ("unknown action \(kind)", [], 1)
        }
    }

    /// The pointer glides there in ten moves a frame apart, as drive.mjs's does.
    private func glide(_ to: CGPoint) async {
        let from = mouse
        for i in 1...10 {
            let at = CGPoint(x: from.x + (to.x - from.x) * Double(i) / 10, y: from.y + (to.y - from.y) * Double(i) / 10)
            _ = await js("__drive.move(x, y); return 1", ["x": at.x, "y": at.y])
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        mouse = to
    }

    /// An element's box in the viewport (CSS px): `selector`, or the card (.iso-plate), or the page.
    private func box(_ selector: String?) async -> CGRect? {
        let value = await js("""
            const el = sel ? document.querySelector(sel) : (document.querySelector('.iso-plate') || document.body);
            if (!el) return null;
            const r = el.getBoundingClientRect();
            return [r.left, r.top, r.width, r.height];
            """, ["sel": selector ?? ""]).0
        guard let values = (value as? [Any])?.compactMap({ Self.number($0) }), values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func readout() async -> String {
        (await js("return (document.querySelector('[data-readout]') || {}).textContent || ''").0 as? String) ?? ""
    }

    /// An element, or a region of it in CSS px, as a PNG at `scale` pixels a px; the view grows taller
    /// first when it reaches below.
    private func shot(_ selector: String?, scale: Double, region: CGRect?) async throws -> Data {
        guard var rect = await box(selector) else { throw Trouble("页面上没有 \(selector ?? ".iso-plate")") }
        if rect.maxY + 8 > view.bounds.height, rect.maxY < 8000 {
            await resize(CGSize(width: view.bounds.width, height: ceil(rect.maxY + 8)))
            rect = await box(selector) ?? rect
        }
        if let region {
            rect = CGRect(x: rect.minX + region.minX, y: rect.minY + region.minY, width: region.width, height: region.height)
        } else {
            rect = rect.insetBy(dx: -4, dy: -4)
        }
        return try await snapshot(rect, scale: scale)
    }

    /// What is drawn in `rect` (view points, which are CSS px), `scale` pixels a point.
    private func snapshot(_ rect: CGRect, scale: Double) async throws -> Data {
        let clip = rect.intersection(view.bounds)
        guard !clip.isNull, clip.width >= 1, clip.height >= 1 else { throw Trouble("那一块不在页面上") }
        let pixels = min(clip.width * max(scale, 0.1), 4096)
        let config = WKSnapshotConfiguration()
        config.rect = clip
        // WebKit gives the window's backing scale's worth of pixels a point.
        config.snapshotWidth = NSNumber(value: Double(pixels / max(window.backingScaleFactor, 1)))
        config.afterScreenUpdates = false
        let image: NSImage = try await withCheckedThrowingContinuation { done in
            view.takeSnapshot(with: config) { image, error in
                if let image { done.resume(returning: image) } else { done.resume(throwing: Trouble(error?.localizedDescription ?? "没有图")) }
            }
        }
        guard let drawn = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: drawn).representation(using: .png, properties: [:]) else {
            throw Trouble("没有位图")
        }
        return png
    }

    /// A function body run in the page: its value (what JSON can carry), or what went wrong — given up
    /// on after `timeout` seconds (a page that never answers does not hold the check).
    private func js(_ body: String, _ arguments: [String: Any] = [:], timeout: Double = 15) async -> (Any?, String?) {
        await withCheckedContinuation { (done: CheckedContinuation<(Any?, String?), Never>) in
            var answered = false
            view.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                guard !answered else { return }
                answered = true
                switch result {
                case .success(let value): done.resume(returning: (value is NSNull ? nil : value, nil))
                case .failure(let error): done.resume(returning: (nil, Self.said(error)))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !answered else { return }
                answered = true
                done.resume(returning: (nil, "页面 \(Int(timeout)) 秒没答"))
            }
        }
    }

    private static func said(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        return (info["WKJavaScriptExceptionMessage"] as? String) ?? error.localizedDescription
    }

    static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    private static func quoted(_ text: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [text])).flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "''"
    }

    /// One floating end, as drive.mjs prints it.
    private static func describe(_ problem: [String: Any]) -> String {
        let at = (problem["at"] as? [Any])?.compactMap { number($0) }.map { String(format: "%g", $0) }.joined(separator: ",") ?? ""
        let gap = number(problem["gap"]).map { String(format: "%.2f px from anything", $0) } ?? "nothing nearby"
        let opacity = number(problem["opacity"]).flatMap { $0 < 1 ? String(format: "   opacity %g", $0) : nil } ?? ""
        return "\(problem["what"] as? String ?? "?")  \(problem["end"] as? String ?? "")\(problem["mark"] as? Bool == true ? " (a mark: neither end rooted)" : "")"
            + "  \(gap)   at card \(at)   length \(number(problem["length"]).map { String(format: "%g", $0) } ?? "?")   d \(problem["d"] as? String ?? "")…\(opacity)"
    }

    /// Frames side by side, numbered, as drive.mjs's sheet.
    private static func tile(_ frames: [CGImage], columns: Int) -> Data? {
        guard let first = frames.first else { return nil }
        let w = first.width, h = first.height
        let cols = max(1, min(columns, frames.count)), rows = (frames.count + cols - 1) / cols
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w * cols, height: h * rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w * cols, height: h * rows))
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                                                    .foregroundColor: NSColor(red: 1, green: 0, blue: 0.67, alpha: 1)]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, frame) in frames.enumerated() {
            let x = (index % cols) * w, y = (rows - 1 - index / cols) * h
            context.draw(frame, in: CGRect(x: x, y: y, width: w, height: h))
            NSAttributedString(string: "\(index)", attributes: label).draw(at: CGPoint(x: x + 6, y: y + h - 18))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    struct Trouble: LocalizedError {
        let text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    // MARK: - The page's side

    /// Before the page's own scripts: its errors told, drive.mjs's slow motion, and the pointer the steps
    /// move (`__drive`), with pointer capture kept here for it — a synthetic pointer is not one WebKit
    /// knows, and setPointerCapture would throw and stop the page's handler.
    static let driveScript = #"""
        (() => {
          const post = (m) => { try { window.webkit.messageHandlers.machine.postMessage(m); } catch (e) {} };
          // WebKit's stack has the frames only, not what went wrong: the message first, then where.
          const stack = (x) => x && x.stack ? '\n' + String(x.stack).replace(/file:\/\/[^\s)]*\//g, '').split('\n').slice(0, 6).join('\n') : '';
          const text = (a) => a.map((x) => { if (typeof x === 'string') return x; if (x instanceof Error) return String(x) + stack(x); try { return JSON.stringify(x); } catch (e) { return String(x); } }).join(' ');
          addEventListener('error', (e) => post({ type: 'error', message: 'exception: ' + (e.message || String(e.error || 'error')) + (e.filename ? ' (' + String(e.filename).split('/').pop().split('?')[0] + ':' + e.lineno + ':' + e.colno + ')' : '') + stack(e.error) }));
          addEventListener('unhandledrejection', (e) => post({ type: 'error', message: 'exception (promise): ' + String(e.reason) + stack(e.reason) }));
          for (const [kind, name] of [['error', 'console.error'], ['warn', 'console.warning']]) {
            const original = console[kind].bind(console);
            console[kind] = (...a) => { post({ type: 'error', message: (name + ': ' + text(a)).slice(0, 600) }); original(...a); };
          }
          const raf = window.requestAnimationFrame.bind(window); let real = null, virtual = 0; window.__driveSpeed = 1;
          window.requestAnimationFrame = (callback) => raf((now) => { if (real === null) { real = now; virtual = now; } virtual += (now - real) * window.__driveSpeed; real = now; callback(virtual); });
          const clock = performance.now.bind(performance); let base = null, shown = 0;
          performance.now = () => { const now = clock(); if (base === null) { base = now; shown = now; } shown += (now - base) * window.__driveSpeed; base = now; return shown; };
          let last = null, captured = null, buttons = 0;
          const chain = (el) => { const out = []; for (let n = el; n; n = n.parentElement) out.push(n); return out; };
          const fire = (el, type, x, y, extra) => {
            const pointer = type.startsWith('pointer') || type.endsWith('pointercapture');
            const init = Object.assign({ bubbles: true, cancelable: true, composed: true, view: window, clientX: x, clientY: y, screenX: x, screenY: y, button: 0, buttons }, extra || {});
            if (pointer) Object.assign(init, { pointerId: 1, pointerType: 'mouse', isPrimary: true, width: 1, height: 1, pressure: buttons ? 0.5 : 0 });
            return el.dispatchEvent(pointer ? new PointerEvent(type, init) : new MouseEvent(type, init));
          };
          const over = (x, y) => {
            const el = captured || document.elementFromPoint(x, y) || document.documentElement;
            if (el !== last) {
              const was = last ? chain(last) : [], now = chain(el), still = { bubbles: false, cancelable: false };
              if (last) { fire(last, 'pointerout', x, y); fire(last, 'mouseout', x, y); }
              for (const n of was) if (!now.includes(n)) { fire(n, 'pointerleave', x, y, still); fire(n, 'mouseleave', x, y, still); }
              fire(el, 'pointerover', x, y); fire(el, 'mouseover', x, y);
              for (const n of now.slice().reverse()) if (!was.includes(n)) { fire(n, 'pointerenter', x, y, still); fire(n, 'mouseenter', x, y, still); }
              last = el;
            }
            return el;
          };
          const set = Element.prototype.setPointerCapture, release = Element.prototype.releasePointerCapture, has = Element.prototype.hasPointerCapture;
          Element.prototype.setPointerCapture = function (id) { try { set.call(this, id); } catch (e) {} captured = this; };
          Element.prototype.releasePointerCapture = function (id) { try { release.call(this, id); } catch (e) {} if (captured === this) captured = null; };
          Element.prototype.hasPointerCapture = function (id) { if (captured === this) return true; try { return has.call(this, id); } catch (e) { return false; } };
          window.__drive = {
            move(x, y) { const el = over(x, y); fire(el, 'pointermove', x, y, { button: -1 }); fire(el, 'mousemove', x, y, { button: -1 }); },
            down(x, y) {
              const el = over(x, y); buttons = 1;
              if (fire(el, 'pointerdown', x, y)) {
                fire(el, 'mousedown', x, y);
                const focus = el.closest && el.closest('a[href], button, input, select, textarea, [tabindex]');
                if (focus && focus.focus) focus.focus();
              }
            },
            up(x, y) {
              const el = captured || over(x, y); buttons = 0;
              fire(el, 'pointerup', x, y); fire(el, 'mouseup', x, y);
              const hit = document.elementFromPoint(x, y); if (hit) fire(hit, 'click', x, y, { detail: 1 });
              if (captured) { const was = captured; captured = null; fire(was, 'lostpointercapture', x, y); }
            },
            key(key, code) {
              const el = document.activeElement || document.body, init = { key, code, bubbles: true, cancelable: true, composed: true };
              if (el.dispatchEvent(new KeyboardEvent('keydown', init)) && key.length === 1) el.dispatchEvent(new KeyboardEvent('keypress', init));
              el.dispatchEvent(new KeyboardEvent('keyup', init));
            },
          };
        })();
        """#

    static let noWebGLScript = """
        (() => { const get = HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext = function (kind, ...rest) { if (/webgl/.test(String(kind))) return null; return get.call(this, kind, ...rest); }; })();
        """

    static let reducedScript = """
        (() => { const media = window.matchMedia.bind(window); window.matchMedia = (q) => /prefers-reduced-motion:\\s*reduce/.test(q) ? media('(min-width: 0px)') : /prefers-reduced-motion:\\s*no-preference/.test(q) ? media('(max-width: 0px)') : media(q); })();
        """
}

/// The page's messages and loads, without WebKit holding the check strongly.
private final class MachineRelay: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var owner: MachineCheck?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak owner] in owner?.receive(body) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak owner] in owner?.loaded(navigation, trouble: nil) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak owner] in owner?.loaded(navigation, trouble: error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak owner] in owner?.loaded(navigation, trouble: error.localizedDescription) }
    }
}

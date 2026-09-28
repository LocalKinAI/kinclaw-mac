import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// A page drawn where nobody sees it: HTML in, a picture of exactly the size
/// asked out — the Easel tab's cards, and the pages its agent reads.
///
/// Easel draws its cards with Playwright and Chromium on the box; here it is a
/// WKWebView that never goes into a window, with a data store of its own that
/// holds no cookies, so a page read this way is read signed in to nothing.
/// Off-screen, WebKit sends no animation frames and no screen updates: the
/// picture is taken without waiting for one (`afterScreenUpdates = false`),
/// after the fonts and the pictures have loaded, and a page that draws only
/// in `requestAnimationFrame` shows what it had drawn before.
@MainActor
final class OffscreenPage {
    let web: WKWebView
    let size: CGSize
    private let waiter = PageLoadWaiter()

    init(size: CGSize) {
        self.size = size
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.navigationDelegate = waiter
    }

    enum Trouble: LocalizedError {
        case load(String), timeout, snapshot(String)
        var errorDescription: String? {
            switch self {
            case .load(let why): return "页面打不开：\(why)"
            case .timeout: return "页面 30 秒没加载完"
            case .snapshot(let why): return "截不了图：\(why)"
            }
        }
    }

    /// A file of this Mac's, able to read what is under `access` (the
    /// pictures a card puts in it).
    func load(file: URL, access: URL) async throws {
        try await loading { $0.loadFileURL(file, allowingReadAccessTo: access) }
    }

    func load(url: URL) async throws {
        try await loading { $0.load(URLRequest(url: url, timeoutInterval: 25)) }
    }

    private func loading(_ start: (WKWebView) -> Void) async throws {
        let waiter = self.waiter
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            var answered = false
            waiter.onDone = { error in
                guard !answered else { return }
                answered = true
                waiter.onDone = nil
                if let error { done.resume(throwing: Trouble.load(error.localizedDescription)) } else { done.resume() }
            }
            start(web)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard !answered else { return }
                answered = true
                waiter.onDone = nil
                done.resume(throwing: Trouble.timeout)
            }
        }
    }

    /// Until the fonts and the pictures — CSS backgrounds too — have come, or
    /// `most` seconds, and a moment for the layout after them.
    func settle(most: Double = 10, extra: Double = 0.15) async {
        _ = try? await js("""
            const until = (p, ms) => Promise.race([p, new Promise(r => setTimeout(r, ms))]);
            const wanted = new Set();
            for (const el of document.querySelectorAll('*')) {
              const bg = getComputedStyle(el).backgroundImage || '';
              for (const m of bg.matchAll(/url\\(["']?([^"')]+)["']?\\)/g)) wanted.add(m[1]);
            }
            const pictures = Array.from(document.images).filter(i => !i.complete)
              .map(i => new Promise(r => { i.addEventListener('load', r); i.addEventListener('error', r); }));
            for (const src of wanted) {
              pictures.push(new Promise(r => { const i = new Image(); i.onload = r; i.onerror = r; i.src = src; }));
            }
            await until(Promise.all([document.fonts ? document.fonts.ready : null, ...pictures]), most * 1000);
            await new Promise(r => setTimeout(r, extra * 1000));
            return 'ok';
            """, ["most": most, "extra": extra])
    }

    /// A function body run in the page; what it returns, as text.
    @discardableResult
    func js(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String {
        let value = try await web.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
        if let text = value as? String { return text }
        return value.map { "\($0)" } ?? ""
    }

    /// The page as it is drawn, `size` points from its top left, as a
    /// picture of exactly that many pixels.
    func snapshot() async throws -> CGImage {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.afterScreenUpdates = false
        config.snapshotWidth = NSNumber(value: Double(size.width))
        let image: NSImage = try await withCheckedThrowingContinuation { done in
            web.takeSnapshot(with: config) { image, error in
                if let image { done.resume(returning: image) } else {
                    done.resume(throwing: Trouble.snapshot(error?.localizedDescription ?? "没有图"))
                }
            }
        }
        guard let drawn = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Trouble.snapshot("没有位图") }
        let w = Int(size.width), h = Int(size.height)
        if drawn.width == w && drawn.height == h { return drawn }
        // A Retina backing gives twice the pixels: drawn again at the size asked.
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Trouble.snapshot("画布") }
        context.interpolationQuality = .high
        context.draw(drawn, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = context.makeImage() else { throw Trouble.snapshot("缩放") }
        return scaled
    }

    static func savePNG(_ image: CGImage, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let out = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Trouble.snapshot("写不了 \(file.path)")
        }
        CGImageDestinationAddImage(out, image, nil)
        guard CGImageDestinationFinalize(out) else { throw Trouble.snapshot("写不了 \(file.path)") }
    }
}

/// `navigationDelegate` is weak, and its calls come on the main thread.
private final class PageLoadWaiter: NSObject, WKNavigationDelegate {
    var onDone: ((Error?) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onDone?(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onDone?(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onDone?(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onDone?(NSError(domain: "WebKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "网页进程退出了"]))
    }
}

/// One social-media card: the agent's HTML drawn at its size, saved as a PNG
/// beside the HTML it came from, and checked the two ways Easel checks one —
/// in the page (text too small, text spilling out of its box or off the
/// card, pictures that did not load, nothing on it) and in the picture
/// (`card_audit.py`'s rule: content from top to bottom, no dead band over
/// 15% of the height, the bottom not left empty).
@MainActor
enum SocialCard {
    struct Result {
        let file: URL
        let source: URL
        let size: CGSize
        /// Problems to fix before it goes in a draft.
        let problems: [String]
        /// Worth a look, not wrong in themselves: small type that a corner
        /// label may have and body text may not.
        let warnings: [String]
        /// The measurements, for the answer.
        let layout: String
        var passed: Bool { problems.isEmpty }
    }

    /// Draw `html` (a whole page, or only the card's markup) at `size` into
    /// `file` (a .png; its .html is kept beside it). `access` is what the page
    /// may read of this Mac: the art folder, for pictures made here. Text
    /// under `smallest` px (at 1080 wide) is pointed out; under 20 it is a
    /// problem — Easel's floor for a label, a source line, a watermark.
    static func render(html: String, css: String?, size: CGSize, to file: URL, access: URL,
                       smallest: Double = 24) async throws -> Result {
        let source = file.deletingPathExtension().appendingPathExtension("html")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document(html: html, css: css, size: size).write(to: source, atomically: true, encoding: .utf8)
        let page = OffscreenPage(size: size)
        try await page.load(file: source, access: access)
        await page.settle()
        let scale = Double(size.width) / 1080
        let found = (try? await page.js(auditScript, ["smallest": max(smallest, 20) * scale, "floor": 20 * scale])) ?? "{}"
        let picture = try await page.snapshot()
        try OffscreenPage.savePNG(picture, to: file)
        let (problems, warnings) = pageProblems(found, smallest: Int(max(smallest, 20).rounded()))
        let measured = density(picture)
        // Easel's fill rule is for tall cards, a 小红书 3:4 read on a phone. A
        // wide one — an X 16:9, a 公众号 cover at 2.35:1 — may rightly leave a
        // band empty, so there it is only pointed out.
        let wide = size.width > size.height * 1.2
        let result = Result(file: file, source: source, size: size, problems: problems + (wide ? [] : measured.problems),
                            warnings: warnings + (wide ? measured.problems.map { "（横图，只作参考）" + $0 } : []),
                            layout: measured.summary)
        // Kept beside the picture, so that a draft it goes into knows.
        let audit: [String: Any] = ["passed": result.passed, "problems": result.problems, "warnings": result.warnings, "layout": result.layout]
        if let data = try? JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? data.write(to: file.deletingPathExtension().appendingPathExtension("audit.json"))
        }
        return result
    }

    /// The card as a page of exactly its size: the page's own margins and
    /// scroll taken away first, so that what the agent writes decides the rest.
    static func document(html: String, css: String?, size: CGSize) -> String {
        let w = Int(size.width), h = Int(size.height)
        let base = "<style id=\"kin-card-base\">html,body{margin:0;padding:0;width:\(w)px;height:\(h)px;overflow:hidden;}</style>"
        let extra = (css?.isEmpty == false) ? "<style id=\"kin-card-css\">\(css!)</style>" : ""
        func tag(_ name: String) -> Range<String.Index>? {
            html.range(of: "<\(name)(\\s[^>]*)?>", options: [.regularExpression, .caseInsensitive])
        }
        if tag("html") != nil || tag("body") != nil || html.range(of: "<!doctype", options: .caseInsensitive) != nil {
            // Whole: ours first in <head> — the charset within its first bytes,
            // or a file read from disk may be taken for Latin-1 — so that the
            // page's own rules come after and win.
            var page = html
            if let head = tag("head") {
                page.insert(contentsOf: "<meta charset=\"utf-8\">" + base + extra, at: head.upperBound)
            } else if let open = tag("html") {
                page.insert(contentsOf: "<head><meta charset=\"utf-8\">" + base + extra + "</head>", at: open.upperBound)
            } else {
                page = "<meta charset=\"utf-8\">" + base + extra + html
            }
            return page
        }
        return """
            <!DOCTYPE html>
            <html lang="zh-CN"><head><meta charset="utf-8">\(base)\(extra)</head>
            <body>\(html)</body></html>
            """
    }

    // MARK: In the page

    /// Text nodes, their sizes and boxes; returns JSON.
    private static let auditScript = """
        const W = window.innerWidth, H = window.innerHeight;
        const out = { tiny: [], small: [], overflow: [], outside: [], clipped: [], broken: [], chars: 0, media: 0 };
        const snip = t => t.replace(/\\s+/g, ' ').trim().slice(0, 24);
        const seen = new Set();
        const note = (list, key, item) => { if (!seen.has(list + key) && out[list].length < 8) { seen.add(list + key); out[list].push(item); } };
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node, count = 0;
        while ((node = walker.nextNode()) && count < 4000) {
          const text = node.textContent.replace(/\\s+/g, ' ').trim();
          if (!text) continue;
          const el = node.parentElement;
          if (!el) continue;
          const cs = getComputedStyle(el);
          if (cs.visibility === 'hidden' || cs.display === 'none' || parseFloat(cs.opacity) === 0) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          const rects = Array.from(range.getClientRects()).filter(r => r.width > 0.5 && r.height > 0.5);
          if (!rects.length) continue;
          count++;
          out.chars += text.length;
          const px = parseFloat(cs.fontSize);
          if (px < floor - 0.01) note('tiny', snip(text) + px, { text: snip(text), px: Math.round(px * 10) / 10 });
          else if (px < smallest - 0.01) note('small', snip(text) + px, { text: snip(text), px: Math.round(px * 10) / 10 });
          if (rects.some(r => r.right > W + 1 || r.bottom > H + 1 || r.left < -1 || r.top < -1)) { note('outside', snip(text), { text: snip(text) }); continue; }
          // Cut off by a box of its own (the card's edge is said above).
          for (let a = el; a && a !== document.body && a !== document.documentElement; a = a.parentElement) {
            const s = getComputedStyle(a);
            if (s.overflowX === 'visible' && s.overflowY === 'visible') continue;
            const box = a.getBoundingClientRect();
            if (rects.some(r => r.right > box.right + 1 || r.bottom > box.bottom + 1 || r.left < box.left - 1 || r.top < box.top - 1)) {
              note('clipped', snip(text), { text: snip(text) });
              break;
            }
          }
        }
        for (const el of document.body.querySelectorAll('*')) {
          if (!Array.from(el.childNodes).some(c => c.nodeType === 3 && c.textContent.trim())) continue;
          const cs = getComputedStyle(el);
          if (cs.display === 'inline' || cs.display === 'contents' || cs.display === 'none') continue;
          // A box that hides what spills is a cut-off, said above; this is text over its edge.
          if (cs.overflowX !== 'visible' || cs.overflowY !== 'visible') continue;
          if (el.scrollHeight > el.clientHeight + 2 || el.scrollWidth > el.clientWidth + 2) {
            note('overflow', snip(el.innerText || ''), { text: snip(el.innerText || ''), box: [el.clientWidth, el.clientHeight], content: [el.scrollWidth, el.scrollHeight] });
          }
        }
        out.media = Array.from(document.querySelectorAll('img,svg,canvas,video')).filter(e => {
          const r = e.getBoundingClientRect(); return r.width > 4 && r.height > 4; }).length;
        out.broken = Array.from(document.images).filter(i => i.complete && i.naturalWidth === 0)
          .map(i => (i.getAttribute('src') || '').slice(0, 120)).slice(0, 5);
        return JSON.stringify(out);
        """

    private static func pageProblems(_ json: String, smallest: Int) -> (problems: [String], warnings: [String]) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return (["页面里的检查没跑成（脚本出错），只看了图"], [])
        }
        func texts(_ key: String) -> [[String: Any]] { object[key] as? [[String: Any]] ?? [] }
        func sized(_ list: [[String: Any]]) -> String {
            list.map { "「\($0["text"] as? String ?? "")」\(($0["px"] as? Double).map { String(format: "%g", $0) } ?? "?")px" }.joined(separator: "、")
        }
        var problems: [String] = [], warnings: [String] = []
        let chars = object["chars"] as? Int ?? 0, media = object["media"] as? Int ?? 0
        if chars == 0 && media == 0 { problems.append("空卡：上面没有字，也没有图") }
        let tiny = texts("tiny")
        if !tiny.isEmpty { problems.append("字太小（小于 20px，手机上看不清；放不下就删字，别缩字号）：" + sized(tiny)) }
        let small = texts("small")
        if !small.isEmpty {
            warnings.append("小于 \(smallest)px 的字：" + sized(small) + "——角标、出处、水印可以这么小（≥20px），正文不行（≥28px）")
        }
        let spill = texts("overflow")
        if !spill.isEmpty {
            problems.append("文字溢出了自己的盒子：" + spill.map { item -> String in
                let box = item["box"] as? [Int] ?? [], content = item["content"] as? [Int] ?? []
                let size = box.count == 2 && content.count == 2 ? "（盒子 \(box[0])×\(box[1])，内容 \(content[0])×\(content[1])）" : ""
                return "「\(item["text"] as? String ?? "")」" + size
            }.joined(separator: "、"))
        }
        let outside = texts("outside")
        if !outside.isEmpty { problems.append("文字跑出了卡片：" + outside.map { "「\($0["text"] as? String ?? "")」" }.joined(separator: "、")) }
        let clipped = texts("clipped")
        if !clipped.isEmpty { problems.append("文字被裁掉了一部分（外面的盒子 overflow 不是 visible）：" + clipped.map { "「\($0["text"] as? String ?? "")」" }.joined(separator: "、")) }
        let broken = object["broken"] as? [String] ?? []
        if !broken.isEmpty { problems.append("图片没加载出来：" + broken.joined(separator: "、") + "（本机图片要放在素材文件夹下，写 file:// 全路径）") }
        return (problems, warnings)
    }

    // MARK: In the picture

    /// `card_audit.py`, row by row: a row holds something when more than
    /// 0.6% of its neighbouring pixels differ by more than 12 grey levels
    /// (text, a drawing, an outline — a flat colour or a smooth gradient does
    /// not). From that: how much of the height the content spans, the empty
    /// band at the bottom, the biggest empty band between, four bands' density.
    struct Density {
        let span: Double, bottomDead: Double, maxGap: Double, fill: Double
        let bands: [Double]
        let problems: [String]

        var summary: String {
            "纵向跨度 \(pct(span)) · 底部空白 \(pct(bottomDead)) · 中间最大空白带 \(pct(maxGap)) · 四段密度 "
                + bands.map { String(format: "%.2f", $0) }.joined(separator: " / ")
        }
        private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    }

    static func density(_ image: CGImage) -> Density {
        let w = image.width, h = image.height
        guard w > 1, h > 0,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return Density(span: 0, bottomDead: 0, maxGap: 0, fill: 0, bands: [0, 0, 0, 0], problems: ["读不了图的像素"])
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = context.data else {
            return Density(span: 0, bottomDead: 0, maxGap: 0, fill: 0, bands: [0, 0, 0, 0], problems: ["读不了图的像素"])
        }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Row 0 of the bitmap is the top of the picture.
        var has = [Bool](repeating: false, count: h)
        for y in 0..<h {
            let row = y * w * 4
            var previous = Int(pixels[row]) + Int(pixels[row + 1]) + Int(pixels[row + 2])
            var edges = 0
            for x in 1..<w {
                let i = row + x * 4
                let grey = Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
                if abs(grey - previous) > 36 { edges += 1 }       // 12 levels of the mean of three
                previous = grey
            }
            has[y] = Double(edges) / Double(w - 1) > 0.006
        }
        let rows = has.filter { $0 }.count
        let fill = Double(rows) / Double(h)
        let first = has.firstIndex(of: true) ?? 0
        let last = has.lastIndex(of: true) ?? 0
        let span = rows > 0 ? Double(last - first + 1) / Double(h) : 0
        let bottomDead = Double(rows > 0 ? h - 1 - last : h) / Double(h)
        var gap = 0, longest = 0
        if rows > 0 {
            for y in first...last {
                if has[y] { gap = 0 } else { gap += 1; longest = max(longest, gap) }
            }
        }
        let maxGap = Double(longest) / Double(h)
        let bands = (0..<4).map { b -> Double in
            let from = b * h / 4, to = (b + 1) * h / 4
            let n = has[from..<to].filter { $0 }.count
            return (Double(n) / Double(max(1, to - from)) * 100).rounded() / 100
        }
        var problems: [String] = []
        if bottomDead > 0.15 { problems.append("底部空白 \(Int((bottomDead * 100).rounded()))%，超过 15%：画幅没填满（最刺眼的廉价感）——补内容、换更省高度的骨架，或者改 1:1") }
        if maxGap > 0.15 { problems.append("中间有一段 \(Int((maxGap * 100).rounded()))% 高的空白：补内容或换骨架") }
        if span < 0.8 { problems.append("内容只铺了画高的 \(Int((span * 100).rounded()))%（要 ≥80%）：内容没顶到上下边距") }
        if bands[3] < 0.10 && bands[0] > 0.3 { problems.append("头重脚轻：内容堆在上面，底下几乎空着") }
        return Density(span: span, bottomDead: bottomDead, maxGap: maxGap, fill: fill, bands: bands, problems: problems)
    }
}

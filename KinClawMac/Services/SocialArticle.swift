import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A 公众号 article as WeChat's editor will take it: batch two of Jacky's
/// 「开干吧」 (2026-09-30), after Easel's gzh-design.
///
/// gzh-design itself is AGPL-3.0 (甲木 × 摸鱼小李, imported into Easel), so
/// none of its themes or scripts are in this app: the agent reads its guide
/// in guides/easel/skills/openclaw/gzh-design — the themes, the components —
/// and writes the article's HTML, as gzh-design has the model do. What is here
/// is ours: the editor's rules, which are facts about the editor. On paste it
/// keeps only inline styles — no <style>, no class — takes <section> and not
/// <div>, loses a text's styling unless the text sits in a <span leaf="">,
/// drops an empty element, and has no position, float, grid or CSS variables.
/// What can be put right mechanically is; what cannot is said, for the agent
/// to change. The article is kept as article.html in its draft, with pictures
/// of it a phone screen at a time; the tab copies it as rich text, local
/// pictures inlined, for the person to paste into the editor themselves.
enum SocialArticle {
    struct Result {
        let file: URL
        /// Phone-screen slices of the article, top to bottom.
        let screens: [URL]
        let fixed: [String]
        let problems: [String]
        let warnings: [String]
        let characters: Int
        let pictures: Int
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    /// How wide a phone shows an article, in points.
    static let phone = CGSize(width: 414, height: 896)

    static func file(in draft: URL) -> URL { draft.appendingPathComponent("article.html") }
    static func screensFolder(in draft: URL) -> URL { draft.appendingPathComponent("article-screens") }

    /// Tidy, check and keep `html` (the article: a <section>, or any fragment)
    /// in `draft`, and draw it at phone width.
    @MainActor
    static func save(html: String, in draft: URL, access: URL) async throws -> Result {
        let files = FileManager.default
        let scratch = draft.appendingPathComponent(".article-raw.html")
        try page(html).write(to: scratch, atomically: true, encoding: .utf8)
        defer { try? files.removeItem(at: scratch) }
        let checker = OffscreenPage(size: phone)
        try await checker.load(file: scratch, access: access)
        await checker.settle(most: 8, extra: 0.3)
        let answer = try await checker.js(tidyScript)
        guard let json = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any],
              let tidied = json["html"] as? String else { throw Failure.message("排版检查没有结果") }
        let file = file(in: draft)
        try tidied.write(to: file, atomically: true, encoding: .utf8)
        // A page around it, to open in a browser and look at, or copy from.
        try page(tidied).write(to: draft.appendingPathComponent("article-preview.html"), atomically: true, encoding: .utf8)
        let screens = try await draw(tidied, into: screensFolder(in: draft), access: access, scratch: scratch)
        return Result(file: file, screens: screens, fixed: json["fixed"] as? [String] ?? [], problems: json["problems"] as? [String] ?? [],
                      warnings: json["warnings"] as? [String] ?? [], characters: json["chars"] as? Int ?? 0,
                      pictures: json["pictures"] as? Int ?? 0)
    }

    /// The fragment on a white page as wide as a phone.
    static func page(_ fragment: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:#fff;}#kin-article{padding:16px 16px 40px;}</style></head>
        <body><div id="kin-article">\(fragment)</div></body></html>
        """
    }

    /// The tidied article, a phone screen at a time (at most twelve).
    @MainActor
    private static func draw(_ fragment: String, into folder: URL, access: URL, scratch: URL) async throws -> [URL] {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try page(fragment).write(to: scratch, atomically: true, encoding: .utf8)
        let screen = OffscreenPage(size: phone)
        try await screen.load(file: scratch, access: access)
        await screen.settle(most: 8, extra: 0.3)
        let height = Double((try? await screen.js("return String(document.documentElement.scrollHeight)")) ?? "") ?? phone.height
        var shots: [URL] = []
        var top = 0.0
        while top < height, shots.count < 12 {
            _ = try? await screen.js("window.scrollTo(0, y); return 'ok'", ["y": top])
            try? await Task.sleep(nanoseconds: 120_000_000)
            let picture = try await screen.snapshot()
            let file = folder.appendingPathComponent(String(format: "%02d.png", shots.count + 1))
            try OffscreenPage.savePNG(picture, to: file)
            shots.append(file)
            top += phone.height
        }
        // A shorter article than last time: the screens past its end are ours and stale.
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".png") {
            if !shots.contains(where: { $0.lastPathComponent == name }) { try? files.removeItem(at: folder.appendingPathComponent(name)) }
        }
        return shots
    }

    /// The article as the pasteboard carries it: pictures on this Mac inlined
    /// as JPEG data, which the editor uploads as it pastes.
    static func forPasting(_ file: URL) -> String? {
        guard var html = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let folder = file.deletingLastPathComponent()
        let sources = html.matches(of: #/<img[^>]*?\ssrc="([^"]+)"/#).map { String($0.1) }
        for source in Set(sources) where !source.hasPrefix("data:") && !source.hasPrefix("http") {
            let path = source.hasPrefix("file://") ? (URL(string: source)?.path ?? "") : source.hasPrefix("/") ? source
                : folder.appendingPathComponent(source).path
            guard let data = jpeg(URL(fileURLWithPath: path.removingPercentEncoding ?? path)) else { continue }
            html = html.replacingOccurrences(of: "src=\"\(source)\"", with: "src=\"data:image/jpeg;base64,\(data.base64EncodedString())\"")
        }
        return html
    }

    /// A picture at most 1080 wide, as a JPEG: a 1080×1440 card is ~300 KB so, 3 MB as a PNG.
    private static func jpeg(_ file: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1440,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(out) ? data as Data : nil
    }

    /// Put the article on the pasteboard as rich text, with its words as plain
    /// text for anything that takes only that.
    @MainActor
    static func copy(_ file: URL) -> Bool {
        guard let html = forPasting(file) else { return false }
        let words = (try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html,
                                                                               .characterEncoding: String.Encoding.utf8.rawValue],
                                             documentAttributes: nil))?.string ?? ""
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(html, forType: .html)
        board.setString(words, forType: .string)
        return true
    }

    // MARK: In the page

    /// Tidy the article in #kin-article for the editor; returns JSON: html, fixed, problems, warnings, chars, pictures.
    private static let tidyScript = """
        const root = document.getElementById('kin-article');
        const fixed = [], problems = [], warnings = [];
        const note = (list, text) => { if (!list.includes(text) && list.length < 20) list.push(text); };
        const snip = el => (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 14);
        const rename = (el, tag) => {
          const n = document.createElement(tag);
          for (const a of Array.from(el.attributes)) n.setAttribute(a.name, a.value);
          while (el.firstChild) n.appendChild(el.firstChild);
          el.replaceWith(n);
          return n;
        };
        for (const el of Array.from(root.querySelectorAll('script,style,link,meta,iframe,form,input,button,textarea,select,object,embed'))) {
          const tag = el.tagName.toLowerCase();
          if (tag === 'style') note(problems, '用了 <style>：编辑器会整个丢掉，样式要写进每个元素自己的 style 属性（照 gzh-design 的组件）');
          else note(fixed, '去掉了 <' + tag + '>（编辑器不收）');
          el.remove();
        }
        for (const el of Array.from(root.querySelectorAll('video,audio'))) {
          note(problems, '<' + el.tagName.toLowerCase() + '> 贴不进去：视频、音频在公众号编辑器里自己插');
          el.remove();
        }
        let divs = 0;
        for (const el of Array.from(root.querySelectorAll('div'))) { rename(el, 'section'); divs++; }
        if (divs) note(fixed, divs + ' 个 <div> 换成了 <section>');
        const links = [];
        for (const el of Array.from(root.querySelectorAll('a'))) {
          const href = el.getAttribute('href');
          if (href) links.push(href);
          rename(el, 'span');
        }
        if (links.length) note(warnings, '链接变成了普通文字（正文里只能链公众号自己的文章）：' + links.slice(0, 4).join('，') + ' —— 给读者的链接放「阅读原文」或写成文字');
        let stripped = 0;
        for (const el of Array.from(root.querySelectorAll('*'))) {
          if (el.closest('svg')) continue;
          for (const a of Array.from(el.attributes)) {
            const keep = a.name === 'style' || a.name === 'leaf' || (el.tagName === 'IMG' && (a.name === 'src' || a.name === 'alt'))
              || ((el.tagName === 'TD' || el.tagName === 'TH') && (a.name === 'colspan' || a.name === 'rowspan'));
            if (!keep) { el.removeAttribute(a.name); if (a.name === 'class' || a.name === 'id') stripped++; }
          }
        }
        if (stripped) note(fixed, '去掉了 ' + stripped + ' 个 class / id（编辑器会丢掉，样式只认 style 属性）');
        for (const el of Array.from(root.querySelectorAll('[style]'))) {
          const s = el.getAttribute('style');
          if (/position\\s*:\\s*(fixed|absolute|sticky)/i.test(s)) note(problems, 'position:fixed/absolute/sticky 贴进去就没了（「' + snip(el) + '」）');
          if (/(^|;)\\s*float\\s*:/i.test(s)) note(problems, 'float 贴进去就没了，用 display:flex（「' + snip(el) + '」）');
          if (/display\\s*:\\s*grid/i.test(s)) note(problems, 'display:grid 不支持，用 flex（「' + snip(el) + '」）');
          if (/var\\(--/i.test(s)) note(problems, 'CSS 变量 var(--…) 不支持，写实际的值（「' + snip(el) + '」）');
          if (/white-space\\s*:\\s*pre/i.test(s)) note(problems, 'white-space:pre 会被吃掉：代码每行一个 <p style="margin:0">，缩进用全角空格（「' + snip(el) + '」）');
          const size = s.match(/font-size\\s*:\\s*([\\d.]+)px/i);
          if (size && parseFloat(size[1]) > 24) note(warnings, '字号 ' + size[1] + 'px，超过 24px（「' + snip(el) + '」）');
        }
        for (const el of Array.from(root.querySelectorAll('strong,b'))) {
          if (/font-size|border-bottom/i.test(el.getAttribute('style') || '')) note(warnings, '<strong> 上的 font-size、border-bottom 贴进去会乱，放到外层 <span>（「' + snip(el) + '」）');
        }
        let pictures = 0;
        for (const img of Array.from(root.querySelectorAll('img'))) {
          let s = (img.getAttribute('style') || '').replace(/(^|;)\\s*width\\s*:\\s*100%\\s*;?/ig, '$1');
          for (const [k, v] of [['max-width', '100%'], ['height', 'auto'], ['display', 'block'], ['margin', '0 auto']]) {
            if (!new RegExp('(^|;)\\\\s*' + k + '\\\\s*:', 'i').test(s)) s += (s.trim() && !s.trim().endsWith(';') ? ';' : '') + k + ':' + v + ';';
          }
          img.setAttribute('style', s);
          const parent = img.parentElement;
          if (!(parent && parent.tagName === 'SPAN' && parent.hasAttribute('leaf'))) {
            const w = document.createElement('span'); w.setAttribute('leaf', ''); img.replaceWith(w); w.appendChild(img);
          }
          if (!img.complete || img.naturalWidth === 0) note(problems, '图片没打开：' + (img.getAttribute('src') || '').slice(-70));
          pictures++;
        }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        const texts = [];
        let t;
        while ((t = walker.nextNode())) texts.push(t);
        let wrapped = 0;
        for (const node of texts) {
          if (!node.textContent.trim() || !node.parentElement || node.parentElement.closest('svg')) continue;
          const p = node.parentElement;
          if (p.tagName === 'SPAN' && p.hasAttribute('leaf')) continue;
          const w = document.createElement('span'); w.setAttribute('leaf', ''); node.replaceWith(w); w.appendChild(node); wrapped++;
        }
        if (wrapped) note(fixed, wrapped + ' 段文字包进了 <span leaf="">（编辑器靠它留住文字的样式）');
        let kept = 0;
        for (const el of Array.from(root.querySelectorAll('section,p,span:not([leaf])'))) {
          if (el.closest('svg')) continue;
          if (!el.textContent.trim() && !el.querySelector('img,svg,br,hr,table')) {
            const w = document.createElement('span'); w.setAttribute('leaf', ''); w.appendChild(document.createElement('br')); el.appendChild(w); kept++;
          }
        }
        if (kept) note(fixed, kept + ' 个空的装饰块里放了 <span leaf=""><br></span>，不然编辑器会删掉它');
        const half = [];
        for (const node of texts) {
          const el = node.parentElement;
          if (!el || el.closest('code,pre,svg')) continue;
          if (/mono|menlo|courier|consolas/i.test(getComputedStyle(el).fontFamily)) continue;
          const found = node.textContent.match(/[\\u4e00-\\u9fff][,.;:?!()]|[,;:?!()][\\u4e00-\\u9fff]/g);
          if (found) half.push(...found.slice(0, 3));
        }
        if (half.length) note(warnings, '中文里有半角标点：' + half.slice(0, 6).join('  ') + ' —— 改成全角（，。；：？！（））');
        let top = root.children.length === 1 && root.firstElementChild.tagName === 'SECTION' ? root.firstElementChild : null;
        if (!top) {
          const w = document.createElement('section');
          while (root.firstChild) w.appendChild(root.firstChild);
          root.appendChild(w); top = w;
          note(fixed, '整篇包进了一个 <section>');
        }
        let style = top.getAttribute('style') || '';
        const add = rule => { style += (style.trim() && !style.trim().endsWith(';') ? ';' : '') + rule; };
        if (!/max-width/i.test(style)) add('max-width:677px;margin:0 auto;');
        if (!/font-family/i.test(style)) add("font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Hiragino Sans GB','Microsoft YaHei',sans-serif;");
        top.setAttribute('style', style);
        return JSON.stringify({ html: root.innerHTML, fixed, problems, warnings, pictures,
                                chars: (root.textContent || '').replace(/\\s/g, '').length });
        """
}

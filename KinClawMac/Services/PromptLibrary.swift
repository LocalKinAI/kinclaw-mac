import Foundation

/// Other people's best image prompts, to start from.
///
/// devanshug2307/Awesome-AI-Image-Prompts (MIT) collects a couple of hundred
/// prompts that are much better than what anybody writes on the spot: a role
/// ("a world-class unit still photographer for a high-budget film"), a named
/// look to aim at, the textures you could touch, the period stated as a rule
/// with what must not appear. The Comfy tab shows them, puts one into the
/// open workflow, or has the writer keep one's craft and change its subject.
///
/// Fetched from the repository and kept, not shipped: it is theirs and it
/// grows. The README is one long Markdown file — `## N. Category`,
/// `### N.M. Title`, the prompt in a code block, an example picture — and one
/// of its prompts is itself a guide full of code fences, so a numbered
/// heading always starts a new entry whatever the fences say.
@MainActor
final class PromptLibrary: ObservableObject {
    static let shared = PromptLibrary()

    struct Entry: Identifiable, Hashable {
        let id: String
        let title: String
        let category: String
        let prompt: String
        let image: URL?
        /// Written for an edit of the user's own photo.
        var needsPhoto: Bool {
            prompt.range(of: #"reference photo|uploaded|input image|this photo|reference image|the photo"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static let source = URL(string: "https://raw.githubusercontent.com/devanshug2307/Awesome-AI-Image-Prompts/main/README.md")!
    static let home = URL(string: "https://github.com/devanshug2307/Awesome-AI-Image-Prompts")!

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var loading = false
    @Published private(set) var trouble: String?

    private var cache: URL { ComfyStudio.root.appendingPathComponent("guides/awesome-ai-image-prompts.md") }

    func load(fresh: Bool = false) async {
        guard entries.isEmpty || fresh, !loading else { return }
        loading = true
        defer { loading = false }
        var text: String?
        if !fresh, let kept = try? String(contentsOf: cache, encoding: .utf8), !kept.isEmpty { text = kept }
        if text == nil, let (data, response) = try? await URLSession.shared.data(from: Self.source),
           (response as? HTTPURLResponse)?.statusCode == 200, let got = String(data: data, encoding: .utf8) {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cache)
            text = got
        }
        guard let text else { trouble = "拿不到提示词库（GitHub）"; return }
        entries = Self.parse(text)
        trouble = entries.isEmpty ? "提示词库的格式看不懂了" : nil
    }

    var categories: [String] {
        var seen: [String] = []
        for e in entries where !seen.contains(e.category) { seen.append(e.category) }
        return seen
    }

    nonisolated static func parse(_ text: String) -> [Entry] {
        let category = try! NSRegularExpression(pattern: #"^## (\d+)\. (.+)$"#)
        let heading = try! NSRegularExpression(pattern: #"^### (\d+\.\d+)\. (.+)$"#)
        let picture = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\((https?://[^)\s]+)\)|<img[^>]+src="([^"]+)""#)
        var out: [Entry] = []
        var current = "", id = "", title = "", blocks: [String] = [], code: [String]? = nil, image: URL?
        func finish() {
            if let code, !code.isEmpty { blocks.append(code.joined(separator: "\n")) }
            code = nil
            guard !id.isEmpty, let best = blocks.max(by: { $0.count < $1.count }), best.count > 40 else { return }
            out.append(Entry(id: id, title: title, category: current,
                             prompt: best.trimmingCharacters(in: .whitespacesAndNewlines), image: image))
        }
        func match(_ re: NSRegularExpression, _ line: String) -> [String]? {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, range: range) else { return nil }
            return (1..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
            }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if let c = match(category, line) {
                finish(); id = ""
                current = c[1].drop(while: { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let h = match(heading, line) {
                finish()
                id = h[0]; title = h[1].trimmingCharacters(in: .whitespaces); blocks = []; image = nil
                continue
            }
            guard !id.isEmpty else { continue }
            if line.hasPrefix("```") {
                if code == nil { code = [] } else {
                    if let done = code, !done.isEmpty { blocks.append(done.joined(separator: "\n")) }
                    code = nil
                }
                continue
            }
            if code != nil { code!.append(line); continue }
            if image == nil, let p = match(picture, line) {
                image = URL(string: p.first(where: { !$0.isEmpty }) ?? "")
            }
        }
        finish()
        return out
    }

    /// Keep the craft of a prompt — its structure, its camera and light, its
    /// textures, its look — and change what it is of.
    static func adapt(_ entry: Entry, to subject: String) async -> String? {
        guard let writer = await FilmStudio.writer(claude: true), let url = URL(string: writer.host + "/api/chat") else { return nil }
        let ask = """
            Here is an excellent image prompt, written by someone who knows their craft:
            <<<
            \(entry.prompt)
            >>>
            Rewrite it for a new subject: "\(subject)".
            Keep everything that makes it good — its structure (keep JSON as JSON with the same keys if it is JSON), \
            the role it gives the image model, the camera and lens, the light, the textures, the palette, the film look, \
            the negative list. Change only what the picture is of, and whatever of the setting, clothing and period the \
            new subject needs to be true (a subject from history gets that period's clothing, buildings and objects, \
            and the negative list names what must not appear from later times). Write it in English unless the \
            subject must be written in another language. Answer with the prompt only.
            """
        let body: [String: Any] = ["model": writer.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var said = (reply["message"] as? [String: Any])?["content"] as? String else { return nil }
        said = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if said.hasPrefix("```") {
            said = said.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let end = said.range(of: "```", options: .backwards) { said = String(said[..<end.lowerBound]) }
        }
        return said.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Other people's prompts for videos that Claude writes as code, to start from.
///
/// LeaddeOpenLab/awesome-opus-5-5-video-prompts collects what people posted
/// on X with their Opus 5.5 videos — hundreds, growing by the hour, but most
/// of them a line or two quoted out of a post. The ones whose whole prompt
/// was published (`prompt.status == "full_original"`, 26 on 2026-09-28) are
/// the ones worth starting from, and the only ones kept: the Montage tab shows
/// them, to read, change and hand to its agent. Five people posted the same
/// showreel prompt word for word; that is one entry with five credits.
///
/// Fetched and kept, not shipped, like PromptLibrary's: the repository has no
/// licence, and the prompts are their authors'. It is one JSON file a post
/// under data/library, and a post read once is not read again.
@MainActor
final class VideoPromptLibrary: ObservableObject {
    static let shared = VideoPromptLibrary()

    enum Kind: String, CaseIterable, Codable {
        case showreel = "动效展示", promo = "产品宣传", explainer = "讲解", animation = "动画短片", interactive = "互动网页"
    }

    struct Credit: Hashable, Codable {
        let name: String
        let post: URL
    }

    struct Entry: Identifiable, Hashable {
        let id: String
        let title: String
        let kind: Kind
        let prompt: String
        let credits: [Credit]
        let cover: URL?
        let tools: [String]
        /// What to know before using it: what it asks for, what to change.
        let note: String?
        /// A web page to play with, not a video: work for a Code session.
        var interactive: Bool { kind == .interactive }
    }

    /// One post, as kept.
    struct Post: Codable {
        let id: String
        let title: String
        let category: String
        let prompt: String
        let author: String
        let url: URL
        let cover: String?
        let tools: [String]
        let published: String
    }

    private struct Kept: Codable {
        var seen: [String]
        var posts: [Post]
    }

    nonisolated static let repo = "LeaddeOpenLab/awesome-opus-5-5-video-prompts"
    static let home = URL(string: "https://github.com/\(repo)")!
    private static let tree = URL(string: "https://api.github.com/repos/\(repo)/git/trees/main?recursive=1")!
    nonisolated private static func raw(_ path: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/\(repo)/main/\(path)")
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var loading = false
    @Published private(set) var trouble: String?
    /// The posts looked at so far, whole prompt or not.
    @Published private(set) var looked = 0
    private var refreshed = false

    private var cache: URL {
        CompanionArt.folder.appendingPathComponent("montage/guides/opus-5-5-video-prompts.json")
    }

    /// What is kept, at once; then, once a launch (or when asked), the posts
    /// added since.
    func load(fresh: Bool = false) async {
        guard !loading else { return }
        var kept = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) }
            ?? Kept(seen: [], posts: [])
        if entries.isEmpty { show(kept) }
        guard fresh || !refreshed else { return }
        loading = true
        defer { loading = false }
        var request = URLRequest(url: Self.tree, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = listing["tree"] as? [[String: Any]] else {
            trouble = kept.posts.isEmpty ? "拿不到提示词库（GitHub）" : "没连上 GitHub，这是上次存下的"
            return
        }
        refreshed = true
        let seen = Set(kept.seen)
        let fresh: [String] = items.compactMap { item in
            guard let path = item["path"] as? String, path.hasPrefix("data/library/"), path.hasSuffix(".json") else { return nil }
            let id = String(path.dropFirst("data/library/".count).dropLast(".json".count))
            return seen.contains(id) ? nil : id
        }
        let got = await Self.fetch(fresh)
        for (id, post) in got {
            kept.seen.append(id)
            if let post { kept.posts.append(post) }
        }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: cache) }
        show(kept)
        trouble = got.count < fresh.count ? "有 \(fresh.count - got.count) 条没拿到，下次再试" : nil
    }

    private func show(_ kept: Kept) {
        looked = kept.seen.count
        entries = Self.entries(from: kept.posts)
        if !kept.posts.isEmpty { trouble = nil }
    }

    func entries(of kind: Kind) -> [Entry] { entries.filter { $0.kind == kind } }

    /// The posts not read before, eight at a time. A post that came back is in
    /// the answer — with nil if its prompt is only a fragment; one that did
    /// not is left out, to be tried again.
    nonisolated private static func fetch(_ ids: [String]) async -> [(String, Post?)] {
        var out: [(String, Post?)] = []
        var next = ids.makeIterator()
        await withTaskGroup(of: (String, Post?)?.self) { group in
            func add() {
                guard let id = next.next(), let url = raw("data/library/\(id).json") else { return }
                group.addTask {
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return (id, post(from: data))
                }
            }
            for _ in 0..<8 { add() }
            while let result = await group.next() {
                if let result { out.append(result) }
                add()
            }
        }
        return out
    }

    /// A post, if the whole of its prompt was published.
    nonisolated static func post(from data: Data) -> Post? {
        guard let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let analysis = d["analysis"] as? [String: Any],
              let evidence = analysis["caseEvidence"] as? [String: Any],
              let prompt = evidence["prompt"] as? [String: Any],
              prompt["status"] as? String == "full_original",
              let post = d["post"] as? [String: Any], let id = post["id"] as? String,
              let text = (d["prompt"] as? String) ?? (prompt["englishText"] as? String),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let author = (post["author"] as? [String: Any])?["username"] as? String,
              let url = URL(string: post["canonicalUrl"] as? String ?? "") else { return nil }
        // "Unknown renderer", "Claude Code": saying nothing about how it was made.
        let tools = (evidence["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            .filter { name in !["unknown", "unspecified", "undisclosed", "claude", "internal"].contains { name.lowercased().contains($0) } }
        return Post(id: id,
                    title: evidence["title"] as? String ?? analysis["summaryEn"] as? String ?? id,
                    category: analysis["category"] as? String ?? "",
                    prompt: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    author: author, url: url,
                    cover: d["coverPath"] as? String,
                    tools: tools,
                    published: post["publishedAt"] as? String ?? "")
    }

    /// The same prompt posted by several people is one entry, credited to all
    /// of them, the first to post it first.
    nonisolated static func entries(from posts: [Post]) -> [Entry] {
        func same(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " .!。"))
        }
        var groups: [String: [Post]] = [:]
        var order: [String] = []
        for post in posts.sorted(by: { $0.published < $1.published }) {
            let key = same(post.prompt)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(post)
        }
        let kinds = Kind.allCases
        return order.compactMap { key -> Entry? in
            guard let group = groups[key], let first = group.first else { return nil }
            let known = ours[first.id]
            var tools: [String] = []
            for tool in group.flatMap(\.tools) where !tools.contains(tool) { tools.append(tool) }
            return Entry(id: first.id, title: known?.title ?? first.title,
                         kind: known?.kind ?? kind(category: first.category, title: first.title),
                         prompt: first.prompt,
                         credits: group.map { Credit(name: $0.author, post: $0.url) },
                         cover: first.cover.flatMap(raw), tools: tools, note: known?.note)
        }
        .sorted { (kinds.firstIndex(of: $0.kind) ?? 0, $0.id) < (kinds.firstIndex(of: $1.kind) ?? 0, $1.id) }
    }

    /// A post that came after these were sorted by hand, by what it is called.
    nonisolated static func kind(category: String, title: String) -> Kind {
        let t = title.lowercased()
        func says(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if ["canvas-interactive", "games-interactive"].contains(category) || says("interactive", "game", "playable") { return .interactive }
        if ["explainers", "manim"].contains(category) || says("explain", "educational", "tutorial") { return .explainer }
        if says("promo", "launch", "product", "brand", "commercial", " ad ") { return .promo }
        if category == "motion-graphics" || says("motion", "showreel") { return .showreel }
        return .animation
    }

    /// The 26 there were on 2026-09-28, sorted and named by hand — the
    /// repository's own categories put 19 of them under "other-animation".
    nonisolated private static let ours: [String: (kind: Kind, title: String, note: String?)] = {
        let showreel = (Kind.showreel, "动效设计师的 15 秒作品集", Optional("五个人发的是同一句提示词；想做成别的主题，把 motion designer 换掉就行"))
        return [
            "2103449416325890146": showreel, "2103495232637882858": showreel, "2103576084499358051": showreel,
            "2104541344945627171": showreel, "2104541641226977654": showreel,
            "2103273003555402193": (.showreel, "一个形状变遍各种 UI 的循环动效（120 BPM）",
                                    "它会先问你要 8–12 个 UI 状态、配色和一首 120 BPM 的免版税音乐，再把状态排到节拍上给你看"),
            "2104219444130234430": (.showreel, "品牌工作室的 40 秒作品集（英雄之旅）", nil),
            "2104471436039803295": (.showreel, "Three.js 15 秒 3D 动效（落地页首屏）", nil),
            "2104486181853610052": (.showreel, "数学动效作品集（20 秒）", nil),
            "2102787937482252537": (.promo, "推理创业公司的发布片", "只有一句话；把公司换成你的"),
            "2103066071838466494": (.promo, "SaaS 产品发布片", "原作者用的是 HyperFrames；它会自己挑一个知名 SaaS、上网找素材"),
            "2104219468079526187": (.promo, "给 EDteam 做宣传片", "先上网研究这家公司；把 EDteam 换成你的"),
            "2104401208958230764": (.promo, "12 秒产品片头（Apple 发布会质感）",
                                    "很长、逐帧的镜头表；会先问你产品名、logo、配色和音乐，不给就用它自己的默认值"),
            "2104489806713553012": (.promo, "Firetower 15 秒动效宣传", "原文是一个 t.co 短链；换成你的产品和网址"),
            "2104525366224412962": (.promo, "Pokobot 15 秒动效宣传", "把 Pokobot 换成你的产品"),
            "2102853258582880547": (.explainer, "内格罗尼鸡尾酒配方动画（30 秒）", nil),
            "2104459910247235966": (.explainer, "讲解《三体 3》里云天明的三个童话", nil),
            "2104468704490909880": (.explainer, "手绘风 P(Doom) 15 秒", nil),
            "2104542961081983435": (.explainer, "纸片定格动画：递归自我进化 agent 的局限（90–120 秒）",
                                    "原文用 Fal AI 上的 GPT Image 2.5（付费）出纸片素材；交给 agent 时可以让它改用盒子上的 Qwen-Image"),
            "2103824976713306214": (.animation, "Ultracode 动画：Claude 小人拍动作片",
                                    "原作者引用了他自己电脑上的参考视频（/Users/danielmcateer/…）：换成你的，或者删掉那一句"),
            "2104200939095904322": (.animation, "物理之美，一镜到底", nil),
            "2104509397535961220": (.animation, "日漫风女仆大战修格斯 15 秒 MV", nil),
            "2103802923465768972": (.interactive, "梵高《星夜》里找猫的 3D 游戏", nil),
            "2104189915693269112": (.interactive, "雨窗：听雨时看着玩的小东西", nil),
            "2104514806443303238": (.interactive, "WebGPU 草莓蛋糕：能捏能切的软体物理", nil),
            "2104520072014508316": (.interactive, "户型图 → 2D/3D 装修设计工具", "要一张户型图"),
        ]
    }()
}

import Foundation

/// Seedance prompts other people made work, to start from: learnprompt/awesome-seedance (code MIT,
/// curation CC BY 4.0, synced daily from goodcase.ai) — 「加，并改写给 H3/LTX 用」 (2026-10-04).
///
/// Two kinds of thing. 27 templates, each a way of writing one kind of video — a time-coded shot
/// script, a reference lock, a storyboard grid, handheld UGC… — with its points, structure and
/// pitfalls, in Chinese, as a block to fill in (【】 is what to change). And 760 cases with their
/// whole prompts, 355 of them retested on MiniMax H3 — the model the box films with — with a
/// verdict: whether it reproduced there is the first thing to look at. Seedance itself is not on the
/// box, so a prompt goes to the Montage or Film agent with a note to make it something H3 and LTX
/// can film (`seedance-on-box.md`, kept beside the library).
///
/// Fetched and kept, not shipped: <art>/guides/awesome-seedance, where the agents read the files
/// too. A file is fetched again only when the repository's copy changed (its git blob id).
@MainActor
final class SeedanceLibrary: ObservableObject {
    static let shared = SeedanceLibrary()

    nonisolated static let repo = "learnprompt/awesome-seedance"
    static let home = URL(string: "https://github.com/\(repo)")!
    private static let tree = URL(string: "https://api.github.com/repos/\(repo)/git/trees/main?recursive=1")!

    struct Template: Identifiable, Hashable {
        let id: String
        let title: String
        let category: String
        let summary: String
        /// The block to fill in and hand over: 【】 marks what to change.
        let copy: String
        let caseCount: Int
        /// Cases filed under it, hottest first (slugs).
        let examples: [String]
    }

    enum Verdict: String {
        case reproduced, degraded, failed, other

        var title: String {
            switch self {
            case .reproduced: return "H3 拍得出"
            case .degraded: return "H3 打折"
            case .failed: return "H3 没拍成"
            case .other: return "H3 测过"
            }
        }
    }

    struct Case: Identifiable, Hashable {
        let id: String
        let title: String
        let summary: String
        let prompt: String
        let model: String
        let creator: String
        let source: URL?
        let poster: URL?
        let video: URL?
        let heat: Int
        /// How it came out when retested on MiniMax H3, if it was.
        let onH3: Verdict?
    }

    @Published private(set) var templates: [Template] = []
    @Published private(set) var cases: [Case] = []
    @Published private(set) var loading = false
    @Published private(set) var trouble: String?
    private var refreshed = false

    private init() {}

    /// Where the library is kept — the agents are told this folder.
    static var folder: URL { CompanionArt.folder.appendingPathComponent("guides/awesome-seedance") }
    private var manifestFile: URL { Self.folder.appendingPathComponent(".manifest.json") }

    // MARK: - Loading

    /// What is kept, at once; then, once a launch (or when asked), what changed in the repository.
    func load(fresh: Bool = false) async {
        guard !loading else { return }
        placeGuide()
        if templates.isEmpty { read() }
        guard fresh || !refreshed else { return }
        loading = true
        defer { loading = false }
        var request = URLRequest(url: Self.tree, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = listing["tree"] as? [[String: Any]] else {
            trouble = templates.isEmpty ? "拿不到 awesome-seedance（GitHub）" : "没连上 GitHub，这是上次存下的"
            return
        }
        refreshed = true
        let wanted: [(path: String, sha: String)] = items.compactMap { item in
            guard let path = item["path"] as? String, let sha = item["sha"] as? String else { return nil }
            let template = (path.hasPrefix("docs/templates/zh/") || path.hasPrefix("docs/templates/en/")) && path.hasSuffix(".md")
            return template || path == "data/cases.json" ? (path, sha) : nil
        }
        var kept = (try? Data(contentsOf: manifestFile))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let stale = wanted.filter { kept[$0.path] != $0.sha }
        let got = await Self.fetch(stale.map(\.path), into: Self.folder)
        for item in stale where got.contains(item.path) { kept[item.path] = item.sha }
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: manifestFile) }
        read()
        trouble = got.count < stale.count ? "有 \(stale.count - got.count) 个文件没拿到，下次再试" : nil
    }

    /// The guide to turning a Seedance prompt into a plan for the box, beside the library.
    private func placeGuide() {
        guard let bundled = Bundle.main.url(forResource: "seedance-on-box", withExtension: "md"),
              let text = try? Data(contentsOf: bundled) else { return }
        let target = Self.folder.appendingPathComponent("seedance-on-box.md")
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if (try? Data(contentsOf: target)) != text { try? text.write(to: target) }
    }

    /// A repository path as kept: docs/templates/zh/x.md → templates/zh/x.md, data/cases.json → cases.json.
    nonisolated static func local(_ path: String) -> String {
        path.hasPrefix("docs/") ? String(path.dropFirst(5)) : path.hasPrefix("data/") ? String(path.dropFirst(5)) : path
    }

    /// The paths that came back, eight at a time.
    nonisolated private static func fetch(_ paths: [String], into folder: URL) async -> Set<String> {
        var got: Set<String> = []
        var next = paths.makeIterator()
        await withTaskGroup(of: String?.self) { group in
            func add() {
                guard let path = next.next(),
                      let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/\(path)") else { return }
                group.addTask {
                    guard let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    let file = folder.appendingPathComponent(local(path))
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    return (try? data.write(to: file)) != nil ? path : nil
                }
            }
            for _ in 0..<8 { add() }
            while let result = await group.next() {
                if let result { got.insert(result) }
                add()
            }
        }
        return got
    }

    private func read() {
        let zh = Self.folder.appendingPathComponent("templates/zh")
        templates = Self.templates(in: zh)
        if let data = try? Data(contentsOf: Self.folder.appendingPathComponent("cases.json")) {
            cases = Self.cases(from: data)
        }
        if !templates.isEmpty || !cases.isEmpty { trouble = nil }
    }

    // MARK: - Reading

    /// The templates, in the order and categories of the index (README.md: `## 🧱 结构基础`, then a
    /// table row a template: `| [逐秒时间轴分镜脚本](./timeline-shot-script.md) | 说明 | 5 |`).
    nonisolated static func templates(in folder: URL) -> [Template] {
        guard let index = try? String(contentsOf: folder.appendingPathComponent("README.md"), encoding: .utf8) else { return [] }
        var out: [Template] = []
        var category = ""
        for line in index.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                category = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    .drop { !$0.isLetter && !$0.isNumber }.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("| ["),
                  let close = line.range(of: "]("), let end = line.range(of: ".md)", range: close.upperBound..<line.endIndex)
            else { continue }
            let title = String(line[line.index(line.startIndex, offsetBy: 3)..<close.lowerBound])
            let id = String(line[close.upperBound..<end.lowerBound]).replacingOccurrences(of: "./", with: "")
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let summary = cells.count > 1 ? cells[1] : ""
            let count = cells.count > 2 ? Int(cells[2]) ?? 0 : 0
            guard let text = try? String(contentsOf: folder.appendingPathComponent(id + ".md"), encoding: .utf8) else { continue }
            out.append(Template(id: id, title: title, category: category, summary: summary,
                                copy: block(in: text), caseCount: count, examples: slugs(in: text)))
        }
        return out
    }

    /// The text of the fenced block to copy (````text … ````).
    nonisolated static func block(in text: String) -> String {
        guard let open = text.range(of: "````text\n"),
              let close = text.range(of: "\n````", range: open.upperBound..<text.endIndex) else { return "" }
        return String(text[open.upperBound..<close.lowerBound])
    }

    /// The goodcase.ai cases a template links, in order, once each.
    nonisolated static func slugs(in text: String) -> [String] {
        var seen: [String] = []
        var rest = text[...]
        while let hit = rest.range(of: "goodcase.ai/cases/") {
            let slug = rest[hit.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            if !slug.isEmpty, !seen.contains(String(slug)) { seen.append(String(slug)) }
            rest = rest[hit.upperBound...]
        }
        return seen
    }

    nonisolated static func cases(from data: Data) -> [Case] {
        guard let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = d["cases"] as? [[String: Any]] else { return [] }
        let rank: [Verdict: Int] = [.reproduced: 3, .degraded: 2, .other: 1, .failed: 0]
        return list.compactMap { c -> Case? in
            guard let slug = c["slug"] as? String,
                  let prompt = (c["promptFull"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prompt.isEmpty else { return nil }
            let h3 = (c["retests"] as? [[String: Any]] ?? [])
                .filter { ($0["model"] as? String ?? "").contains("H3") }
                .map { Verdict(rawValue: $0["verdict"] as? String ?? "") ?? .other }
                .max { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            func link(_ key: String) -> URL? { (c[key] as? String).flatMap(URL.init(string:)) }
            return Case(id: slug,
                        title: (c["title"] as? String) ?? (c["titleEn"] as? String) ?? slug,
                        summary: (c["summary"] as? String) ?? (c["summaryEn"] as? String) ?? "",
                        prompt: prompt,
                        model: (c["models"] as? [String])?.first ?? "Seedance",
                        creator: c["creator"] as? String ?? "",
                        source: link("sourceUrl"), poster: link("posterUrl"), video: link("mediaUrl"),
                        heat: c["heatScore"] as? Int ?? 0, onH3: h3)
        }
        .sorted { $0.heat > $1.heat }
    }

    // MARK: - Handing over

    /// What goes to an agent with a case: credit, and the note that it is to be filmed on the box.
    func handover(_ item: Case, prompt: String, film: Bool) -> String {
        let verdict = item.onH3.map { "（awesome-seedance 在 H3 上重测：\($0.title)）" } ?? ""
        return """
            下面是一条 Seedance 的提示词：awesome-seedance 的「\(item.title)」，\(item.creator) \(item.source?.absoluteString ?? "")\(verdict)。
            Seedance 不在盒子上：照 \(Self.folder.path)/seedance-on-box.md 把它改成盒子上 H3 / LTX 能拍的方案\
            \(film ? "，用 Film 的流程（分镜、首帧、H3 或 LTX、配乐）" : "")——先说打算怎么拍、几个镜头、要多久，我点头再拍。

            \(prompt)
            """
    }

    /// What goes to an agent with a filled-in template.
    func handover(_ item: Template, text: String, film: Bool) -> String {
        """
        按下面这个 awesome-seedance 模板「\(item.title)」的写法，做一个在盒子上用 H3 / LTX 拍的方案（不是 Seedance 的\
        提示词；怎么改见 \(Self.folder.path)/seedance-on-box.md）\(film ? "，用 Film 的流程" : "")——先说打算怎么拍，我点头再拍。

        \(text)
        """
    }
}

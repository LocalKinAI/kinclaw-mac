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
        guard let writer = await FilmStudio.writer(), let url = URL(string: writer.host + "/api/chat") else { return nil }
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

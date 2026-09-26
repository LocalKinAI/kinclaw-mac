import Foundation

/// A topic in, reference videos out — the ones a movement can actually be taken
/// from, and may be.
///
/// "智能找" is three small judgments, none of them the user's to make by hand:
///
///   1. **What to search for.** "八段锦" typed into a search box finds talks,
///      history and group classes. What is wanted is one person showing the
///      whole thing to a camera, so the writer model turns the topic into two
///      or three queries for exactly that, in the topic's language and in
///      English.
///   2. **What may be used.** The search is YouTube's own, with its Creative
///      Commons filter on, so everything listed is offered for reuse; the real
///      licence field is still read when one is picked, before any of it is
///      fetched (`MotionImport.look`), because a filter is a claim and the
///      field is the record.
///   3. **What can be tracked.** One person, whole body, a camera that mostly
///      stays put. The model that can see is shown the thumbnails, six at a
///      time, and says how many people, whether the body is all there, and how
///      good a reference it would make out of ten, with a reason — and the list
///      is sorted by that. A thumbnail is not the video, so it is a first
///      sorting, not a promise; the tracker says "nobody found" soon enough
///      when it was wrong.
@MainActor
final class MotionFinder: ObservableObject {
    static let shared = MotionFinder()

    struct Candidate: Identifiable, Equatable {
        var id: String
        var title: String
        var author: String
        var seconds: Double
        var address: String { "https://www.youtube.com/watch?v=\(id)" }
        var thumbnail: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
        /// How good a reference it looks, 0–10, and why — nil until looked at.
        var fit: Int?
        var why: String?
        /// Whether it is the thing that was asked for at all: a search for
        /// 八段锦 also brings back a very trackable tai chi form.
        var onTopic: Bool?
    }

    @Published private(set) var topic = ""
    @Published private(set) var found: [Candidate] = []
    @Published private(set) var doing: String?
    @Published private(set) var trouble: String?
    @Published var open = false

    func close() { open = false }

    /// Search, then look. The list appears as soon as there is one and is
    /// re-sorted as the thumbnails are judged.
    func find(_ wanted: String) {
        let topic = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty, doing == nil else { return }
        self.topic = topic
        found = []; trouble = nil; open = true
        doing = "在想怎么搜「\(topic)」…"
        Task { @MainActor in
            defer { doing = nil }
            do {
                let queries = await Self.queries(for: topic)
                var seen = Set<String>(), list: [Candidate] = []
                for query in queries {
                    doing = "在搜：\(query)"
                    for candidate in try await Self.search(query) where !seen.contains(candidate.id) {
                        seen.insert(candidate.id); list.append(candidate)
                    }
                    found = list
                }
                // Long enough to hold a movement, short enough to be a demonstration.
                list = list.filter { $0.seconds == 0 || ($0.seconds >= 15 && $0.seconds <= 1500) }
                found = Array(list.prefix(18))
                guard !found.isEmpty else { trouble = "没搜到 Creative Commons 许可的「\(topic)」视频。换个说法试试，或者自己拍一段。"; return }
                for start in stride(from: 0, to: found.count, by: 6) {
                    doing = "在看封面 \(min(start + 6, found.count))/\(found.count)"
                    let batch = Array(found[start..<min(start + 6, found.count)])
                    for (id, verdict) in await Self.judge(batch, topic: topic) {
                        if let at = found.firstIndex(where: { $0.id == id }) {
                            found[at].fit = verdict.fit; found[at].why = verdict.why; found[at].onTopic = verdict.onTopic
                        }
                    }
                    // What was asked for first, then how well it can be tracked.
                    found.sort { a, b in
                        let (ta, tb) = (a.onTopic ?? true, b.onTopic ?? true)
                        return ta != tb ? ta : (a.fit ?? -1) > (b.fit ?? -1)
                    }
                }
            } catch { trouble = error.localizedDescription }
        }
    }

    // MARK: - The three judgments

    /// Two or three searches that find one person demonstrating the topic.
    static func queries(for topic: String) async -> [String] {
        guard let writer = await FilmStudio.writer(claude: true), let url = URL(string: writer.host + "/api/chat") else { return [topic] }
        let ask = """
            I need reference videos for motion capture of: "\(topic)". A good one shows ONE person performing it, whole \
            body in frame, filmed by a camera that does not move much — a demonstration, not a talk, a group class, a \
            competition montage or a news report. Write 3 YouTube search queries likely to find such videos: one in the \
            language of the topic, two in English using the usual English name of the activity plus words like \
            "demonstration", "full body", "front view", "follow along". Answer with JSON only: {"queries": ["...", "...", "..."]}
            """
        let body: [String: Any] = ["model": writer.model, "stream": false, "think": false,
                                   "messages": [["role": "user", "content": ask]]]
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = (reply["message"] as? [String: Any])?["content"] as? String,
              let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let answer = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              let list = answer["queries"] as? [String] else { return [topic] }
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? [topic] : Array(cleaned.prefix(3))
    }

    /// YouTube's search with its Creative Commons filter, read flat: titles,
    /// lengths and authors, nothing fetched.
    static func search(_ query: String) async throws -> [Candidate] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        let results = "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIwAQ%253D%253D"
        let out = try await MotionImport.run(["--flat-playlist", "--playlist-end", "10", "-J", "--no-warnings", results])
        guard let start = out.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(out[start...].utf8)) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String, id.count == 11 else { return nil }     // a video, not a channel or a playlist
            return Candidate(id: id, title: (entry["title"] as? String) ?? "",
                             author: (entry["channel"] as? String) ?? (entry["uploader"] as? String) ?? "",
                             seconds: (entry["duration"] as? Double) ?? Double((entry["duration"] as? Int) ?? 0))
        }
    }

    /// The thumbnails, looked at: is this something a body can be tracked in?
    static func judge(_ batch: [Candidate], topic: String) async -> [String: (fit: Int, why: String, onTopic: Bool)] {
        var pictures: [Data] = [], ids: [String] = []
        for candidate in batch {
            guard let url = candidate.thumbnail, let (data, _) = try? await URLSession.shared.data(from: url), data.count > 1000 else { continue }
            pictures.append(data); ids.append(candidate.id)
        }
        guard !pictures.isEmpty else { return [:] }
        let ask = """
            These \(pictures.count) images are the thumbnails of videos found for: "\(topic)". I want to track ONE person's \
            whole-body movement from a video, so a good reference shows a single performer, head to foot in frame, large \
            enough to see the limbs, filmed from a camera that stays put, doing the activity itself. Bad: several people, \
            a talking head, a close-up, a title card with no person, a collage, heavy text over the body.
            Their titles, in the same order: \(batch.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: " | "))
            For each image, in order, answer with JSON only:
            {"videos": [{"n": 1, "people": 1, "whole_body": true, "on_topic": true, "fit": 0-10, "why": "一句中文：为什么适合或不适合"}, ...]}
            on_topic is false when the title and picture show a different activity from "\(topic)" (a related but \
            different form counts as different).
            """
        guard let answer = await FilmStudio.look(ask, at: pictures), let list = answer["videos"] as? [[String: Any]] else { return [:] }
        var verdicts: [String: (Int, String, Bool)] = [:]
        for (index, item) in list.enumerated() where index < ids.count {
            let at = ((item["n"] as? Int) ?? (index + 1)) - 1
            guard ids.indices.contains(at) else { continue }
            let fit = (item["fit"] as? Int) ?? Int((item["fit"] as? Double) ?? 0)
            verdicts[ids[at]] = (min(max(fit, 0), 10), (item["why"] as? String) ?? "", (item["on_topic"] as? Bool) ?? true)
        }
        return verdicts
    }
}

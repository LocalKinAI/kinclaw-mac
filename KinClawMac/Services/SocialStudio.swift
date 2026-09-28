import AppKit
import AVFoundation
import Foundation
import ImageIO

/// The Easel tab: our own Easel, worked by our own agent. The menu calls it
/// Easel ("把社媒改名字叫Easel"); inside it is still `social` — the mode, the
/// social_* tools, the art folder social/ — so that running agents and saved
/// drafts keep working.
///
/// Easel (ZJU-REAL, Apache-2.0) is a social-media workbench for Chinese
/// platforms — an account profile, trending lists, topic scoring, copy with
/// the AI taste taken out, cards drawn from HTML and checked, a quality gate —
/// run by OpenClaw on skills written as SKILL.md files. OpenClaw could not run
/// on the box ("easel想法不错，可以复刻一个吗，然后加个tab，用我们自己的agent操控
/// 啊，不用openclaw"), so here it is again the way the other Studio tabs are
/// made: its guides copied into the tab's folder (guides/easel/, with its
/// licence) for the agent to read, and the steps it needed a runtime for made
/// tools of the panel — the profile's six files, public trending lists, a card
/// drawn and checked off-screen, a page read signed in to nothing, and a draft
/// written as a folder. What the tab makes is a draft and nothing more:
/// publishing is the person's own click on the platform, and the app never
/// signs in anywhere. Besides the Chinese platforms Easel was made for, a
/// draft can be for TikTok, X, YouTube Shorts and WeChat's three places
/// (公众号, 视频号, 朋友圈) — see `SocialPlatform`.
@MainActor
final class SocialStudio: ObservableObject {
    static let shared = SocialStudio()

    static var root: URL { CompanionArt.folder.appendingPathComponent("social") }
    static var draftsFolder: URL { root.appendingPathComponent("drafts") }
    static var profilesFolder: URL { root.appendingPathComponent("profiles") }
    static var guides: URL { root.appendingPathComponent("guides/easel") }
    /// Cards drawn before they belong to a draft, a day's folder each.
    static var cardsFolder: URL { root.appendingPathComponent("cards") }
    static var trendsFolder: URL { root.appendingPathComponent("trends") }
    static var capturesFolder: URL { root.appendingPathComponent("captures") }
    /// An earlier Easel run's drafts, shown and never moved or written.
    static var easelFolder: URL { CompanionArt.folder.appendingPathComponent("easel") }

    /// The six files of an account, as Easel's profiles/_template has them.
    static let profileFiles = ["identity", "style", "audience", "platforms", "preferences", "memory"]

    struct Draft: Identifiable, Equatable {
        struct Source: Equatable {
            let fact: String
            let source: String
            let url: String?
            let date: String?
        }
        let id: String
        let folder: URL
        let platform: String
        let title: String
        let titleOptions: [String]
        /// A 公众号 article's 摘要, the line under its title in a feed.
        let summary: String?
        let body: String
        let tags: [String]
        let cards: [URL]
        let video: URL?
        let created: Date
        let account: String?
        let sources: [Source]
        let checks: [String]
        /// From the earlier Easel run: read only.
        let legacy: Bool
    }

    @Published private(set) var drafts: [Draft] = []
    @Published private(set) var accounts: [String] = []
    @Published var selected: String?
    /// What is being drawn or read off-screen right now.
    @Published private(set) var working: String?
    @Published private(set) var lastTrends: Date?
    @Published var note: String?

    private init() {}

    // MARK: Drafts

    func reload(select: String? = nil) {
        let drafts = Self.draftsFolder, easel = Self.easelFolder, profiles = Self.profilesFolder
        Task {
            let (found, names) = await Task.detached(priority: .utility) {
                (Self.scan(drafts, legacy: false) + Self.scan(easel, legacy: true), Self.accounts(in: profiles))
            }.value
            self.drafts = found.sorted { $0.created > $1.created }
            accounts = names
            if let select, found.contains(where: { $0.id == select }) {
                selected = select
            } else if selected == nil || !found.contains(where: { $0.id == selected }) {
                selected = self.drafts.first?.id
            }
        }
    }

    nonisolated static func accounts(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { name in
            var directory: ObjCBool = false
            return !name.hasPrefix(".") && !name.hasPrefix("_")
                && FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path, isDirectory: &directory) && directory.boolValue
        }.sorted()
    }

    /// Every folder with a 发布文案.txt or a meta.json in it.
    nonisolated static func scan(_ folder: URL, legacy: Bool) -> [Draft] {
        let files = FileManager.default
        let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            let draft = folder.appendingPathComponent(name)
            guard files.fileExists(atPath: draft.appendingPathComponent("meta.json").path)
                    || files.fileExists(atPath: draft.appendingPathComponent("发布文案.txt").path) else { return nil }
            return read(draft, legacy: legacy)
        }
    }

    /// A draft folder, ours or Easel's: meta.json first, 发布文案.txt for
    /// whatever it lacks, the pictures from cards/ (or Easel's images/).
    nonisolated static func read(_ folder: URL, legacy: Bool) -> Draft {
        let files = FileManager.default
        let meta = (try? Data(contentsOf: folder.appendingPathComponent("meta.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let text = (try? String(contentsOf: folder.appendingPathComponent("发布文案.txt"), encoding: .utf8)) ?? ""
        let sections = postSections(text)
        let options = (meta["title_options"] as? [String]) ?? sections["标题"].map { lines in
            lines.split(separator: "\n").map { $0.replacingOccurrences(of: #"\s*〔.*〕\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        } ?? []
        let title = (meta["title"] as? String) ?? options.first ?? folder.lastPathComponent
        let summary = ((meta["summary"] as? String) ?? sections["摘要"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (meta["body"] as? String) ?? sections["正文"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = (meta["tags"] as? [String]) ?? sections["话题"].map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init).filter { $0.hasPrefix("#") }
        } ?? []
        var cards: [URL] = []
        for sub in ["cards", "images"] {
            let dir = folder.appendingPathComponent(sub)
            let names = ((try? files.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.lowercased().hasSuffix(".png") || $0.lowercased().hasSuffix(".jpg") }
            if !names.isEmpty {
                cards = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { dir.appendingPathComponent($0) }
                break
            }
        }
        let video = (meta["video"] as? String).map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : folder.appendingPathComponent($0) }
        let iso = ISO8601DateFormatter()
        let created = (meta["created_at"] as? String).flatMap { iso.date(from: $0) }
            ?? (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        let sources = (meta["sources"] as? [[String: Any]] ?? []).map {
            Draft.Source(fact: $0["fact"] as? String ?? "", source: $0["source"] as? String ?? "",
                         url: $0["url"] as? String, date: $0["date"] as? String)
        }
        return Draft(id: (legacy ? "easel/" : "") + folder.lastPathComponent, folder: folder,
                     platform: meta["platform"] as? String ?? "小红书", title: title, titleOptions: options.isEmpty ? [title] : options,
                     summary: summary?.isEmpty == false ? summary : nil,
                     body: body, tags: tags, cards: cards, video: video, created: created,
                     account: meta["account"] as? String, sources: sources, checks: meta["checks"] as? [String] ?? [],
                     legacy: legacy)
    }

    /// 发布文案.txt, by its headings: 标题…：, 正文：, 话题：, 卡片…：.
    nonisolated static func postSections(_ text: String) -> [String: String] {
        var sections: [String: String] = [:]
        var current: String?
        var lines: [String] = []
        func close() { if let current { sections[current] = lines.joined(separator: "\n") } }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let key = ["标题", "摘要", "正文", "话题", "卡片", "视频", "出处"].first(where: { trimmed.hasPrefix($0) }),
               trimmed.hasSuffix("：") || trimmed.hasSuffix(":") {
                close()
                current = key
                lines = []
            } else {
                lines.append(line)
            }
        }
        close()
        return sections
    }

    /// Where each platform takes a post: the page opened for the person, who
    /// signs in and posts there themselves. 朋友圈 has none.
    static func publishPage(_ platform: String) -> URL? {
        SocialPlatform.of(platform)?.publishPage
    }

    /// What 复制文案 copies: the post's text box, whole — the body, then the tags.
    nonisolated static func pastedText(body: String, tags: [String]) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
            + (tags.isEmpty ? "" : "\n\n" + tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }.joined(separator: " "))
    }

    // MARK: Writing one

    struct DraftInput {
        var platform = "小红书"
        var titleOptions: [String] = []
        /// 公众号's 摘要.
        var summary: String?
        var body = ""
        var tags: [String] = []
        var cards: [URL] = []
        var video: URL?
        /// The video as measured before the draft is written (its picture as
        /// shown, and its length), for the checks.
        var videoSize: CGSize?
        var videoSeconds: Double?
        var sources: [Draft.Source] = []
        var account: String?
        var notes: String?
        var slug: String?
        /// A draft of ours to write over (its old files moved aside first).
        var replacing: String?
    }

    /// Write a draft folder: 发布文案.txt (title options, body, tags, the cards
    /// in order), cards/01.png… with each card's HTML beside it, the video if
    /// there is one, meta.json with the platform and every fact's source.
    func write(_ input: DraftInput) -> Result<(Draft, [String]), SocialFailure> {
        let files = FileManager.default
        guard let title = input.titleOptions.first?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return .failure(SocialFailure("要 title_options：至少一个标题"))
        }
        guard !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(SocialFailure("要 body：正文")) }
        for card in input.cards where !files.fileExists(atPath: card.path) {
            return .failure(SocialFailure("没有这张卡片：\(card.path)"))
        }
        if let video = input.video, !files.fileExists(atPath: video.path) { return .failure(SocialFailure("没有这个视频：\(video.path)")) }

        let folder: URL
        let stamp = DateFormatter()
        if let replacing = input.replacing?.trimmingCharacters(in: .whitespaces), !replacing.isEmpty {
            guard !replacing.hasPrefix("easel/"), !replacing.contains("/"), !replacing.contains(".."),
                  files.fileExists(atPath: Self.draftsFolder.appendingPathComponent(replacing).path) else {
                return .failure(SocialFailure("draft 要是 social_drafts 列出来的、我们自己的草稿（Easel 的旧草稿只读）：\(replacing)"))
            }
            folder = Self.draftsFolder.appendingPathComponent(replacing)
        } else {
            stamp.dateFormat = "yyyyMMdd-HHmm"
            let base = stamp.string(from: Date()) + "-" + Self.slug(input.slug ?? title)
            var name = base, n = 2
            while files.fileExists(atPath: Self.draftsFolder.appendingPathComponent(name).path) { name = "\(base)-\(n)"; n += 1 }
            folder = Self.draftsFolder.appendingPathComponent(name)
        }
        // Over an earlier version: what was there goes aside, never away, and a
        // card given from that version is read from where it went — worked out
        // while both paths still exist. A write that fails puts it all back.
        var aside: URL?
        var setAside: [String] = []
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let keep = ["发布文案.txt", "meta.json", "cards"] + ((try? files.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("video.") }
            let present = keep.filter { files.fileExists(atPath: folder.appendingPathComponent($0).path) }
            var given = input.cards
            var video = input.video
            if !present.isEmpty {
                stamp.dateFormat = "yyyyMMdd-HHmmss"
                let when = stamp.string(from: Date())
                var place = folder.appendingPathComponent(".previous/" + when)
                var n = 2
                while files.fileExists(atPath: place.path) { place = folder.appendingPathComponent(".previous/\(when)-\(n)"); n += 1 }
                let old = folder.resolvingSymlinksInPath().path + "/"
                func moved(_ file: URL) -> URL {
                    let path = file.resolvingSymlinksInPath().path
                    return path.hasPrefix(old) ? place.appendingPathComponent(String(path.dropFirst(old.count))) : file
                }
                given = given.map(moved)
                video = video.map(moved)
                try files.createDirectory(at: place, withIntermediateDirectories: true)
                aside = place
                for name in present {
                    try files.moveItem(at: folder.appendingPathComponent(name), to: place.appendingPathComponent(name))
                    setAside.append(name)
                }
            }
            let cards = folder.appendingPathComponent("cards")
            try files.createDirectory(at: cards, withIntermediateDirectories: true)
            var placed: [URL] = []
            for (i, card) in given.enumerated() {
                let name = String(format: "%02d", i + 1)
                let target = cards.appendingPathComponent(name + "." + (card.pathExtension.isEmpty ? "png" : card.pathExtension.lowercased()))
                try files.copyItem(at: card, to: target)
                // Its HTML, to draw it again later, and what its audit said.
                for (from, to) in [("html", ".html"), ("audit.json", ".audit.json")] {
                    let beside = card.deletingPathExtension().appendingPathExtension(from)
                    if files.fileExists(atPath: beside.path) { try? files.copyItem(at: beside, to: cards.appendingPathComponent(name + to)) }
                }
                placed.append(target)
            }
            var videoName: String?
            if let video {
                videoName = "video." + (video.pathExtension.isEmpty ? "mp4" : video.pathExtension.lowercased())
                try files.copyItem(at: video, to: folder.appendingPathComponent(videoName!))
            }
            let checks = Self.checks(input, cards: placed)
            let iso = ISO8601DateFormatter()
            var meta: [String: Any] = [
                "platform": input.platform, "title": title, "title_options": input.titleOptions, "body": input.body,
                "tags": input.tags.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 },
                "cards": placed.map { "cards/" + $0.lastPathComponent },
                "created_at": iso.string(from: Date()), "status": "draft — 发布由人自己在平台上点",
                "sources": input.sources.map { source -> [String: Any] in
                    var row: [String: Any] = ["fact": source.fact, "source": source.source]
                    if let url = source.url { row["url"] = url }
                    if let date = source.date { row["date"] = date }
                    return row
                },
                "checks": checks,
            ]
            if let videoName { meta["video"] = videoName }
            if let summary = input.summary, !summary.isEmpty { meta["summary"] = summary }
            if let account = input.account { meta["account"] = account }
            if let notes = input.notes { meta["notes"] = notes }
            let json = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try json.write(to: folder.appendingPathComponent("meta.json"))
            try Self.postText(input, cards: placed, video: videoName).write(to: folder.appendingPathComponent("发布文案.txt"), atomically: true, encoding: .utf8)
            let draft = Self.read(folder, legacy: false)
            reload(select: draft.id)
            return .success((draft, checks))
        } catch {
            // The earlier version back where it was; what this write made, beside it.
            if let aside {
                for name in setAside {
                    let back = folder.appendingPathComponent(name)
                    if files.fileExists(atPath: back.path) { try? files.moveItem(at: back, to: aside.appendingPathComponent(name + ".failed")) }
                    try? files.moveItem(at: aside.appendingPathComponent(name), to: back)
                }
            }
            return .failure(SocialFailure("写不了草稿：\(error.localizedDescription)"))
        }
    }

    nonisolated static func slug(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: #"[\\/:*?"<>|\s#，。、！？：；,.!?;]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(cleaned.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty ? "draft" : String(cleaned.prefix(24))
    }

    /// 发布文案.txt, laid out as the earlier Easel draft's was.
    nonisolated static func postText(_ input: DraftInput, cards: [URL], video: String?) -> String {
        var lines = ["平台：\(input.platform)", "", "标题（选一个）："] + input.titleOptions.map { "  " + $0 }
        if let summary = input.summary, !summary.isEmpty { lines += ["", "摘要：", summary] }
        lines += ["", "正文：", input.body.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !input.tags.isEmpty { lines += ["", "话题：", input.tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }.joined(separator: " ")] }
        if !cards.isEmpty {
            lines += ["", "卡片（cards/01 … 按顺序上传）："] + cards.enumerated().map { "  \($0.offset + 1). cards/\($0.element.lastPathComponent)" }
        }
        if let video { lines += ["", "视频：", "  " + video] }
        if !input.sources.isEmpty {
            lines += ["", "出处："] + input.sources.map { s in
                "  · \(s.fact) —— \(s.source)" + (s.date.map { "，\($0)" } ?? "") + (s.url.map { "，\($0)" } ?? "")
            }
        }
        lines += ["", "（草稿。发布由你自己在平台上点；这个 app 不登录、不发帖。）"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Easel's publish checklist, the parts a program can tell: what is
    /// missing, what is over a platform's limit, what a platform punishes —
    /// each platform by its own published numbers, cited where they are used
    /// (read on 2026-09-28). The wording is read in Chinese and in English:
    /// a TikTok, X or Shorts draft is often English.
    nonisolated static func checks(_ input: DraftInput, cards: [URL]) -> [String] {
        var checks: [String] = []
        /// What was measured rather than found wrong: said after the rest.
        var measured: [String] = []
        let known = SocialPlatform.of(input.platform)
        let platform = known?.rawValue ?? input.platform
        let title = input.titleOptions.first ?? ""
        // The post's text box as the person fills it (复制文案): body, then tags.
        let pasted = pastedText(body: input.body, tags: input.tags)
        let tagCount = Set((input.tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 } + hashtags(in: input.body)).map { $0.lowercased() }).count
        let sized: [(card: URL, size: CGSize)] = cards.compactMap { card in pixelSize(card).map { (card, $0) } }
        func dims(_ size: CGSize) -> String { "\(Int(size.width))×\(Int(size.height))" }
        let video = input.video != nil

        if known == nil {
            checks.append("⚠️ 不认识「\(input.platform)」这个平台，只查了通用的几项。认识的：" + SocialPlatform.allCases.map(\.rawValue).joined(separator: "、"))
        }
        if known?.needsVideo == true, !video { checks.append("❌ \(platform) 要视频，这份草稿没有（pixelle_* 做一支 9:16 的）") }

        switch known {
        case .xiaohongshu?:
            if title.count > 20 { checks.append("⚠️ 标题 \(title.count) 个字：小红书标题最多 20 个字") }
            if input.body.count > 1000 { checks.append("⚠️ 正文 \(input.body.count) 个字：小红书正文最多 1000 个字") }
            if cards.isEmpty, !video { checks.append("❌ 没有图也没有视频：小红书要至少一张图") }
            if cards.count > 18 { checks.append("❌ \(cards.count) 张卡片：小红书一帖最多 18 张（9 张以内最好）") }
            // 3:4 is what 小红书's feed shows whole.
            for (card, size) in sized where !(near(size, 3, 4) || near(size, 1, 1)) {
                checks.append("⚠️ \(card.lastPathComponent) 是 \(dims(size))：小红书是 3:4（1080×1440）或 1:1")
            }

        case .x?:
            // 280, weighted: https://docs.x.com/fundamentals/counting-characters and
            // twitter-text's config/v3.json (see `xLength`). X Premium posts run to
            // 25,000: https://help.x.com/en/using-x/x-premium.
            let weight = xLength(pasted)
            if weight > 280 {
                checks.append("❌ X 计 \(weight)/280（中日韩字和 emoji 算 2，链接算 23）：超了——删字，或拆成一串（thread）；X Premium 账号能发到 25,000")
            } else {
                measured.append("✅ X 计 \(weight)/280（中日韩字和 emoji 算 2，链接一律算 23）")
            }
            // Four pictures a post, a video counting as one of them:
            // https://help.x.com/en/using-x/posting-gifs-and-pictures, https://docs.x.com/x-api/media/introduction.
            let media = cards.count + (video ? 1 : 0)
            if media > 4 { checks.append("❌ \(media) 个图片和视频：X 一帖最多 4 个，多的放进下一条（thread）") }
            // "No more than 2 hashtags per post": https://help.x.com/en/using-x/how-to-use-hashtags.
            if tagCount > 2 { checks.append("⚠️ \(tagCount) 个话题：X 建议一帖不超过 2 个，多了像广告") }
            if hasLink(pasted) { checks.append("⚠️ 带链接：X 上带外链的帖子推得少——Easel 的平台指南是把链接放进第一条回复") }
            for (card, size) in sized where !(near(size, 16, 9) || near(size, 1, 1) || near(size, 4, 5)) {
                checks.append("⚠️ \(card.lastPathComponent) 是 \(dims(size))：X 用 16:9（1600×900）整张显示；1:1（1080×1080）、4:5（1080×1350）在手机上更大；别的比例会被裁")
            }
            if Set(sized.map { ratioKey($0.size) }).count > 1 { checks.append("⚠️ 几张图的比例不一样：X 多图排成网格、各自裁切，统一一个比例") }
            // Without Premium, a video of up to 20 minutes: https://docs.x.com/x-api/media/introduction.
            if let seconds = input.videoSeconds, seconds > 20 * 60 { checks.append("⚠️ 视频 \(minutes(seconds)) 长：没有 Premium 的账号一支最多 20 分钟") }

        case .tiktok?:
            // A video's caption: 2,200 UTF-16 units through TikTok's own API
            // (https://developers.tiktok.com/doc/content-posting-api-reference-direct-post);
            // a photo post: title 90, description 4,000, up to 35 photos
            // (https://developers.tiktok.com/doc/content-posting-api-reference-photo-post).
            // The app itself takes a 4,000-character caption.
            let caption = pasted.utf16.count
            if caption > 4000 { checks.append("❌ 文案 \(caption) 个字符：TikTok 最多 4,000") }
            else if caption > 2200, cards.isEmpty { checks.append("⚠️ 文案 \(caption) 个字符：App 里能写到 4,000，TikTok 官方接口给视频的上限是 2,200——网页上传可能截断") }
            if !cards.isEmpty, title.utf16.count > 90 { checks.append("⚠️ 标题 \(title.utf16.count) 个字符：TikTok 图集（photo mode）的标题最多 90") }
            if cards.isEmpty, !video { checks.append("❌ 没有视频也没有图：TikTok 要一支视频（9:16），或者一组图（photo mode，最多 35 张）") }
            if cards.count > 35 { checks.append("❌ \(cards.count) 张图：TikTok 图集最多 35 张") }
            if video, !cards.isEmpty { checks.append("⚠️ 又有视频又有图：TikTok 一帖是一支视频或一组图；图要当视频封面，就在发布页的封面里放") }
            // "Maximum 5 hashtags", the app's own prompt since August 2025:
            // https://www.mediapost.com/publications/article/408371/.
            if tagCount > 5 { checks.append("⚠️ \(tagCount) 个话题：TikTok 发布时提示最多 5 个（2025-08 起）") }
            else if tagCount == 0 { checks.append("⚠️ 没有话题标签（TikTok 最多放 5 个）") }
            if let size = input.videoSize, size.width > size.height { checks.append("⚠️ 视频是横的（\(dims(size))）：TikTok 竖屏看，9:16（1080×1920）才铺满") }
            if let seconds = input.videoSeconds, seconds > 600 { checks.append("⚠️ 视频 \(minutes(seconds)) 长：TikTok 按账号给时长上限，官方接口最多收 10 分钟") }
            for (card, size) in sized where size.width > size.height {
                checks.append("⚠️ \(card.lastPathComponent) 是横图（\(dims(size))）：TikTok 图集竖屏全屏看，1080×1920（9:16）铺满")
            }

        case .shorts?:
            // Up to three minutes, square or vertical: https://support.google.com/youtube/answer/15424877.
            // Title 100, description 5,000, no invalid characters (< and >):
            // https://support.google.com/youtube/answer/57404, https://developers.google.com/youtube/v3/docs/videos.
            if let size = input.videoSize, size.width > size.height { checks.append("❌ 视频是横的（\(dims(size))）：Shorts 要竖的或方的，横的会当成普通视频") }
            if let seconds = input.videoSeconds, seconds > 180 { checks.append("❌ 视频 \(minutes(seconds)) 长：Shorts 最长 3 分钟，更长的会当成普通视频") }
            if title.count > 100 { checks.append("❌ 标题 \(title.count) 个字符：YouTube 标题最多 100") }
            if pasted.count > 5000 { checks.append("❌ 描述 \(pasted.count) 个字符：YouTube 描述最多 5,000") }
            if (title + pasted).contains(where: { $0 == "<" || $0 == ">" }) { checks.append("❌ 标题或描述里有 < 或 >：YouTube 不收这两个字符") }
            // Over 60, every one is ignored: https://support.google.com/youtube/answer/6390658.
            if tagCount > 60 { checks.append("❌ \(tagCount) 个话题：超过 60 个，YouTube 会把这支视频的话题全部忽略") }
            // Links in Shorts descriptions are not clickable: https://support.google.com/youtube/answer/13748639.
            if hasLink(pasted) { checks.append("⚠️ 描述里有链接：Shorts 的描述和评论里的链接点不开——链接放频道主页，或者给这支 Short 挂关联视频") }

        case .wechatArticle?:
            // The editor: title 64, 摘要 120 (without one, the body's first 54
            // characters), body 50,000 — https://kf.qq.com/faq/161220AVNfeI161220AVvAr6.html.
            // The draft API: title 32; an article's cover cropped 2.35:1 and 1:1 —
            // https://developers.weixin.qq.com/doc/subscription/api/draftbox/draftmanage/api_draft_add.html.
            if title.count > 64 { checks.append("❌ 标题 \(title.count) 个字：公众号标题最多 64 个字") }
            else if title.count > 32 { checks.append("⚠️ 标题 \(title.count) 个字：编辑器收 64 个字，官方草稿接口只收 32 个——32 字以内哪儿都能用") }
            if let summary = input.summary, summary.count > 120 { checks.append("❌ 摘要 \(summary.count) 个字：公众号摘要最多 120 个字") }
            if input.summary?.isEmpty ?? true { checks.append("⚠️ 没写摘要（summary）：不写的话，公众号抓正文前 54 个字当摘要") }
            if input.body.count > 50000 { checks.append("❌ 正文 \(input.body.count) 个字：公众号正文最多 50,000 字") }
            if let cover = cards.first {
                if let size = pixelSize(cover), !(near(size, 2.35, 1) || near(size, 1, 1)) {
                    checks.append("⚠️ 封面 \(cover.lastPathComponent) 是 \(dims(size))：公众号封面裁成 2.35:1（900×383）和 1:1 两块——画成 2.35:1，要紧的字放在正中间的方块里，或者再画一张 1:1")
                }
            } else {
                checks.append("❌ 没有封面：公众号文章要一张封面图（第一张卡片，2.35:1，900×383）")
            }
            if hasLink(input.body) { checks.append("⚠️ 正文里有网址：公众号正文的外部链接受限（Easel 的平台指南），要链出去就放「阅读原文」") }

        case .channels?:
            // 视频号's own help (https://findeross.weixin.qq.com/cgi-bin/mmfindernodelivecrmwebbroker-bin/helper-center/pages/Yhdpjlq2RIkcmnQu,
            // as search engines hold it on 2026-09-28; signed out, the page now renders
            // empty): a description of up to 1,000 characters; width over height
            // 0.33–3.0, 16:9 or 9:16 best; 3 s to 60 min from a phone, 8 h from a computer.
            if pasted.count > 1000 { checks.append("❌ 描述 \(pasted.count) 个字：视频号描述最多 1,000 字（含话题）") }
            if let size = input.videoSize {
                let ratio = size.width / max(1, size.height)
                if ratio < 0.33 || ratio > 3.0 { checks.append("❌ 视频 \(dims(size))：视频号只收宽高比 0.33–3.0 的视频") }
                else if !(near(size, 9, 16) || near(size, 16, 9)) { checks.append("⚠️ 视频 \(dims(size))：视频号建议 9:16 或 16:9") }
            }
            if let seconds = input.videoSeconds, seconds < 3 { checks.append("❌ 视频只有 \(minutes(seconds))：视频号最短 3 秒") }

        case .moments?:
            // Nine pictures; ten to twenty are made into a video (WeChat 8.0.18:
            // https://news.qq.com/rain/a/20220126A0AWB700). Videos up to 5 minutes, rolled
            // out from March 2025; 30 s before (https://news.qq.com/rain/a/20250310A05PJ800).
            if cards.count > 9 { checks.append("❌ \(cards.count) 张图：朋友圈一次最多 9 张（选 9 张以上会被做成一段视频）") }
            if video, !cards.isEmpty { checks.append("⚠️ 又有视频又有图：朋友圈一条是一段视频或一组图") }
            if let seconds = input.videoSeconds, seconds > 300 { checks.append("❌ 视频 \(minutes(seconds)) 长：朋友圈视频最长 5 分钟") }
            else if let seconds = input.videoSeconds, seconds > 30 { checks.append("⚠️ 视频 \(minutes(seconds)) 长：朋友圈 30 秒以上的视频要新版微信（2025 年 3 月起逐步放到 5 分钟）") }
            if !input.tags.isEmpty { checks.append("⚠️ 朋友圈没有话题：# 只会当成普通的字") }
            if cards.count > 1 {
                for (card, size) in sized where !near(size, 1, 1) {
                    checks.append("⚠️ \(card.lastPathComponent) 是 \(dims(size))：朋友圈多图排成九宫格、裁成方块，边上会被裁掉——用 1:1（1080×1080）")
                }
            }

        default:
            break
        }
        // How many tags suit each, from Easel's guide (social-content/references/
        // platform-specs.md); TikTok, X, Shorts and 朋友圈 are said above, and
        // where nobody says (公众号, 知乎, 视频号) nothing is said.
        let tagRange: ClosedRange<Int>?
        switch known {
        case .xiaohongshu?: tagRange = 5...10
        case .douyin?: tagRange = 3...5
        case .bilibili?: tagRange = 4...10
        case .weibo?: tagRange = 1...3
        case .tiktok?, .x?, .shorts?, .moments?, .wechatArticle?, .zhihu?, .channels?: tagRange = nil
        default: tagRange = 3...10
        }
        if let tagRange {
            if tagCount == 0 { checks.append("⚠️ 没有话题标签（\(platform) \(tagRange.lowerBound)–\(tagRange.upperBound) 个合适）") }
            else if !tagRange.contains(tagCount) { checks.append("⚠️ \(tagCount) 个话题：\(platform) \(tagRange.lowerBound)–\(tagRange.upperBound) 个合适") }
        }
        if let size = input.videoSize {
            measured.append("✅ 量了视频：\(dims(size))" + (input.videoSeconds.map { " · \(minutes($0))" } ?? ""))
        }
        // What social_card's audit said of each card, where it drew one.
        for card in cards {
            let audit = card.deletingPathExtension().appendingPathExtension("audit.json")
            guard let data = try? Data(contentsOf: audit),
                  let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  said["passed"] as? Bool == false else { continue }
            let first = (said["problems"] as? [String])?.first ?? ""
            checks.append("❌ cards/\(card.lastPathComponent) 的审查没过：\(first)（social_card 改好再换进来）")
        }
        let all = ([input.body, input.summary ?? ""] + input.titleOptions).joined(separator: "\n")
        // For the English words: any case, and a curly apostrophe read as a straight one.
        let lower = all.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        func found(_ words: [String]) -> [String] { words.filter { lower.contains($0.lowercased()) } }
        let hasNumbers = all.range(of: #"\d"#, options: .regularExpression) != nil
        if hasNumbers, input.sources.isEmpty { checks.append("❌ 文案里有数字，但没有出处：每个事实都要写进 sources（来源 + 日期）") }
        let offsite = ["微信", "vx", "VX", "wx", "二维码", "加群", "私信我", "http://", "https://", "淘宝", "拼多多", "京东"]
            .filter { all.contains($0) }
        if known == .xiaohongshu, !offsite.isEmpty { checks.append("⚠️ 有导流外站的字眼（\(offsite.joined(separator: "、"))）：小红书会限流甚至处罚") }
        let absolute = found(["顶级", "国家级", "100%", "史上最", "全网最", "万能", "闭眼入", "买它", "绝对是",
                              "guaranteed", "miracle", "risk-free", "best ever"])
        if !absolute.isEmpty { checks.append("⚠️ 绝对化 / 营销腔用语（\(absolute.joined(separator: "、"))）：广告法和各平台都敏感，换掉") }
        let doom = found(["末日", "吓死", "震惊", "细思极恐", "要完了",
                          "you won't believe", "shocking", "terrifying", "doomed", "end of the world", "apocalypse"])
        if !doom.isEmpty { checks.append("⚠️ 吓人的字眼（\(doom.joined(separator: "、"))）：不写末日、不制造焦虑，不做标题党") }
        let slop = found(["值得注意的是", "总而言之", "综上所述", "不得不说", "毫无疑问", "众所周知", "让我们一起", "在当今",
                          "delve", "in today's fast-paced", "it's worth noting", "it is worth noting", "in conclusion",
                          "game-changer", "game changer", "unlock the power", "let's dive in", "dive into", "a testament to",
                          "tapestry", "ever-evolving", "embark on", "in the realm of"])
        if !slop.isEmpty { checks.append("⚠️ AI 味套话（\(slop.joined(separator: "、"))）：删掉或改成人话") }
        if checks.isEmpty { checks.append("✅ 能查的都过了：长度、图和视频、话题、出处、导流、用语") }
        return checks + measured
    }

    /// A picture's size in pixels, from its file's header.
    nonisolated static func pixelSize(_ file: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Within 2% of the ratio a:b (width to height).
    nonisolated static func near(_ size: CGSize, _ a: Double, _ b: Double) -> Bool {
        size.height > 0 && abs((size.width / size.height) / (a / b) - 1) < 0.02
    }

    nonisolated static func ratioKey(_ size: CGSize) -> String { String(format: "%.2f", size.width / max(1, size.height)) }

    nonisolated static func minutes(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The hashtags written into a text itself: # and the letters and digits after it.
    nonisolated static func hashtags(in text: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: #"#[\p{L}\p{N}_]+"#) else { return [] }
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// The web addresses in a text, as a platform would link them — with
    /// http(s):// or without (localkin.ai); an e-mail address is not one.
    nonisolated static func links(in text: String) -> [NSRange] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .filter { ["http", "https"].contains($0.url?.scheme?.lowercased() ?? "") }
            .map(\.range)
    }

    nonisolated static func hasLink(_ text: String) -> Bool { !links(in: text).isEmpty }

    /// A post's length as X counts it against its 280 — twitter-text's
    /// config v3 (https://github.com/twitter/twitter-text/blob/master/config/v3.json;
    /// https://docs.x.com/fundamentals/counting-characters): the text NFC-normalized,
    /// code points in U+0000–U+10FF, U+2000–U+200D, U+2010–U+201F and
    /// U+2032–U+2037 weigh 1 and every other one 2 (Chinese, Japanese and
    /// Korean among them); an emoji weighs 2 whatever it is made of, and a link
    /// 23, however long, because t.co wraps it.
    nonisolated static func xLength(_ text: String) -> Int {
        let text = text.precomposedStringWithCanonicalMapping
        let ns = text as NSString
        var total = 0, cursor = 0
        var plain = ""
        for range in links(in: text) where range.location >= cursor {
            plain += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            total += 23
            cursor = range.location + range.length
        }
        plain += ns.substring(from: cursor)
        for character in plain {
            let scalars = character.unicodeScalars
            if let first = scalars.first, first.properties.isEmojiPresentation || (first.properties.isEmoji && scalars.count > 1) {
                total += 2
                continue
            }
            for scalar in scalars {
                let v = scalar.value
                let light = v <= 0x10FF || (0x2000...0x200D).contains(v) || (0x2010...0x201F).contains(v) || (0x2032...0x2037).contains(v)
                total += light ? 1 : 2
            }
        }
        return total
    }

    // MARK: Profiles

    /// An account's folder: made from Easel's template (its six files) the
    /// first time.
    func createProfile(_ account: String) -> Result<URL, SocialFailure> {
        guard let name = Self.safeName(account) else { return .failure(SocialFailure("账号名不能有 / 或 .. ，也不能空")) }
        let files = FileManager.default
        let folder = Self.profilesFolder.appendingPathComponent(name)
        guard !files.fileExists(atPath: folder.path) else { return .failure(SocialFailure("已经有这个账号了：\(folder.path)")) }
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let template = Self.guides.appendingPathComponent("profiles/_template")
            for file in Self.profileFiles {
                let from = template.appendingPathComponent(file + ".md")
                let to = folder.appendingPathComponent(file + ".md")
                if files.fileExists(atPath: from.path) { try files.copyItem(at: from, to: to) }
                else { try "# \(file)\n\n".write(to: to, atomically: true, encoding: .utf8) }
            }
            reload()
            return .success(folder)
        } catch {
            return .failure(SocialFailure("建不了：\(error.localizedDescription)"))
        }
    }

    /// One of an account's six files, the old one moved aside first.
    func writeProfile(_ account: String, file: String, text: String) -> Result<URL, SocialFailure> {
        guard let name = Self.safeName(account) else { return .failure(SocialFailure("账号名不对：\(account)")) }
        let base = file.hasSuffix(".md") ? String(file.dropLast(3)) : file
        guard Self.profileFiles.contains(base) else {
            return .failure(SocialFailure("file 是 " + Self.profileFiles.joined(separator: " / ") + " 之一"))
        }
        let files = FileManager.default
        let folder = Self.profilesFolder.appendingPathComponent(name)
        guard files.fileExists(atPath: folder.path) else { return .failure(SocialFailure("没有这个账号：\(name)（先 action create）")) }
        let target = folder.appendingPathComponent(base + ".md")
        do {
            if files.fileExists(atPath: target.path) {
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyyMMdd-HHmmss"
                let aside = folder.appendingPathComponent(".previous")
                try files.createDirectory(at: aside, withIntermediateDirectories: true)
                let when = stamp.string(from: Date())
                var kept = aside.appendingPathComponent("\(base)-\(when).md")
                var n = 2
                while files.fileExists(atPath: kept.path) { kept = aside.appendingPathComponent("\(base)-\(when)-\(n).md"); n += 1 }
                try files.moveItem(at: target, to: kept)
            }
            try text.write(to: target, atomically: true, encoding: .utf8)
            return .success(target)
        } catch {
            return .failure(SocialFailure("写不了：\(error.localizedDescription)"))
        }
    }

    nonisolated static func safeName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."), !name.hasPrefix("."), !name.hasPrefix("_") else { return nil }
        return name
    }

    // MARK: Cards and pages

    /// A card drawn and checked: see `SocialCard`.
    func card(html: String, css: String?, size: CGSize, name: String?, smallest: Double) async -> Result<SocialCard.Result, SocialFailure> {
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        let clock = DateFormatter()
        clock.dateFormat = "HHmmss"
        let label = name.map(Self.slug) ?? "card"
        let file = Self.cardsFolder.appendingPathComponent(day.string(from: Date()))
            .appendingPathComponent("\(clock.string(from: Date()))-\(label).png")
        working = "在画卡片 \(label)"
        defer { working = nil }
        do {
            let result = try await SocialCard.render(html: html, css: css, size: size, to: file, access: CompanionArt.folder, smallest: smallest)
            return .success(result)
        } catch {
            return .failure(SocialFailure(error.localizedDescription))
        }
    }

    struct Page {
        let title: String
        let text: String
        let picture: URL
        let read: Date
    }

    /// A public page read off-screen, signed in to nothing: its title, its
    /// text as the page shows it, and a picture of it from `top` down.
    func page(_ url: URL, size: CGSize, top: Double, wait: Double) async -> Result<Page, SocialFailure> {
        guard url.scheme == "https" || url.scheme == "http" else { return .failure(SocialFailure("只读 http(s) 网页")) }
        working = "在读 \(url.host ?? url.absoluteString)"
        defer { working = nil }
        let page = OffscreenPage(size: size)
        do {
            try await page.load(url: url)
            await page.settle(most: 10, extra: wait)
            if top > 0 { _ = try? await page.js("window.scrollTo(0, y); return 'ok'", ["y": top]) }
            let title = (try? await page.js("return document.title || ''")) ?? ""
            let text = (try? await page.js("return document.body ? document.body.innerText : ''")) ?? ""
            let picture = try await page.snapshot()
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss"
            let file = Self.capturesFolder.appendingPathComponent("\(stamp.string(from: Date()))-\(Self.slug(url.host ?? "page")).png")
            try OffscreenPage.savePNG(picture, to: file)
            try? text.write(to: file.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            return .success(Page(title: title, text: text, picture: file, read: Date()))
        } catch {
            return .failure(SocialFailure(error.localizedDescription))
        }
    }

    // MARK: Trends

    func trends(_ sources: [String], limit: Int, geo: String = "US") async -> (boards: [SocialTrends.Board], file: URL?) {
        working = "在读热榜"
        defer { working = nil }
        let boards = await SocialTrends.fetch(sources, limit: limit, geo: geo)
        lastTrends = Date()
        // Kept, so that a fact taken from a list can say which list and when.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let file = Self.trendsFolder.appendingPathComponent(stamp.string(from: Date()) + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: Self.trendsFolder, withIntermediateDirectories: true)
            try encoder.encode(boards).write(to: file)
            return (boards, file)
        } catch {
            return (boards, nil)
        }
    }
}

struct SocialFailure: Error, LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

/// The platforms a draft is written for: the name a draft is saved under
/// (its raw value), what else a person or an agent may call it, where it is
/// posted, and what it takes. Easel's own were the Chinese ones; TikTok, X,
/// YouTube Shorts and WeChat's three places came with the rename ("可以支持
/// tiktok，x，wechat吗，youtube shorts"). A draft for a platform not here is
/// still saved, under the name it was given, and checked only in general.
enum SocialPlatform: String, CaseIterable {
    case xiaohongshu = "小红书"
    case douyin = "抖音"
    case bilibili = "B站"
    case weibo = "微博"
    case zhihu = "知乎"
    case kuaishou = "快手"
    case wechatArticle = "公众号"
    case channels = "视频号"
    case moments = "朋友圈"
    case tiktok = "TikTok"
    case x = "X"
    case shorts = "YouTube Shorts"

    /// The platform a name means, in any case, English or Chinese: "tiktok",
    /// "x", "twitter", "推特", "wechat article", "channels", "moments",
    /// "shorts", "油管短视频", "小红书"… nil for one it does not know.
    static func of(_ name: String) -> SocialPlatform? {
        let bare = name.lowercased().replacingOccurrences(of: #"[\s_\-·•・/|()（）\[\]【】.:：,，]+"#, with: "", options: .regularExpression)
        guard !bare.isEmpty else { return nil }
        // Names too short to look for inside others.
        switch bare {
        case "x", "𝕏", "xcom", "twitter", "xtwitter", "twitterx", "推特": return .x
        case "red", "xhs", "rednote": return .xiaohongshu
        case "mp", "wechat", "weixin", "微信": return .wechatArticle
        case "yt", "youtube", "ytshorts", "油管": return .shorts
        case "b站", "bili": return .bilibili
        default: break
        }
        // Inside a longer name, the more particular first: 抖音国际版 is TikTok
        // before it is 抖音, 微信视频号 is 视频号 before it is 微信.
        let inside: [(SocialPlatform, [String])] = [
            (.tiktok, ["tiktok", "抖音国际版"]),
            (.shorts, ["shorts", "油管短视频", "youtube短视频", "油管", "youtube"]),
            (.x, ["twitter", "推特"]),
            (.channels, ["视频号", "channels"]),
            (.moments, ["朋友圈", "moments"]),
            (.wechatArticle, ["公众号", "公众平台", "订阅号", "服务号", "officialaccount", "wechatarticle", "微信文章", "微信", "wechat", "weixin"]),
            (.xiaohongshu, ["小红书", "xiaohongshu", "rednote", "红书"]),
            (.douyin, ["抖音", "douyin"]),
            (.bilibili, ["bilibili", "哔哩", "b站"]),
            (.weibo, ["微博", "weibo"]),
            (.zhihu, ["知乎", "zhihu"]),
            (.kuaishou, ["快手", "kuaishou"]),
        ]
        return inside.first { $0.1.contains { bare.contains($0) } }?.0
    }

    /// A video is what it posts: a draft for it without one is not ready.
    /// (TikTok takes a video or a set of pictures; checked on its own.)
    var needsVideo: Bool { [.douyin, .bilibili, .kuaishou, .channels, .shorts].contains(self) }

    /// The page the person posts it on, signed in there by themselves.
    var publishPage: URL? {
        let address: String
        switch self {
        case .xiaohongshu: address = "https://creator.xiaohongshu.com/publish/publish"
        case .douyin: address = "https://creator.douyin.com/creator-micro/content/upload"
        case .bilibili: address = "https://member.bilibili.com/platform/upload/video/frame"
        case .weibo: address = "https://weibo.com"
        case .zhihu: address = "https://www.zhihu.com/creator"
        case .kuaishou: address = "https://cp.kuaishou.com/article/publish/video"
        case .wechatArticle: address = "https://mp.weixin.qq.com"
        case .channels: address = "https://channels.weixin.qq.com/platform/post/create"
        case .tiktok: address = "https://www.tiktok.com/tiktokstudio/upload"
        case .x: address = "https://x.com/compose/post"
        // YouTube Studio's upload, for whichever channel the person is signed in to.
        case .shorts: address = "https://www.youtube.com/upload"
        case .moments: return nil
        }
        return URL(string: address)
    }

    /// Why there is no page to open, where there is none.
    var noPage: String? {
        self == .moments ? "朋友圈没有网页版：在手机上的微信里发（新版 Mac 微信也能发朋友圈）" : nil
    }

    /// Its title box: how long a title may be there, where there is a limit
    /// (the numbers and their sources are in `SocialStudio.checks`).
    var titleLimit: Int? {
        switch self {
        case .xiaohongshu: return 20
        case .wechatArticle: return 64
        case .shorts: return 100
        case .tiktok: return 90     // a photo post's; a TikTok video has only its caption
        default: return nil
        }
    }

    /// No title box at all: the title only names the draft.
    var untitled: Bool { [.x, .moments, .weibo].contains(self) }

    /// A text's length as the platform counts it: X weighs it, TikTok counts
    /// UTF-16 units, the rest characters.
    func length(_ text: String) -> Int {
        switch self {
        case .x: return SocialStudio.xLength(text)
        case .tiktok: return text.utf16.count
        default: return text.count
        }
    }

    /// The post's picture on a phone, height over width, when it has no card
    /// of its own to go by.
    var frame: CGFloat {
        switch self {
        case .tiktok, .shorts, .douyin, .kuaishou, .channels: return 16 / 9
        case .x: return 9 / 16
        case .wechatArticle: return 383 / 900
        case .moments: return 1
        default: return 4 / 3
        }
    }
}

/// Public trending lists, read over plain HTTPS with no account: each list
/// from the platform's own public endpoint where there is one that answers
/// without a sign-in, and said plainly when there is not. Measured from this
/// Mac on 2026-09-28: Weibo's own endpoints answer 403 (they want a visitor
/// cookie) — its list comes through v2.xxapi.cn, a third party, and is marked
/// so; Xiaohongshu has no public list at all.
///
/// For TikTok, X and Shorts, what people search: Google Trends' own daily RSS
/// (trends.google.com/trending/rss?geo=US — 200, ten items a country). X's own
/// trends want a sign-in (x.com/explore sends to the login page, its API
/// answers 400), so X's list comes from trends24.in, a third party that
/// publishes X's trends by the hour, and says so. TikTok (Creative Center's
/// lists answer "no permission", 40101, signed out; tiktok.com/discover
/// carries no list in its page), YouTube (the Trending page is gone — signed
/// out, /feed/trending is an empty home page; charts.youtube.com reads its
/// data with an API key, which is not used here) and WeChat (微信指数 and
/// 搜一搜 are inside the app; weixin.sogou.com has only a search box) have no
/// list that answers without a sign-in or a key: each says so, and what to
/// do instead.
enum SocialTrends {
    struct Item: Codable {
        let rank: Int
        let title: String
        let heat: String?
        let url: String?
        let note: String?
    }

    struct Board: Codable {
        let source: String
        let name: String
        /// Where it actually came from.
        let via: String
        let read: Date
        let items: [Item]
        let problem: String?
    }

    static let all = ["weibo", "douyin", "bilibili", "bilibili_search", "baidu", "zhihu", "toutiao", "xiaohongshu",
                      "google_trends", "x", "tiktok", "youtube", "wechat"]
    static let defaults = ["weibo", "douyin", "bilibili", "baidu"]

    /// `geo`: the country for google_trends and x (two letters, as Google
    /// Trends takes them: US, GB, JP…); "google_trends:JP" asks one list for
    /// another.
    static func fetch(_ wanted: [String], limit: Int, geo: String = "US") async -> [Board] {
        let names = wanted.isEmpty ? defaults : wanted.contains("all") ? all : wanted
        return await withTaskGroup(of: (Int, Board).self) { group in
            for (i, name) in names.enumerated() {
                group.addTask { (i, await board(name.lowercased(), limit: limit, geo: geo)) }
            }
            var found: [(Int, Board)] = []
            for await pair in group { found.append(pair) }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// The JSON at an address, or why not: the HTTP status, or what came instead.
    private static func json(_ address: String) async -> Result<Any, SocialFailure> {
        guard let url = URL(string: address) else { return .failure(SocialFailure("地址不对")) }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(SocialFailure(status == 403 || status == 401 || status == 302 ? "HTTP \(status)（要登录或访客 cookie）" : "HTTP \(status)"))
            }
            guard let value = try? JSONSerialization.jsonObject(with: data) else {
                return .failure(SocialFailure(data.isEmpty ? "回了空内容（多半要登录）" : "回的不是 JSON（多半是验证页）"))
            }
            return .success(value)
        } catch {
            return .failure(SocialFailure(error.localizedDescription))
        }
    }

    /// A page or a feed as text, or why not.
    private static func text(_ address: String, accept: String) async -> Result<String, SocialFailure> {
        guard let url = URL(string: address) else { return .failure(SocialFailure("地址不对")) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(SocialFailure(status == 403 || status == 401 ? "HTTP \(status)（要登录，或者不让程序读）" : "HTTP \(status)"))
            }
            guard let page = String(data: data, encoding: .utf8), !page.isEmpty else { return .failure(SocialFailure("回了空内容")) }
            return .success(page)
        } catch {
            return .failure(SocialFailure(error.localizedDescription))
        }
    }

    /// Google Trends' daily RSS for a country: its newest ten rising searches,
    /// with each one's rough number of searches, when it started and a news
    /// story about it. Read 2026-09-28: https://trends.google.com/trending/rss?geo=US
    /// answered 200 with ten items (GB, JP, TW, HK, SG, KR, AU, IN, DE too; CN
    /// is empty — Google has no data there).
    private static func googleTrends(_ geo: String) async -> Result<[Item], SocialFailure> {
        switch await text("https://trends.google.com/trending/rss?geo=\(encoded(geo))", accept: "application/rss+xml, text/xml, */*") {
        case .failure(let failure): return .failure(failure)
        case .success(let feed):
            let reader = TrendsFeedReader()
            let parser = XMLParser(data: Data(feed.utf8))
            parser.delegate = reader
            guard parser.parse() else { return .failure(SocialFailure("RSS 读不懂：\(parser.parserError?.localizedDescription ?? "")")) }
            let posted = DateFormatter()
            posted.locale = Locale(identifier: "en_US_POSIX")
            posted.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let clock = DateFormatter()
            clock.dateFormat = "M月d日 HH:mm"
            // By how many search for it, the newest first among equals.
            let ranked = reader.entries.map { entry -> (entry: TrendsFeedReader.Entry, searches: Int, started: Date?) in
                (entry, Int(entry.traffic.filter(\.isNumber)) ?? 0, posted.date(from: entry.date))
            }.sorted { ($0.searches, $0.started ?? .distantPast) > ($1.searches, $1.started ?? .distantPast) }
            return .success(ranked.enumerated().map { i, row in
                let searches = row.searches >= 10_000 ? "\(row.searches / 10_000) 万+ 次搜索" : row.searches > 0 ? "\(row.searches)+ 次搜索" : nil
                let news = row.entry.newsTitle.isEmpty ? nil
                    : "新闻：\(row.entry.newsTitle)" + (row.entry.newsSource.isEmpty ? "" : "（\(row.entry.newsSource)）")
                let note = [row.started.map { "起于 " + clock.string(from: $0) }, news].compactMap { $0 }.joined(separator: " · ")
                return Item(rank: i + 1, title: row.entry.title, heat: searches,
                            url: row.entry.newsURL.isEmpty ? "https://trends.google.com/trending?geo=\(geo)" : row.entry.newsURL,
                            note: note.isEmpty ? nil : note)
            })
        }
    }

    /// trends24.in's pages by the country codes Google Trends takes: every one
    /// answered 200 on 2026-09-28 (Taiwan and Hong Kong have none: 404).
    private static let trends24: [String: (slug: String, name: String)] = [
        "WW": ("", "全球"), "US": ("united-states", "美国"), "GB": ("united-kingdom", "英国"), "UK": ("united-kingdom", "英国"),
        "JP": ("japan", "日本"), "SG": ("singapore", "新加坡"), "CA": ("canada", "加拿大"), "AU": ("australia", "澳大利亚"),
        "IN": ("india", "印度"), "DE": ("germany", "德国"), "FR": ("france", "法国"), "KR": ("korea", "韩国"),
        "MY": ("malaysia", "马来西亚"), "PH": ("philippines", "菲律宾"), "ID": ("indonesia", "印度尼西亚"),
        "BR": ("brazil", "巴西"), "MX": ("mexico", "墨西哥"),
    ]

    /// X's trends for the latest hour on trends24.in, a third party (X's own
    /// want a sign-in): the first list on its country page is the newest
    /// hour, with the time it was taken.
    private static func xTrends(_ slug: String) async -> Result<(items: [Item], taken: Date?), SocialFailure> {
        switch await text("https://trends24.in/\(slug.isEmpty ? "" : slug + "/")", accept: "text/html") {
        case .failure(let failure): return .failure(failure)
        case .success(let page):
            let block = #"<h3[^>]*data-timestamp="?([0-9.]+)"?[^>]*>.*?</h3>\s*<ol[^>]*trend-card__list[^>]*>(.*?)</ol>"#
            guard let list = try? NSRegularExpression(pattern: block, options: [.dotMatchesLineSeparators]),
                  let items = try? NSRegularExpression(pattern: #"class="?trend-link"?[^>]*>([^<]*)</a>(?:\s*<span[^>]*data-count="?([0-9]*))?"#),
                  let found = list.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
                  let stamp = Range(found.range(at: 1), in: page), let body = Range(found.range(at: 2), in: page) else {
                return .failure(SocialFailure("trends24.in 的页面变了，找不到榜单"))
            }
            let html = String(page[body])
            let taken = Double(page[stamp]).map { Date(timeIntervalSince1970: $0) }
            let rows = items.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match -> (String, String?)? in
                guard let name = Range(match.range(at: 1), in: html) else { return nil }
                let count = Range(match.range(at: 2), in: html).map { String(html[$0]) }
                return (unescaped(String(html[name])).trimmingCharacters(in: .whitespaces), count?.isEmpty == false ? count : nil)
            }.filter { !$0.0.isEmpty }
            return .success((rows.enumerated().map { i, row in
                Item(rank: i + 1, title: row.0, heat: heat(row.1).map { "\($0) 帖" },
                     url: "https://x.com/search?q=\(encoded(row.0))", note: nil)
            }, taken))
        }
    }

    /// &amp;, &quot;, &#39;, &#x2F;… as the characters they stand for.
    private static func unescaped(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        if let numeric = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            for match in numeric.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 2), in: out) else { continue }
                let hex = match.range(at: 1).length > 0
                if let value = UInt32(out[digits], radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    out.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        for (entity, character) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        return out
    }

    private static func heat(_ value: Any?) -> String? {
        guard let value else { return nil }
        let number: Double? = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap { Double($0) }
        guard let number else { return (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        if number >= 100_000_000 { return String(format: "%.2f 亿", number / 100_000_000) }
        if number >= 10_000 { return String(format: "%.1f 万", number / 10_000) }
        return String(Int(number))
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private static func board(_ name: String, limit: Int, geo: String) async -> Board {
        let now = Date()
        func made(_ title: String, _ via: String, _ items: [Item]) -> Board {
            Board(source: name, name: title, via: via, read: now, items: Array(items.prefix(limit)),
                  problem: items.isEmpty ? "回了，但一条也没有" : nil)
        }
        func failed(_ title: String, _ via: String, _ why: String) -> Board {
            Board(source: name, name: title, via: via, read: now, items: [], problem: why)
        }
        // "google_trends:JP": one list for another country than `geo`.
        let parts = name.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        let region = (parts.count > 1 && !parts[1].isEmpty ? parts[1] : geo).uppercased()
        switch parts.first ?? name {
        case "google_trends", "google", "googletrends", "谷歌趋势":
            switch await googleTrends(region) {
            case .success(let items) where !items.isEmpty:
                return made("Google 搜索趋势 · \(region)", "trends.google.com/trending/rss?geo=\(region)（Google 官方 RSS：最近开始上升的搜索，最多 10 条，按搜索量排）", items)
            case .success:
                return failed("Google 搜索趋势 · \(region)", "trends.google.com", "这个地区（\(region)）没有数据：geo 用两个字母的国家代码，如 US、GB、JP、SG、TW、HK；中国大陆没有 Google 的数据")
            // A country it has no list for is answered 400 (CN, on 2026-09-28).
            case .failure(let failure) where failure.text.hasPrefix("HTTP 400") || failure.text.hasPrefix("HTTP 404"):
                return failed("Google 搜索趋势 · \(region)", "trends.google.com", "这个地区（\(region)）没有数据（Google 回 \(failure.text)）：geo 用两个字母的国家代码，如 US、GB、JP、SG、TW、HK；中国大陆没有 Google 的数据")
            case .failure(let failure):
                return failed("Google 搜索趋势 · \(region)", "trends.google.com", failure.text)
            }
        case "x", "twitter", "推特":
            let known = trends24[region] ?? (["GLOBAL", "WORLD", "WORLDWIDE", "ALL", ""].contains(region) ? trends24["WW"] : nil)
            let page = known ?? trends24["WW"]!
            let aside = known == nil ? "；trends24.in 没有 \(region) 的页面，读的是全球" : ""
            switch await xTrends(page.slug) {
            case .success(let found):
                let clock = DateFormatter()
                clock.dateFormat = "M月d日 HH:mm"
                let hour = found.taken.map { "X 在 \(clock.string(from: $0)) 那一小时的趋势" } ?? "X 最近一小时的趋势"
                return made("X 趋势 · \(page.name)", "trends24.in/\(page.slug) 转述（第三方：\(hour)；X 自己的趋势不登录看不到\(aside)）", found.items)
            case .failure(let failure):
                return failed("X 趋势 · \(page.name)", "trends24.in（第三方）", "X 自己的趋势要登录（x.com/explore 会跳到登录页）；第三方 trends24.in 也没拿到：\(failure.text)")
            }
        case "tiktok":
            return failed("TikTok", "—", "TikTok 没有不登录就能读的公开榜：Creative Center 的热门话题、歌曲接口不登录只回 no permission（40101），tiktok.com/discover 的页面里也没有榜单（2026-09-28 在这台 Mac 上试过）。要看 TikTok 上在火什么：google_trends 看大家在搜什么、x 看 X 上在聊什么；或者请对方在 TikTok App 的搜索和 Discover 里看，或自己登录 TikTok Creative Center 看")
        case "youtube", "youtube_shorts", "shorts":
            return failed("YouTube", "—", "YouTube 没有不登录、不用 API key 就能读的热门榜：Trending 页已经没有了（不登录打开 youtube.com/feed/trending 只是一页空的首页），charts.youtube.com 的数据要带页面里的 API key 去调接口——这里不用任何 key。要看 Shorts 上在火什么：google_trends 看大家在搜什么；或者请对方在 YouTube Studio 数据分析的「研究」（Research）里看（要登录）")
        case "wechat", "weixin", "微信", "公众号", "视频号", "朋友圈":
            return failed("微信", "—", "微信没有不登录就能读的公开热榜：微信指数、搜一搜的热点都在微信 App 里，要登录；搜狗微信（weixin.sogou.com）的首页现在只剩一个搜索框。写公众号、视频号、朋友圈：从微博、百度、头条、抖音的榜推（读者是同一群人），或者请对方在微信「搜一搜」里看热点")
        default:
            break
        }
        switch name {
        case "weibo":
            // Its own first; it wants a visitor cookie, which an app does not collect for it.
            let own = await json("https://weibo.com/ajax/side/hotSearch")
            if case .success(let value) = own,
               let list = ((value as? [String: Any])?["data"] as? [String: Any])?["realtime"] as? [[String: Any]], !list.isEmpty {
                return made("微博热搜", "weibo.com/ajax/side/hotSearch（官方）", list.enumerated().compactMap { i, row in
                    guard let word = row["word"] as? String else { return nil }
                    return Item(rank: i + 1, title: word, heat: heat(row["num"]), url: "https://s.weibo.com/weibo?q=\(encoded("#\(word)#"))",
                                note: row["label_name"] as? String)
                })
            }
            let why: String
            if case .failure(let failure) = own { why = failure.text } else { why = "格式不认识" }
            switch await json("https://v2.xxapi.cn/api/weibohot") {
            case .success(let value):
                let list = (value as? [String: Any])?["data"] as? [[String: Any]] ?? []
                return made("微博热搜", "v2.xxapi.cn 转述（第三方：weibo.com 自己的接口 \(why)）", list.enumerated().compactMap { i, row in
                    guard let title = row["title"] as? String else { return nil }
                    return Item(rank: FilmTools.int(row["index"]) ?? i + 1, title: title, heat: heat(row["hot"]), url: row["url"] as? String, note: nil)
                })
            case .failure(let failure):
                return failed("微博热搜", "weibo.com；v2.xxapi.cn", "官方接口 \(why)；第三方 v2.xxapi.cn 也没拿到：\(failure.text)")
            }
        case "douyin":
            switch await json("https://www.iesdouyin.com/web/api/v2/hotsearch/billboard/word/") {
            case .success(let value):
                let root = value as? [String: Any]
                let list = root?["word_list"] as? [[String: Any]] ?? []
                let at = (root?["active_time"] as? String).map { "，榜单时间 \($0)（北京时间）" } ?? ""
                return made("抖音热榜", "iesdouyin.com 热搜榜（官方公开接口\(at)）", list.enumerated().compactMap { i, row in
                    guard let word = row["word"] as? String else { return nil }
                    return Item(rank: i + 1, title: word, heat: heat(row["hot_value"]),
                                url: "https://www.douyin.com/search/\(encoded(word))", note: nil)
                })
            case .failure(let failure):
                return failed("抖音热榜", "iesdouyin.com", failure.text)
            }
        case "bilibili":
            switch await json("https://api.bilibili.com/x/web-interface/popular?ps=\(min(50, max(10, limit)))&pn=1") {
            case .success(let value):
                let list = ((value as? [String: Any])?["data"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
                return made("B站综合热门（视频）", "api.bilibili.com/x/web-interface/popular（官方）", list.enumerated().compactMap { i, row in
                    guard let title = row["title"] as? String else { return nil }
                    let stat = row["stat"] as? [String: Any]
                    let owner = (row["owner"] as? [String: Any])?["name"] as? String
                    let reason = (row["rcmd_reason"] as? [String: Any])?["content"] as? String
                    return Item(rank: i + 1, title: title, heat: heat(stat?["view"]).map { "播放 \($0)" },
                                url: (row["bvid"] as? String).map { "https://www.bilibili.com/video/\($0)" },
                                note: [owner.map { "UP 主 \($0)" }, reason].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                })
            case .failure(let failure):
                return failed("B站综合热门", "api.bilibili.com", failure.text)
            }
        case "bilibili_search":
            switch await json("https://api.bilibili.com/x/web-interface/wbi/search/square?limit=\(min(50, max(10, limit)))") {
            case .success(let value):
                let trending = (((value as? [String: Any])?["data"] as? [String: Any])?["trending"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
                return made("B站热搜", "api.bilibili.com 搜索热词（官方）", trending.enumerated().compactMap { i, row in
                    guard let word = (row["show_name"] as? String) ?? (row["keyword"] as? String) else { return nil }
                    return Item(rank: i + 1, title: word, heat: heat(row["heat_score"]),
                                url: "https://search.bilibili.com/all?keyword=\(encoded(row["keyword"] as? String ?? word))", note: nil)
                })
            case .failure(let failure):
                return failed("B站热搜", "api.bilibili.com", failure.text)
            }
        case "baidu":
            switch await json("https://top.baidu.com/api/board?platform=pc&tab=realtime") {
            case .success(let value):
                let cards = ((value as? [String: Any])?["data"] as? [String: Any])?["cards"] as? [[String: Any]] ?? []
                var rows = cards.first?["content"] as? [[String: Any]] ?? []
                if let nested = rows.first?["content"] as? [[String: Any]] { rows = nested }
                return made("百度实时热搜", "top.baidu.com/api/board（官方）", rows.enumerated().compactMap { i, row in
                    guard let word = (row["word"] as? String) ?? (row["query"] as? String) else { return nil }
                    let desc = (row["desc"] as? String).map { String($0.prefix(60)) }
                    return Item(rank: i + 1, title: word, heat: heat(row["hotScore"]), url: row["url"] as? String,
                                note: desc?.isEmpty == false ? desc : nil)
                })
            case .failure(let failure):
                return failed("百度实时热搜", "top.baidu.com", failure.text)
            }
        case "zhihu":
            switch await json("https://api.zhihu.com/topstory/hot-lists/total?limit=50") {
            case .success(let value):
                let list = (value as? [String: Any])?["data"] as? [[String: Any]] ?? []
                return made("知乎热榜", "api.zhihu.com 热榜（官方）", list.enumerated().compactMap { i, row in
                    let target = row["target"] as? [String: Any]
                    guard let title = target?["title"] as? String else { return nil }
                    let id = target?["id"].map { "\($0)" }
                    return Item(rank: i + 1, title: title, heat: row["detail_text"] as? String,
                                url: id.map { "https://www.zhihu.com/question/\($0)" }, note: nil)
                })
            case .failure(let failure):
                return failed("知乎热榜", "api.zhihu.com", failure.text)
            }
        case "toutiao":
            switch await json("https://www.toutiao.com/hot-event/hot-board/?origin=toutiao_pc") {
            case .success(let value):
                let list = (value as? [String: Any])?["data"] as? [[String: Any]] ?? []
                return made("今日头条热榜", "toutiao.com 热榜（官方）", list.enumerated().compactMap { i, row in
                    guard let title = row["Title"] as? String else { return nil }
                    let link = (row["Url"] as? String).map { $0.components(separatedBy: "?").first ?? $0 }
                    return Item(rank: i + 1, title: title, heat: heat(row["HotValue"]), url: link, note: nil)
                })
            case .failure(let failure):
                return failed("今日头条热榜", "toutiao.com", failure.text)
            }
        case "xiaohongshu", "rednote", "xhs":
            return failed("小红书", "—", "小红书没有不登录就能读的公开热榜（热点在 App 里，要登录）。要看小红书在火什么：请对方在 App 里看，或者从微博、抖音、百度的榜推")
        default:
            return failed(name, "—", "不认识这个来源：可以用 " + all.joined(separator: "、"))
        }
    }
}

/// Google Trends' RSS, item by item: the title, ht:approx_traffic, pubDate,
/// and the first ht:news_item's title, address and source.
private final class TrendsFeedReader: NSObject, XMLParserDelegate {
    struct Entry {
        var title = "", traffic = "", date = ""
        var newsTitle = "", newsURL = "", newsSource = ""
    }

    private(set) var entries: [Entry] = []
    private var current: Entry?
    private var text = ""
    private var inNews = false
    private var newsDone = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "item" { current = Entry(); newsDone = false }
        if elementName == "ht:news_item" { inNews = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { text = "" }
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title" where !inNews: current?.title = value
        case "ht:approx_traffic": current?.traffic = value
        case "pubDate": current?.date = value
        case "ht:news_item_title" where !newsDone: current?.newsTitle = value
        case "ht:news_item_url" where !newsDone: current?.newsURL = value
        case "ht:news_item_source" where !newsDone: current?.newsSource = value
        case "ht:news_item":
            inNews = false
            newsDone = true
        case "item":
            if let current, !current.title.isEmpty { entries.append(current) }
            current = nil
        default:
            break
        }
    }
}

/// The Easel tab's tools, for its agent and the kernel.
@MainActor
enum SocialTools {
    static func call(_ name: String, _ args: [String: Any]) async -> (String, Bool) {
        let studio = SocialStudio.shared
        switch name {
        case "social_status":
            studio.reload()
            let drafts = SocialStudio.scan(SocialStudio.draftsFolder, legacy: false).sorted { $0.created > $1.created }
            let legacy = SocialStudio.scan(SocialStudio.easelFolder, legacy: true)
            let accounts = SocialStudio.accounts(in: SocialStudio.profilesFolder)
            var lines = ["Easel 标签（\(SocialStudio.root.path)）：只做草稿，发布由人自己在平台上点；这个 app 不登录、不发帖。",
                         "平台：" + SocialPlatform.allCases.map(\.rawValue).joined(separator: "、")]
            if let working = studio.working { lines.append("正在：\(working)") }
            lines.append("账号画像：" + (accounts.isEmpty ? "还没有（social_profile action create）" : accounts.joined(separator: "、")))
            lines.append("草稿 \(drafts.count) 份" + (legacy.isEmpty ? "" : "，另有原版 Easel（OpenClaw）跑出来的旧草稿 \(legacy.count) 份（只读）") + "：")
            lines += (drafts + legacy).prefix(6).map(draftLine)
            if let last = studio.lastTrends { lines.append("上次读热榜：\(time(last))") }
            let guides = FileManager.default.fileExists(atPath: SocialStudio.guides.path)
            lines.append("指南：" + (guides ? "\(SocialStudio.guides.path)（Easel，Apache-2.0）" : "没找到 guides/easel"))
            return (lines.joined(separator: "\n"), false)

        case "social_profile":
            let action = (args["action"] as? String ?? "list").lowercased()
            let account = (args["account"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch action {
            case "list":
                let accounts = SocialStudio.accounts(in: SocialStudio.profilesFolder)
                if accounts.isEmpty { return ("还没有账号画像。action create 建一个（Easel 模板的六个文件：\(SocialStudio.profileFiles.joined(separator: "、"))）", false) }
                return (accounts.map { "· \($0)（\(SocialStudio.profilesFolder.appendingPathComponent($0).path)）" }.joined(separator: "\n"), false)
            case "create":
                switch studio.createProfile(account) {
                case .success(let folder):
                    return ("建好了：\(folder.path)，六个文件是 Easel 的模板（\(SocialStudio.profileFiles.joined(separator: "、"))）。和对方一起填，用 action write 写回", false)
                case .failure(let failure): return (failure.text, true)
                }
            case "read":
                guard let name = SocialStudio.safeName(account) else { return ("要 account", true) }
                let folder = SocialStudio.profilesFolder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: folder.path) else { return ("没有这个账号：\(name)", true) }
                let wanted = (args["file"] as? String).map { $0.hasSuffix(".md") ? String($0.dropLast(3)) : $0 }
                let names = wanted.map { [$0] } ?? SocialStudio.profileFiles
                let parts = names.map { file -> String in
                    let text = (try? String(contentsOf: folder.appendingPathComponent(file + ".md"), encoding: .utf8)) ?? "（没有这个文件）"
                    return "=== \(file).md ===\n" + text
                }
                return (parts.joined(separator: "\n\n"), false)
            case "write":
                guard let file = args["file"] as? String, let text = args["text"] as? String else { return ("write 要 account、file 和 text（整个文件的新内容）", true) }
                switch studio.writeProfile(account, file: file, text: text) {
                case .success(let target): return ("写好了：\(target.path)（旧的在 .previous/ 里）", false)
                case .failure(let failure): return (failure.text, true)
                }
            default:
                return ("action 是 list、read、create 或 write", true)
            }

        case "social_trends":
            let sources: [String]
            if let list = args["sources"] as? [Any] { sources = list.map(FilmTools.text) }
            else if let one = args["sources"] as? String { sources = one.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) }
            else { sources = [] }
            let limit = min(50, max(5, FilmTools.int(args["limit"]) ?? 20))
            let geo = (args["geo"] as? String)?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
            let (boards, file) = await studio.trends(sources, limit: limit, geo: geo.isEmpty ? "US" : geo)
            var lines: [String] = []
            for board in boards {
                lines.append("== \(board.name) · 来自 \(board.via) · 读于 \(time(board.read))")
                if let problem = board.problem { lines.append("  没拿到：\(problem)"); continue }
                lines += board.items.map { item in
                    "\(item.rank). \(item.title)" + (item.heat.map { " · \($0)" } ?? "") + (item.note.map { $0.isEmpty ? "" : " · \($0)" } ?? "")
                        + (item.url.map { " · \($0)" } ?? "")
                }
            }
            if let file { lines.append("这次读到的都存在 \(file.path)：引用榜单里的事，出处写它（来源 + 时间）") }
            lines.append("热榜只说明大家在看什么，不是事实本身：用里面的事之前，找到原始出处再写。")
            return (lines.joined(separator: "\n"), false)

        case "social_card":
            guard let html = args["html"] as? String, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ("social_card 要 html：一张卡片的 HTML（整页，或只是卡片本身的标签）", true)
            }
            let width = FilmTools.int(args["width"]) ?? 1080, height = FilmTools.int(args["height"]) ?? 1440
            guard (200...4096).contains(width), (200...4096).contains(height) else { return ("width、height 要在 200–4096 之间", true) }
            let smallest = FilmTools.number(args["min_font"]) ?? 24
            switch await studio.card(html: html, css: args["css"] as? String, size: CGSize(width: width, height: height),
                                     name: args["name"] as? String, smallest: smallest) {
            case .failure(let failure): return ("没画成：\(failure.text)", true)
            case .success(let card):
                var lines = ["\(card.file.lastPathComponent) · \(width)×\(height) → \(card.file.path)（HTML 在 \(card.source.lastPathComponent)）"]
                lines.append(card.passed ? "审查：✅ 通过" : "审查：❌ \(card.problems.count) 个问题，改好再放进草稿")
                lines += card.problems.map { "  - " + $0 }
                lines += card.warnings.map { "  ? " + $0 }
                lines.append("  版面：" + card.layout)
                lines.append("image://\(card.file.path)")
                return (lines.joined(separator: "\n"), false)
            }

        case "social_page":
            guard let address = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: address),
                  url.scheme == "https" || url.scheme == "http" else {
                return ("social_page 要 url（http 或 https 的公开网页）", true)
            }
            let width = FilmTools.int(args["width"]) ?? 1080, height = FilmTools.int(args["height"]) ?? 1440
            guard (320...4096).contains(width), (320...8000).contains(height) else { return ("width 320–4096，height 320–8000", true) }
            let chars = min(40000, max(1000, FilmTools.int(args["chars"]) ?? 12000))
            switch await studio.page(url, size: CGSize(width: width, height: height), top: FilmTools.number(args["top"]) ?? 0,
                                     wait: min(10, max(0.5, FilmTools.number(args["wait"]) ?? 2.5))) {
            case .failure(let failure): return ("读不了：\(failure.text)", true)
            case .success(let page):
                let text = page.text.count > chars ? String(page.text.prefix(chars)) + "\n…（还有 \(page.text.count - chars) 字，chars 调大可以多拿）" : page.text
                return (["「\(page.title)」\(address) · 读于 \(time(page.read))（这台 Mac 上，没带任何登录）",
                         "截图：\(page.picture.path)（全文也存在同名 .txt）",
                         "页面上的字：", text,
                         "image://\(page.picture.path)"].joined(separator: "\n"), false)
            }

        case "social_draft":
            var input = SocialStudio.DraftInput()
            // Saved under the platform's own name ("tiktok", "推特", "moments" → TikTok, X, 朋友圈).
            if let platform = (args["platform"] as? String)?.trimmingCharacters(in: .whitespaces), !platform.isEmpty {
                input.platform = SocialPlatform.of(platform)?.rawValue ?? platform
            }
            if let options = args["title_options"] as? [Any] { input.titleOptions = options.map(FilmTools.text).filter { !$0.isEmpty } }
            else if let title = args["title"] as? String { input.titleOptions = [title] }
            if let summary = (args["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty { input.summary = summary }
            input.body = args["body"] as? String ?? ""
            if let tags = args["tags"] as? [Any] { input.tags = tags.map(FilmTools.text).filter { !$0.isEmpty } }
            input.cards = (args["cards"] as? [Any] ?? []).map { URL(fileURLWithPath: (FilmTools.text($0) as NSString).expandingTildeInPath) }
            if let video = (args["video"] as? String)?.trimmingCharacters(in: .whitespaces), !video.isEmpty {
                let file = URL(fileURLWithPath: (video as NSString).expandingTildeInPath)
                input.video = file
                // Measured for the checks: its picture as shown, and its length.
                let asset = AVURLAsset(url: file)
                if let length = try? await asset.load(.duration), length.seconds.isFinite, length.seconds > 0 { input.videoSeconds = length.seconds }
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let picture = try? await track.load(.naturalSize, .preferredTransform) {
                    let shown = picture.0.applying(picture.1)
                    if abs(shown.width) > 0, abs(shown.height) > 0 { input.videoSize = CGSize(width: abs(shown.width), height: abs(shown.height)) }
                }
            }
            input.sources = (args["sources"] as? [[String: Any]] ?? []).compactMap { row in
                guard let fact = row["fact"] as? String, let source = row["source"] as? String else { return nil }
                return SocialStudio.Draft.Source(fact: fact, source: source, url: row["url"] as? String, date: row["date"].map(FilmTools.text))
            }
            input.account = args["account"] as? String
            input.notes = args["notes"] as? String
            input.slug = args["slug"] as? String
            input.replacing = args["draft"] as? String
            switch studio.write(input) {
            case .failure(let failure): return ("没存成：\(failure.text)", true)
            case .success(let (draft, checks)):
                if PanelTools.place == nil || PanelTools.place == "social" {
                    NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "social", "raise": false])
                }
                var lines = ["草稿存好了：\(draft.folder.path)（平台：\(draft.platform)）",
                             "（\(draft.cards.count) 张卡片\(draft.video != nil ? "、一段视频" : "")；Easel 标签里已经选中，像手机上的帖子一样显示）",
                             "自检："] + checks.map { "  " + $0 }
                lines.append(SocialPlatform.of(draft.platform)?.noPage.map { "发布由对方自己点：\($0)。标签里有「复制文案」。" }
                             ?? "发布由对方自己在平台上点（标签里有「复制文案」和「打开发布页」）。")
                if let cover = draft.cards.first { lines.append("image://\(cover.path)") }
                return (lines.joined(separator: "\n"), false)
            }

        case "social_drafts":
            let limit = max(1, FilmTools.int(args["limit"]) ?? 20)
            let drafts = (SocialStudio.scan(SocialStudio.draftsFolder, legacy: false) + SocialStudio.scan(SocialStudio.easelFolder, legacy: true))
                .sorted { $0.created > $1.created }
            if drafts.isEmpty { return ("还没有草稿（\(SocialStudio.draftsFolder.path)）", false) }
            if let wanted = (args["draft"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
                guard let draft = drafts.first(where: { $0.id == wanted || $0.folder.lastPathComponent == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) }) else {
                    return ("没有这份草稿：\(wanted)", true)
                }
                var lines = [draftLine(draft), "标题备选：" + draft.titleOptions.joined(separator: " ｜ ")]
                if let summary = draft.summary { lines.append("摘要：" + summary) }
                lines += ["正文：\n" + draft.body, "话题：" + draft.tags.joined(separator: " ")]
                lines += draft.cards.map { "卡片：\($0.path)" }
                if let video = draft.video { lines.append("视频：\(video.path)") }
                lines += draft.sources.map { "出处：\($0.fact) —— \($0.source)" + ($0.date.map { "，\($0)" } ?? "") + ($0.url.map { "，\($0)" } ?? "") }
                lines += draft.checks.map { "自检：\($0)" }
                lines += draft.cards.prefix(4).map { "image://\($0.path)" }
                return (lines.joined(separator: "\n"), false)
            }
            return (drafts.prefix(limit).map(draftLine).joined(separator: "\n"), false)

        default:
            return ("没有叫 \(name) 的 Easel 工具", true)
        }
    }

    private static func draftLine(_ draft: SocialStudio.Draft) -> String {
        "· \(draft.id) · \(draft.platform) · 「\(draft.title)」 · \(draft.cards.count) 张卡片\(draft.video != nil ? " + 视频" : "")"
            + (draft.legacy ? " · 原版 Easel 的旧草稿（只读）" : "") + " · \(time(draft.created))"
    }

    private static func time(_ date: Date) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm"
        return clock.string(from: date) + " " + (TimeZone.current.abbreviation() ?? "")
    }
}

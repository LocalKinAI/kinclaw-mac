import Foundation

/// Easel's planning layer, made ours: the 选题库, the 内容日历 with the year's
/// festivals and 电商 dates, and 爆款拆解. Jacky, 2026-09-30, after the whole
/// Easel (ZJU-REAL, Apache-2.0) was dug out of the box's Trash: its workbench
/// had what the tab lacked — 「开干吧」 to 拆解 → 选题库 → 日历 → 一稿多发.
///
/// Files beside the drafts, so they survive the app and read in Finder:
/// social/ideas.json, social/calendar.json, social/breakdowns/<id>.json. The
/// agent keeps them with social_ideas, social_calendar and social_breakdown;
/// the tab shows them. Nothing here signs in or posts anywhere: a calendar
/// entry marked 已发 is the person saying so.
extension SocialStudio {
    /// One thing worth making, from wherever it came: a hot list, a 拆解, a
    /// thought. It moves 待做 → 进行中 → 已完成, and onto the calendar.
    struct Idea: Codable, Identifiable, Equatable {
        enum Status: String, Codable, CaseIterable {
            case todo, doing, done
            var title: String {
                switch self { case .todo: return "待做"; case .doing: return "进行中"; case .done: return "已完成" }
            }
            static func of(_ word: String) -> Status? {
                switch word.trimmingCharacters(in: .whitespaces).lowercased() {
                case "todo", "待做", "想做": return .todo
                case "doing", "进行中", "在做": return .doing
                case "done", "已完成", "完成", "做完": return .done
                default: return nil
                }
            }
        }
        var id: String
        var title: String
        var angle: String?
        /// 热榜 · 拆解 · 节日 · 灵感 · 手动 — whatever it came from, in words.
        var source: String?
        var platforms: [String]?
        var status: Status
        var created: Date
        var updated: Date
        /// The 拆解 it was taken from.
        var breakdown: String?
        /// Draft folders made from it.
        var drafts: [String]?
    }

    /// A post planned for a day. The day is a plain date — 2026-10-01 — the
    /// day it goes out wherever the person is.
    struct Planned: Codable, Identifiable, Equatable {
        enum Status: String, Codable, CaseIterable {
            case planned, ready, posted
            var title: String {
                switch self { case .planned: return "计划"; case .ready: return "待发"; case .posted: return "已发" }
            }
            static func of(_ word: String) -> Status? {
                switch word.trimmingCharacters(in: .whitespaces).lowercased() {
                case "planned", "计划", "排了": return .planned
                case "ready", "待发", "做好了": return .ready
                case "posted", "已发", "发了": return .posted
                default: return nil
                }
            }
        }
        var id: String
        var day: String
        var platform: String?
        var title: String
        var status: Status
        var idea: String?
        var draft: String?
        var note: String?
    }

    /// Easel's 爆款拆解: a post someone else made that worked, taken apart —
    /// its hook, how it is built, why it caught on, a template to reuse, and
    /// topics for this account.
    struct Breakdown: Codable, Identifiable, Equatable {
        var id: String
        var created: Date
        var platform: String?
        /// A link, or where it was seen.
        var source: String?
        /// The post as it was pasted.
        var text: String
        var hook: String
        var structure: [String]
        var why: [String]
        var template: String
        var topics: [String]
    }

    static var ideasFile: URL { root.appendingPathComponent("ideas.json") }
    static var calendarFile: URL { root.appendingPathComponent("calendar.json") }
    static var breakdownsFolder: URL { root.appendingPathComponent("breakdowns") }

    func reloadPlan() {
        ideas = Self.readJSON([Idea].self, Self.ideasFile) ?? []
        planned = (Self.readJSON([Planned].self, Self.calendarFile) ?? []).sorted { $0.day < $1.day }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.breakdownsFolder, includingPropertiesForKeys: nil)) ?? []
        breakdowns = files.filter { $0.pathExtension == "json" }
            .compactMap { Self.readJSON(Breakdown.self, $0) }
            .sorted { $0.created > $1.created }
    }

    // MARK: 选题库

    @discardableResult
    func addIdea(_ title: String, angle: String? = nil, source: String? = nil, platforms: [String]? = nil,
                 breakdown: String? = nil) -> Idea {
        let now = Date()
        let idea = Idea(id: Self.newID(), title: title, angle: Self.blank(angle), source: Self.blank(source),
                        platforms: platforms?.isEmpty == true ? nil : platforms, status: .todo, created: now, updated: now,
                        breakdown: breakdown, drafts: nil)
        ideas.insert(idea, at: 0)
        saveIdeas()
        return idea
    }

    func updateIdea(_ id: String, _ change: (inout Idea) -> Void) -> Idea? {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return nil }
        change(&ideas[index])
        ideas[index].updated = Date()
        saveIdeas()
        return ideas[index]
    }

    /// Taken out of the list — kept in ideas-removed.json, not lost.
    func removeIdea(_ id: String) -> Idea? {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return nil }
        let gone = ideas.remove(at: index)
        var kept = Self.readJSON([Idea].self, Self.root.appendingPathComponent("ideas-removed.json")) ?? []
        kept.append(gone)
        Self.writeJSON(kept, Self.root.appendingPathComponent("ideas-removed.json"))
        saveIdeas()
        return gone
    }

    private func saveIdeas() { Self.writeJSON(ideas, Self.ideasFile) }

    // MARK: 内容日历

    @discardableResult
    func plan(day: String, title: String, platform: String? = nil, status: Planned.Status = .planned,
              idea: String? = nil, draft: String? = nil, note: String? = nil) -> Planned {
        let entry = Planned(id: Self.newID(), day: day, platform: Self.blank(platform), title: title, status: status,
                            idea: Self.blank(idea), draft: Self.blank(draft), note: Self.blank(note))
        planned.append(entry)
        planned.sort { $0.day < $1.day }
        savePlanned()
        // An idea put on the calendar is being made.
        if let idea, let index = ideas.firstIndex(where: { $0.id == idea }), ideas[index].status == .todo {
            ideas[index].status = .doing
            ideas[index].updated = Date()
            saveIdeas()
        }
        return entry
    }

    func updatePlanned(_ id: String, _ change: (inout Planned) -> Void) -> Planned? {
        guard let index = planned.firstIndex(where: { $0.id == id }) else { return nil }
        change(&planned[index])
        planned.sort { $0.day < $1.day }
        savePlanned()
        return planned.first { $0.id == id }
    }

    func removePlanned(_ id: String) -> Planned? {
        guard let index = planned.firstIndex(where: { $0.id == id }) else { return nil }
        let gone = planned.remove(at: index)
        savePlanned()
        return gone
    }

    private func savePlanned() { Self.writeJSON(planned, Self.calendarFile) }

    // MARK: 爆款拆解

    /// Keep a 拆解; its topics go into the 选题库 unless told not to.
    func saveBreakdown(_ breakdown: Breakdown, topicsToIdeas: Bool) -> (Breakdown, [Idea]) {
        var kept = breakdown
        if kept.id.isEmpty { kept.id = Self.newID() }
        try? FileManager.default.createDirectory(at: Self.breakdownsFolder, withIntermediateDirectories: true)
        Self.writeJSON(kept, Self.breakdownsFolder.appendingPathComponent(kept.id + ".json"))
        breakdowns.removeAll { $0.id == kept.id }
        breakdowns.insert(kept, at: 0)
        let added = topicsToIdeas ? kept.topics.map { addIdea($0, source: "拆解", platforms: kept.platform.map { [$0] }, breakdown: kept.id) } : []
        return (kept, added)
    }

    // MARK: Files

    static func newID() -> String {
        let clock = DateFormatter()
        clock.dateFormat = "yyyyMMdd-HHmmss"
        return clock.string(from: Date()) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
    }

    private static func blank(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func readJSON<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func writeJSON<T: Encodable>(_ value: T, _ url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - The year's 节点

/// Easel's table of the year — 法定节假日, 传统节日, 国际节日, 电商大促, 行业节点,
/// 考试 (skills/openclaw/skill-event-calendar/references/events-china.md, in
/// the guides) — put on real dates: 公历 as written, 农历 through the system's
/// Chinese calendar (Easel carried lunar.py for that; Foundation has it),
/// "第 N 个周日" counted, 月初 the 1st and 月底 the 25th. A row with a month and
/// no day (高考 in June, 年货节 in January) is that month's theme; a tournament
/// with no date is left out. The file has several tables, each with its own
/// columns, so each is read by its header.
@MainActor
enum SocialEvents {
    struct Event: Identifiable, Equatable {
        let day: Date
        /// The table's own words for when: "农历八月十五", "11.11", "6.14前后".
        let when: String
        let name: String
        let kind: String
        let stars: Int
        let tracks: String
        let platform: String
        let note: String
        var id: String { when + name + String(Int(day.timeIntervalSince1970)) }
        /// The table gives a span or a choice, not a day: "4.4或4.5", "6.14前后", "8月底".
        var rough: Bool {
            // "7月初", not 农历's "九月初九".
            ["或", "前后", "-"].contains { when.contains($0) } || when.wholeMatch(of: #/\d{1,2}月[初底]/#) != nil
        }
    }

    /// A 节点 with a month and no day: the month's theme.
    struct Season: Identifiable, Equatable {
        let months: ClosedRange<Int>
        let when: String
        let name: String
        let kind: String
        let stars: Int
        let tracks: String
        let platform: String
        let note: String
        var id: String { when + name }
    }

    private struct Row { let when, name, kind, tracks, platform, note: String; let stars: Int }

    private static var table: [Row]?
    private static var rows: [Row] {
        if let table { return table }
        let file = SocialStudio.guides.appendingPathComponent("skills/openclaw/skill-event-calendar/references/events-china.md")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var found: [Row] = [], header: [String] = [], section = ""
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") { section = String(line.dropFirst(3)); header = []; continue }
            guard line.hasPrefix("|"), !line.hasPrefix("|--") else { continue }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.contains("节点名称") { header = cells; continue }
            func cell(_ names: String...) -> String {
                for name in names { if let at = header.firstIndex(of: name), at < cells.count { return cells[at] } }
                return ""
            }
            let when = cell("日期", "月份", "时间")
            guard !when.isEmpty else { continue }                   // the tournaments have none
            let kind = cell("类型")
            found.append(Row(when: when, name: cell("节点名称"),
                             kind: !kind.isEmpty ? kind : section.contains("考试") ? "考试" : section.contains("电商") ? "电商大促" : section,
                             tracks: cell("适合赛道"), platform: cell("平台"), note: cell("备注"),
                             stars: cell("蹭点价值").filter { $0 == "★" }.count))
        }
        if !found.isEmpty { table = found }         // the guides may be copied in later
        return found
    }

    /// Every dated 节点 from `start` to `end`, in order.
    static func between(_ start: Date, _ end: Date) -> [Event] {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.component(.year, from: start), last = calendar.component(.year, from: end)
        let from = calendar.startOfDay(for: start)
        return (first...max(first, last)).flatMap(year).filter { $0.day >= from && $0.day <= end }
    }

    /// A year's 节点, worked out once: a 农历 date is found by walking the
    /// year a day at a time, and the calendar page asks for a month on every redraw.
    private static var years: [Int: [Event]] = [:]
    static func year(_ year: Int) -> [Event] {
        if let kept = years[year] { return kept }
        let found = rows.flatMap { row in
            dates(row.when, in: year).map { Event(day: $0, when: row.when, name: row.name, kind: row.kind, stars: row.stars,
                                                   tracks: row.tracks, platform: row.platform, note: row.note) }
        }.sorted { $0.day < $1.day }
        if !rows.isEmpty { years[year] = found }
        return found
    }

    /// The month's themes: rows that name a month ("6月", "7-8月") and no day.
    static func seasons(in month: Int) -> [Season] {
        rows.compactMap { row -> Season? in
            guard let match = row.when.wholeMatch(of: #/(\d{1,2})(?:-(\d{1,2}))?月/#), let first = Int(match.1) else { return nil }
            let last = match.2.flatMap { Int($0) } ?? first
            guard first <= last, (first...last).contains(month) else { return nil }
            return Season(months: first...last, when: row.when, name: row.name, kind: row.kind, stars: row.stars,
                          tracks: row.tracks, platform: row.platform, note: row.note)
        }.sorted { $0.stars > $1.stars }
    }

    private static let lunarMonths = ["正月": 1, "二月": 2, "三月": 3, "四月": 4, "五月": 5, "六月": 6, "七月": 7, "八月": 8,
                                      "九月": 9, "十月": 10, "冬月": 11, "十一月": 11, "腊月": 12, "十二月": 12]

    private static func lunarDay(_ words: String) -> Int? {
        let units = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        if words.hasPrefix("初") { return words.dropFirst().first.flatMap { units[String($0)] } }
        if words == "二十" { return 20 }
        if words == "三十" { return 30 }
        if words.hasPrefix("廿") { return words.dropFirst().first.flatMap { units[String($0)] }.map { 20 + $0 } }
        if words.hasPrefix("十") { return words.dropFirst().first.flatMap { units[String($0)] }.map { 10 + $0 } }
        return nil
    }

    /// The dates in `year` a table entry falls on.
    static func dates(_ when: String, in year: Int) -> [Date] {
        let gregorian = Calendar(identifier: .gregorian)
        func on(_ month: Int, _ day: Int) -> Date? { gregorian.date(from: DateComponents(year: year, month: month, day: day)) }
        if when.hasPrefix("农历") {
            let rest = String(when.dropFirst(2))
            if rest.hasPrefix("除夕") {
                // The day before 正月初一 — the lunar year's last, 29th or 30th.
                return lunar(month: 1, day: 1, in: year).compactMap { gregorian.date(byAdding: .day, value: -1, to: $0) }
            }
            guard let (name, month) = lunarMonths.first(where: { rest.hasPrefix($0.key) }),
                  let day = lunarDay(String(rest.dropFirst(name.count))) else { return [] }
            return lunar(month: month, day: day, in: year)
        }
        let digits = when.replacingOccurrences(of: "前后", with: "")
        // "5.第2个周日", "11月第4个周四"
        if let match = digits.firstMatch(of: #/^(\d{1,2})(?:\.|月)第(\d)个周([日一二三四五六])/#) {
            let weekdays = ["日": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
            guard let month = Int(match.1), let nth = Int(match.2), let weekday = weekdays[String(match.3)] else { return [] }
            return gregorian.date(from: DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: nth)).map { [$0] } ?? []
        }
        // "7月初" the 1st, "8月底" the 25th: a week to plan in before the month is out.
        if let match = digits.wholeMatch(of: #/(\d{1,2})月(初|底)/#), let month = Int(match.1) {
            return on(month, match.2 == "初" ? 1 : 25).map { [$0] } ?? []
        }
        // "1.1", "6.18", "10.1-10.7" (its first day), "4.4或4.5" (the first)
        if let match = digits.firstMatch(of: #/^(\d{1,2})\.(\d{1,2})/#), let month = Int(match.1), let day = Int(match.2) {
            return on(month, day).map { [$0] } ?? []
        }
        return []
    }

    /// Where 农历 month/day falls in a Gregorian year (the month's own, not a leap one).
    private static func lunar(month: Int, day: Int, in year: Int) -> [Date] {
        let gregorian = Calendar(identifier: .gregorian)
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = gregorian.timeZone
        guard var day0 = gregorian.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = gregorian.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return [] }
        var found: [Date] = []
        while day0 < end {
            let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: day0)
            if parts.month == month, parts.day == day, parts.isLeapMonth != true { found.append(day0) }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: day0) else { break }
            day0 = next
        }
        return found
    }
}

// MARK: - The agent's tools

@MainActor
enum SocialPlanTools {
    static func day(_ date: Date) -> String {
        let clock = DateFormatter()
        clock.calendar = Calendar(identifier: .gregorian)
        clock.dateFormat = "yyyy-MM-dd"
        return clock.string(from: date)
    }

    static func date(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let clock = DateFormatter()
        clock.calendar = Calendar(identifier: .gregorian)
        clock.dateFormat = "yyyy-MM-dd"
        return clock.date(from: text)
    }

    static func ideaLine(_ idea: SocialStudio.Idea) -> String {
        var line = "· [\(idea.id)] \(idea.status.title) 「\(idea.title)」"
        if let angle = idea.angle { line += " — \(angle)" }
        if let source = idea.source { line += " · 来自\(source)" }
        if let platforms = idea.platforms, !platforms.isEmpty { line += " · " + platforms.joined(separator: "/") }
        if let drafts = idea.drafts, !drafts.isEmpty { line += " · 草稿 " + drafts.joined(separator: "、") }
        return line
    }

    static func plannedLine(_ entry: SocialStudio.Planned) -> String {
        var line = "· [\(entry.id)] \(entry.day) \(entry.status.title) 「\(entry.title)」"
        if let platform = entry.platform { line += " · \(platform)" }
        if let draft = entry.draft { line += " · 草稿 \(draft)" }
        if let note = entry.note { line += " · \(note)" }
        return line
    }

    static func eventLine(_ event: SocialEvents.Event) -> String {
        "· \(day(event.day)) \(event.name)（\(event.kind)，\(String(repeating: "★", count: event.stars))）"
            + (event.rough ? "（表上写「\(event.when)」）" : "")
            + (event.tracks.isEmpty ? "" : " · 适合：\(event.tracks)") + (event.platform.isEmpty ? "" : " · 平台：\(event.platform)")
            + (event.note.isEmpty ? "" : " · \(event.note)")
    }

    static func seasonLine(_ season: SocialEvents.Season) -> String {
        "· \(season.when) \(season.name)（\(season.kind)，\(String(repeating: "★", count: season.stars))）"
            + (season.tracks.isEmpty ? "" : " · 适合：\(season.tracks)") + (season.platform.isEmpty ? "" : " · 平台：\(season.platform)")
            + (season.note.isEmpty ? "" : " · \(season.note)")
    }

    static func texts(_ value: Any?) -> [String]? {
        if let list = value as? [Any] { return list.map(FilmTools.text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        if let one = value as? String {
            return one.split(whereSeparator: { "、，,\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return nil
    }

    static func call(_ name: String, _ args: [String: Any]) async -> (String, Bool) {
        let studio = SocialStudio.shared
        studio.reloadPlan()
        let action = (args["action"] as? String ?? "list").lowercased()
        switch name {
        case "social_ideas":
            switch action {
            case "add":
                guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    return ("social_ideas add 要 title：这个选题是什么", true)
                }
                let idea = studio.addIdea(title, angle: args["angle"] as? String, source: args["source"] as? String,
                                          platforms: texts(args["platforms"]))
                SocialPage.show(.ideas)
                return ("记进选题库了：\n" + ideaLine(idea), false)
            case "update":
                guard let id = args["id"] as? String else { return ("social_ideas update 要 id（social_ideas list 里的方括号）", true) }
                let status = (args["status"] as? String).flatMap(SocialStudio.Idea.Status.of)
                guard let idea = studio.updateIdea(id, { idea in
                    if let title = args["title"] as? String, !title.isEmpty { idea.title = title }
                    if let angle = args["angle"] as? String { idea.angle = angle.isEmpty ? nil : angle }
                    if let source = args["source"] as? String { idea.source = source.isEmpty ? nil : source }
                    if let platforms = texts(args["platforms"]) { idea.platforms = platforms }
                    if let status { idea.status = status }
                    if let draft = (args["draft"] as? String), !draft.isEmpty, !(idea.drafts ?? []).contains(draft) {
                        idea.drafts = (idea.drafts ?? []) + [draft]
                    }
                }) else { return ("选题库里没有 \(id)", true) }
                SocialPage.show(.ideas)
                return ("改好了：\n" + ideaLine(idea), false)
            case "remove":
                guard let id = args["id"] as? String, let gone = studio.removeIdea(id) else { return ("选题库里没有这个 id", true) }
                return ("从选题库拿掉了「\(gone.title)」（留在 ideas-removed.json 里）", false)
            default:
                let status = (args["status"] as? String).flatMap(SocialStudio.Idea.Status.of)
                let shown = studio.ideas.filter { status == nil || $0.status == status }
                if shown.isEmpty { return (status == nil ? "选题库是空的。social_ideas add 记一个；热榜、拆解、节日都能来" : "没有「\(status!.title)」的选题", false) }
                let groups = SocialStudio.Idea.Status.allCases.map { state in
                    (state, shown.filter { $0.status == state })
                }.filter { !$0.1.isEmpty }
                return (groups.map { "\($0.0.title)（\($0.1.count)）：\n" + $0.1.map(ideaLine).joined(separator: "\n") }.joined(separator: "\n"), false)
            }

        case "social_calendar":
            let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
            switch action {
            case "add":
                guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                      let dayText = args["day"] as? String, date(dayText) != nil else {
                    return ("social_calendar add 要 title 和 day（yyyy-MM-dd）", true)
                }
                let status = (args["status"] as? String).flatMap(SocialStudio.Planned.Status.of) ?? .planned
                let entry = studio.plan(day: dayText, title: title,
                                        platform: (args["platform"] as? String).map { SocialPlatform.of($0)?.rawValue ?? $0 },
                                        status: status, idea: args["idea"] as? String, draft: args["draft"] as? String,
                                        note: args["note"] as? String)
                SocialPage.show(.calendar)
                return ("排进日历了：\n" + plannedLine(entry), false)
            case "update":
                guard let id = args["id"] as? String else { return ("social_calendar update 要 id", true) }
                let status = (args["status"] as? String).flatMap(SocialStudio.Planned.Status.of)
                guard let entry = studio.updatePlanned(id, { entry in
                    if let title = args["title"] as? String, !title.isEmpty { entry.title = title }
                    if let dayText = args["day"] as? String, date(dayText) != nil { entry.day = dayText }
                    if let platform = args["platform"] as? String { entry.platform = platform.isEmpty ? nil : (SocialPlatform.of(platform)?.rawValue ?? platform) }
                    if let status { entry.status = status }
                    if let draft = args["draft"] as? String { entry.draft = draft.isEmpty ? nil : draft }
                    if let note = args["note"] as? String { entry.note = note.isEmpty ? nil : note }
                }) else { return ("日历上没有 \(id)", true) }
                SocialPage.show(.calendar)
                return ("改好了：\n" + plannedLine(entry), false)
            case "remove":
                guard let id = args["id"] as? String, let gone = studio.removePlanned(id) else { return ("日历上没有这个 id", true) }
                return ("从日历上拿掉了 \(gone.day)「\(gone.title)」", false)
            default:
                let start = date(args["from"] as? String) ?? today
                let days = max(1, min(366, FilmTools.int(args["days"]) ?? 30))
                let end = date(args["to"] as? String)
                    ?? Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: start) ?? start
                let (from, to) = (day(start), day(end))
                let entries = studio.planned.filter { $0.day >= from && $0.day <= to }
                let minimum = max(0, min(5, FilmTools.int(args["min_stars"]) ?? 3))
                let events = SocialEvents.between(start, end).filter { $0.stars >= minimum }
                var lines = ["\(from) 到 \(to)："]
                lines.append(entries.isEmpty ? "日历上还没排内容" : "排了的内容：")
                lines += entries.map(plannedLine)
                if action != "entries" {
                    lines.append(events.isEmpty ? "这段时间没有 \(minimum) 星以上的节点"
                                 : "节日和节点（\(minimum) 星以上，Easel 的全年表；「前后」的日子各平台不一）：")
                    lines += events.map(eventLine)
                    // The months the range touches, each once: their themes.
                    let gregorian = Calendar(identifier: .gregorian)
                    var months: [Int] = [], cursor = gregorian.date(from: gregorian.dateComponents([.year, .month], from: start)) ?? start
                    while cursor <= end, months.count < 13 {
                        let month = gregorian.component(.month, from: cursor)
                        if !months.contains(month) { months.append(month) }
                        guard let next = gregorian.date(byAdding: .month, value: 1, to: cursor) else { break }
                        cursor = next
                    }
                    var seen = Set<String>()
                    let seasons = months.flatMap(SocialEvents.seasons).filter { $0.stars >= minimum && seen.insert($0.id).inserted }
                    if !seasons.isEmpty {
                        lines.append("整月的节点（考试、大促，没有具体日子）：")
                        lines += seasons.map(seasonLine)
                    }
                }
                return (lines.joined(separator: "\n"), false)
            }

        case "social_breakdown":
            switch action {
            case "save":
                guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                      let hook = args["hook"] as? String, let template = args["template"] as? String else {
                    return ("social_breakdown save 要 text（原文）、hook、template，还有 structure、why、topics", true)
                }
                let breakdown = SocialStudio.Breakdown(
                    id: "", created: Date(), platform: (args["platform"] as? String).map { SocialPlatform.of($0)?.rawValue ?? $0 },
                    source: args["source"] as? String, text: text, hook: hook, structure: texts(args["structure"]) ?? [],
                    why: texts(args["why"]) ?? [], template: template, topics: texts(args["topics"]) ?? [])
                let (kept, added) = studio.saveBreakdown(breakdown, topicsToIdeas: args["topics_to_ideas"] as? Bool ?? true)
                SocialPage.show(.breakdowns)
                var lines = ["拆解存好了（\(kept.id)），Easel 标签的「拆解」里能看"]
                if !added.isEmpty { lines.append("\(added.count) 个选题进了选题库：") ; lines += added.map(ideaLine) }
                return (lines.joined(separator: "\n"), false)
            case "get":
                guard let id = args["id"] as? String, let one = studio.breakdowns.first(where: { $0.id == id }) else {
                    return ("没有这个拆解", true)
                }
                let platform: String = one.platform.map { "（\($0)）" } ?? ""
                let source: String = one.source.map { " · \($0)" } ?? ""
                let structure: String = one.structure.map { "  · \($0)" }.joined(separator: "\n")
                let why: String = one.why.map { "  · \($0)" }.joined(separator: "\n")
                let lines: [String] = ["拆解 \(one.id)\(platform)\(source)", "钩子：\(one.hook)", "结构：\n\(structure)",
                                       "为什么火：\n\(why)", "模板：\n\(one.template)",
                                       "选题：\(one.topics.joined(separator: "；"))", "原文：\n\(one.text)"]
                return (lines.joined(separator: "\n"), false)
            default:
                if studio.breakdowns.isEmpty { return ("还没有拆解。对方贴来一条爆款或对标内容时，拆完用 social_breakdown save 存下", false) }
                let rows: [String] = studio.breakdowns.prefix(20).map { one in
                    let platform: String = one.platform.map { "\($0) · " } ?? ""
                    return "· [\(one.id)] \(platform)钩子：\(one.hook.prefix(40)) · \(one.topics.count) 个选题"
                }
                return (rows.joined(separator: "\n"), false)
            }

        case "social_subtitles":
            return await subtitles(action, args)

        case "social_article":
            guard let wanted = (args["draft"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty,
                  let html = args["html"] as? String, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ("social_article 要 draft（草稿的文件夹名）和 html（整篇文章）", true)
            }
            let drafts = SocialStudio.scan(SocialStudio.draftsFolder, legacy: false)
            guard let draft = drafts.first(where: { $0.folder.lastPathComponent == wanted || $0.id == wanted || $0.title == wanted }) else {
                return ("没有这份草稿：\(wanted)。先用 social_draft 存一份公众号草稿（标题、摘要、封面），再排它的正文", true)
            }
            studio.working = "在排「\(draft.title)」的公众号正文"
            defer { studio.working = nil }
            do {
                let result = try await SocialArticle.save(html: html, in: draft.folder, access: CompanionArt.folder)
                studio.reload(select: draft.id)
                SocialPage.show(.drafts)
                var lines = ["排好了：\(result.file.path)（\(result.characters) 字，\(result.pictures) 张图，手机上 \(result.screens.count) 屏）",
                             result.problems.isEmpty ? "编辑器会收下的样子：没有要改的" : "要改（贴进编辑器会坏）："]
                lines += result.problems.map { "  ❌ " + $0 }
                lines += result.warnings.map { "  ⚠️ " + $0 }
                if !result.fixed.isEmpty { lines.append("已经顺手改好：" + result.fixed.joined(separator: "；")) }
                lines.append("Easel 标签里这份草稿下面有「复制排版」：对方点它，到公众号编辑器里粘贴（本机的图会一起贴过去）。改完再调一次 social_article 覆盖")
                lines += result.screens.prefix(3).map { "image://\($0.path)" }
                if result.screens.count > 3 { lines.append("其余 \(result.screens.count - 3) 屏在 \(SocialArticle.screensFolder(in: draft.folder).path)") }
                return (lines.joined(separator: "\n"), false)
            } catch {
                return ("没排成：\(error.localizedDescription)", true)
            }

        default:
            return ("没有这个工具：\(name)", true)
        }
    }

    /// Easel's auto-subtitle and subtitle-translate: hear → the agent corrects → burn.
    private static func subtitles(_ action: String, _ args: [String: Any]) async -> (String, Bool) {
        guard let path = (args["video"] as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return ("social_subtitles 要 video：视频文件的路径", true)
        }
        let video = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: video.path) else { return ("没有这个文件：\(video.path)", true) }
        // One folder a video: its parent's name and its own, so two runs'
        // final.mp4 do not share one.
        let folder = SocialSubtitles.folder.appendingPathComponent(
            SocialStudio.slug(video.deletingLastPathComponent().lastPathComponent + "-" + video.deletingPathExtension().lastPathComponent))
        func stamp(_ seconds: Double) -> String { String(format: "%d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60)) }
        func listed(_ lines: [SocialSubtitles.Line]) -> String {
            lines.enumerated().map { index, line in
                "\(index + 1)  \(stamp(line.start))–\(stamp(line.end))  \(line.text)" + (line.second.map { "  ｜ \($0)" } ?? "")
            }.joined(separator: "\n")
        }
        switch action {
        case "burn":
            var lines: [SocialSubtitles.Line]
            if let given = args["lines"] as? [[String: Any]] {
                lines = given.compactMap { row in
                    guard let text = row["text"].map(FilmTools.text), !text.isEmpty,
                          let start = FilmTools.number(row["start"]), let end = FilmTools.number(row["end"]), end > start else { return nil }
                    let second = row["second"].map(FilmTools.text)
                    return SocialSubtitles.Line(start: start, end: end, text: text, second: second?.isEmpty == false ? second : nil)
                }
                if lines.count != given.count { return ("lines 里有 \(given.count - lines.count) 行少了 start、end（秒，end 要大于 start）或 text", true) }
            } else if let kept = SocialSubtitles.load(from: folder) {
                lines = kept
            } else {
                return ("还没听过这个视频：先 social_subtitles hear", true)
            }
            guard !lines.isEmpty else { return ("没有要烧进去的字幕", true) }
            lines.sort { $0.start < $1.start }
            var style = SocialSubtitles.Style()
            if let size = FilmTools.number(args["size"]) { style.size = size }
            if let lift = FilmTools.number(args["lift"]) { style.lift = lift }
            let name = SocialStudio.safeName(args["name"] as? String ?? "") ?? (video.deletingPathExtension().lastPathComponent + "-字幕")
            SocialStudio.shared.working = "在把字幕烧进 \(video.lastPathComponent)"
            defer { SocialStudio.shared.working = nil }
            do {
                let out = try await SocialSubtitles.burn(video, lines: lines, style: style, into: folder, name: name)
                var answer = ["烧好了：\(out.path)", "（\(lines.count) 行\(lines.contains { $0.second != nil } ? "，双语" : "")；字幕文件 lines.srt、lines.ass 在 \(folder.path)）",
                              "看两帧：字的大小、位置、有没有挡住画面里的字（这个视频自己带字幕的话会叠在一起）。要做草稿就把这个路径给 social_draft 的 video"]
                for index in Set([0, lines.count / 2]).sorted() {
                    let still = folder.appendingPathComponent("still-\(index + 1).png")
                    try? await SocialSubtitles.still(out, at: (lines[index].start + lines[index].end) / 2, to: still)
                    if FileManager.default.fileExists(atPath: still.path) { answer.append("image://\(still.path)") }
                }
                return (answer.joined(separator: "\n"), false)
            } catch {
                return ("没烧成：\(error.localizedDescription)", true)
            }
        default:
            SocialStudio.shared.working = "在听 \(video.lastPathComponent)"
            defer { SocialStudio.shared.working = nil }
            do {
                let lines = try await SocialSubtitles.hear(video, language: args["language"] as? String, script: args["script"] as? String,
                                                           longest: FilmTools.int(args["longest"]), into: folder)
                if lines.isEmpty { return ("没听到人声（\(video.lastPathComponent)）", false) }
                return (["听出 \(lines.count) 行（mlx_whisper medium，在这台 Mac 上；存在 \(folder.path)/lines.srt）：", listed(lines),
                         "逐行对一遍：人名、术语、数字最容易错；有稿子（旁白、口播稿）就照稿子改。要双语就每行加 second（你来翻）。" +
                         "然后 social_subtitles burn，把改好的全部 lines 传回来（start、end 是秒，可以微调）"].joined(separator: "\n"), false)
            } catch {
                return ("没听成：\(error.localizedDescription)", true)
            }
        }
    }
}

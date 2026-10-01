import SwiftUI

/// The Easel tab's pages. 草稿 is the tab as it was; the other three are
/// Easel's planning layer (SocialPlan.swift): the 选题库, the 内容日历 with
/// the year's 节点, and the 爆款拆解 kept. The agent fills them with
/// social_ideas, social_calendar and social_breakdown; the person sees them
/// here, and can move an idea or a planned post along by hand.
enum SocialPage: String, CaseIterable, Identifiable {
    case drafts, ideas, calendar, breakdowns
    static let key = "kinclaw.social.page"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .drafts: return "草稿"
        case .ideas: return "选题库"
        case .calendar: return "日历"
        case .breakdowns: return "拆解"
        }
    }

    /// Put the tab on this page — when the agent has just changed what it shows.
    static func show(_ page: SocialPage) { UserDefaults.standard.set(page.rawValue, forKey: key) }
}

// MARK: - 选题库

struct SocialIdeasPage: View {
    @ObservedObject private var studio = SocialStudio.shared

    var body: some View {
        if studio.ideas.isEmpty {
            SocialEmpty(symbol: "lightbulb", text: "选题库是空的。\n让 agent 从热榜、一条爆款的拆解或者日历上的节点里找选题，它会记在这里：待做 → 进行中 → 已完成")
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(SocialStudio.Idea.Status.allCases, id: \.self) { status in
                    column(status)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func column(_ status: SocialStudio.Idea.Status) -> some View {
        let shown = studio.ideas.filter { $0.status == status }
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(status.title, detail: shown.isEmpty ? nil : "\(shown.count)")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { idea in card(idea) }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func card(_ idea: SocialStudio.Idea) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(idea.title).font(.kinHeadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let angle = idea.angle {
                Text(angle).font(.kinCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if let source = idea.source { SocialChip(text: source) }
                ForEach(idea.platforms ?? [], id: \.self) { SocialChip(text: $0, quiet: true) }
                Spacer(minLength: 0)
            }
            ForEach(idea.drafts ?? [], id: \.self) { folder in
                Button {
                    studio.selected = folder
                    SocialPage.show(.drafts)
                } label: { Label("草稿 \(folder)", systemImage: "doc.richtext").font(.kinCaption).lineLimit(1) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .help("到「草稿」里看这一份")
            }
            if let planned = studio.planned.first(where: { $0.idea == idea.id }) {
                Text("日历：\(planned.day) · \(planned.status.title)").font(.kinCaption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .contextMenu {
            ForEach(SocialStudio.Idea.Status.allCases.filter { $0 != idea.status }, id: \.self) { status in
                Button("移到「\(status.title)」") { _ = studio.updateIdea(idea.id) { $0.status = status } }
            }
            Divider()
            Button("从选题库拿掉（留在 ideas-removed.json）") { _ = studio.removeIdea(idea.id) }
        }
        .help("右键：移到别的一栏，或者拿掉")
    }
}

// MARK: - 日历

struct SocialCalendarPage: View {
    @ObservedObject private var studio = SocialStudio.shared
    @State private var month = SocialCalendarPage.firstOfMonth(Date())
    @State private var picked = SocialPlanTools.day(Date())

    private static let gregorian = Calendar(identifier: .gregorian)

    static func firstOfMonth(_ date: Date) -> Date {
        gregorian.date(from: gregorian.dateComponents([.year, .month], from: date)) ?? date
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                monthBar
                seasons
                grid
                Text("格子里是三星以上的节点和排了的内容；点一天看这天的全部。节点来自 Easel 的全年表，农历节日按当年真实日期")
                    .font(.kinCaption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Theme.hairline).frame(width: 0.5)
            ScrollView { dayDetail.padding(14) }
                .frame(width: 290)
                .background(Theme.sidebar)
        }
    }

    private var monthBar: some View {
        let parts = Self.gregorian.dateComponents([.year, .month], from: month)
        return HStack(spacing: 8) {
            Text(verbatim: "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月").font(.kinTitle)
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.quiet).help("上个月")
            Button("今天") {
                month = Self.firstOfMonth(Date())
                picked = SocialPlanTools.day(Date())
            }
            .buttonStyle(.quietFilled)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.quiet).help("下个月")
        }
    }

    private func shift(_ months: Int) {
        month = Self.gregorian.date(byAdding: .month, value: months, to: month) ?? month
    }

    /// The month's themes: 高考, 年货节, 双十一 — a month and no day.
    @ViewBuilder private var seasons: some View {
        let themes = SocialEvents.seasons(in: Self.gregorian.component(.month, from: month)).filter { $0.stars >= 3 }
        if !themes.isEmpty {
            HStack(spacing: 6) {
                Text("这个月").font(.kinCaption).foregroundStyle(.secondary)
                ForEach(themes) { season in
                    SocialChip(text: "\(season.name) \(String(repeating: "★", count: season.stars))")
                        .help([season.when, season.kind, season.tracks.isEmpty ? season.platform : "适合：\(season.tracks)", season.note]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Six weeks, Monday first, as a Chinese wall calendar has them.
    private var days: [Date] {
        let offset = (Self.gregorian.component(.weekday, from: month) + 5) % 7
        guard let start = Self.gregorian.date(byAdding: .day, value: -offset, to: month) else { return [] }
        return (0..<42).compactMap { Self.gregorian.date(byAdding: .day, value: $0, to: start) }
    }

    private var grid: some View {
        let days = self.days
        let events = Dictionary(grouping: SocialEvents.between(days.first ?? month, days.last ?? month)) { SocialPlanTools.day($0.day) }
        let entries = Dictionary(grouping: studio.planned) { $0.day }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { name in
                    Text(name).font(.kinCaption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { date in
                    let key = SocialPlanTools.day(date)
                    cell(date, key: key, events: events[key] ?? [], entries: entries[key] ?? [])
                }
            }
        }
    }

    private func cell(_ date: Date, key: String, events: [SocialEvents.Event], entries: [SocialStudio.Planned]) -> some View {
        let inMonth = Self.gregorian.isDate(date, equalTo: month, toGranularity: .month)
        let today = key == SocialPlanTools.day(Date())
        let big = events.filter { $0.stars >= 3 }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(Self.gregorian.component(.day, from: date))")
                    .font(.system(size: 12, weight: today ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(today ? Theme.accent : inMonth ? Color.primary : Color.secondary)
                Text(SocialCalendarPage.lunar(date)).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
            }
            ForEach(big.prefix(2)) { event in
                Text(event.name).font(.system(size: 10, weight: event.stars >= 5 ? .semibold : .regular))
                    .foregroundStyle(SocialCalendarPage.tint(event.kind)).lineLimit(1)
            }
            if big.count > 2 { Text("+\(big.count - 2)").font(.system(size: 9)).foregroundStyle(.tertiary) }
            ForEach(entries.prefix(2)) { entry in
                Text(entry.title).font(.system(size: 10)).lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(SocialCalendarPage.wash(entry.status)))
            }
            if entries.count > 2 { Text("还有 \(entries.count - 2) 篇").font(.system(size: 9)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(picked == key ? Theme.accentWash : Theme.card.opacity(inMonth ? 1 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(today ? Theme.accent : Theme.hairline, lineWidth: today ? 1 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { picked = key }
        .opacity(inMonth ? 1 : 0.6)
    }

    // MARK: The day picked

    @ViewBuilder private var dayDetail: some View {
        let date = SocialPlanTools.date(picked) ?? Date()
        let events = SocialEvents.between(date, date)
        let entries = studio.planned.filter { $0.day == picked }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SocialCalendarPage.title(date)).font(.kinHeadline)
                Text("农历" + SocialCalendarPage.lunar(date, full: true)).font(.kinCaption).foregroundStyle(.secondary)
            }
            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("节点")
                    ForEach(events) { event in eventRow(event) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("这天的内容", detail: entries.isEmpty ? nil : "\(entries.count)")
                if entries.isEmpty {
                    Text("这天没排内容。跟 agent 说「\(SocialCalendarPage.short(date))排一篇……」").font(.kinCaption).foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in entryRow(entry) }
            }
            ahead(from: date)
        }
    }

    private func eventRow(_ event: SocialEvents.Event) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(event.name).font(.kinLabel.weight(.semibold)).foregroundStyle(SocialCalendarPage.tint(event.kind))
                Text(String(repeating: "★", count: event.stars)).font(.system(size: 9)).foregroundStyle(Theme.notice)
            }
            Text([event.kind, event.rough ? "表上写「\(event.when)」" : "",
                  event.tracks.isEmpty ? "" : "适合：\(event.tracks)", event.platform.isEmpty ? "" : "平台：\(event.platform)", event.note]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.kinCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func entryRow(_ entry: SocialStudio.Planned) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.kinLabel.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Menu(entry.status.title) {
                    ForEach(SocialStudio.Planned.Status.allCases, id: \.self) { status in
                        Button(status.title) { _ = studio.updatePlanned(entry.id) { $0.status = status } }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().font(.kinCaption)
                .help("计划 → 待发（草稿做好了）→ 已发（你在平台上发了之后自己标）")
                if let platform = entry.platform { SocialChip(text: platform, quiet: true) }
                Spacer(minLength: 0)
            }
            if let draft = entry.draft {
                Button {
                    studio.selected = draft
                    SocialPage.show(.drafts)
                } label: { Label("草稿 \(draft)", systemImage: "doc.richtext").font(.kinCaption).lineLimit(1) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            if let note = entry.note { Text(note).font(.kinCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SocialCalendarPage.wash(entry.status)))
    }

    /// The big ones coming: a post for one wants a week or two of making.
    @ViewBuilder private func ahead(from date: Date) -> some View {
        let end = Self.gregorian.date(byAdding: .day, value: 45, to: date) ?? date
        let next = Self.gregorian.date(byAdding: .day, value: 1, to: date) ?? date
        let coming = SocialEvents.between(next, end).filter { $0.stars >= 4 }
        if !coming.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                SectionTitle("接下来 45 天的大节点", detail: "提前 7–14 天准备")
                ForEach(coming) { event in
                    let away = Self.gregorian.dateComponents([.day], from: Self.gregorian.startOfDay(for: date), to: event.day).day ?? 0
                    Button {
                        picked = SocialPlanTools.day(event.day)
                        month = Self.firstOfMonth(event.day)
                    } label: {
                        HStack(spacing: 6) {
                            Text(SocialCalendarPage.short(event.day)).font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(event.name).font(.kinLabel).foregroundStyle(SocialCalendarPage.tint(event.kind))
                            Spacer(minLength: 0)
                            Text("\(away) 天后").font(.kinCaption).foregroundStyle(away <= 14 ? Theme.notice : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Words and colours

    static func tint(_ kind: String) -> Color {
        if kind.contains("电商") { return Theme.notice }
        if kind.contains("法定") || kind.contains("传统") { return Theme.bad }
        return .secondary
    }

    static func wash(_ status: SocialStudio.Planned.Status) -> Color {
        switch status {
        case .planned: return Color.primary.opacity(0.07)
        case .ready: return Theme.accentWash
        case .posted: return Theme.good.opacity(0.22)
        }
    }

    static func title(_ date: Date) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "zh_CN")
        clock.calendar = gregorian
        clock.dateFormat = "M月d日 EEEE"
        return clock.string(from: date)
    }

    static func short(_ date: Date) -> String {
        let parts = gregorian.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0) 月 \(parts.day ?? 0) 日"
    }

    private static let chinese = Calendar(identifier: .chinese)
    private static let lunarMonths = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    /// 农历: "初九" in a cell (the month's name on its first day), "八月初九" in full.
    static func lunar(_ date: Date, full: Bool = false) -> String {
        let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = parts.month, let day = parts.day, (1...12).contains(month), (1...30).contains(day) else { return "" }
        let monthName = (parts.isLeapMonth == true ? "闰" : "") + lunarMonths[month - 1] + "月"
        let dayName: String
        switch day {
        case 1...10: dayName = "初" + digits[day]
        case 11...19: dayName = "十" + digits[day - 10]
        case 20: dayName = "二十"
        case 21...29: dayName = "廿" + digits[day - 20]
        default: dayName = "三十"
        }
        if full { return monthName + dayName }
        return day == 1 ? monthName : dayName
    }
}

// MARK: - 拆解

struct SocialBreakdownsPage: View {
    @ObservedObject private var studio = SocialStudio.shared
    @State private var chosen: String?
    @State private var copied = false

    var body: some View {
        if studio.breakdowns.isEmpty {
            SocialEmpty(symbol: "scissors", text: "还没有拆解。\n把一条火的帖子贴给 agent（或者给它链接），让它拆：钩子、结构、为什么火、能套用的模板、你的账号能做的选题")
        } else {
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(studio.breakdowns) { one in row(one) }
                    }
                    .padding(6)
                }
                .frame(width: 250)
                .background(Theme.sidebar)
                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                if let one = studio.breakdowns.first(where: { $0.id == chosen }) ?? studio.breakdowns.first {
                    ScrollView { detail(one).padding(20).frame(maxWidth: 640, alignment: .leading) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func row(_ one: SocialStudio.Breakdown) -> some View {
        let picked = (chosen ?? studio.breakdowns.first?.id) == one.id
        return Button {
            chosen = one.id
            copied = false
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(one.hook).font(.kinLabel).lineLimit(2)
                Text([one.platform ?? "", SocialBreakdownsPage.when(one.created), "\(one.topics.count) 个选题"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(picked ? Theme.accentWash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ one: SocialStudio.Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("钩子", detail: [one.platform, one.source].compactMap { $0 }.joined(separator: " · "))
                Text(one.hook).font(.kinBody.weight(.semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("结构")
                ForEach(Array(one.structure.enumerated()), id: \.offset) { index, beat in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1)").font(.kinCaption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 14, alignment: .trailing)
                        Text(beat).font(.kinLabel).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("为什么火")
                ForEach(Array(one.why.enumerated()), id: \.offset) { _, reason in
                    Text("· " + reason).font(.kinLabel).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionTitle("能套用的模板")
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(one.template, forType: .string)
                        copied = true
                    } label: { Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.quiet)
                }
                Text(one.template).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("选题", detail: "进了选题库的打了勾")
                ForEach(Array(one.topics.enumerated()), id: \.offset) { _, topic in
                    let kept = studio.ideas.contains { $0.breakdown == one.id && $0.title == topic }
                    Label(topic, systemImage: kept ? "checkmark.circle.fill" : "circle").font(.kinLabel)
                        .foregroundStyle(kept ? Theme.accent : Color.primary)
                }
            }
            DisclosureGroup("原文") {
                Text(one.text).font(.kinLabel).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }
            .font(.kinCaption)
        }
    }

    static func when(_ date: Date) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "M月d日 HH:mm"
        return clock.string(from: date)
    }
}

// MARK: - Small things

struct SocialChip: View {
    let text: String
    var quiet = false

    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(quiet ? Color.primary.opacity(0.06) : Theme.accentWash))
            .foregroundStyle(quiet ? Color.secondary : Theme.accent)
    }
}

struct SocialEmpty: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text(text).font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

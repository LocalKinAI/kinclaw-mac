import SwiftUI

/// The Easel tab (it was 社媒): our own Easel, worked by our own agent, for
/// the Chinese platforms and TikTok, X, YouTube Shorts, 公众号, 视频号 and 朋友圈.
///
/// On the left, the tab's agent: it reads the account's profile and Easel's
/// guides, looks at the trending lists when asked, picks a topic with the
/// person, writes the copy, draws the cards and checks them, and saves a
/// draft. On the right, the drafts — each shown the way it will look on a
/// phone: the cards to swipe through, the title, the text, the tags — with
/// what the person needs to post it themselves: the copy to paste, the folder
/// of cards, the platform's own page. The app signs in nowhere and posts
/// nothing. Below the drafts, the accounts' profiles. See `SocialStudio`.
struct SocialView: View {
    @ObservedObject private var studio = SocialStudio.shared
    @ObservedObject private var agent = StudioAgent.social
    @State private var words = ""
    /// Which card of the chosen draft is showing.
    @State private var page = 0
    @State private var copied: String?
    @State private var naming = false
    @State private var account = ""

    var body: some View {
        GeometryReader { space in
            HStack(spacing: 0) {
                AgentDock(agent: agent,
                          examples: ["拿宇宙看板做一篇小红书图文",
                                     "看看今天的热榜，有没有适合科普号的选题",
                                     "给最新那支 Pixelle 视频配 TikTok 和 YouTube Shorts 的英文文案"],
                          widest: space.size.width - 640, onExample: { agent.say($0) }) {
                    starter
                }
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    HStack(spacing: 0) {
                        sidebar.frame(width: 250).background(Theme.sidebar)
                        Rectangle().fill(Theme.hairline).frame(width: 0.5)
                        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .tint(Theme.accent)
        .onAppear { if !agent.running { agent.shown = true } }
        .task { studio.reload() }
        .onChange(of: studio.selected) { _, _ in
            page = 0
            copied = nil
        }
        .alert("新建账号画像", isPresented: $naming) {
            TextField("账号名，比如：宇宙看板", text: $account)
            Button("建") {
                switch studio.createProfile(account) {
                case .success(let folder): studio.note = "建好了：\(folder.path)。和 agent 一起把六个文件填上"
                case .failure(let failure): studio.note = failure.text
                }
                account = ""
            }
            Button("取消", role: .cancel) { account = "" }
        } message: {
            Text("在 profiles/ 下建一个文件夹，放 Easel 模板的六个文件：身份、风格、受众、平台、偏好、经验。然后和 agent 一起填")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if !agent.shown {
                    Button { agent.shown = true } label: { Label("agent", systemImage: "sidebar.left") }
                        .buttonStyle(.quietFilled)
                        .help("把 agent 那一栏拿出来")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Easel").font(.kinTitle)
                    Text("照 ZJU-REAL/Easel 的做法：账号画像、热榜、选题、文案、卡片、自检，做成草稿——小红书、抖音、公众号、视频号、朋友圈、TikTok、X、YouTube Shorts… · 发布永远是你自己在平台上点，这里不登录、不发帖")
                        .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                        .help("小红书、抖音、B站、微博、知乎、快手、公众号、视频号、朋友圈、TikTok、X、YouTube Shorts。名字和做法来自 ZJU-REAL/Easel（Apache-2.0），它的指南在 social/guides/easel")
                }
                Spacer(minLength: 12)
                if let working = studio.working {
                    ProgressView().controlSize(.small)
                    Text(working).font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { studio.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.quiet)
                    .help("重新读草稿和账号")
                Button {
                    try? FileManager.default.createDirectory(at: SocialStudio.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(SocialStudio.root)
                } label: { Image(systemName: "folder") }
                    .buttonStyle(.quiet)
                    .help("在 Finder 里打开 \(SocialStudio.root.path)：草稿、卡片、账号、热榜快照、Easel 的指南")
            }
            if let note = studio.note {
                Text(note).font(.kinCaption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: Drafts and accounts

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle("草稿", detail: studio.drafts.isEmpty ? nil : "\(studio.drafts.count)")
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            if studio.drafts.isEmpty {
                Text("还没有草稿。跟左边的 agent 说想发什么").font(.kinCaption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(studio.drafts) { draft in draftRow(draft) }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 8)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            accounts
        }
    }

    private func draftRow(_ draft: SocialStudio.Draft) -> some View {
        let chosen = (studio.selected ?? studio.drafts.first?.id) == draft.id
        let when = DateFormatter()
        when.dateFormat = "M月d日 HH:mm"
        return Button { studio.selected = draft.id } label: {
            HStack(spacing: 8) {
                StudioPicture(url: draft.cards.first, largest: 200, fill: true)
                    .frame(width: 42, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title).font(.kinLabel).lineLimit(2)
                    Text([draft.platform, when.string(from: draft.created), "\(draft.cards.count) 张"].joined(separator: " · ")
                         + (draft.video != nil ? " + 视频" : "") + (draft.legacy ? " · 原版 Easel 旧稿" : ""))
                        .font(.kinCaption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chosen ? Theme.accentWash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle("账号画像", detail: studio.accounts.isEmpty ? nil : "\(studio.accounts.count)")
                Spacer()
                Button { naming = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.quiet)
                    .help("新建账号画像（Easel 模板的六个文件）")
            }
            if studio.accounts.isEmpty {
                Text("还没有。agent 会先和你一起建一个：定位、语气、受众、平台、红线").font(.kinCaption).foregroundStyle(.secondary)
            }
            ForEach(studio.accounts, id: \.self) { name in
                Button { NSWorkspace.shared.open(SocialStudio.profilesFolder.appendingPathComponent(name)) } label: {
                    Label(name, systemImage: "person.crop.square").font(.kinLabel).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在 Finder 里打开这个账号的六个文件")
            }
        }
        .padding(12)
    }

    // MARK: One draft, as a phone shows it

    @ViewBuilder private var detail: some View {
        if let draft = studio.drafts.first(where: { $0.id == studio.selected }) ?? studio.drafts.first {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    phone(draft)
                    VStack(alignment: .leading, spacing: 16) {
                        actions(draft)
                        titles(draft)
                        if let video = draft.video { videoBox(video) }
                        if !draft.sources.isEmpty { sources(draft) }
                        if !draft.checks.isEmpty { checks(draft) }
                        if draft.legacy {
                            Text("这是之前原版 Easel（OpenClaw）跑出来的草稿（在 easel/ 文件夹里），只读：要改就让 agent 照它做一份新的")
                                .font(.kinCaption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "megaphone").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                Text("草稿会像手机上的帖子一样出现在这里：卡片、标题、正文、话题。\n发布是你自己的事：复制文案、打开发布页、按顺序传图")
                    .font(.kinLabel).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }

    private func phone(_ draft: SocialStudio.Draft) -> some View {
        let width: CGFloat = 340
        let shown = min(page, max(0, draft.cards.count - 1))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentWash).frame(width: 26, height: 26)
                    .overlay(Text(String((draft.account ?? "我").prefix(1))).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent))
                Text(draft.account ?? "你的账号").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(draft.platform).font(.kinCaption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            ZStack {
                Rectangle().fill(Color.black.opacity(0.06))
                if draft.cards.isEmpty {
                    if let video = draft.video {
                        StudioVideoPlayer(url: video)
                    } else {
                        Text("没有卡片").font(.kinCaption).foregroundStyle(.secondary)
                    }
                } else {
                    StudioPicture(url: draft.cards[shown], largest: 1100)
                    HStack {
                        if shown > 0 { arrow("chevron.left") { page = shown - 1 } }
                        Spacer()
                        if shown < draft.cards.count - 1 { arrow("chevron.right") { page = shown + 1 } }
                    }
                    .padding(8)
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(shown + 1)/\(draft.cards.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: width, height: width * aspect(draft))
            .clipped()
            if draft.cards.count > 1 {
                HStack(spacing: 4) {
                    Spacer()
                    ForEach(0..<draft.cards.count, id: \.self) { i in
                        Circle().fill(i == shown ? Theme.accent : Color.primary.opacity(0.2)).frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.title).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                Text(draft.body).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                if !draft.tags.isEmpty {
                    Text(draft.tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }.joined(separator: " "))
                        .font(.system(size: 13)).foregroundStyle(Color(light: 0x1F4E8C, dark: 0x8AB4F8))
                }
            }
            .padding(12)
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    /// The picture's shape on the phone, height over width: the cover's own,
    /// within what a phone shows (9:16 tall to 2.35:1 wide); a video's 9:16;
    /// or the platform's usual.
    private func aspect(_ draft: SocialStudio.Draft) -> CGFloat {
        if let cover = draft.cards.first, let size = SocialStudio.pixelSize(cover) {
            return min(16 / 9, max(383 / 900, size.height / size.width))
        }
        if draft.video != nil { return 16 / 9 }
        return SocialPlatform.of(draft.platform)?.frame ?? 4 / 3
    }

    private func arrow(_ symbol: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Circle().fill(Color.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private func actions(_ draft: SocialStudio.Draft) -> some View {
        let platform = SocialPlatform.of(draft.platform)
        let steps: String
        if let noPage = platform?.noPage {
            steps = "发布是你自己的事：\(noPage)。复制文案 → 按顺序放 cards/ 里的图 → 粘贴 → 发。"
        } else {
            let copying = platform?.untitled == true ? "复制文案" : "复制标题和文案"
            let opening = SocialStudio.publishPage(draft.platform) != nil ? "打开发布页" : "到\(draft.platform)的发布页"
            steps = "发布是你自己的事：\(copying) → \(opening) → 按顺序传 cards/ 里的图\(draft.video != nil ? "或视频" : "") → 粘贴 → 发。"
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    copy(SocialStudio.pastedText(body: draft.body, tags: draft.tags))
                    copied = "文案"
                } label: { Label(copied == "文案" ? "已复制" : "复制文案", systemImage: copied == "文案" ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.primary)
                    .help(platform?.untitled == true
                          ? "正文和话题：\(draft.platform)只有这一个框"
                          : "正文和话题。标题\(draft.summary != nil ? "和摘要" : "")在下面单独复制：\(draft.platform)的标题和正文是分开的框")
                Button { NSWorkspace.shared.activateFileViewerSelecting([draft.folder]) } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .buttonStyle(.quietFilled)
                .help("草稿文件夹：cards/ 里的图按 01、02… 的顺序上传")
                if let url = SocialStudio.publishPage(draft.platform) {
                    Button { NSWorkspace.shared.open(url) } label: { Label("打开发布页", systemImage: "arrow.up.right.square") }
                        .buttonStyle(.quietFilled)
                        .help("在默认浏览器里打开\(draft.platform)的发布页（\(url.host ?? "")）：你自己登录、传图、粘贴、点发布。这个 app 不登录、不发帖")
                } else if platform?.noPage != nil, let weChat = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tencent.xinWeChat") {
                    Button { NSWorkspace.shared.openApplication(at: weChat, configuration: NSWorkspace.OpenConfiguration()) } label: {
                        Label("打开微信", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.quietFilled)
                    .help("打开这台 Mac 上的微信：朋友圈由你自己发。这个 app 不替你发")
                }
            }
            Text(steps)
                .font(.kinCaption).foregroundStyle(.secondary)
        }
    }

    private func titles(_ draft: SocialStudio.Draft) -> some View {
        let platform = SocialPlatform.of(draft.platform)
        let limit = platform?.titleLimit
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("标题备选", detail: platform?.untitled == true ? "\(draft.platform)没有标题栏，这只是草稿的名字" : limit.map { "\(draft.platform)最多 \($0)" })
            ForEach(Array(draft.titleOptions.enumerated()), id: \.offset) { _, title in
                let count = platform?.length(title) ?? title.count
                HStack(spacing: 6) {
                    Text(title).font(.kinBody).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Text("\(count) 字").font(.kinCaption.monospacedDigit())
                        .foregroundStyle(limit.map { count > $0 } == true ? Theme.notice : Color.secondary)
                    Button {
                        copy(title)
                        copied = title
                    } label: { Image(systemName: copied == title ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.quiet)
                        .help("复制这个标题")
                }
            }
            if let summary = draft.summary {
                SectionTitle("摘要", detail: "\(summary.count)/120 字")
                HStack(alignment: .top, spacing: 6) {
                    Text(summary).font(.kinLabel).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button {
                        copy(summary)
                        copied = "摘要"
                    } label: { Image(systemName: copied == "摘要" ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.quiet)
                        .help("复制摘要：公众号后台标题下面的那一栏")
                }
            }
        }
    }

    private func videoBox(_ video: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("视频", detail: video.lastPathComponent)
            StudioVideoPlayer(url: video)
                .frame(width: 180, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func sources(_ draft: SocialStudio.Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("出处", detail: "每个事实都要有")
            ForEach(Array(draft.sources.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.fact).font(.kinLabel).textSelection(.enabled)
                    HStack(spacing: 4) {
                        Text(source.source + (source.date.map { " · \($0)" } ?? "")).font(.kinCaption).foregroundStyle(.secondary)
                        if let link = source.url.flatMap(URL.init(string:)) {
                            Link(destination: link) { Image(systemName: "arrow.up.right.square").font(.kinCaption) }
                                .help(link.absoluteString)
                        }
                    }
                }
            }
        }
    }

    private func checks(_ draft: SocialStudio.Draft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("自检", detail: "Easel 的发布清单里程序能查的部分")
            ForEach(Array(draft.checks.enumerated()), id: \.offset) { _, check in
                Text(check).font(.kinCaption)
                    .foregroundStyle(check.hasPrefix("❌") ? Theme.bad : check.hasPrefix("⚠️") ? Theme.notice : Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: The first words

    private var starter: some View {
        let after = agent.terminal != nil
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(after ? "接着跟它说：回到上面这段对话"
                            : "想发什么？比如：拿宇宙看板做一篇小红书图文。它先读你的账号画像和看板，给你两三个选题和一种卡片风格，你挑了再写、再画",
                      text: $words, axis: .vertical)
                .textFieldStyle(.plain).font(.kinBody).lineLimit(3...8)
                .onSubmit(send)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
            Button(after ? "接着说" : "开始", action: send)
                .buttonStyle(.primary)
                .disabled(words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("开一个 agent（\(agent.whereTitle)，\(agent.brainTitle)，用 Easel 的工具），第一句就是这个")
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func send() {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        words = ""
        agent.say(text)
    }
}

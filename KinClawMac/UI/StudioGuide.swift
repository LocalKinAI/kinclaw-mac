import AppKit
import SwiftUI

/// What each Studio tab is for — "我在studio有这么多工作流和工具，但是我并不知道
/// 他们都能干什么，甚至合适干什么，你可以给我每个加说明和指导吗，分析他们最擅长什么".
///
/// Opened from the "?" at the end of the Studio group in the top bar: what
/// someone wants to make, and the tab that makes it best; the open tab's card —
/// what it is good at, what it is not, what it costs in time on the box, and
/// how to ask its agent; and the box's services. Every time given was measured
/// on the box (an M3 Ultra, 96 GB); nothing here is a guess.
enum StudioGuide {
    struct Route: Identifiable {
        let want: String
        let mode: ChatMode
        let why: String
        var id: String { want }
    }

    struct Card {
        let what: String
        let best: [String]
        let weak: [String]
        let time: [String]
        let asks: [String]
    }

    static let routes: [Route] = [
        Route(want: "一支 30–90 秒的讲解、科普视频（竖屏、横屏、方形都有）", mode: .pixelle,
              why: "一句话一个画面，一个人念完，二十几种版式；5 场约 5 分钟出静态版，再决定要不要动"),
        Route(want: "有人物、有情节的短片，同一个人贯穿几个镜头", mode: .film,
              why: "H3 按参考图保住人脸；先定每个镜头的第一帧再拍，画面稳"),
        Route(want: "让她（或一个角色）做一个具体动作：太极、舞蹈、走路", mode: .motion,
              why: "动作从一段真人视频里取（光凭文字编不出）；没有视频就说动作名，它去 YouTube 找 CC 授权的给你挑"),
        Route(want: "一段视频里的人和景整个换掉：动作、机位、布局不变", mode: .motion,
              why: "「整场白模」：原片整个场景做成白模，换上你说的人和地方，H3 照着白模拍"),
        Route(want: "一个地方的空镜，镜头按我说的推、环绕，没有参考视频", mode: .motion,
              why: "「提示词白模」：先搭方块白模和镜头路径，H3 照着深度拍"),
        Route(want: "一支完整成片：多场景、剪辑、字幕、配乐，一步步审", mode: .montage,
              why: "OpenMontage 走专业流程，每步有检查点，Backlot 看板上审"),
        Route(want: "动效片、片头、动态文字、图表动画：字要一个不错", mode: .montage,
              why: "不用 AI 画面：Claude 写 HTML 动画（HyperFrames），逐帧渲成视频，15 秒 1080p60 渲约 22 秒"),
        Route(want: "一首歌配画面，唱到哪画到哪：节日、亲友祝福", mode: .montage,
              why: "YuE2 唱中文歌词，按每句唱的时间出画面，整首唱完再淡出（国庆祝福 60 秒版）"),
        Route(want: "把网页或产品做成电影感宣传片", mode: .montage,
              why: "video-shotcraft：真实页面截图、2.5D 运镜、卡点剪辑，157 张镜头配方卡（还没在这里做过）"),
        Route(want: "一张图、改一张图、做成 3D、放大或补帧、任何现成工作流", mode: .comfy,
              why: "盒子 ComfyUI 的模板当表单用：挑一个、填几项、跑"),
        Route(want: "一首带人声、有歌词的歌，或者翻唱一首", mode: .comfy,
              why: "YuE2；做好的歌 Film、Pixelle、Montage、Easel 都能拿去当配乐"),
        Route(want: "小红书、公众号、X、TikTok 的帖子：文案、卡片、视频", mode: .social,
              why: "按平台规则写和自检，只做草稿，发布是你自己点"),
    ]

    static let cards: [ChatMode: Card] = [
        .film: Card(
            what: "从一句话到一部有旁白、有配乐的短片：Claude 写分镜，每个镜头先画第一帧，MiniMax H3 拍（带声音），再剪、配旁白和音乐、调色、加片名。",
            best: ["同一个人贯穿多个镜头：H3 按参考图保住脸",
                   "电影感的光和构图；先定第一帧再拍（钉帧）比让镜头自己动更顺",
                   "旁白按描述造声音，一次念完",
                   "只重拍一个镜头：一句话说怎么改，它先看现在这条再改写；或者只用文字改画面（约 2 分钟）再拍",
                   "定妆：最多四个人，可以用你给的照片当某个人的脸"],
            weak: ["数不清东西：「五个饼两条鱼」要先让它一格一格数布景，改对了再拍",
                   "复杂动作：文字编不出舞蹈，去 Motion 用参考视频",
                   "导演要 Claude 当：别的模型挑镜头、数东西都不行"],
            time: ["H3 一个 5 秒镜头约 10 分钟；4 个镜头的片子一小时起",
                   "配乐 MiniMax 每秒音乐约 6 秒（30 秒一段 3 分钟）；带人声的歌用 YuE2 约 17 秒"],
            asks: ["拍一部 30 秒的短片：雨夜书店里一个女孩找到一本旧书，配旁白和音乐。先给我看每个镜头的第一帧",
                   "给「米迦勒」换成这首歌当配乐，旁白不动",
                   "第 3 镜重拍：她应该回头看门口，别的不动"]),
        .motion: Card(
            what: "让她照一段真人视频的动作动起来，放进你说的地方和衣服里；或者把整段视频的人和景都换掉；或者不要参考视频，用白模搭一个场景、按指定路线拍。四条路：骨架（默认）、3D 机位（静止/环绕/推进）、整场白模、提示词白模。",
            best: ["真实、复杂的人体动作：太极、舞蹈——只要有一段参考视频",
                   "精确可控的镜头运动：推、环绕、沿街前进",
                   "整场白模：原片的动作、机位、布局全留着，人和景换成你说的",
                   "白模路线：一个场景的空镜，地方和镜头都照你说的"],
            weak: ["只凭文字编动作（试过，是死路）",
                   "白模路线里的人只能站着",
                   "参考视频要一个人、全身、机位稳"],
            time: ["10 秒动作约 5 分钟",
                   "整场白模 10 秒约 15 分钟（先停在白模给你看）",
                   "提示词白模 5 秒约 9 分钟（先停在俯视图给你看）"],
            asks: ["找几段八段锦的参考视频给我挑",
                   "用这段太极视频，让她在晨雾的公园里打一遍，白色练功服",
                   "整场白模：这段太极换成穿汉服的白须老者，在竹林的石板庭院里",
                   "提示词白模：雨夜的老街，镜头沿街往前推 5 秒"]),
        .pixelle: Card(
            what: "一篇稿子变成一支讲解视频（竖屏为主，也有横屏、方形）：一段一个场景，每场一张 AI 图，一个人一次念完旁白，卡片加字幕、垫音乐，响度拉到 −14 LUFS。像 NotebookLM 的讲解。",
            best: ["知识、科普、观点类讲解，要快",
                   "画面能动：pan 慢推慢移（几秒一场），LTX 真的动（约 3 分钟一场，补帧后顺滑）",
                   "做好的片子能重做：重配音、让画面动、换一首 YuE2 的歌，不重画图",
                   "二十几种版式：书页、霓虹、手绘线稿、复古时装、心理卡片……还有不画图的纯文字版",
                   "先试再做：一张图约 45 秒，一句配音几秒（会听回来查念错的数字、名字、多音字）；声音可按描述现造"],
            weak: ["剧情和固定人物：每场是一张独立的图，人物对不上",
                   "图表、文字类画面用 LTX 会扭线条——用 pan；要图表真的动起来，去 Montage 用 HyperFrames",
                   "单独重做某一场：只能整支重做（没改的场景画面不变）"],
            time: ["静态版 5 场约 5 分钟",
                   "LTX 每场约 3 分钟；pan 几秒"],
            asks: ["40 秒竖屏，讲系外行星是怎么被发现的，先给我看稿子和每场的画面",
                   "把刚才那支做成会动的，图表那场用 pan"]),
        .montage: Card(
            what: "盒子上的 OpenMontage 按专业流程做完整成片：立项、分镜、素材、剪辑、字幕、配乐，每一步都有检查点，你在 Backlot 看板上审。也能不要 AI 画面，让 Claude 直接写代码做动效片（HyperFrames）。",
            best: ["步骤多、要一步步审的完整项目：宣传片、节日祝福",
                   "动效片、片头、动态文字、图表：Claude 写 HTML 动画，逐帧渲染（HyperFrames），中文字一个不错，改一个字重渲一遍",
                   "歌配画面：YuE2 唱中文歌词，画面一句一句对着唱词走",
                   "网页、产品宣传片：video-shotcraft 的镜头配方卡（真实页面截图、2.5D 运镜、卡点剪辑；还没在这里做过）",
                   "从一套 Opus 5.5 视频提示词库起步",
                   "接着做以前的项目（从检查点继续）"],
            weak: ["快：它走完整流程，一次只能跑一个重活",
                   "临时改一个小地方：Film 或 Pixelle 更直接"],
            time: ["一张图约 2 分钟，H3 一个 5 秒镜头约 10 分钟，配乐每秒约 6 秒",
                   "HyperFrames 动效 15 秒 1080p60 渲约 22 秒；Remotion 45 秒 1080p 约 25 秒（写代码的时间另算）"],
            asks: ["用 OpenMontage 做一支 30 秒的国庆祝福，先给我看分镜",
                   "用 HyperFrames 给《以诺天使》做个 15 秒系列片头，中文片名，用 Film 里米迦勒的镜头"]),
        .comfy: Card(
            what: "盒子 ComfyUI 的几百个模板当表单用：挑一个（或者说你要什么，让它挑）、改几项、跑，结果回到这个标签里。社区插件的示例也在里面。",
            best: ["Qwen Image 2.1 文生图（约 1 分钟一张）和改图",
                   "YuE2：带人声、有歌词的歌（每秒音乐约 17 秒），也能翻唱",
                   "图片做成 3D 模型（约 6 分钟）",
                   "RIFE 补帧（几秒）；SeedVR2 放大（很清楚但很慢）",
                   "导入别人的工作流：json、ComfyUI 出的 PNG、GitHub 链接都行，缺什么模型和节点会列出来",
                   "图片提示词库：两百来条别人写好的好提示词，挑一条换成你的主题"],
            weak: ["570 个模板里现在能直接跑的只有 21 个；326 个走付费云端，216 个要先下模型——列表里每个都标了",
                   "3D 的烘焙节点在 Mac 上跑不完也停不掉（用「我的」里的不烘焙版）；int8 的补丁会崩（用 bf16 版）",
                   "SeedVR2 每秒视频要 6 分钟，只适合给定稿精修；大模型类模板不如盒子上的 kinfer"],
            time: ["图约 1 分钟，歌 80 秒约 22 分钟，3D 约 6 分钟"],
            asks: ["用 YuE2 写一首 60 秒的民谣，主题是回家，歌词你来写",
                   "把这张照片做成 3D 模型"]),
        .social: Card(
            what: "照 Easel 的做法，按账号画像给各平台做草稿：选题、文案、卡片、自检。平台：小红书、抖音、B站、微博、知乎、快手、公众号、视频号、朋友圈、TikTok、X、YouTube Shorts。",
            best: ["小红书图文卡片（3:4），一张张画、一张张审",
                   "按各平台自己的规则自检：字数、话题数、尺寸，X 的加权 280",
                   "从热榜找选题：微博、抖音、B站、百度、知乎、头条、Google Trends、X",
                   "读网页（比如宇宙看板）：字和数字照页面原样取，截图直接做卡片",
                   "英文帖；要视频的平台用 Pixelle（讲解）或 Montage（动效）做",
                   "爆款拆解：贴一条火的帖子，拆出钩子、结构、为什么火、能套的模板，选题进选题库",
                   "选题库（待做 · 进行中 · 已完成）和内容日历：日历上带着全年节点——节日按当年的农历日期、618 / 双11、行业节点",
                   "一稿多发：同一个内容给几个平台各写一版，标签里放在一起",
                   "给视频配字幕（在这台 Mac 上听，逐行校对再烧进去），可以中英双语",
                   "公众号正文排版：照 gzh-design 的主题排好，标签里「复制排版」，贴进公众号编辑器"],
            weak: ["发布：只做草稿，这个 app 不登录、不发帖",
                   "TikTok、YouTube、微信没有公开热榜"],
            time: ["一篇图文几分钟；带视频的加上 Pixelle 的时间"],
            asks: ["给宇宙看板写一篇小红书，先看看最近什么话题热，给我两三个方向",
                   "拆一下这条爆款，看看我的账号能怎么做（把帖子贴进来）",
                   "下个月有什么节点？给我排一个内容日历"]),
    ]

    /// The box's services and what each one costs; started and stopped from
    /// the LocalKin console's 盒子 panel.
    static let box: [(name: String, note: String)] = [
        ("ComfyUI :8188", "H3、Qwen 图、音乐、YuE2、3D、放大、补帧都在这里跑，几个标签排队共用"),
        ("出片 LTX-2.5 :8001", "图生视频，768² 的 5 秒约 2.5 分钟；自然景物动得好，图表的线条会扭"),
        ("精修 LTX q8 :8003", "脸和衣料更干净，时间约 5 倍：只给定稿的镜头"),
        ("改图 klein :8002", "10–22 秒一张；改过大图后内存会涨到 70 GB，拍 H3 前会被停"),
        ("画图 :8000", "Qwen Image 快速出图（ollamadiffuser）"),
        ("旁白 :8102 / 对话语音 :8101", "8102 按描述造声音（电影、Pixelle）；8101 是预设声音"),
        ("语音识别 :8100", "Qwen3-ASR：听回配音有没有念错、Pixelle 切句"),
        ("kinfer :11590", "盒子上的大模型；闲 10 分钟自己卸"),
        ("Pixelle :8190 / Backlot :4750", "Pixelle 的接口；OpenMontage 的看板"),
    ]
}

/// The guide, for the popover.
struct StudioGuideView: View {
    let current: ChatMode
    let go: (ChatMode) -> Void
    @State private var shown: ChatMode

    init(current: ChatMode, go: @escaping (ChatMode) -> Void) {
        self.current = current
        self.go = go
        _shown = State(initialValue: StudioGuide.cards[current] == nil ? .film : current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Studio 指南").font(.kinTitle)
                Text("想做什么，去哪个标签").font(.kinLabel).foregroundStyle(.secondary)
                Text("找错了标签也不要紧：agent 会说该去哪、问你要不要转，你说好它就转过去；它们也看得见彼此在忙什么、做好了什么。")
                    .font(.kinCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(StudioGuide.routes) { route in
                        Button { go(route.mode); shown = route.mode } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(route.want).font(.kinBody)
                                    Text(route.why).font(.kinCaption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Label(route.mode.title, systemImage: route.mode.symbol)
                                    .font(.kinCaption.weight(.semibold))
                                    .foregroundStyle(route.mode == current ? Theme.accent : Color.secondary)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(route.mode == current ? Theme.accentWash : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("去 \(route.mode.title)")
                    }
                }
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                Picker("", selection: $shown) {
                    ForEach(ModeGroup.studio.members) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let card = StudioGuide.cards[shown] { cardView(card) }
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                Text("盒子上的服务").font(.kinLabel).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(StudioGuide.box, id: \.name) { service in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(service.name).font(.kinCaption.weight(.semibold)).frame(width: 150, alignment: .leading)
                            Text(service.note).font(.kinCaption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("在 localhost:9000 的「盒子」面板里起停") {
                    if let url = URL(string: "http://localhost:9000/") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link).font(.kinCaption)
                Text("手机上：连着 Tailscale 打开 http://localkin-mac.tailff9e14.ts.net —— 各标签的 agent 和成果、跟它们说话、叫停、起停盒子的服务")
                    .font(.kinCaption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 560, alignment: .leading)
        }
        .frame(maxHeight: 640)
    }

    private func cardView(_ card: StudioGuide.Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.what).font(.kinBody).fixedSize(horizontal: false, vertical: true)
            section("最擅长", card.best, color: Theme.accent)
            section("不适合", card.weak, color: .orange)
            section("要多久", card.time, color: .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("可以这样跟它说").font(.kinCaption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(card.asks, id: \.self) { ask in
                    Text("「\(ask)」").font(.kinCaption).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section(_ title: String, _ lines: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.kinCaption.weight(.semibold)).foregroundStyle(color)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("·").font(.kinCaption).foregroundStyle(.secondary)
                    Text(line).font(.kinCaption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

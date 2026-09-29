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
        Route(want: "一支 30–90 秒的竖屏讲解、科普视频", mode: .pixelle,
              why: "一句话一个画面，一个人念完，5 场约 5 分钟出静态版，再决定要不要动"),
        Route(want: "有人物、有情节的短片，同一个人贯穿几个镜头", mode: .film,
              why: "H3 按参考图保住人脸；先定每个镜头的第一帧再拍，画面稳"),
        Route(want: "让她（或一个角色）做一个具体动作：太极、舞蹈、走路", mode: .motion,
              why: "动作从一段真人视频里取——光凭文字编不出动作"),
        Route(want: "一个地方的空镜，镜头按我说的推、环绕，没有参考视频", mode: .motion,
              why: "「提示词白模」：先搭方块白模和镜头路径，H3 照着深度拍"),
        Route(want: "一支完整成片：多场景、剪辑、字幕、配乐，一步步审", mode: .montage,
              why: "OpenMontage 走专业流程，每步有检查点，Backlot 看板上审"),
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
                   "旁白按描述造声音，一次念完"],
            weak: ["数不清东西：「五个饼两条鱼」要先把静帧改对再拍",
                   "复杂动作：文字编不出舞蹈，去 Motion 用参考视频",
                   "导演要 Claude 当：别的模型挑镜头、数东西都不行"],
            time: ["H3 一个 5 秒镜头约 10 分钟；4 个镜头的片子一小时起",
                   "配乐 MiniMax 每秒音乐约 70 秒；带人声的歌用 YuE2 约 17 秒"],
            asks: ["拍一部 30 秒的短片：雨夜书店里一个女孩找到一本旧书，配旁白和音乐。先给我看每个镜头的第一帧",
                   "给「米迦勒」换成这首歌当配乐，旁白不动"]),
        .motion: Card(
            what: "让她照一段真人视频的动作动起来，放进你说的地方和衣服里；或者不要参考视频，用白模搭一个场景、按指定路线拍。三条路：骨架（默认）、3D 机位（静止/环绕/推进）、提示词白模。",
            best: ["真实、复杂的人体动作：太极、舞蹈——只要有一段参考视频",
                   "精确可控的镜头运动：推、环绕、沿街前进",
                   "白模路线：一个场景的空镜，地方和镜头都照你说的"],
            weak: ["只凭文字编动作（试过，是死路）",
                   "白模路线里的人只能站着",
                   "参考视频要一个人、全身、机位稳"],
            time: ["10 秒动作约 5 分钟",
                   "提示词白模 5 秒约 9 分钟（先停在俯视图给你看）"],
            asks: ["用这段太极视频，让她在晨雾的公园里打一遍，白色练功服",
                   "提示词白模：雨夜的老街，镜头沿街往前推 5 秒"]),
        .pixelle: Card(
            what: "一篇稿子变成一支竖屏讲解视频：一段一个场景，每场一张 AI 图，一个人一次念完旁白，卡片加字幕、垫音乐，响度拉到 −14 LUFS。像 NotebookLM 的讲解。",
            best: ["知识、科普、观点类讲解，要快",
                   "画面能动：pan 慢推慢移（几秒一场），LTX 真的动（约 3 分钟一场，补帧后顺滑）",
                   "做好的片子能重做：重配音、让画面动、换一首 YuE2 的歌，不重画图"],
            weak: ["剧情和固定人物：每场是一张独立的图，人物对不上",
                   "图表、文字类画面用 LTX 会扭线条——用 pan",
                   "单独重做某一场：只能整支重做（没改的场景画面不变）"],
            time: ["静态版 5 场约 5 分钟",
                   "LTX 每场约 3 分钟；pan 几秒"],
            asks: ["40 秒竖屏，讲系外行星是怎么被发现的，先给我看稿子和每场的画面",
                   "把刚才那支做成会动的，图表那场用 pan"]),
        .montage: Card(
            what: "盒子上的 OpenMontage 按专业流程做完整成片：立项、分镜、素材、剪辑、字幕、配乐，每一步都有检查点，你在 Backlot 看板上审。",
            best: ["步骤多、要一步步审的完整项目：宣传片、节日祝福",
                   "从一套 Opus 5.5 视频提示词库起步",
                   "接着做以前的项目（从检查点继续）"],
            weak: ["快：它走完整流程，一次只能跑一个重活",
                   "临时改一个小地方：Film 或 Pixelle 更直接"],
            time: ["一张图约 2 分钟，H3 一个 5 秒镜头约 10 分钟，音乐每秒约 70 秒"],
            asks: ["用 OpenMontage 做一支 30 秒的国庆祝福，先给我看分镜"]),
        .comfy: Card(
            what: "盒子 ComfyUI 的几百个模板当表单用：挑一个（或者说你要什么，让它挑）、改几项、跑，结果回到这个标签里。社区插件的示例也在里面。",
            best: ["Qwen Image 2.1 文生图（约 1 分钟一张）和改图",
                   "YuE2：带人声、有歌词的歌（每秒音乐约 17 秒），也能翻唱",
                   "图片做成 3D 模型（约 6 分钟）",
                   "RIFE 补帧（几秒）；SeedVR2 放大（很清楚但很慢）"],
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
                   "英文帖；要视频的平台用 Pixelle 做"],
            weak: ["发布：只做草稿，这个 app 不登录、不发帖",
                   "TikTok、YouTube、微信没有公开热榜"],
            time: ["一篇图文几分钟；带视频的加上 Pixelle 的时间"],
            asks: ["给宇宙看板写一篇小红书，先看看最近什么话题热，给我两三个方向"]),
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

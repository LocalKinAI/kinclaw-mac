import Foundation

/// Top-level surface picker for the spotlight panel. The same window
/// hosts three different agent UX shapes — switching is a one-click
/// thing, not a window swap.
///
///   .chat   → conversation surface (Local KinClaw + Cloud LocalKin)
///   .cowork → chat + inline live screen feed ("agent's eyes" mode,
///             driven by the kinclaw kernel's screen claw). The agent
///             picker splits Cowork souls into two source groups:
///               🦞 KinClaw — public souls from the kinclaw kernel
///                            (`./souls/`, `~/.localkin/souls/`)
///               🛡️ Private — souls from a sibling localkin checkout
///                            at `souls/private/` (file-system scanned
///                            via PrivateSoulLoader, never network-
///                            registered, never uploaded)
///   .code   → repo picker + file tree + diff viewer + chat,
///             driven by kincode kernel running on :5002
///   .term   → a third-party agent (Claude Code today) in a real
///             terminal, pointed at the Ollama and the model the model
///             menu is already using — or your own shell in the same
///             tab strip, for the times the answer is one command
///   .web    → a browser in the panel: the page you are signed into,
///             one button from the agent
///   .motion → a movement taken from a real performance, performed by her:
///             a reference video's pose skeleton drives the video model
///   .comfy  → ComfyUI's ready-made workflows on the box, as forms, with
///             the writer model to pick and change them and the node
///             editor one button away
///   .film   → one sentence in, a short film out: a storyboard, a still
///             and a clip per shot on the user's own image and video
///             servers, cut together
///   .montage → OpenMontage on the box: an agent there makes the video with
///             OpenMontage's pipelines and the box's own models, and its
///             Backlot board shows the production as it happens
///
/// This mirrors Claude Code Desktop's three-mode top bar, but plugged
/// into the LocalKin kernel family (kinclaw + kincode) instead of
/// Anthropic-only. Mode persists across launches so the user doesn't
/// have to re-pick on every summon.
enum ChatMode: String, CaseIterable, Identifiable {
    case chat
    case cowork
    case code
    case term
    case web
    case film
    case motion
    case jev
    case comfy
    case montage

    var id: String { rawValue }

    /// Short label shown in the ModeBar pill.
    var title: String {
        switch self {
        case .chat:   return "Chat"
        case .cowork: return "Cowork"
        case .code:   return "Code"
        case .term:   return "Term"
        case .web:    return "Web"
        case .film:   return "Film"
        case .motion: return "Motion"
        case .jev:    return "Jev"
        case .comfy:  return "Comfy"
        case .montage: return "Montage"
        }
    }

    /// SF Symbol name for the pill icon. Picked to read at 11pt: a
    /// plain bubble for chat, an eye for cowork (we're showing the
    /// agent the screen), a chevron for code.
    var symbol: String {
        switch self {
        case .chat:   return "bubble.left.and.bubble.right"
        case .cowork: return "eye"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        case .term:   return "terminal"
        case .web:    return "globe"
        case .film:   return "film"
        case .motion: return "figure.taichi"
        case .jev:    return "gamecontroller"
        case .comfy:  return "point.3.connected.trianglepath.dotted"
        case .montage: return "rectangle.stack.badge.play"
        }
    }

    /// One-line tooltip for hover.
    var help: String {
        switch self {
        case .chat:
            return "Chat with any agent (Local KinClaw or Cloud LocalKin)"
        case .cowork:
            return "Cowork — agent watches your screen (KinClaw souls, public + private)"
        case .code:
            return "Code — repo-aware coding agent (kincode on :5002)"
        case .term:
            return "Term — another agent in a terminal, on the model you picked, or your own shell"
        case .web:
            return "Web — a browser in the panel; 给 agent 看这页 hands the page over"
        case .film:
            return "Film — 一句话拍个短片：分镜、出图、出片、剪辑，都在自己的机器上"
        case .motion:
            return "Motion — 找一段真人动作的视频，只取骨架，让她照着做：太极、舞蹈、任何说不清的动作"
        case .jev:
            return "Jev — 游戏：帝国时代和帝国、开车、飞机大战、像素鸟、俄罗斯方块、2048、贪吃蛇、21 点和三种棋。决策模型每一步答一道选择题；你也可以自己上手，和它比同一局，或者看它和电脑打"
        case .comfy:
            return "Comfy — 盒子上 ComfyUI 的现成工作流：挑模板、填表、运行；或者一句话让 agent 挑和改"
        case .montage:
            return "Montage — OpenMontage，在盒子上：说想拍什么，agent 在那边写稿、出图、拍片、配乐、剪辑；上面是它的 Backlot 看板，下面是 agent 本身"
        }
    }
}

extension ChatMode {
    /// UserDefaults key for the persisted last-used mode.
    static let storageKey = "kinclaw.mode"

    /// Read the persisted mode, falling back to .chat for first run
    /// and for any unknown value (handles forward-compat — older
    /// builds reading a future mode string just default to chat).
    static func loadPersisted() -> ChatMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return ChatMode(rawValue: raw) ?? .chat
    }

    /// Persist this mode as the user's last-used surface.
    func persist() {
        UserDefaults.standard.set(rawValue, forKey: ChatMode.storageKey)
        ModeGroup.remember(self)
    }
}

/// The modes as the top bar shows them: four groups, not nine tabs.
///
/// Nine pills in a row read as nine equal things, and at the panel's usual
/// width the row ran out before the modes did. Grouped by what a person has
/// come to do — talk, work, make something, play — the open group shows its
/// members and the others are one word each. A click on a closed group goes
/// back to whichever of its members was used last.
enum ModeGroup: String, CaseIterable, Identifiable {
    case talk, work, studio, play

    var id: String { rawValue }

    var members: [ChatMode] {
        switch self {
        case .talk:   return [.chat, .cowork]
        case .work:   return [.code, .term, .web]
        case .studio: return [.film, .motion, .montage, .comfy]
        case .play:   return [.jev]
        }
    }

    /// A group of one is shown by its one member's name.
    var title: String {
        switch self {
        case .talk:   return "Talk"
        case .work:   return "Work"
        case .studio: return "Studio"
        case .play:   return members[0].title
        }
    }

    var symbol: String {
        switch self {
        case .talk:   return "bubble.left.and.bubble.right"
        case .work:   return "hammer"
        case .studio: return "film.stack"
        case .play:   return members[0].symbol
        }
    }

    static func of(_ mode: ChatMode) -> ModeGroup {
        allCases.first { $0.members.contains(mode) } ?? .talk
    }

    private var lastKey: String { "kinclaw.mode.last.\(rawValue)" }

    /// Where a click on this group goes: the member used last, else the first.
    var last: ChatMode {
        let raw = UserDefaults.standard.string(forKey: lastKey) ?? ""
        return ChatMode(rawValue: raw).flatMap { members.contains($0) ? $0 : nil } ?? members[0]
    }

    static func remember(_ mode: ChatMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: of(mode).lastKey)
    }
}

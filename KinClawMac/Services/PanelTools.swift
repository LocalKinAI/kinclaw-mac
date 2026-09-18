import Foundation

/// The tools the panel offers the agent, and what they answer with.
///
/// Wording matters here more than usual: these descriptions are the only thing
/// the model reads before deciding whether this is the right tool. So each one
/// says what makes it different from the kernel's own — this is *your* browser,
/// signed in, and *your* terminals, the ones you are watching — rather than
/// describing a browser in general.
///
/// Answers are plain text, not JSON. A model reads a table of tabs better than
/// it reads a JSON array of them, and every MCP answer is text in the end.
@MainActor
enum PanelTools {

    static let definitions: [[String: Any]] = [
        [
            "name": "browser_open",
            "description": """
                Open a URL in the Web tab of the KinClaw panel — the user's own \
                browser, with their cookies and sign-ins — wait for it to load, \
                and return the page's title and text. Use this rather than a \
                fetch when the page needs a session the fetch would not have, \
                when the user is looking at it, or when they asked you to open \
                something. The page stays open for them to see.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to open."],
                    "new_tab": ["type": "boolean",
                                "description": "Open a new tab instead of reusing the current one."],
                ],
                "required": ["url"],
            ],
        ],
        [
            "name": "browser_read",
            "description": """
                Read the page the KinClaw panel's Web tab is showing right now: \
                its title, URL and visible text, after the page's JavaScript \
                has run. Use it to see what the user is looking at.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "chars": ["type": "integer",
                              "description": "How much text to return (default 20000)."],
                    "tab": ["type": "integer",
                            "description": "Which tab, as numbered by browser_tabs. Default: the open one."],
                ],
            ],
        ],
        [
            "name": "browser_tabs",
            "description": "List the tabs open in the KinClaw panel's Web tab, and which one is in front.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "terminal_tabs",
            "description": """
                List the tabs in the KinClaw panel's Term tab: which agent or \
                shell each one is running, in which folder, and whether its \
                process is still alive.
                """,
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "avatar_outfits",
            "description": """
                List what the KinClaw companion can look like: the real-person \
                looks (video-driven) and the 3D outfits (VRM models), which one \
                she is wearing, and whether she is on screen right now.
                """,
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "avatar_wear",
            "description": """
                Change how the KinClaw companion looks, by name — a real-person \
                look or a 3D outfit, and a partial name is enough. Use it when \
                the user asks her to change clothes or to be someone else. Call \
                avatar_outfits first if you do not know what she has.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "outfit": ["type": "string",
                               "description": "An outfit name from avatar_outfits; part of one is enough."],
                ],
                "required": ["outfit"],
            ],
        ],
        [
            "name": "image_generate",
            "description": """
                Draw a picture from a description, on the user's own diffusion \
                server, and save it where the KinClaw companion keeps her art. \
                Use it when they ask for an image — a scene, a portrait, a \
                background — rather than describing one in words. Takes about \
                15 seconds. The answer is where the file landed.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string",
                               "description": "What to draw, in English — the models were trained on it."],
                    "mood": ["type": "string",
                             "description": "Save it under one of the companion's moods (开心/温柔/好奇/困/担心) or states (idle/listening/thinking/speaking) so she shows it then. Default: the rotating pool."],
                    "width": ["type": "integer", "description": "Pixels wide (default 768)."],
                    "height": ["type": "integer", "description": "Pixels tall (default 768)."],
                    "steps": ["type": "integer", "description": "Denoising steps (default 4, which is what the turbo models want)."],
                    "seed": ["type": "integer", "description": "Fixed seed, to repeat a picture."],
                ],
                "required": ["prompt"],
            ],
        ],
        [
            "name": "video_generate",
            "description": """
                Film a short clip from a description, on the user's own \
                diffusion server, and save it where the KinClaw companion \
                keeps her art — an mp4 there becomes her moving background. \
                This takes minutes, so it starts the job and answers with \
                where the file will land; call video_status to see whether it \
                is done.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string",
                               "description": "What to film, in English — a scene with some motion in it."],
                    "mood": ["type": "string",
                             "description": "Save it under one of the companion's moods (开心/温柔/好奇/困/担心) or states (idle/listening/thinking/speaking). Default: the rotating pool."],
                    "seconds": ["type": "number",
                                "description": "How long, 1–10 (default 4). Longer costs proportionally more time."],
                    "width": ["type": "integer", "description": "Pixels wide (default 704)."],
                    "height": ["type": "integer", "description": "Pixels tall (default 480)."],
                    "seed": ["type": "integer", "description": "Fixed seed, to repeat a clip."],
                ],
                "required": ["prompt"],
            ],
        ],
        [
            "name": "video_status",
            "description": """
                How the clips are coming along: what is still filming, what \
                landed and where, and what failed and why.
                """,
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "terminal_read",
            "description": """
                Read what a terminal in the KinClaw panel is showing — the \
                user's own shell or agent session. This is the screen they are \
                looking at: the command that just ran, its output, the error. \
                Reading only; you cannot type into their shell.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "tab": ["type": "integer",
                            "description": "Which tab, as numbered by terminal_tabs. Default: the open one."],
                    "lines": ["type": "integer",
                              "description": "How many lines back from the bottom (default 200)."],
                ],
            ],
        ],
    ]

    /// Run a tool. The pair is (text, isError) — an error is still an answer,
    /// and one the model can act on, so it goes back as text rather than as a
    /// JSON-RPC failure.
    static func call(_ name: String, _ args: [String: Any]) async -> (String, Bool) {
        switch name {
        case "browser_open":  return await browserOpen(args)
        case "browser_read":  return await browserRead(args)
        case "browser_tabs":  return (BrowserTabs.shared.summary(), false)
        case "terminal_tabs": return (AgentTerminalSessions.shared.summary(), false)
        case "terminal_read": return terminalRead(args)
        case "avatar_outfits": return (wardrobe(), false)
        case "avatar_wear":  return wear(args)
        case "image_generate": return await draw(args)
        case "video_generate": return film(args)
        case "video_status": return (DiffuserClient.shared.videoReport, false)
        default:              return ("这个面板没有叫 \(name) 的工具", true)
        }
    }

    // MARK: Browser

    private static func browserOpen(_ args: [String: Any]) async -> (String, Bool) {
        guard let url = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else {
            return ("browser_open 需要一个 url", true)
        }
        guard BrowserTabs.address(url) != nil else {
            return ("\(url) 不像一个网址。要搜索的话，打开搜索引擎的结果页。", true)
        }
        let browser = BrowserTabs.shared
        let newTab = args["new_tab"] as? Bool ?? false
        let id: UUID
        if newTab || browser.tabs.isEmpty {
            id = browser.newTab().id
        } else if let current = browser.selected?.id {
            id = current
            browser.selectedID = current
        } else {
            id = browser.newTab().id
        }
        browser.ensureView(id)
        browser.load(id, text: url)
        let settled = await browser.waitForLoad(id, seconds: 30)
        let state = browser.liveState(id)
        if let error = state.error {
            return ("打不开 \(url)：\(error)", true)
        }
        let text = await browser.pageText(id, limit: 20_000)
        let head = "\(state.title.isEmpty ? "(无标题)" : state.title)\n\(state.url.isEmpty ? url : state.url)"
        if !settled {
            return (head + "\n\n（30 秒还没加载完，下面是目前的内容）\n\n" + text, false)
        }
        return (head + "\n\n" + text, false)
    }

    private static func browserRead(_ args: [String: Any]) async -> (String, Bool) {
        let browser = BrowserTabs.shared
        let limit = min(max(args["chars"] as? Int ?? 20_000, 200), 200_000)
        guard let tab = pick(args["tab"] as? Int, from: browser.tabs.map(\.id),
                             current: browser.selected?.id) else {
            return ("面板的 Web 标签里现在没有打开的页面", true)
        }
        browser.ensureView(tab)
        let state = browser.liveState(tab)
        let text = await browser.pageText(tab, limit: limit)
        if text.isEmpty {
            return ("\(state.url.isEmpty ? "这个标签" : state.url) 还没有可读的内容", true)
        }
        return ("\(state.title.isEmpty ? "(无标题)" : state.title)\n\(state.url)\n\n" + text, false)
    }

    // MARK: Terminals

    private static func terminalRead(_ args: [String: Any]) -> (String, Bool) {
        let sessions = AgentTerminalSessions.shared
        let lines = min(max(args["lines"] as? Int ?? 200, 5), 2000)
        guard let id = pick(args["tab"] as? Int, from: sessions.sessions.map(\.id),
                            current: sessions.selected?.id) else {
            return ("面板的 Term 标签里现在没有打开的终端", true)
        }
        guard let text = sessions.screenText(id, lines: lines) else {
            return ("这个标签还没有启动终端（它的进程要等标签第一次显示才开）", true)
        }
        if text.isEmpty { return ("这个终端目前是空的", false) }
        return (text, false)
    }

    // MARK: Drawing

    private static func draw(_ args: [String: Any]) async -> (String, Bool) {
        guard let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return ("image_generate 需要 prompt", true)
        }
        // A mood or state name puts it in that folder, which is what makes the
        // companion show it at the right moment rather than in the rotation.
        let mood = (args["mood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folder = mood.isEmpty ? CompanionArt.folder
                                  : CompanionArt.folder.appendingPathComponent(mood)
        let client = DiffuserClient.shared
        do {
            let file = try await client.generate(
                prompt: prompt, into: folder,
                steps: args["steps"] as? Int ?? 4,
                width: args["width"] as? Int ?? 768,
                height: args["height"] as? Int ?? 768,
                seed: args["seed"] as? Int
            )
            let where_ = mood.isEmpty ? "陪伴模式的图片池" : "「\(mood)」那一组"
            return ("画好了，存到\(where_)：\(file.path)", false)
        } catch {
            let status = await client.refresh()
            let hint = status.reachable ? "" : "（出图服务在 \(DiffuserClient.host)，看看它在不在）"
            return ("画不出来：\(error.localizedDescription)\(hint)", true)
        }
    }

    /// Start a clip. Answers immediately — see the tool's description for why.
    private static func film(_ args: [String: Any]) -> (String, Bool) {
        guard let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return ("video_generate 需要 prompt", true)
        }
        let mood = (args["mood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folder = mood.isEmpty ? CompanionArt.folder
                                  : CompanionArt.folder.appendingPathComponent(mood)
        // Ten seconds is the point past which a clip stops being a background
        // loop and starts being a wait.
        let seconds = min(max(args["seconds"] as? Double ?? 4, 1), 10)
        let file = DiffuserClient.shared.startVideo(
            prompt: prompt, into: folder, seconds: seconds,
            width: args["width"] as? Int ?? 704,
            height: args["height"] as? Int ?? 480,
            seed: args["seed"] as? Int
        )
        let where_ = mood.isEmpty ? "陪伴模式的图片池" : "「\(mood)」那一组"
        return ("开拍了，\(Int(seconds)) 秒的片子，几分钟后落在\(where_)：\(file.path)（用 video_status 看进度）", false)
    }

    // MARK: Her clothes

    private static func wardrobe() -> String {
        let looks = AvatarStage.characters
        let outfits = VRMWardrobe.outfits
        let real = AvatarServerBox.shared.base != nil
        let threeD = VRMServerBox.shared.base != nil
        guard !looks.isEmpty || !outfits.isEmpty else {
            return "她现在什么形象都没有。真人形象来自数字人服务的视频，3D 形象是 "
                + "\(VRMWardrobe.folder.path) 里的 .vrm 模型（VRoid Hub 上能下）。"
        }
        var lines: [String] = []
        if !looks.isEmpty {
            let wearing = AvatarStage.chosen?.id
            lines.append("真人形象（视频驱动）：")
            lines += looks.map { "\($0.id == wearing && real ? "→" : " ") \($0.name)" }
        }
        if !outfits.isEmpty {
            let wearing = VRMWardrobe.chosen?.id
            if !lines.isEmpty { lines.append("") }
            lines.append("3D 形象（VRM）：")
            lines += outfits.map { "\($0.id == wearing && threeD ? "→" : " ") \($0.name)" }
        }
        lines.append("")
        let visible = CompanionPresence.shared.onScreen
        switch (visible, real, threeD) {
        case (true, true, _): lines.append("她现在以真人形象在屏幕上。")
        case (true, _, true): lines.append("她现在以 3D 形象在屏幕上。")
        case (true, _, _):    lines.append("陪伴模式开着，但她没有形象，只有背景图。")
        default:              lines.append("陪伴模式没开，所以换了要等下次见面才看得到。")
        }
        return lines.joined(separator: "\n")
    }

    /// Wear a look or an outfit. Real people first: a name that matches both is
    /// far likelier to mean the person than the model, and the two surfaces are
    /// one or the other — the 3D canvas covers the panel.
    private static func wear(_ args: [String: Any]) -> (String, Bool) {
        guard let wanted = (args["outfit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !wanted.isEmpty else {
            return ("avatar_wear 需要一个名字", true)
        }
        if let look = AvatarStage.match(wanted) {
            if VRMServerBox.shared.base != nil {
                VRMWardrobe.isEnabled = false
                VRMServerBox.shared.stop()
            }
            AvatarStage.isEnabledSetting = true
            AvatarServerBox.shared.switchCharacter(look)
            AvatarServerBox.shared.startIfWanted()
            return ("换成「\(look.name)」了" + seen(), false)
        }
        if let outfit = VRMWardrobe.match(wanted) {
            if AvatarServerBox.shared.base != nil {
                AvatarServerBox.shared.stop()
            }
            VRMWardrobe.isEnabled = true          // which turns the person off
            VRMStage.shared.wear(outfit)
            VRMServerBox.shared.startIfWanted()
            return ("换成 3D 的「\(outfit.name)」了" + seen(), false)
        }
        let names = AvatarStage.characters.map(\.name) + VRMWardrobe.outfits.map(\.name)
        return names.isEmpty
            ? ("她还没有任何形象可以换", true)
            : ("没有叫「\(wanted)」的，她有的是：" + names.joined(separator: "、"), true)
    }

    /// Whether the change is something the user can see right now, as the end
    /// of a sentence.
    private static func seen() -> String {
        CompanionPresence.shared.onScreen ? "。" : "，等陪伴模式（⇧⌘M）打开就能看到。"
    }

    /// A tab by its 1-based number, as the list tools print them, falling back
    /// to whichever one is in front.
    private static func pick(_ number: Int?, from ids: [UUID], current: UUID?) -> UUID? {
        if let number, number >= 1, number <= ids.count { return ids[number - 1] }
        return current ?? ids.first
    }
}

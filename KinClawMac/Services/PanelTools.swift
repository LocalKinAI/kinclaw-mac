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
                Change how the KinClaw companion looks. `outfit` picks something \
                she has, by name (part of one is enough): a real-person look, a \
                3D model, an outfit she has worn before, or "original" for the \
                clothes the model came in. `repaint` makes a new outfit for the \
                3D companion from a description — her clothes keep their cut \
                and are repainted in any colours, fabric and pattern ("a deep \
                red dress with white lace", "navy sailor uniform with a red \
                ribbon", "black gothic dress, purple ribbons"). Write it in \
                English; about half a minute, and she changes when it lands, \
                so say so rather than waiting. Give it a short `name` so she \
                can wear it again. Use this when the user asks her to change \
                clothes; call avatar_outfits if you do not know what she has.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "outfit": ["type": "string",
                               "description": "A name from avatar_outfits (part of one is enough), or \"original\"."],
                    "repaint": ["type": "string",
                                "description": "A new outfit, described in English: colours, fabric, pattern. The clothes only — no shoes, hair or accessories in this one."],
                    "shoes": ["type": "string",
                              "description": "Optional, with repaint: the shoes, described on their own (\"black patent boots\"). Left out, her shoes stay as they are."],
                    "name": ["type": "string", "description": "Short name to keep a repainted outfit under, e.g. \"red-lace\"."],
                ],
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
            "name": "character_show",
            "description": """
                Who the companion is: her name, the description she was drawn \
                from, whether an anchor portrait exists yet, and how many \
                pictures she has. Read this before drawing her, so a scene is \
                an edit of the same woman rather than a new stranger.
                """,
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "character_new",
            "description": """
                Draw candidate portraits of a new companion from one \
                description, each with a different seed, on the text-to-image \
                server. About 15 seconds each. Nothing is adopted yet — the \
                answer lists the candidates, and character_adopt picks one. \
                Use this only when asked for a new companion or a different \
                look; changing scene or clothes is character_scene.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "look": ["type": "string",
                             "description": "What she looks like, in English: age range, hair, build, the way she dresses. One sentence. An adult, fictional person — never a real or named individual."],
                    "count": ["type": "integer", "description": "How many candidates (default 4, max 8)."],
                ],
                "required": ["look"],
            ],
        ],
        [
            "name": "character_adopt",
            "description": """
                Make one candidate the anchor: every later picture of her is \
                an edit of it, which is what keeps her the same person. Takes \
                one normalising pass through the edit server (about a minute) \
                so the anchor is rendered by the model that will draw the \
                scenes.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "index": ["type": "integer", "description": "Which candidate, 1-based, as character_show lists them."],
                    "raw": ["type": "boolean", "description": "Skip the normalising pass (use when the edit server is down). Default false."],
                ],
                "required": ["index"],
            ],
        ],
        [
            "name": "character_scene",
            "description": """
                Put her somewhere else, or in something else: a kitchen in the \
                morning, a red coat, a night market. This edits her anchor on \
                the edit server, so it is the same woman — the instruction is \
                what changes around her ("change her coat to a red one"), not \
                a description of a person. About a minute. Optionally animates \
                the result, which then runs as a background job.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "instruction": ["type": "string",
                                    "description": "What to change, in English, as an instruction."],
                    "mood": ["type": "string",
                             "description": "File it under one of her moods (开心/温柔/好奇/困/担心) or states (idle/listening/thinking/speaking) so she shows it then."],
                    "clip": ["type": "boolean", "description": "Also animate it (image-to-video, minutes). Default false."],
                    "seconds": ["type": "number", "description": "Clip length if clip is true (default 4)."],
                ],
                "required": ["instruction"],
            ],
        ],
        [
            "name": "character_probe",
            "description": """
                Diagnostic: ask the art picker what it would show for a given \
                state and subject, without waiting for a real reply. Answers \
                with the file it chose and where she ended up. Use it when \
                the background is not changing and it is not clear whether \
                the choice or the display is at fault.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "state": ["type": "string", "description": "idle / listening / thinking / speaking."],
                    "subject": ["type": "string", "description": "The subject keyword a reply would carry, e.g. market."],
                    "say": ["type": "string", "description": "Simulate the user saying this (runs the same matching a real utterance gets)."],
                    "tag": ["type": "string", "description": "Simulate a reply whose tag carries this subject; \"-\" for a reply with no tag."],
                ],
                "required": [],
            ],
        ],
        [
            "name": "character_go",
            "description": """
                Move her to one of her places by name, or back to the main \
                one with an empty name. Use it when the user names somewhere \
                she has — "go to the park", "back to the kitchen". The answer \
                says where she is and which words each place answers to, \
                which is also how to find out why a place did not come up.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "scene": ["type": "string",
                              "description": "A scene name (厨房/海边/公园…), a word it answers to, or \"\" for the main scene."],
                ],
                "required": ["scene"],
            ],
        ],
        [
            "name": "avatar_stage",
            "description": """
                What the 3D stage is doing: whether a model is loaded, what \
                went wrong if it did, how many expressions the model has, and \
                the size of the canvas it is drawing into. Ask this when she \
                should be on screen and is not.
                """,
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "avatar_move",
            "description": """
                Make the 3D companion move. She also wanders and plays by \
                herself when nobody is talking to her.
                - `walk`: come | near | far | left | right | around — inside \
                one of her places.
                - `play`: wave, stretch, spin, jump, pick, look, dance — or the \
                name of a motion she made up before.
                - `hold`: mug | book | phone | umbrella | flower | none — puts \
                it in her hand; she carries it and does what people do with \
                one (sips, reads, glances up from the phone, smells the flower).
                - `sit`: stool (a stool appears and she sits on it) | floor \
                (she kneels) | stand.
                - `compose`: make a motion up, for anything not on that list \
                ("比个心", "鞠躬", "假装投篮"). Give it a `name` and `frames`: \
                keyframes {t: seconds, slider: value, …}. She eases between \
                them, starts from standing and goes back to it by herself, and \
                the motion is kept under its name. A frame names only the \
                sliders that change; a single frame is a pose she moves into, \
                holds for two seconds and leaves. Sliders:
                  (a limb slider ends in L or R for one side — armRaiseL — \
                and with neither it means both)
                  arms — armRaise: -0.2 hanging, 0.45 straight out, 1 \
                overhead · armFront: 0 out to the side, 1 straight ahead, 1.4 \
                across the chest · elbow: 0 straight, 1 folded · armTwist: -1 \
                forearm down, 1 forearm up
                  head — headTurn (+ her left), headNod (+ down), headTilt (+ \
                toward her left shoulder), each -1…1
                  torso — lean (+ forward; 0.8 is a deep bow), twist, bend, -1…1
                  legs — legFront (+ a kick forward, - back), legSide \
                0…1, knee 0…1
                  body — crouch 0…1 (past 0.5 she kneels), sit 0…1 (seated, a \
                stool under her), jump 0…1, turn (1 is half a turn, 2 a full \
                spin), sway -1…1
                  hands — hand (handL / handR): relax | open | fist | point | peace | \
                thumb | ok
                  face — face: neutral | happy | sad | angry | relaxed | \
                surprised · wink: left | right | none · eyes 0…1 shut · mouth \
                0…1 open
                Arm poses known to look right — build from these, animate \
                between them (both arms unless marked):
                  hands together at the chest (clap, pray): armFront 0.8, \
                armRaise 0.3, elbow 0.5 · hands over the head (big heart, \
                cheer): armRaise 0.95, armFront 0.12, elbow 0.82 · hands at \
                the cheeks: armFront 1.25, armRaise 0.12, elbow 0.8 · hand at \
                the chin (one arm): armFront 1, armRaise 0.12, elbow 0.95 · \
                salute (one arm): armRaise 0.5, armFront 0.25, elbow 0.85, \
                armTwist 0.75 · hands on hips: armRaise 0.12, armFront -0.15, \
                elbow 0.62, armTwist -0.55 · arms crossed: armFront 1, \
                armRaise 0.02, elbow 0.72, armTwist -0.75 · a waving arm: \
                armRaise 0.5, elbow 0.5, armTwist 1, then armTwist 1 ↔ 0.5 · \
                pointing ahead: armFront 1, armRaise 0.45, hand point. \
                Forearms folded in front of the face hide it — keep hands at \
                the chest or above the head.
                A bow: [{"t":0},{"t":0.6,"lean":0.8,"headNod":0.4},\
                {"t":1.4,"lean":0.8,"headNod":0.4},{"t":2,"lean":0,"headNod":0}]
                - `motion`: a .vrma file name, "dance", or "" to stop.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "walk": ["type": "string", "description": "come | near | far | left | right | around"],
                    "play": ["type": "string", "description": "A built-in (wave, stretch, spin, jump, pick, look, dance) or the name of a motion she composed."],
                    "hold": ["type": "string", "description": "mug | book | phone | umbrella | flower | none"],
                    "sit": ["type": "string", "description": "stool | floor | stand"],
                    "compose": [
                        "type": "object",
                        "description": "A motion made up on the spot, in the pose language above.",
                        "properties": [
                            "name": ["type": "string", "description": "Short English name to keep it under, e.g. \"bow\", \"heart\"."],
                            "frames": ["type": "array", "items": ["type": "object"],
                                       "description": "Keyframes, each {t: seconds, <slider>: value, …}. One frame is a held pose."],
                            "loops": ["type": "integer", "description": "Times to repeat (default 1)."],
                        ],
                        "required": ["name", "frames"],
                    ] as [String: Any],
                    "motion": ["type": "string",
                               "description": "\"dance\", a .vrma file name from ~/.kinclaw/vrm/motions/, or \"\" to stop."],
                    "loops": ["type": "integer", "description": "How many times to play a file (default 1)."],
                ],
            ],
        ],
        [
            "name": "companion_open",
            "description": """
                Show the panel in companion mode — the picture of her and the \
                voice, no transcript. Use it when the user asks to see her, \
                or to talk face to face. It is also how a scene change gets \
                looked at from outside: without the companion on screen there \
                is nothing to look at.
                """,
            "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
        ],
        [
            "name": "avatar_desktop",
            "description": """
                Put the 3D companion on the desktop as a floating figure in \
                front of every window, or bring her back into the panel. \
                Use it when the user asks for her to be on their desktop, to \
                stand in the corner, or to get out of the way. `through` \
                makes her ignore the mouse, so clicks land on whatever is \
                behind her.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "on": ["type": "boolean", "description": "true puts her on the desktop, false brings her back into the panel."],
                    "through": ["type": "boolean", "description": "Mouse passes through her (she becomes scenery). Optional."],
                ],
                "required": ["on"],
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
        case "avatar_desktop": return desktop(args)
        case "companion_open":
            NotificationCenter.default.post(name: .kinclawOpenCompanion, object: nil)
            return ("陪伴模式打开了", false)
        case "avatar_move":    return await move(args)
        case "avatar_stage":   return (await stageReport(), false)
        case "character_go":   return goToScene(args)
        case "character_probe": return probe(args)
        case "character_show":   return (who(), false)
        case "character_new":    return newCharacter(args)
        case "character_adopt":  return adopt(args)
        case "character_scene":  return await putHer(args)
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
        // A source picture makes this image-to-video: the clip is that
        // picture moving, rather than somebody new who matches the words.
        var source: URL?
        if let path = (args["image"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ("找不到要动起来的那张图：\(url.path)", true)
            }
            source = url
        }
        let file = DiffuserClient.shared.startVideo(
            prompt: prompt, into: folder, seconds: seconds,
            width: args["width"] as? Int ?? 704,
            height: args["height"] as? Int ?? 480,
            seed: args["seed"] as? Int, from: source
        )
        let where_ = mood.isEmpty ? "陪伴模式的图片池" : "「\(mood)」那一组"
        return ("开拍了，\(Int(seconds)) 秒的片子，几分钟后落在\(where_)：\(file.path)（用 video_status 看进度）", false)
    }

    // MARK: The probe

    private static func probe(_ args: [String: Any]) -> (String, Bool) {
        guard let art = CompanionPresence.shared.art else {
            return ("陪伴模式还没开过（⇧⌘M），拿不到她的素材", true)
        }
        if art.scenes.isEmpty { art.reload() }
        // The two events, exactly as the conversation delivers them.
        if let said = args["say"] as? String {
            let before = art.scene?.name ?? "（没定）"
            let heard = art.hear(said)
            return ("用户说「\(said)」→ \(heard.map { "听出了「\($0.name)」" } ?? "没提到她有的地方")"
                  + "｜场景：\(before) → \(art.scene?.name ?? "（没定）")", false)
        }
        if let tag = args["tag"] as? String {
            let before = art.scene?.name ?? "（没定）"
            art.replyTagged(subject: tag == "-" ? "" : tag)
            return ("回复标签 \(tag == "-" ? "（无）" : tag)｜场景：\(before) → \(art.scene?.name ?? "（没定）")"
                  + "｜没提地方 \(art.repliesAwayFromHomeCount)/2", false)
        }
        let state = (args["state"] as? String) ?? "idle"
        let subject = (args["subject"] as? String) ?? ""
        let before = art.scene?.name ?? "（没定）"
        let picked = art.art(for: state, mood: nil, subject: subject, fallback: nil)
        let after = art.scene?.name ?? "（没定）"
        let name = picked.map { $0.deletingLastPathComponent().lastPathComponent + "/" + $0.lastPathComponent }
        return ("state=\(state) subject=\(subject.isEmpty ? "—" : subject)\n"
              + "场景：\(before) → \(after)\n"
              + "选中的文件：\(name ?? "没有")", false)
    }

    // MARK: Where she is

    private static func goToScene(_ args: [String: Any]) -> (String, Bool) {
        guard let wanted = args["scene"] as? String else {
            return ("character_go 需要 scene", true)
        }
        guard let art = CompanionPresence.shared.art else {
            return ("陪伴模式还没开过（⇧⌘M），还拿不到她的场景", true)
        }
        art.reload()
        guard !art.scenes.isEmpty else { return ("她还没有场景", true) }
        let moved = art.goTo(wanted)
        var lines: [String] = []
        if let moved {
            lines.append("她在「\(moved.name)」了")
        } else {
            lines.append("没有叫「\(wanted)」的地方")
        }
        lines.append("她的场景和对应的词：")
        for scene in art.scenes {
            let mark = scene.name == art.scene?.name ? "→ " : "  "
            lines.append("\(mark)\(scene.name)：\(scene.words.prefix(8).joined(separator: " "))")
        }
        if let cue = art.placesCue(building: CompanionCharacter.shared.building) {
            lines.append("这一轮她会被告知：" + cue)
        }
        for (first, second) in CompanionArt.twinScenes() {
            lines.append("⚠️「\(second)」和「\(first)」是同一份素材——去了也看不出换了地方")
        }
        return (lines.joined(separator: "\n"), moved == nil)
    }

    // MARK: The stage, when nobody is on screen

    private static func stageReport() async -> String {
        let status = await VRMStage.shared.snapshot()
        if status.isEmpty { return "3D 那一层没有在跑" }
        var lines: [String] = []
        let ready = (status["ready"] as? Bool) ?? false
        lines.append("页面就绪：\(ready ? "是" : "否")")
        lines.append("模型：\((status["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "没加载")")
        if let error = status["error"] as? String, !error.isEmpty { lines.append("错误：\(error)") }
        if let bridge = status["bridge"] as? String { lines.append("桥这一侧：" + bridge) }
        let calls = CompanionPresence.shared.wantedLog
        if !calls.isEmpty { lines.append("谁在叫她（新→旧）：" + calls.prefix(6).joined(separator: "  ")) }
        if let where_ = status["where"] as? [String: Any], status["place"] is String {
            let depth = where_["depth"] as? Double ?? 0
            let doing = (where_["act"] as? String) ?? ((where_["walking"] as? Bool) == true ? "在走" : "站着")
            lines.append(String(format: "在场景里：离镜头 %.1f 米｜%@｜%@", depth, doing,
                                (where_["attend"] as? Bool) == true ? "有人找她" : "自己玩"))
        }
        if let framing = status["framing"] as? String {
            let lit = status["light"] is [String: Any] ? "跟着场景" : "棚灯"
            let shot = ["portrait": "半身（站在场景前）", "scene": "场景机位（她在里面走）"][framing] ?? "全身"
            lines.append("取景：\(shot)｜灯光：\(lit)")
        }
        if let expressions = status["expressions"] as? [Any] { lines.append("表情数：\(expressions.count)") }
        if let size = status["size"] as? [Any], size.count == 2 {
            lines.append("画布：\(size[0]) × \(size[1])")
        }
        if let frames = status["frames"] { lines.append("已渲染帧：\(frames)") }
        lines.append("在桌面上：\(CompanionOverlay.shared.isOn ? "是" : "否")")
        return lines.joined(separator: "\n")
    }

    // MARK: Moving

    private static func move(_ args: [String: Any]) async -> (String, Bool) {
        if let made = args["compose"] as? [String: Any] {
            guard let frames = made["frames"] as? [[String: Any]] else {
                return ("compose 需要 frames：一组关键帧 {t, 滑杆: 值…}", true)
            }
            return await VRMStage.shared.compose(name: (made["name"] as? String) ?? "",
                                                 frames: frames, loops: made["loops"] as? Int ?? 1)
        }
        // Several of these can come in one call: "sit down with a book".
        var said: [String] = []
        if let what = args["hold"] as? String { said.append(VRMStage.shared.hold(what)) }
        if let how = args["sit"] as? String, !how.isEmpty { said.append(VRMStage.shared.sit(how)) }
        if !said.isEmpty, args["walk"] == nil, args["play"] == nil, args["motion"] == nil {
            return (said.joined(separator: "；"), false)
        }
        if let where_ = args["walk"] as? String, !where_.isEmpty {
            let answer = VRMStage.shared.walk(where_.lowercased())
            return ((said + [answer]).joined(separator: "；"), !answer.hasPrefix("她"))
        }
        if let name = args["play"] as? String, !name.isEmpty {
            let answer = await VRMStage.shared.play(name.lowercased())
            return (answer, answer != "好")
        }
        guard let motion = args["motion"] as? String else {
            return ("avatar_move 需要 walk、play、hold、sit、compose 或 motion 之一", true)
        }
        let answer = VRMStage.shared.move(motion, loops: args["loops"] as? Int ?? 1)
        let files = VRMStage.motions
        let list = files.isEmpty
            ? "。动作文件夹是空的：BOOTH 上 VRoid 官方送七个免费的 .vrma，放进 ~/.kinclaw/vrm/motions/ 就能放"
            : "。现有动作：" + files.joined(separator: "、")
        return (answer + list, answer == "3D 形象没开")
    }

    // MARK: On the desktop

    private static func desktop(_ args: [String: Any]) -> (String, Bool) {
        guard let on = args["on"] as? Bool else { return ("avatar_desktop 需要 on", true) }
        let overlay = CompanionOverlay.shared
        if on, VRMServerBox.shared.base == nil {
            // She needs the 3D stage to stand anywhere: the video looks are
            // rectangles, and a rectangle floating over the desktop is a
            // video player, not somebody in the room.
            if AvatarStage.isEnabled { AvatarStage.isEnabledSetting = false }
            VRMWardrobe.isEnabled = true
            VRMServerBox.shared.startIfWanted()
        }
        on ? overlay.show() : overlay.hide()
        if let through = args["through"] as? Bool { overlay.setClickThrough(through) }
        if !on { return ("收回面板了", false) }
        return ("她站到桌面上了\(overlay.clickThrough ? "（鼠标穿透）" : "，可以拖着走")", false)
    }

    // MARK: Who she is

    private static func who() -> String {
        let her = CompanionCharacter.shared
        her.load()
        var lines: [String] = []
        let name = her.sheet.name.isEmpty ? "（还没名字）" : her.sheet.name
        lines.append("名字：\(name)")
        lines.append("外貌：\(her.sheet.look.isEmpty ? "（还没设定）" : her.sheet.look)")
        if let anchor = her.anchorURL, FileManager.default.fileExists(atPath: anchor.path) {
            lines.append("锚图：\(anchor.path) —— 每张都从这张编辑，所以是同一个人")
        } else {
            lines.append("锚图：还没有。先 character_new 画候选，再 character_adopt 定妆")
        }
        if !her.candidates.isEmpty {
            lines.append("候选（character_adopt 用序号）：")
            for (i, c) in her.candidates.enumerated() {
                lines.append("  \(i + 1). \(c.lastPathComponent)")
            }
        }
        lines.append("她现在有 \(CompanionArt.countOnDisk()) 张图/片")
        // Where she is, and where she can be. A companion that cannot answer
        // "where are you" from her own tools will make something up.
        let scenes = CompanionArt.scenesOnDisk()
        if !scenes.isEmpty {
            let main = UserDefaults.standard.string(forKey: CompanionArt.mainSceneKey) ?? ""
            let named = scenes.map { $0 == main ? "\($0)（主场景）" : $0 }
            lines.append("她的场景：" + named.joined(separator: "、"))
            lines.append("聊到没有的地方，她留在当前场景，同时后台造那个地方（约三分钟），造好了自己切过去")
        }
        if let building = her.building { lines.append("正在造场景：\(building)") }
        // Where she is right now, and how close she is to going home — the
        // two numbers that answer "why is she still at the beach".
        if let art = CompanionPresence.shared.art, !art.scenes.isEmpty {
            lines.append("她此刻在：\(art.scene?.name ?? "（还没定）")"
                       + "｜没提到地方的回复数：\(art.repliesAwayFromHomeCount)/2")
            let tags = CompanionPresence.shared.tags
            if !tags.isEmpty {
                lines.append("她最近几条回复的开头：")
                for tag in tags.prefix(6) { lines.append("   " + tag) }
            }
            if !art.shown.isEmpty {
                lines.append("最近放过的片段（新→旧）：" + art.shown.joined(separator: "  "))
            }
        }
        // What the last operation said, because a caller that started one
        // minutes ago has nowhere else to read it.
        if her.busy { lines.append("正在忙：\(her.note ?? "…")") }
        else if let note = her.note { lines.append("上一步：\(note)") }
        lines.append("服务：画 \(DiffuserClient.host)｜改 \(DiffuserClient.editHost)｜拍 \(DiffuserClient.videoHost)")
        if let trouble = CompanionArt.folderTrouble { lines.append("⚠︎ \(trouble)") }
        return lines.joined(separator: "\n")
    }

    private static func newCharacter(_ args: [String: Any]) -> (String, Bool) {
        guard let look = (args["look"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !look.isEmpty else {
            return ("character_new 需要 look：一句英文的外貌描述", true)
        }
        let count = min(max(args["count"] as? Int ?? 4, 1), 8)
        CompanionCharacter.shared.makeCandidates(look: look, count: count)
        return ("在画 \(count) 张候选，每张约 15 秒。画完用 character_show 看序号，character_adopt 定妆。", false)
    }

    private static func adopt(_ args: [String: Any]) -> (String, Bool) {
        let her = CompanionCharacter.shared
        her.load()
        guard let index = args["index"] as? Int,
              index >= 1, index <= her.candidates.count else {
            return ("序号超出范围：现在有 \(her.candidates.count) 张候选", true)
        }
        let candidate = her.candidates[index - 1]
        if args["raw"] as? Bool == true {
            her.adoptRaw(candidate)
            return ("用了第 \(index) 张当锚图（没过定妆）", false)
        }
        her.adopt(candidate)
        return ("在定妆第 \(index) 张（一次编辑，约一分钟）。之后 character_scene 就都是她了。", false)
    }

    private static func putHer(_ args: [String: Any]) async -> (String, Bool) {
        guard let instruction = (args["instruction"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else {
            return ("character_scene 需要 instruction", true)
        }
        let mood = (args["mood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let her = CompanionCharacter.shared
        switch await her.scene(instruction, mood: mood) {
        case .failure(let error):
            return ("改不出来：\(error.localizedDescription)", true)
        case .success(let file):
            var answer = "有了：\(file.path)"
            if args["clip"] as? Bool == true {
                let seconds = min(max(args["seconds"] as? Double ?? 4, 1), 10)
                let clip = her.clip(from: file, seconds: seconds, mood: mood)
                answer += "\n还在把它拍成 \(Int(seconds)) 秒的片子（图生视频，所以还是她）：\(clip.path)（video_status 看进度）"
            }
            return (answer, false)
        }
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
            // What the model she is wearing has been repainted as.
            if let model = wearing {
                let painted = VRMOutfits.names(for: model)
                let on = VRMOutfits.remembered(for: model)
                lines.append("")
                lines.append("这个模型穿过的（avatar_wear outfit 换回；repaint 现画新的）：")
                lines.append("\(on == nil ? "→" : " ") original（模型自带的那身）")
                lines += painted.map { "\($0 == on ? "→" : " ") \($0)" }
            }
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
        if let words = (args["repaint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            return VRMStage.shared.repaint(words, shoes: (args["shoes"] as? String) ?? "",
                                           name: (args["name"] as? String) ?? "")
        }
        guard let wanted = (args["outfit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !wanted.isEmpty else {
            return ("avatar_wear 需要 outfit（换一身已有的）或 repaint（现画一身新的）", true)
        }
        // Something she has painted before, or back into what she came in.
        if let answer = VRMStage.shared.dress(in: wanted) { return (answer + seen(), false) }
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

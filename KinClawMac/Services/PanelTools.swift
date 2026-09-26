import AppKit
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
            "name": "panel_show",
            "description": "Show the KinClaw panel, optionally on one of its tabs: chat, cowork, code, term, web, film, motion, montage, comfy, jev; or make it full screen. With film, motion, comfy or montage, `ask` hands a request to the agent on that tab's left. Use it when the user asks to see the panel or to go to a tab (\"打开片场\" → film). With mode film, `film` selects a film and `shot` opens that shot's words for rewriting (\"我想改第三个镜头\").",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "mode": ["type": "string", "description": "chat | cowork | code | term | web | film | motion | montage | comfy | jev. Omit to leave the tab as it is."],
                    "film": ["type": "string", "description": "With mode film: the film to show, by id or title."],
                    "shot": ["type": "integer", "description": "With film: open this shot's prompt editor."],
                    "full_screen": ["type": "boolean", "description": "true: the panel goes full screen; false: back to a window. Omit to leave it."],
                    "ask": ["type": "string", "description": "With mode film, motion, comfy or montage: hand these words to the agent docked in that tab (Claude Code or Codex, holding that tab's tools, which plans, asks, runs and checks), starting it if it is not running. For \"让片场的 agent 拍…\" / \"让 Comfy 那边的 agent 做…\"."],
                    "agent": ["type": "boolean", "description": "With mode film, motion, comfy or montage: open that tab's agent dock without saying anything to it."],
                    "resume": ["type": "boolean", "description": "With mode film, motion, comfy or montage: bring that tab's agent back into its last conversation, waiting for the next word — after the app was restarted in the middle of one."],
                ] as [String: Any],
            ],
        ],
        [
            "name": "settings_open",
            "description": "Open KinClaw Mac's Settings window, optionally on one of its tabs. Use it when the user asks for the settings, or has to fill something in there (the box's services and Laya are under backend).",
            "inputSchema": [
                "type": "object",
                "properties": ["tab": ["type": "string", "description": "general | hotkey | backend | agents | skills | voice | mcp | harvest | routines | data | about. Omit to leave it where it is."]],
            ],
        ],
        [
            "name": "box_services",
            "description": """
                The model servers on the user's LAN box: see which are up, \
                start one, or stop one. `draw` (text-to-image), `edit` \
                (changes her scene, clothes, plates), `film` (video), `filmHQ` \
                (the slow high-quality video model, ~45 GB while it works), \
                `laya` (the small decision model that scores film shots and \
                plays in the Jev tab — 2 GB, 23 ms a question on the box), \
                `brain` (kinfer, the box's language-model server — about 35 GB \
                resident and it does not unload by itself, so it and filmHQ \
                should not run together). The others cost a few GB idle and \
                start in seconds, and the app starts them by itself when it \
                needs them; use this when the user asks to turn something on \
                or off, or wants to know what is running.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "status | start | stop. Default status."],
                    "service": ["type": "string", "description": "draw | edit | film | filmHQ | brain | laya. Needed for start and stop."],
                ],
            ],
        ],
        [
            "name": "film_make",
            "description": """
                Make a short film on the user's own machines: shots drawn and \
                filmed on the box, cut together with sound. It runs for minutes \
                to an hour in the background — say so, and follow it with \
                film_status (wait: true). Everything you give is used as \
                written; the studio fills in only what you leave out. Given \
                only `idea`, it writes the storyboard itself.
                Two ways to film. `engine: "ltx"` (about 2 minutes a shot): one \
                continuous activity in one place, each shot carrying on from \
                the last frame of the one before (`kind: "activity"`), or a \
                story of things, places, hands and backs (`kind: "story"`). \
                `engine: "h3"` (about 12 minutes a shot; always a story): a \
                film with people. Its `cast` — each person once, `name` and \
                `look` (40–70 English words: age, face, hair, build, what they \
                wear) — is drawn once as a portrait, each shot's set is drawn \
                with nobody in it, and each shot is filmed from the portraits \
                of its `who` and its set, so faces and clothes stay the same. \
                Give each shot of a person its `who` (the cast's names); a shot \
                of a person with nobody in `who` stops the film instead of \
                being filmed empty, and a shot of nobody is `subject: "place"` \
                or `"thing"`. `picture` is the set exactly as it should be \
                drawn (with nobody in it, on H3) and `h3` the words H3 films \
                from — leave them out and the studio writes them. \
                `stop_after: "frames"` stops once every shot's first frame is \
                made, before the long filming: look at each (film_shot), fix \
                what is wrong (film_edit, film_cast, film_fix_picture), then \
                film_continue. ("sets" stops earlier, once the portraits and \
                sets are drawn.) Worth it on H3, where a wrong frame costs ten \
                minutes.
                The models take every word literally and know nothing you do \
                not say: write what the camera sees, not prose — the body and \
                what each limb does, only what is inside the frame, no \
                similes ("as if holding a ball" draws a ball), no technique \
                names, never a person, animal or object in `motion` or its \
                sound that is not already in the picture. `place` is the one \
                location, said once; `look` what every frame shares. With \
                `lead: true` the companion is in every shot, written as "she", \
                her outfit said once in `wears`. When it is done, look at every \
                shot yourself before saying the film is good: film_guide says \
                how, and how to fix what is wrong.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "A short title."],
                    "idea": ["type": "string", "description": "The user's idea, in their words. Given alone, with no shots, the studio writes the storyboard itself."],
                    "count": ["type": "integer", "description": "With idea alone: how many shots, 2–8. Default 4."],
                    "shape": ["type": "string", "description": "square (1:1, 704×704 — the default) | portrait (9:16, 576×1024, what a phone holds upright) | landscape (16:9)."],
                    "kind": ["type": "string", "description": "story (a sequence of events, each shot drawn on its own) | activity (one continuous performance in one place, each shot carrying on from the last) | auto (default: the studio decides; with engine h3 it is a story)."],
                    "engine": ["type": "string", "description": "ltx (default, ~2 minutes a shot) | h3 (a story with a cast, the same faces throughout, ~12 minutes a shot)."],
                    "cast": [
                        "type": "array",
                        "description": "H3: the people of the story, at most 4, each drawn once as a reference portrait. Omit and the studio casts it from the shots.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string", "description": "As the shots' `who` names them, in English: \"the woman\", \"Peter\"."],
                                "look": ["type": "string", "description": "40–70 English words of what a camera sees: age, face, hair, build, what they wear. No pose, no expression, no setting."],
                            ] as [String: Any],
                            "required": ["name", "look"],
                        ] as [String: Any],
                    ] as [String: Any],
                    "stop_after": ["type": "string", "description": "H3: \"frames\" to stop once every first frame is made (look, fix, then film_continue), \"sets\" to stop once the portraits and sets are drawn. Omit to run straight through."],
                    "pin": ["type": "boolean", "description": "H3: make each shot's first frame from the portraits and the set and pin it where the shot starts. Omit for the user's setting (usually on)."],
                    "music": ["type": ["boolean", "string"], "description": "false: no music under the film. A text: what the music should be. Omit for the user's setting and the studio's choice."],
                    "as_written": ["type": "boolean", "description": "Use every shot's still and motion exactly as written: no pass rereads the pose off the shot before or rewrites the movement, and no reviewer sends a shot back. Default false."],
                    "title_card": ["type": "boolean", "description": "The title over the last shot, faded in and out. Default true."],
                    "grade": ["type": "boolean", "description": "One warm grade over every shot. Default true."],
                    "upscale": ["type": "boolean", "description": "The picture doubled (the longer side at most 1920). Default true."],
                    "look": ["type": "string", "description": "Shared by every frame: \"35mm film still, golden hour, warm palette, shallow depth of field\"."],
                    "place": ["type": "string", "description": "The one location, said once, with the landmarks that make it that spot."],
                    "lead": ["type": "boolean", "description": "true: she (the companion) is in every shot. Default false."],
                    "wears": ["type": "string", "description": "With lead: her outfit for the whole film, shoes included."],
                    "narration_language": ["type": "string", "description": "Language of the voice-over, written and spoken: zh | en | ja | es | fr | it | pt | hi, or \"none\" for a film without one. Omit to follow the idea's language."],
                    "voiceover": ["type": "string", "description": "The whole voice-over as one passage, read over the film in one go, in narration_language. Omit and the studio writes one (or uses each shot's narration)."],
                    "narrator_voice": ["type": "string", "description": "How the narrator sounds, in words (\"a warm, low female voice, unhurried\"). Omit for the studio's choice."],
                    "seconds": ["type": "number", "description": "Length of each shot, 2–10. Default 4 (H3 films at least about 5)."],
                    "retakes": ["type": "integer", "description": "How many times a reviewer that can see may send a shot back with rewritten words, 0–3 (0: no review; H3 at most 1). Omit for the user's setting."],
                    "shots": [
                        "type": "array",
                        "description": "2–12 shots, in order.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "framing": ["type": "string", "description": "Where the camera is: \"wide shot from the front, whole body\", \"close-up of her hands\"."],
                                "still": ["type": "string", "description": "What the photograph shows, literally: posture and limbs, nothing outside the frame, no similes."],
                                "motion": ["type": "string", "description": "What moves: one body movement from that pose, a camera move at most, then the sound."],
                                "subject": ["type": "string", "description": "figure (a person — the default) | thing (an object, close) | place (the place, nobody in it) | her (the companion)."],
                                "who": ["type": "array", "items": ["type": "string"], "description": "H3: which of the cast are in this shot, by name. [] for nobody."],
                                "picture": ["type": "string", "description": "The picture to draw, exactly: on H3 the set with nobody in it (camera, lens, what is there, the light). Omit and the studio writes it."],
                                "h3": ["type": "string", "description": "H3: the words the shot is filmed from, as written. Omit and the studio writes them."],
                                "narration": ["type": "string", "description": "Optional voice-over for this shot: a storyteller's line, sayable in three seconds."],
                                "counts": FilmTools.counts,
                            ] as [String: Any],
                            "required": ["still", "motion"],
                        ] as [String: Any],
                    ] as [String: Any],
                ],
            ],
        ],
        [
            "name": "film_shot",
            "description": """
                Everything about one shot of a film, and its pictures: the \
                words as planned and as actually used, the picture the set was \
                drawn from, who is in it, the words H3 films it from, what you \
                gave as written, the reviewer's verdict, and every file — set, \
                first frame, take — with the exact words each model was given. \
                You see the set, the first frame and the portraits of who is in \
                it. Use it before filming (after stop_after) and whenever a \
                shot came out wrong, to see why.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                ],
                "required": ["film", "shot"],
            ],
        ],
        [
            "name": "film_edit",
            "description": """
                Change what a shot is, before it is filmed or to film it again: \
                any of subject, framing, still, motion, picture, who, h3, \
                narration. What you give is used as written. What was made from \
                the old words is set aside (kept as takes, never deleted) and \
                made again by film_continue: a new picture, still, framing or \
                subject redraws the set and the first frame; new `who` remakes \
                the first frame; new motion or h3 films it again. H3 words you \
                did not write yourself are written again for what changed; \
                `h3: ""` hands them back to the studio. Not while the film is \
                being shot: film_stop first.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                    "subject": ["type": "string", "description": "figure | thing | place | her."],
                    "framing": ["type": "string"],
                    "still": ["type": "string"],
                    "motion": ["type": "string"],
                    "picture": ["type": "string", "description": "The picture to draw, exactly (on H3: the set, nobody in it)."],
                    "who": ["type": "array", "items": ["type": "string"], "description": "Which of the cast are in it; [] for nobody."],
                    "h3": ["type": "string", "description": "The words H3 films it from; \"\" to let the studio write them."],
                    "narration": ["type": "string"],
                ],
                "required": ["film", "shot"],
            ],
        ],
        [
            "name": "film_cast",
            "description": """
                A film's cast (H3). With only `film`: each person, their look, \
                the shots they are in, and their portraits — you see them. With \
                `name` and `look`: adds a person (at most four) or changes one's \
                look, and their portrait is drawn again. With `portrait`: a \
                picture file to use as their portrait as it is (a face you made \
                or chose elsewhere). The first frames of their shots were made \
                from the old portrait and are made again; film_continue goes on.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "name": ["type": "string", "description": "Who, as the shots' `who` names them."],
                    "look": ["type": "string", "description": "40–70 English words of what a camera sees."],
                    "portrait": ["type": "string", "description": "Path of a picture to use as their portrait."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_continue",
            "description": "Carry on with a film that stopped — at stop_after, after film_stop, after an error, or after film_edit / film_cast: every shot not finished is made, finished ones stay, and it is cut at the end. `stop_after` stops again: \"sets\" or \"frames\" (H3).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "stop_after": ["type": "string", "description": "\"sets\" | \"frames\": stop again there. Omit to run to the end."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_status",
            "description": """
                How the films are going: which shot is being drawn or filmed, \
                what is finished, and where the finished file is. With `film` \
                (an id or title) it answers for that one, shot by shot.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "A film's id or title. Omit for all of them."],
                    "wait": ["type": "boolean", "description": "Wait (up to about 45 seconds) for what the studio is doing — filming, a picture being changed, a cut — to finish before answering. Use it instead of asking again and again while something runs for minutes."],
                ],
            ],
        ],
        [
            "name": "motion_make",
            "description": """
                Film her performing a movement taken from a real video: tai \
                chi, a dance, a stretch — anything a sentence cannot describe \
                and a body can show. Only the pose skeleton is taken from the \
                reference (found on this Mac, nothing uploaded but the stick \
                figure); the person, the clothes and the place in the result \
                are hers. The reference should show ONE person, whole body, \
                from a camera that does not move much. It is filmed in \
                ten-second stretches, each carrying on from the last frame of \
                the one before, so it can be as long as the reference: about \
                four and a half minutes of work for ten seconds of film. Use \
                motion_status to follow it. The video must be a file on this \
                Mac that the user may use — their own, or one whose licence \
                allows it (Creative Commons, a stock library); pass where it \
                came from in `credit`, because a published result has to say.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "video": ["type": "string", "description": "Path to the reference video on this Mac. Or give `url`."],
                    "url": ["type": "string", "description": "An address instead of a file (YouTube, TikTok…). Its licence is read first: Creative Commons is fetched; anything else is refused unless `rights` is true."],
                    "rights": ["type": "boolean", "description": "true ONLY when the user has told you, in this conversation, that the video is theirs or that they have permission to use it. Never assume it."],
                    "scene": ["type": "string", "description": "Where she is and what she wears, one sentence, in any language: \"清晨起雾的公园，圆形砖地，穿蓝色棉袄、灰色长裤、白布鞋\"."],
                    "start": ["type": "number", "description": "Second of the reference to start from. Default 0."],
                    "camera": ["type": "string", "description": "skeleton (default: filmed from where the reference was; the movement may travel and turn) | static | orbit | push — the last three are the 3D route: her body is tracked in 3D, put on a blockout set in Blender on the box, and the camera holds still at a quarter view, walks an arc round her, or moves in. She may step and turn: frames one camera cannot read (side-on, front and back look alike) are repaired or filled in, and a track that is still unsteady after that is refused with a sentence."],
                    "place": ["type": "string", "description": "For the 3D route, the blockout set: park (a pavilion, trees, a bench; default) | open (empty ground, trees far off). What it looks like is still said in `scene`."],
                    "seconds": ["type": "number", "description": "How long, 4–120. Default 10."],
                    "title": ["type": "string", "description": "A short title."],
                    "credit": ["type": "string", "description": "Where the movement came from: title, author, address, licence."],
                    "until": ["type": "string", "description": "\"still\": stop once her first picture is drawn — look at it with motion_status(take), then motion_continue. Worth it before minutes of filming."],
                    "scene_as_written": ["type": "boolean", "description": "`scene` is already the English the models should read: used as written, not rewritten."],
                    "words": ["type": "string", "description": "The words the video model films from, as written (English), instead of the studio's own (\"… follows the reference movement exactly, slowly … Static camera. Ambient sound only …\")."],
                ] as [String: Any],
                "required": ["scene"],
            ],
        ],
        [
            "name": "jev_play",
            "description": "Have a decision model play a game in the Jev tab: each move is one multiple-choice question whose options are the legal moves described in words. Games: empire (帝国, a small Age of Empires for two — `blue` against `red`: villagers, three resources, four ages, eight buildings, spearmen/archers/knights that counter one another; one order a side each round; a fallen town centre loses, else the stronger empire at round 100), drive (a five-lane highway: lane, speed and fuel every tick), shooter (a plane shooting down fighters, swoopers and bombers), flappy (Flappy Bird: flap or glide), tetris, 2048, snake, blackjack (200 hands against the dealer; the yardstick is exact basic strategy, so chips and agreement mean something), and three for two players — chess (`white` against `black`), xiangqi, Chinese chess (`red` against `black`), and gomoku, five in a row (`black`, who moves first, against `white`). Players: jev (TypeSafe's API — needs the user's key, which only they can enter in the tab), laya (the open local model of the same kind), llm (a local chat model), duoJev and duoLaya (the fast judge first; when it is unsure, its best three go to the chat model, which is shown the board), deep (the program itself looking as far as the words for a reader look — what a perfect reader could do), heuristic (the game's own evaluator, the yardstick), random. The same seed deals the same game to every player, so they can be compared. Plays up to `moves` moves and reports the score, how often the player agreed with the heuristic, and the time per move.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "game": ["type": "string", "description": "empire | drive | shooter | flappy | tetris | 2048 | snake | blackjack | gomoku | chess | xiangqi. Default: the one showing."],
                    "player": ["type": "string", "description": "jev | laya | llm | duoJev | duoLaya | deep | heuristic | random — for the games played alone. Default: the one selected."],
                    "model": ["type": "string", "description": "When player is llm: which chat model, as for white_model."],
                    "white": ["type": "string", "description": "For chess: who plays White, same choices. Any two can meet: jev against laya, a chat model against the yardstick."],
                    "red": ["type": "string", "description": "For xiangqi: who plays Red, who moves first. For empire: who plays Red, who orders second. Same as `white`."],
                    "blue": ["type": "string", "description": "For empire: who plays Blue, who orders first each round."],
                    "black": ["type": "string", "description": "For chess and xiangqi: who plays Black."],
                    "white_model": ["type": "string", "description": "When white is llm: which chat model — an Ollama model name, or \"http://host:11434|name\" to say which machine's (the box's Ollama has local models that cost no cloud quota). Omit for the app's own pick."],
                    "black_model": ["type": "string", "description": "When black is llm: which chat model."],
                    "moves": ["type": "integer", "description": "How many moves at most. Default 50."],
                    "seed": ["type": "integer", "description": "Which game is dealt. Default: the tab's."],
                ] as [String: Any],
            ],
        ],
        [
            "name": "motion_find",
            "description": "Find reference videos for a movement by topic (\"八段锦\", \"tai chi\", \"ballet barre\"): searches YouTube for Creative Commons videos only, then has the model that can see look at the thumbnails and score each for motion capture — one person, whole body, steady camera. Shows the list in the Motion tab and returns it, best first. Give the user the list and let THEM choose; then motion_make with the chosen `url`.",
            "inputSchema": [
                "type": "object",
                "properties": ["topic": ["type": "string", "description": "What movement to find, in any language."]],
                "required": ["topic"],
            ],
        ],
        [
            "name": "motion_status",
            "description": "How the Motion tab's takes are getting on: what each is doing, and the finished file's path. With `take`: all of that one — each step and segment, the files, the words each model was given, and her first picture and the pose it was drawn from, which you see. `wait: true` waits (up to five minutes) until a take moves on.",
            "inputSchema": ["type": "object", "properties": [
                "take": ["type": "string", "description": "A take's id or title, for all of it."],
                "wait": ["type": "boolean", "description": "Wait until something changes (up to five minutes) before answering."],
            ] as [String: Any]],
        ],
        [
            "name": "motion_stop",
            "description": "Stop the take being filmed in the Motion tab. The segments already filmed stay; motion_continue carries on.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "motion_continue",
            "description": "Carry on with a take that stopped — at until: \"still\", after motion_stop, or after an error: what is done stays, the rest is made. `until: \"still\"` stops again once her first picture is drawn.",
            "inputSchema": ["type": "object", "properties": [
                "take": ["type": "string", "description": "The take's id or title."],
                "until": ["type": "string", "description": "\"still\" to stop once her first picture is drawn."],
            ] as [String: Any], "required": ["take"]],
        ],
        [
            "name": "video_frames",
            "description": "Look at any video on this Mac: up to twelve frames, `every` seconds apart (default 1, sparser for a long one), side by side in one picture with the time on each — you see it. For a Motion take, a Comfy video, anything made.",
            "inputSchema": ["type": "object", "properties": [
                "path": ["type": "string", "description": "The video's path."],
                "every": ["type": "number", "description": "Seconds between frames. Default 1."],
            ] as [String: Any], "required": ["path"]],
        ],
        [
            "name": "books_scan",
            "description": "Walk a folder for books — .txt, .md, .pdf, .epub over 2 KB — and list them on the shelf in the Jev tab. Only names are read, so it is a second for a few thousand files; the title, the dynasty and the author are taken from filenames of the form 书名-朝代-作者. Books already known keep the shelf they were put on.",
            "inputSchema": [
                "type": "object",
                "properties": ["folder": ["type": "string", "description": "The folder to walk. Default: the one in the tab."]],
            ],
        ],
        [
            "name": "books_sort",
            "description": "Put the books on shelves. Each one is a single Choice question to Jev — the shelves are the options — with the title, the dynasty, the author and the first page of the file as the state; what comes back is a probability for every shelf, so a book the model was not sure about is flagged rather than filed quietly. About 150 ms and a few hundred tokens a book. Needs the user's TypeSafe key, which only they can enter, in the Jev tab.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Only this many, for a look before spending on all of them."],
                    "again": ["type": "boolean", "description": "Re-file the ones already done — what to do after the shelves change. Default false."],
                ],
            ],
        ],
        [
            "name": "books_status",
            "description": "What is on each shelf in the Jev tab, how many are still unsorted, how many the model was unsure about, and what Jev has cost so far.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "jev_status",
            "description": "What the Jev tab is doing right now, without touching it: which game, who is playing, whether a game is running, how it stands, moves so far, agreement with the heuristic, time per move, Jev's tokens. Look here before jev_play, which deals a new game over whatever is on the board.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "city_play",
            "description": "Run 放逐之城 in the Jev tab — a town that has to get through its winters (Banished-like): seasons, fields planted in spring and harvested in autumn, firewood for the cold months, houses, families, newcomers, tools. Choose the mayor (me: the user plays with the mouse; computer: the script; jev: TypeSafe's Jev picks which need comes first every few seconds of play; llm: a chat model does), the speed, or a new town. Shows the tab on the town and answers with how it stands. Games start paused unless a speed is given here.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "mayor": ["type": "string", "description": "me | computer | jev | llm. Omit to keep."],
                    "model": ["type": "string", "description": "For llm: \"host|model\" or a model name; empty for the app's own pick."],
                    "speed": ["type": "number", "description": "0 (pause), 1, 2, 4 or 8. A year is four minutes at 1×."],
                    "restart": ["type": "boolean", "description": "true: a new town on a new map."],
                ],
            ],
        ],
        [
            "name": "city_status",
            "description": "How 放逐之城 stands, without touching it: year and month, the mayor, people, the stores, food made and eaten this past year, births, newcomers and deaths by cause, the buildings, the mayor's last decision.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "sandbox_build",
            "description": "沙盒搭建 in the Jev tab — a Minecraft-like world of blocks the user builds in with the mouse (left click puts the block in hand, right click takes one away, drag turns the view). Give a request (\"一座带塔楼的小城堡\") and a chat model writes a plan in the building language, which goes up block by block where the user last clicked; then Jev measures the build and says what it thinks it is and how well it matches the request. Shows the tab and answers, once it stands, with the plan, the measurements and Jev's verdict — up to a few minutes. Without a request it only shows the world.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "request": ["type": "string", "description": "What to build, in any language."],
                    "model": ["type": "string", "description": "The chat model that writes the plan: \"host|model\" or a model name; empty for the app's own pick. Omit to keep."],
                    "judge": ["type": "boolean", "description": "Ask Jev once it stands. Default true."],
                    "new_world": ["type": "boolean", "description": "true: a fresh world first — the old one, and everything built on it, is gone."],
                ],
            ],
        ],
        [
            "name": "sandbox_status",
            "description": "How 沙盒搭建 stands, without touching it: blocks placed, the block in hand, whether a build is going up, the last request and plan, the measurements of the build nearest the last click, and Jev's last verdict.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "sandbox_play",
            "description": "沙盒搭建's seat, as in 放逐之城 — who builds: me (the user, by hand), computer (the script grows a village round the square: homes, a well, fields, a market, a watchtower, a church, a windmill, lamps, a wall, a dock, a bridge), jev (TypeSafe's Jev chooses each next building from options that say what the village has and lacks) or llm (a chat model chooses from the same options). The program finds each a site, levels it, runs a path to the square and raises it block by block. Start or pause, or a new world. Shows the tab and answers with the village so far. The village waits for run: true.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "seat": ["type": "string", "description": "me | computer | jev | llm. Omit to keep."],
                    "model": ["type": "string", "description": "For llm: \"host|model\" or a model name; empty for the app's own pick. Omit to keep."],
                    "run": ["type": "boolean", "description": "true: start growing; false: pause. Omit to keep."],
                    "new_world": ["type": "boolean", "description": "true: a fresh world and an empty village first — the old one is gone."],
                ],
            ],
        ],
        [
            "name": "comfy_templates",
            "description": "ComfyUI's ready-made workflows on the user's box (about 300 that run locally: text-to-image, image editing, video, audio, 3D…), plus the ones the user saved. Search by words in the title, model or tags — e.g. \"qwen\", \"视频\", \"H3\", \"背景\". Returns name, title, category, models and download size. Pass a name to comfy_run.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Words to look for. Empty lists the categories and the user's saved workflows."],
                    "cloud": ["type": "boolean", "description": "Include api_ templates, which call paid cloud services instead of the box. Default false."],
                    "runnable": ["type": "boolean", "description": "Only the ones whose models and nodes are all on the box — what can run right now. Default false; each line says either way."],
                ],
            ],
        ],
        [
            "name": "comfy_run",
            "description": "Run a ComfyUI workflow on the box and bring back what it made (saved under the art folder's comfy/, each run in its own folder with the exact prompt.json it ran) — you see the pictures. Open a template by `template` (a name from comfy_templates), or give only `ask` and the writer model picks the template. `ask` is what the user wants in their words — the writer turns it into the workflow's settings, writing the prompt the way that model wants it (for MiniMax H3 it follows MiniMax's official prompt guide); if it cannot, nothing runs and you are told why. `changes` sets exact values (node and name from comfy_status; a change that matches no setting stops the run and is named). Waits for the result unless wait is false; video workflows take many minutes. A run that fails or is refused is an error, with ComfyUI's reason. Refused while the Film or Motion tab is shooting.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "template": ["type": "string", "description": "Template name. Omit to keep the workflow that is open, or to let `ask` pick one."],
                    "ask": ["type": "string", "description": "What the user wants, in their words."],
                    "changes": ["type": "array", "description": "Exact values: [{\"node\": \"459\", \"name\": \"prompt\", \"value\": \"...\"}].",
                                "items": ["type": "object"]],
                    "files": ["type": "array", "description": "Local files for the workflow's inputs (pictures, videos, sounds): [{\"node\": \"137\", \"path\": \"/path/to/picture.png\"}]. Uploaded to the box. A template's own sample inputs are not on the box, so a workflow that starts from a picture needs this.",
                              "items": ["type": "object"]],
                    "run": ["type": "boolean", "description": "Default true. False only opens and fills the workflow, to look at it with comfy_status first."],
                    "wait": ["type": "boolean", "description": "Default true: wait for the result (a studio agent's call waits up to about fifteen minutes; after that comfy_status wait: true)."],
                    "keep_seed": ["type": "boolean", "description": "Keep the seeds in the form instead of new random ones. A seed you set in `changes` is always kept."],
                ],
            ],
        ],
        [
            "name": "comfy_import",
            "description": "Import a ComfyUI workflow into the Comfy tab's 我的 and open it: a local .json, a PNG ComfyUI made (the graph is inside it), or a link to either (GitHub page links work). Says what the box is missing to run it — models, or community custom nodes.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "A local .json or .png."],
                    "url": ["type": "string", "description": "A link to a .json or .png."],
                ],
            ],
        ],
        [
            "name": "comfy_status",
            "description": "The Comfy tab right now: the open workflow and its settings (node, name, value — what comfy_run's `changes` take), models it needs that the box lacks, whether it is running, and the latest results with their file paths — you see the pictures. `wait: true` waits (up to five minutes) for a run to finish first.",
            "inputSchema": ["type": "object", "properties": [
                "wait": ["type": "boolean", "description": "Wait for the run in progress to finish (up to five minutes) before answering."],
            ] as [String: Any]],
        ],
        [
            "name": "comfy_stop",
            "description": "Stop the ComfyUI workflow that is running (ComfyUI interrupts it on the box).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "montage_ask",
            "description": "Make a video with OpenMontage on the box: shows the Montage tab and says the words to that tab's agent (Claude Code or Codex on the Mac, working ~/OpenMontage on the box through a bridge: it writes, generates with the box's Qwen-Image, H3 and MiniMax Music, and edits), starting it if it is not running. Use it when the user asks for a video by OpenMontage (\"用 OpenMontage 拍…\"). It is slow and it asks the user to approve its script and plan in its terminal; say so.",
            "inputSchema": [
                "type": "object",
                "properties": ["words": ["type": "string", "description": "What to say to the agent, in the user's words."]],
                "required": ["words"],
            ],
        ],
        [
            "name": "montage_stop",
            "description": "End the OpenMontage agent on the box. Its projects stay on the box and on the board; a new agent can be told to carry one on.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "montage_status",
            "description": "The Montage tab: whether OpenMontage's Backlot board is open and on which project, whether the agent on the box is running and on what model, and the last lines of its terminal.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "film_recut",
            "description": "Cut a film again from the files it has — shots, voice-over, music — without making anything new, and finish it: the title over the last shot, one warm grade, the picture doubled (each on unless turned off, here or in film_make). Use after a shot, the narration or the music was replaced by hand, or to change the finishing.",
            "inputSchema": ["type": "object", "properties": [
                "film": ["type": "string", "description": "The film's id or title."],
                "title_card": ["type": "boolean", "description": "The film's title over its last shot. Kept for later cuts."],
                "grade": ["type": "boolean", "description": "One warm grade over every shot. Kept for later cuts."],
                "upscale": ["type": "boolean", "description": "The picture doubled (the longer side at most 1920). Kept for later cuts."],
            ] as [String: Any], "required": ["film"]],
        ],
        [
            "name": "film_rescore",
            "description": "Give a finished film a fitting narrator and background music without filming anything: the writer picks a voice from the box's TTS (and how it should read — grave, warm…) and describes music for MusicGen; every voice-over line is read again in that voice, the music is made on the box (kin audio MusicGen; first use downloads it there, ~4 GB) and laid under the film, lower while the narrator speaks; then it is cut again. Old voice files and cut are kept aside. `music: false` does the voice only.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "music": ["type": "boolean", "description": "Default true."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_stop",
            "description": "Stop what the Film tab or the Motion tab is doing right now — a film being shot, a take being filmed, a review in progress. What is already done stays done and can be carried on (film_reshoot with no shot, or 「接着拍」). The clip the box is already rendering finishes there and is thrown away, so the box is free again within a minute or two. Use it when the user says to stop, or when what is being made is plainly not what they asked for.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "film_review",
            "description": "Review a finished film's shots again without filming anything: for each shot, whether she does the planned action and with how much of her body, whether anything went wrong, what was seen, and the second opinions of Laya and Jev (text decision models that judge the written description against the plan; each is switched on in Settings → Backend, Jev needs the user's TypeSafe key). About ten seconds a shot; read the result with film_status. `opinions_only` skips the looking and asks only Laya/Jev again about the description already written — a second a shot.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "opinions_only": ["type": "boolean", "description": "Only ask Laya/Jev again, on the description the reviewer already wrote. Default false."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_reshoot",
            "description": """
                Redo one shot of a film and cut it again. The easy way is \
                `direction`: the user's wish in a sentence, and the studio \
                rewrites the shot's words to it after looking at the current \
                take. Or write them yourself — a new `framing` or \
                `still` for a different frame, a new `motion` for a different \
                take of the same frame, or neither to simply roll again. Words \
                you give are used as written (same rules as film_make: \
                literal, no similes). Every shot starts from the last frame of \
                the one before it, so a shot that now ends somewhere else \
                leaves the next one starting from a moment that no longer \
                happened: pass `following: true` to redo the shots after it \
                too (about two and a half minutes each). The old takes are \
                kept beside the new ones. Without `shot`, it carries on with a \
                film that stopped: every shot not finished is tried again.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                    "direction": ["type": "string", "description": "What the user wants different, in their own words (\"手再慢一点，脚别动\", \"镜头近一点\"). The studio looks at the current take and rewrites the shot's words itself — prefer this to writing `framing`/`still`/`motion` yourself; pass the user's sentence as they said it."],
                    "framing": ["type": "string", "description": "A new camera position for the shot. Optional."],
                    "still": ["type": "string", "description": "A new frame: her pose, literally. Optional."],
                    "motion": ["type": "string", "description": "A new take: one slow movement, the camera, ambient sound. Optional."],
                    "following": ["type": "boolean", "description": "Also redo every shot after this one, so they carry on from its new ending. Default false."],
                    "narration": ["type": "string", "description": "A new voice-over line for the shot (\"\" removes it). Given alone, nothing is filmed: the line is spoken by the user's TTS and the film is cut again in seconds."],
                    "hq": ["type": "boolean", "description": "Film it on the high-quality model: a little cleaner, five times slower (~9 min a shot), and it needs about 45 GB of the box's memory, so kinfer must be off. For a shot the user is already happy with, never for a draft."],
                    "method": ["type": "string", "description": "How to film it this time. h3 (H3 films: from the cast's portraits and the set — faces stay the same, but things and numbers drift and the camera wanders) | animate (LTX from one picture — the shot's first frame from film_fix_picture if it has one, else its set — about 2 minutes; the shot shows what the picture shows, moving: use it when the picture is right and H3 keeps getting a thing wrong; `motion` is what moves) | move (no video model: the camera glides over the picture — nothing in it changes, so a count stays right; for shots of things and places; the sound of the take it replaces is kept; seconds to make)."],
                    "glide": ["type": "string", "description": "For method move: push_in (default) | pull_out | pan_left | pan_right | rise | fall | hold."],
                    "h3": ["type": "string", "description": "H3 films: this shot's H3 prompt written by you, in H3's own six-part form (subject_definitions / summary / retention_analysis / detailed_description / overall_soundscape / non_diegetic_music), used as written."],
                    "counts": FilmTools.counts,
                    "match": [
                        "type": "object",
                        "description": "A thing in this shot that must look as it does in another shot — {\"thing\": \"bread\", \"like\": 4}. The studio takes the first frame of this shot's take, has the model that can see describe the thing in shot `like`, changes the frame to match, and films from it on LTX. For \"shot 7's bread is not shot 4's\".",
                        "properties": [
                            "thing": ["type": "string", "description": "What, in English: \"bread\", \"the basket\"."],
                            "like": ["type": "integer", "description": "The shot where it looks right."],
                        ] as [String: Any],
                        "required": ["thing", "like"],
                    ] as [String: Any],
                    "later": ["type": "boolean", "description": "Set the shot up but do not film yet: redoing several shots, give later: true to all but the last (or then call film_reshoot with no shot) and they are filmed in one run — each model loaded once, one wait."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_frames",
            "description": """
                Look at one shot of a film: frames one second apart (or \
                `every` seconds) from its take, side by side in one picture \
                with the time on each — you see the picture itself. `like` \
                adds a frame of other shots beside them, to compare ("is it \
                the same bread as shot 4?"). `picture: true` shows what the \
                shot is filmed from instead: its set (H3) or still, and the \
                first frame if film_fix_picture made one. Look at every shot \
                this way before telling the user a film is good, and again \
                after every fix.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                    "every": ["type": "number", "description": "Seconds between frames. Default 1."],
                    "like": ["type": "array", "items": ["type": "integer"], "description": "Other shots to put beside it."],
                    "picture": ["type": "boolean", "description": "Show the pictures it is filmed from instead of the take."],
                ],
                "required": ["film", "shot"],
            ],
        ],
        [
            "name": "film_count",
            "description": """
                Count a thing in a shot, frame by frame — each frame on its \
                own at full size, which is how a count comes out right (from a \
                grid of small frames a model said ten baskets where there were \
                twelve). With `expected` it says which frames are wrong. \
                `picture: true` counts in the picture the shot is filmed from — \
                count the set BEFORE filming a shot whose numbers matter: what \
                the set holds is what H3 keeps.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                    "thing": ["type": "string", "description": "What to count, in English, as it looks: \"woven baskets\", \"round loaves\"."],
                    "expected": ["type": "integer", "description": "How many there should be."],
                    "picture": ["type": "boolean", "description": "Count in the set / first frame instead of the take."],
                    "every": ["type": "number", "description": "Seconds between the frames counted. Default 1."],
                ],
                "required": ["film", "shot", "thing"],
            ],
        ],
        [
            "name": "film_fix_picture",
            "description": """
                Change a shot's picture with words — Qwen-Image edit on the \
                box, about two minutes, in the background (film_status says \
                when it is done). `from`: "set" (the picture an H3 shot is \
                filmed in: the place and the props, nobody in it — change it, \
                then film_reshoot the shot), "take" (a frame of the current \
                take, `at` seconds in, people and all — the result becomes \
                the shot's first frame, to film_reshoot with method animate), \
                or "start" (that first frame again). `like`: shots whose look \
                must be matched, given to the editor as image 2, 3… — so the \
                instruction can say "make the bread exactly like the loaves in \
                image 2". Say precisely what it must become (colour, shape, \
                surface — look at the other shot first; a wrong description \
                gives a wrong picture) and what must stay. The old picture is \
                kept. Look at the result (film_frames picture: true) before \
                filming from it.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot, from 1."],
                    "instruction": ["type": "string", "description": "What to change, precisely, and what must stay. Refer to the other shots' frames as image 2, 3…"],
                    "from": ["type": "string", "description": "set | take | start | new. new: draw the set afresh from `instruction` (the whole picture described, not a change) — three drawings, and the first that shows `counts` right is kept (give `counts` here, or the shot's own are used). For a set whose numbers a change keeps getting wrong: a change keeps the old picture's crowded layout. Default: start if the shot has a first frame, else set."],
                    "at": ["type": "number", "description": "With from: take — seconds into the take. Default 0.2."],
                    "like": ["type": "array", "items": ["type": "integer"], "description": "Shots to match, shown to the editor as image 2, 3…"],
                    "counts": FilmTools.counts,
                ],
                "required": ["film", "shot", "instruction"],
            ],
        ],
        [
            "name": "film_grade",
            "description": """
                Even out a shot's light and colour. Without `shot` it \
                measures every shot (mean brightness 0–255 and colourfulness) \
                so the one that stands out shows. `like` matches another \
                shot; or set `exposure` (stops, ±) and `saturation` (1 = as \
                it is); `off: true` takes a grade away and stops the cut from \
                adding one. The cut already evens out a shot brighter or \
                darker than both its neighbours. The film is cut again.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "film": ["type": "string", "description": "The film's id or title."],
                    "shot": ["type": "integer", "description": "Which shot. Omit to measure them all."],
                    "like": ["type": "integer", "description": "The shot to match."],
                    "exposure": ["type": "number", "description": "Stops of light, -1.5 to 1.5."],
                    "saturation": ["type": "number", "description": "Colourfulness, 0.5 to 1.5; 1 leaves it."],
                    "off": ["type": "boolean", "description": "No grade on this shot, not even an automatic one."],
                ],
                "required": ["film"],
            ],
        ],
        [
            "name": "film_guide",
            "description": "How to take a film from its first cut to one worth showing: what to look at, which tool fixes what, and what the video models can and cannot be trusted with. Read it once before judging or fixing a film.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
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
    /// Where the Jev tab's game stands, in lines: for the end of a game played
    /// by a tool, and for looking without touching.
    private static func jevReport(_ arcade: JevArcade) -> [String] {
        let who = arcade.game.sides.isEmpty ? arcade.player.title
            : arcade.game.sides.enumerated().map { "\($0.element) \(arcade.rivals[$0.offset].title)" }.joined(separator: " 对 ")
        var lines = ["\(arcade.game.title) · \(who) · 种子 \(arcade.seed)：\(arcade.game.status)" + (arcade.game.over ? "（这一局结束了）" : "")]
        for (seat, side) in arcade.game.sides.enumerated() where arcade.seats[seat].moves > 0 {
            let tally = arcade.seats[seat]
            lines.append("\(side)：\(tally.moves) 步，平均 \(tally.spent / tally.moves) ms，和启发式一致 \(100 * tally.agreed / tally.moves)%")
        }
        if arcade.moves > 0, arcade.game.sides.isEmpty {
            lines.append("\(arcade.moves) 步，平均 \(arcade.spent / arcade.moves) ms 一步，和启发式一致 \(Int(100 * arcade.agreed / arcade.moves))%")
        }
        if arcade.tokens > 0 { lines.append("Jev 读了 \(arcade.tokens) tokens ≈ $\(String(format: "%.4f", arcade.cost))") }
        if let last = arcade.last, let picked = last.options.first(where: { $0.id == last.chosen }) { lines.append("最后一步选了：\(picked.label)") }
        if let trouble = arcade.trouble { lines.append("停下来的原因：\(trouble)") }
        // A game for two: the position itself, so that "I could not move" can be looked at.
        if !arcade.game.sides.isEmpty, !arcade.game.position.isEmpty { lines.append("局面：\n" + arcade.game.position) }
        return lines
    }

    /// `image://` lines for the pictures among some files — at most four —
    /// which the caller sees (the kernel attaches them; a studio agent's
    /// relay hands them over as pictures).
    static func pictures(_ files: [URL]) -> [String] {
        files.filter { ["png", "jpg", "jpeg", "webp"].contains($0.pathExtension.lowercased()) }
            .prefix(4).map { "image://\($0.path)" }
    }

    private static func comfyReport() -> String {
        let comfy = ComfyStudio.shared
        var lines: [String] = []
        if let working = comfy.working { lines.append("正在：\(working)\(comfy.progress.map { " \(Int($0 * 100))%" } ?? "")") }
        if let note = comfy.note { lines.append(note) }
        if let t = comfy.current {
            lines.append("打开的工作流：\(t.name)（\(t.title)）")
            for f in comfy.fields {
                let value = f.value.count > 300 ? String(f.value.prefix(300)) + "…" : f.value
                lines.append("  [\(f.node)] \(f.nodeTitle) · \(f.name) = \(value)\(f.options.map { " （可选 \($0.prefix(12).joined(separator: " | "))\($0.count > 12 ? " …" : "")）" } ?? "")")
            }
            for m in comfy.missing {
                lines.append("  缺模型：\(m.directory)/\(m.name)" + (m.partial.map { "（只下了 \(ComfyStudio.gigabytes($0))，中途断了，可以接着下）" } ?? "") + (m.onBox.map { "（盒子上已有：\($0)，可以直接链接）" } ?? m.bytes.map { " \(ComfyStudio.gigabytes($0))" } ?? ""))
            }
        } else {
            lines.append("没有打开的工作流")
        }
        if let run = comfy.runs.first {
            lines.append("最近一次：\(run.title)，\(run.outputs.count) 个文件")
            lines += run.outputs.map { "  \($0.path)" }
        }
        return lines.joined(separator: "\n")
    }

    /// How long a tool may wait for its work before answering, in seconds:
    /// what the caller's relay allows, less a margin. The kernel gives up at
    /// sixty; a studio agent's relay waits fifteen minutes.
    @TaskLocal static var patience: Double = 44
    /// Two-second polls a waiting tool may make. A status call waits five
    /// minutes at most, so whoever is waiting still hears how it goes.
    static var polls: Int { max(1, Int(min(patience, 300) / 2)) }
    static var longPolls: Int { max(1, Int(patience / 2)) }

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
        case "film_frames": return await filmFrames(args)
        case "film_count": return await filmCount(args)
        case "film_fix_picture": return await filmFixPicture(args)
        case "film_grade": return await filmGrade(args)
        case "film_guide": return (FilmStudio.guide, false)
        case "video_generate": return film(args)
        case "video_status": return (DiffuserClient.shared.videoReport, false)
        case "avatar_desktop": return desktop(args)
        case "panel_show":
            var info: [String: Any] = [:]
            if let mode = args["mode"] as? String, !mode.isEmpty { info["mode"] = mode }
            if let full = args["full_screen"] as? Bool { info["fullScreen"] = full }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: info)
            // The tab's own agent: film and comfy have one docked under them.
            // Each of the Studio's tabs has its own agent, on its left.
            let docked = (args["mode"] as? String).flatMap(StudioAgent.Place.init(rawValue:)).map(StudioAgent.of)
            if let agent = docked, let words = (args["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
                agent.say(words)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return ("面板打开了，交给了 \(agent.place.rawValue) 标签的 agent。它会先说打算怎么做，要花时间的事等人点头。\n" + agent.report, false)
            }
            if let agent = docked, args["agent"] as? Bool == true { agent.shown = true }
            if let agent = docked, args["resume"] as? Bool == true, !agent.running {
                agent.start(continuing: true)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return ("接回了 \(agent.place.rawValue) 标签的 agent 上一次的对话。\n" + agent.report, false)
            }
            if let film = args["film"] as? String, !film.isEmpty {
                // After the tab has had a moment to exist: a view that is not
                // on screen yet is not listening yet.
                try? await Task.sleep(nanoseconds: 400_000_000)
                var which: [String: Any] = ["film": film]
                if let shot = args["shot"] as? Int { which["shot"] = shot }
                NotificationCenter.default.post(name: .kinclawFilmShow, object: nil, userInfo: which)
            }
            return ("面板打开了" + ((info["mode"] as? String).map { "，在 \($0) 标签" } ?? ""), false)
        case "settings_open":
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .kinclawOpenSettings, object: nil)
            let sent = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let tab = (args["tab"] as? String)?.lowercased(), !tab.isEmpty {
                NotificationCenter.default.post(name: .kinclawSettingsTab, object: nil, userInfo: ["tab": tab])
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            // What AppKit thinks exists, which is more than the window server
            // will admit to: a window that was made and never ordered in is
            // only visible from in here.
            let windows = NSApp.windows.map { w in
                "\(type(of: w)) 「\(w.title)」 visible=\(w.isVisible) mini=\(w.isMiniaturized) \(Int(w.frame.width))x\(Int(w.frame.height))@(\(Int(w.frame.minX)),\(Int(w.frame.minY))) level=\(w.level.rawValue)"
            }
            let opened = NSApp.windows.contains { $0.isVisible && $0.frame.width >= 700 && !($0 is NSPanel) }
            return ((opened ? "设置窗口打开了" : "设置窗口没出来")
                    + "\n激活策略=\(NSApp.activationPolicy().rawValue) active=\(NSApp.isActive)\n" + windows.joined(separator: "\n"), !(sent && opened))
        case "box_services": return await boxServices(args)
        case "film_make":    return filmMake(args)
        case "film_shot":
            guard let film = args["film"] as? String, let shot = FilmTools.int(args["shot"]) else { return ("film_shot 需要 film 和 shot", true) }
            switch FilmStudio.shared.describeShot(film: film, shot: shot) {
            case .success(let seen): return (([seen.said] + seen.pictures.map { "image://\($0.path)" }).joined(separator: "\n"), false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_edit":
            guard let film = args["film"] as? String, let shot = FilmTools.int(args["shot"]) else { return ("film_edit 需要 film 和 shot", true) }
            switch FilmStudio.shared.editShot(film: film, shot: shot, subject: args["subject"] as? String, framing: args["framing"] as? String,
                                              still: args["still"] as? String, motion: args["motion"] as? String,
                                              picture: args["picture"] as? String, who: args["who"] as? [String],
                                              h3: args["h3"] as? String, narration: args["narration"] as? String) {
            case .success(let said): return (said, false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_cast":
            guard let film = args["film"] as? String else { return ("film_cast 需要 film", true) }
            if let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                switch FilmStudio.shared.setCast(film: film, member: name, look: args["look"] as? String, portrait: args["portrait"] as? String) {
                case .success(let said): return (said, false)
                case .failure(let failure): return (failure.localizedDescription, true)
                }
            }
            switch FilmStudio.shared.describeCast(film: film) {
            case .success(let seen): return (([seen.said] + seen.pictures.map { "image://\($0.path)" }).joined(separator: "\n"), false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_continue":
            guard let film = args["film"] as? String else { return ("film_continue 需要 film", true) }
            switch FilmStudio.shared.resume(film: film, hold: FilmStudio.hold(args["stop_after"])) {
            case .success(let made):
                return ("接着拍「\(made.title)」了" + (made.hold.map { "，会停在\($0 == "sets" ? "布景" : "首帧")" } ?? "，一直拍到剪好")
                        + "。film_status 看进度", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_status":  return await filmStatus(args)
        case "film_reshoot": return filmReshoot(args)
        case "motion_make":
            var args = args
            // Named wrong, a camera or a place became the default without a
            // word: it is said, before a download.
            let cameraName = ((args["camera"] as? String) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if !cameraName.isEmpty, cameraName != "skeleton", MotionStage.Camera(rawValue: cameraName) == nil {
                return ("camera 只能是 skeleton、static、orbit、push", true)
            }
            let placeName = ((args["place"] as? String) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if !placeName.isEmpty, MotionStage.Place(rawValue: placeName) == nil { return ("place 只能是 park、open", true) }
            if (args["video"] as? String ?? "").isEmpty, let address = (args["url"] as? String)?.trimmingCharacters(in: .whitespaces), !address.isEmpty {
                do {
                    let info = try await MotionImport.look(address)
                    guard info.open || (args["rights"] as? Bool) == true else {
                        return ("「\(info.title)」（\(info.author)）的许可是\(info.licence.isEmpty ? "网站的标准许可" : info.licence)，不允许下载再创作。是用户自己的视频或已获授权，才能用：先问清楚，再带 rights: true。", true)
                    }
                    let file = try await MotionImport.fetch(info, into: MotionStudio.root.appendingPathComponent(".imports"))
                    args["video"] = file.path
                    if (args["credit"] as? String ?? "").isEmpty { args["credit"] = info.credit }
                    if (args["title"] as? String ?? "").isEmpty { args["title"] = String(info.title.prefix(24)) }
                } catch { return (error.localizedDescription, true) }
            }
            guard let path = (args["video"] as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return ("motion_make 需要 video（参考视频的路径）或 url", true) }
            let seconds = (args["seconds"] as? Double) ?? Double((args["seconds"] as? Int) ?? 10)
            let start = (args["start"] as? Double) ?? Double((args["start"] as? Int) ?? 0)
            switch MotionStudio.shared.make(video: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                                            title: (args["title"] as? String) ?? "", start: start, seconds: seconds,
                                            scene: (args["scene"] as? String) ?? "", credit: args["credit"] as? String,
                                            camera: MotionStage.Camera(rawValue: cameraName),
                                            place: MotionStage.Place(rawValue: placeName) ?? .park,
                                            hold: (args["until"] as? String) == "still" ? "still" : nil,
                                            sceneEnglish: args["scene_as_written"] as? Bool == true ? (args["scene"] as? String) : nil,
                                            words: (args["words"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }) {
            case .success(let take):
                let minutes = max(1, Int((take.seconds * 27 / 60).rounded())) + (take.camera == nil ? 0 : 2)
                return ("开拍了：「\(take.title)」\(Int(take.seconds)) 秒，分 \(take.segments.count) 段，大约 \(minutes + 2) 分钟"
                        + (take.hold == "still" ? "；画好她的起始画面就停，motion_status(take) 看过再 motion_continue" : "")
                        + "。motion_status(wait: true) 跟着；成片会在 \(take.file.path)", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "jev_play":
            let arcade = JevArcade.shared
            guard !arcade.running else { return ("Jev 标签里正在玩，先等它停", true) }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            if let game = args["game"] as? String { arcade.choose(game) }
            if let name = args["player"] as? String, let player = JevArcade.Player(rawValue: name) { arcade.player = player }
            // The first seat is whoever moves first: White at chess, Red at xiangqi, Black at gomoku.
            let gomoku = (args["game"] as? String ?? arcade.game.id) == "gomoku", empire = (args["game"] as? String ?? arcade.game.id) == "empire"
            let first = gomoku ? args["black"] : empire ? args["blue"] : (args["white"] ?? args["red"])
            let second = gomoku ? args["white"] : empire ? args["red"] : args["black"]
            if let name = first as? String, let player = JevArcade.Player(rawValue: name) { arcade.rivals[0] = player }
            if let name = second as? String, let player = JevArcade.Player(rawValue: name) { arcade.rivals[1] = player }
            if let model = args["model"] as? String { arcade.models[0] = model }
            if let model = (gomoku ? args["black_model"] : empire ? args["blue_model"] : (args["white_model"] ?? args["red_model"])) as? String { arcade.models[0] = model }
            if let model = (gomoku ? args["white_model"] : empire ? args["red_model"] : args["black_model"]) as? String { arcade.models[1] = model }
            if let seed = args["seed"] as? Int, seed > 0 { arcade.seed = UInt64(seed) }
            // 「我」 is somebody at the keyboard; a tool does not move for them.
            if arcade.personSeated { return ("这一局有一方是「我」：那是人在键盘上玩，jev_play 不替人走。换个玩家再来", true) }
            arcade.restart()
            let limit = min(max((args["moves"] as? Int) ?? 50, 1), 2000)
            // A game asked for in conversation is played to be reported, not
            // watched: no pause between moves, and the tab's own pace put back after.
            let pace = arcade.pause
            arcade.pause = 0
            arcade.start(limit: limit)
            // A tool call has about a minute before whoever made it gives up;
            // a model that takes a second a move gets fifty of them, and says so.
            let began = Date()
            while arcade.running, Date().timeIntervalSince(began) < 55 { try? await Task.sleep(nanoseconds: 200_000_000) }
            let cutShort = arcade.running
            arcade.stop()
            arcade.pause = pace
            var lines = jevReport(arcade)
            if cutShort { lines.append("到 55 秒先停在这儿了；在 Jev 标签里点「开始」可以接着玩。") }
            return (lines.joined(separator: "\n"), arcade.trouble != nil && arcade.moves == 0)
        case "books_scan":
            let shelf = BookShelf.shared
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            let folder = (args["folder"] as? String) ?? BookShelf.folder
            if let given = args["folder"] as? String, !given.isEmpty { UserDefaults.standard.set(given, forKey: BookShelf.folderKey) }
            switch shelf.scan(folder) {
            case .success(let count):
                let waiting = shelf.books.filter { $0.shelf == nil }.count
                return ("在 \(folder) 下找到 \(count) 本，其中 \(waiting) 本还没分类。books_sort 分类", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "books_sort":
            let shelf = BookShelf.shared
            guard shelf.working == nil else { return ("正在分类：\(shelf.working!)", true) }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            shelf.sort(again: args["again"] as? Bool ?? false, limit: args["limit"] as? Int)
            if let trouble = shelf.trouble { return (trouble, true) }
            return ("开始分类了。books_status 看进度", false)
        case "books_status":
            let shelf = BookShelf.shared
            var lines: [String] = []
            if let busy = shelf.working { lines.append("正在：\(busy)") }
            if let trouble = shelf.trouble { lines.append("上一次的问题：\(trouble)") }
            let waiting = shelf.books.filter { $0.shelf == nil }.count
            let unsure = shelf.books.filter { $0.shelf != nil && $0.unsure }.count
            lines.append("一共 \(shelf.books.count) 本 · 分好 \(shelf.books.count - waiting) · 还没分 \(waiting) · 不确定 \(unsure)")
            for entry in shelf.counted { lines.append("  \(entry.shelf)：\(entry.books.count)") }
            if shelf.tokens > 0 {
                lines.append("Jev 读了 \(shelf.tokens) token ≈ $\(String(format: "%.4f", Double(shelf.tokens) * 0.042 / 1_000_000))")
            }
            return (lines.joined(separator: "\n"), false)
        case "jev_status":
            let arcade = JevArcade.shared
            let state = arcade.running ? "正在玩" : arcade.game.over ? "这一局结束了" : arcade.moves > 0 ? "停着，没下完" : "还没开始"
            return (([state] + jevReport(arcade)).joined(separator: "\n"), false)
        case "city_play":
            let game = CityGame.shared
            UserDefaults.standard.set("city", forKey: "kinclaw.jev.doing")
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            if args["restart"] as? Bool == true { game.restart() }
            if let raw = args["mayor"] as? String {
                guard let seat = CitySeat(rawValue: raw) else { return ("mayor 只能是 me、computer、jev 或 llm", true) }
                game.seat = seat
            }
            if let model = args["model"] as? String { game.model = model }
            if let speed = (args["speed"] as? Double) ?? (args["speed"] as? Int).map(Double.init) { game.speed = [0, 1, 2, 4, 8].contains(speed) ? speed : 1 }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return (game.report, false)
        case "city_status":
            return (CityGame.shared.report, false)
        case "sandbox_build":
            let game = SandboxGame.shared
            UserDefaults.standard.set("sandbox", forKey: "kinclaw.jev.doing")
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            if args["new_world"] as? Bool == true { game.newWorld() }
            if let model = args["model"] as? String { game.model = model }
            guard let words = (args["request"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
                try? await Task.sleep(nanoseconds: 800_000_000)
                return (game.report, false)
            }
            guard !game.building else { return ("还在盖上一个，等它盖完：sandbox_status 看进度", true) }
            game.request = words
            game.buildFromRequest()
            for _ in 0..<480 {                      // the plan (a model can take minutes) and the blocks going up
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !game.building { break }
            }
            if args["judge"] as? Bool != false, !game.building, game.lastPlan != nil {
                game.judge()
                for _ in 0..<90 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !game.judging { break }
                }
            }
            return (game.report, false)
        case "sandbox_status":
            return (SandboxGame.shared.report, false)
        case "sandbox_play":
            let game = SandboxGame.shared
            UserDefaults.standard.set("sandbox", forKey: "kinclaw.jev.doing")
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "jev", "raise": false])
            if args["new_world"] as? Bool == true { game.newWorld() }
            if let raw = args["seat"] as? String {
                guard let seat = SandboxSeat(rawValue: raw) else { return ("seat 只能是 me、computer、jev 或 llm", true) }
                game.seat = seat
            }
            if let model = args["model"] as? String { game.model = model }
            // After the tab has had a moment to show: its view pauses the village when it goes away.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let run = args["run"] as? Bool { game.setGrowing(run) }
            try? await Task.sleep(nanoseconds: 800_000_000)
            return (game.report, false)
        case "motion_find":
            guard let topic = (args["topic"] as? String)?.trimmingCharacters(in: .whitespaces), !topic.isEmpty else { return ("motion_find 需要 topic", true) }
            let finder = MotionFinder.shared
            guard finder.doing == nil else { return ("还在找「\(finder.topic)」，等一下", true) }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "motion", "raise": false])
            finder.find(topic)
            for _ in 0..<90 {                       // searches and thumbnails: usually under a minute
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if finder.doing == nil { break }
            }
            if let trouble = finder.trouble { return (trouble, true) }
            let lines = finder.found.prefix(10).map { c in
                "· \(c.fit.map { "适合 \($0)/10" } ?? "没看封面")\(c.onTopic == false ? "（不是这个动作）" : "") · \(c.title.prefix(60)) · \(c.author) · \(Int(c.seconds)) 秒 · \(c.address)" + (c.why.map { "\n    \($0)" } ?? "")
            }
            return ("「\(topic)」找到 \(finder.found.count) 个 Creative Commons 视频，已经显示在 Motion 标签里，按适合度排好了：\n" + lines.joined(separator: "\n"), false)
        case "motion_stop":
            guard let what = MotionStudio.shared.stop() else { return ("Motion 没在拍", false) }
            return ("停了「\(what)」：拍好的段留着，motion_continue 接着拍", false)
        case "motion_continue":
            guard let wanted = (args["take"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty else {
                return ("motion_continue 需要 take（id 或标题）", true)
            }
            switch MotionStudio.shared.resume(wanted, hold: (args["until"] as? String) == "still" ? "still" : nil) {
            case .success(let take): return ("接着拍「\(take.title)」了。motion_status(wait: true) 跟着", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "video_frames":
            guard let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
                return ("video_frames 需要 path", true)
            }
            let clip = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: clip.path) else { return ("没有这个文件：\(path)", true) }
            let at = await FilmStudio.moments(in: clip, every: FilmTools.number(args["every"]) ?? 1, most: 12)
            let grabbed = await FilmStudio.frames(of: clip, at: at, largest: 720)
            guard !grabbed.isEmpty else { return ("读不出这段视频的画面：\(path)", true) }
            let sheet = FileManager.default.temporaryDirectory
                .appendingPathComponent("kinclaw-frames-\(abs(clip.path.hashValue))-\(Int(Date().timeIntervalSince1970)).jpg")
            guard FilmStudio.contactSheet(grabbed.map { (String(format: "%.1fs", $0.second), $0.image) }, columns: 4, width: 360, to: sheet) else {
                return ("拼不出图", true)
            }
            return ("\(clip.lastPathComponent)：\(grabbed.count) 帧，在 " + at.map { String(format: "%.1f", $0) }.joined(separator: "、")
                    + " 秒\nimage://\(sheet.path)", false)
        case "motion_status":
            let studio = MotionStudio.shared
            if studio.takes.isEmpty { return ("还没有拍过动作", false) }
            if let wanted = (args["take"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
                guard let take = studio.takes.first(where: { $0.id == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) }) else {
                    return ("没有这一条：\(wanted)", true)
                }
                return (studio.describe(take), false)
            }
            if args["wait"] as? Bool == true {
                // Until a take moves on, or as long as a tool may wait.
                func now() -> String { (studio.progress ?? "") + studio.takes.prefix(8).map { "\($0.state)\($0.finished)" }.joined() }
                let before = now()
                for _ in 0..<polls where studio.progress != nil || studio.working != nil {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if now() != before { break }
                }
            }
            let lines = studio.takes.prefix(8).map { take -> String in
                let state: String
                switch take.state {
                case .waiting: state = "等着"
                case .tracking: state = "在提取动作"
                case .drawing: state = "在画起始画面"
                case .filming: state = "在拍，\(take.finished)/\(take.segments.count) 段好了"
                case .joining: state = "在接起来"
                case .done: state = "拍好了 → \(take.file.path)"
                case .failed: state = "没拍成：\(take.note ?? "")"
                }
                return "「\(take.title)」\(take.id)：\(Int(take.seconds)) 秒，\(state)"
            }
            return ((studio.progress.map { "正在：\($0)\n" } ?? "") + lines.joined(separator: "\n"), false)
        case "comfy_templates":
            let comfy = ComfyStudio.shared
            if comfy.templates.isEmpty { await comfy.refresh() }
            if comfy.templates.isEmpty { return (comfy.note ?? "拿不到 ComfyUI 的模板", true) }
            let cloud = args["cloud"] as? Bool ?? false
            let q = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty, args["runnable"] as? Bool == true {
                if comfy.readiness.isEmpty { await comfy.scan() }
                let ok = (comfy.saved + comfy.templates).filter { comfy.readiness[$0.name]?.runs == true }
                return ("盒子上现在能跑的 \(ok.count) 个：\n" + ok.map { "· \($0.name) — \($0.title)" }.joined(separator: "\n"), false)
            }
            if q.isEmpty {
                let counts = comfy.categories.map { c in "\(c) \(comfy.templates.filter { $0.category == c && (cloud || $0.local) }.count)" }
                return ("分类：" + counts.joined(separator: " · ") + "\n我的：" + (comfy.saved.isEmpty ? "（没有）" : comfy.saved.map(\.name).joined(separator: "、")), false)
            }
            let words = q.split(separator: " ").map(String.init)
            if comfy.readiness.isEmpty { await comfy.scan() }
            let runnable = args["runnable"] as? Bool ?? false
            let hits = (comfy.saved + comfy.templates).filter { t in
                (cloud || t.local) && (!runnable || comfy.readiness[t.name]?.runs == true) && words.allSatisfy { w in
                    [t.name, t.title, t.description, t.category, t.also.joined(separator: " "), t.models.joined(separator: " "), t.tags.joined(separator: " ")].contains { $0.lowercased().contains(w) }
                }
            }
            if hits.isEmpty { return ("没有「\(q)」的模板", false) }
            let lines = hits.prefix(25).map { t in
                "· \(t.name) — \(t.title)（\(t.category)\(t.models.isEmpty ? "" : " · " + t.models.joined(separator: ", "))\(t.size.map { $0 > 0 ? " · " + ComfyStudio.gigabytes($0) : "" } ?? "")\(t.local ? "" : " · 云端付费")）" + {
                    guard let r = comfy.readiness[t.name] else { return "" }
                    return r.runs ? " ✓ 能跑" : !r.nodes.isEmpty ? " ✗ 缺插件" : r.lacking > 0 ? " ✗ 缺 \(r.lacking)/\(r.models) 个模型" : ""
                }()
            }
            return ("\(hits.count) 个\(hits.count > 25 ? "，前 25 个" : "")：\n" + lines.joined(separator: "\n"), false)
        case "comfy_run":
            let comfy = ComfyStudio.shared
            if let busy = comfy.busyElsewhere { return (busy + "，等它拍完", true) }
            guard !comfy.running else { return ("ComfyUI 正在跑一个，先 comfy_status 看看或 comfy_stop", true) }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "comfy", "raise": false])
            if comfy.templates.isEmpty { await comfy.refresh() }
            if let name = args["template"] as? String, !name.isEmpty {
                guard let t = comfy.template(named: name) else { return ("没有叫 \(name) 的模板，用 comfy_templates 找", true) }
                await comfy.open(t)
                guard comfy.current?.id == t.id else { return (comfy.note ?? "打不开 \(name)", true) }
            }
            var done: [String] = []
            if let ask = args["ask"] as? String, !ask.trimmingCharacters(in: .whitespaces).isEmpty {
                // Not done is said, and nothing runs: it used to run the
                // template as it was.
                if let trouble = await comfy.ask(ask) { return ("ask 没做成，没有开跑：\(trouble)", true) }
                if let note = comfy.note { done.append("按 ask：\(note)") }
            }
            guard comfy.current != nil else { return (comfy.note ?? "没有打开的工作流：给 template 或 ask", true) }
            var seeded = args["keep_seed"] as? Bool ?? false
            var missed: [String] = []
            for change in args["changes"] as? [[String: Any]] ?? [] {
                guard let node = change["node"].map({ "\($0)" }), let name = change["name"] as? String, let value = change["value"] else {
                    missed.append("\(change)：要 node、name、value")
                    continue
                }
                guard let field = comfy.fields.first(where: { $0.node == node && $0.name == name }) else {
                    missed.append("node \(node) · \(name)：没有这个设置")
                    continue
                }
                await comfy.set(field, to: FilmTools.text(value))
                // A seed given is the seed wanted, not one to replace.
                if field.isSeed { seeded = true }
            }
            if !missed.isEmpty {
                return ("这些 changes 对不上，没有开跑（comfy_status 看有哪些设置）：\n" + missed.joined(separator: "\n"), true)
            }
            if !(args["changes"] as? [[String: Any]] ?? []).isEmpty { done.append("changes 都改上了") }
            for file in args["files"] as? [[String: Any]] ?? [] {
                guard let node = file["node"].map({ "\($0)" }), let path = file["path"] as? String,
                      FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath),
                      let field = comfy.fields.first(where: { $0.node == node && $0.isFile }) else {
                    return ("files 里这一项用不了（node 不是读文件的节点，或文件不存在）：\(file)", true)
                }
                await comfy.upload(URL(fileURLWithPath: (path as NSString).expandingTildeInPath), into: field)
            }
            if args["run"] as? Bool != false, comfy.missing.isEmpty, comfy.fields.contains(where: \.needsInput), let why = comfy.blocked {
                return (why + "。用 files 传本地文件：" + comfy.fields.filter(\.needsInput).map { "node \($0.node)（\($0.nodeTitle)）" }.joined(separator: "、"), true)
            }
            if !comfy.missing.isEmpty {
                return ("「\(comfy.current?.title ?? "")」缺模型，盒子上没有：\n" + comfy.missing.map { "· \($0.directory)/\($0.name) \($0.bytes.map(ComfyStudio.gigabytes) ?? "")" }.joined(separator: "\n")
                        + "\n下载要用户在 Comfy 标签里点「下载」确认。", true)
            }
            if args["run"] as? Bool == false { return ((done + [comfyReport()]).joined(separator: "\n"), false) }
            let before = comfy.runs.first?.id
            comfy.run(keepSeed: seeded ? true : nil)
            guard comfy.running else { return ("没跑起来：" + (comfy.note ?? "不知道为什么"), true) }
            guard args["wait"] as? Bool ?? true else {
                return ((done + ["开始跑「\(comfy.current?.title ?? "")」，comfy_status(wait: true) 等结果"]).joined(separator: "\n"), false)
            }
            // As long as the caller's relay waits (a studio agent's: minutes).
            for _ in 0..<longPolls {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !comfy.running { break }
            }
            if comfy.running {
                return ((done + ["还在跑（\(comfy.working ?? "")\(comfy.progress.map { " \(Int($0 * 100))%" } ?? "")），comfy_status(wait: true) 接着等"]).joined(separator: "\n"), false)
            }
            // This run's result and only this one's: a refused or failed run
            // used to answer with the files of the run before it.
            guard let run = comfy.runs.first, run.id != before, !run.outputs.isEmpty else {
                return ("没跑成：" + (comfy.note ?? "没有拿到输出"), true)
            }
            return ((done + [comfy.note ?? "好了", "这次的输出（\(run.folder.path)，里面有 prompt.json 和 run.json）："]
                     + run.outputs.map { "  \($0.path)" } + Self.pictures(run.outputs)).joined(separator: "\n"), false)
        case "comfy_import":
            let comfy = ComfyStudio.shared
            guard !comfy.running else { return ("ComfyUI 正在跑，等它跑完", true) }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "comfy", "raise": false])
            if let path = args["path"] as? String, !path.isEmpty {
                let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: file.path) else { return ("没有这个文件：\(path)", true) }
                await comfy.importWorkflow(from: file)
            } else if let url = args["url"] as? String, !url.isEmpty {
                await comfy.importWorkflow(from: url)
            } else {
                return ("comfy_import 需要 path 或 url", true)
            }
            var report = comfyReport()
            if !comfy.missingNodes.isEmpty { report = "缺社区节点：\(comfy.missingNodes.joined(separator: "、"))\n" + report }
            return (report, comfy.current == nil)
        case "comfy_status":
            if args["wait"] as? Bool == true, ComfyStudio.shared.running {
                for _ in 0..<polls {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !ComfyStudio.shared.running { break }
                }
            }
            return (comfyReport() + (ComfyStudio.shared.running ? "" : "\n" + Self.pictures(ComfyStudio.shared.runs.first?.outputs ?? []).joined(separator: "\n")), false)
        case "comfy_stop":
            guard ComfyStudio.shared.running else { return ("ComfyUI 没在跑", false) }
            ComfyStudio.shared.stop()
            return ("停了", false)
        case "montage_ask":
            guard let words = (args["words"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
                return ("要说点什么：想拍什么", true)
            }
            NotificationCenter.default.post(name: .kinclawShowPanel, object: nil, userInfo: ["mode": "montage", "raise": false])
            let agent = StudioAgent.montage
            let was = agent.running
            agent.say(words)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return ((was ? "说给 Montage 的 agent 了。" : "开了 Montage 的 agent（\(agent.whereTitle)，\(agent.brainTitle)，经桥操作盒子上的 OpenMontage），第一句就是这个。")
                    + "它会在终端里问你批不批剧本和计划；过程在 Montage 标签上面的看板上。\n" + MontageStudio.shared.report, false)
        case "montage_status":
            return (MontageStudio.shared.report, false)
        case "montage_stop":
            guard StudioAgent.montage.running else { return ("Montage 的 agent 没在跑", false) }
            StudioAgent.montage.stop()
            return ("停了。项目还在盒子上，看板上能看", false)
        case "film_recut":
            guard let id = args["film"] as? String else { return ("film_recut 需要 film", true) }
            switch FilmStudio.shared.recut(film: id, titleCard: args["title_card"] as? Bool, grade: args["grade"] as? Bool,
                                           upscale: args["upscale"] as? Bool) {
            case .success(let film): return ("在重新剪「\(film.title)」", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_rescore":
            guard let id = args["film"] as? String else { return ("film_rescore 需要 film", true) }
            switch FilmStudio.shared.rescore(film: id, music: args["music"] as? Bool ?? true) {
            case .success(let film): return ("在给「\(film.title)」重新配音\((args["music"] as? Bool ?? true) ? "配乐" : "")，完成后重新剪。film_status 看进度", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        case "film_stop":
            let film = FilmStudio.shared.stop(), motion = MotionStudio.shared.stop()
            if film == nil, motion == nil { return ("片场和动作都没在忙，没什么可停的", false) }
            let said = [film.map { "片场停了（\($0)）" }, motion.map { "动作停了（\($0)）" }].compactMap { $0 }
            return (said.joined(separator: "；") + "。已经做好的留着，「接着拍」可以继续", false)
        case "film_review":
            guard let film = args["film"] as? String else { return ("film_review 需要 film", true) }
            guard FilmStudio.shared.shooting == nil, FilmStudio.shared.revising == nil else { return ("片场正忙，等这一条拍完", true) }
            if args["opinions_only"] as? Bool == true {
                // Quick enough to wait for, and the caller wants the numbers.
                let result: Result<FilmStudio.Film, FilmStudio.Failure> = await withCheckedContinuation { done in
                    FilmStudio.shared.reassess(film: film, opinionsOnly: true) { done.resume(returning: $0) }
                }
                switch result {
                case .failure(let failure): return (failure.localizedDescription, true)
                case .success(let made): return await call("film_status", ["film": made.id])
                }
            }
            FilmStudio.shared.reassess(film: film)
            return ("在重新把关（每个镜头十来秒，不重拍）。film_status 看结果", false)
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

    // MARK: The box

    private static func boxServices(_ args: [String: Any]) async -> (String, Bool) {
        let box = BoxServices.shared
        let action = ((args["action"] as? String) ?? "status").lowercased()
        if action == "start" || action == "stop" {
            guard let name = args["service"] as? String,
                  let kind = BoxServices.Kind.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) else {
                return ("service 填 draw、edit、film、filmHQ 或 brain", true)
            }
            guard !BoxServices.ssh.isEmpty else {
                return ("还没填盒子的 SSH：Settings → Backend → 盒子上的服务", true)
            }
            if action == "start" { await box.start(kind) } else { await box.stop(kind) }
        }
        await box.refresh()
        await box.refreshMemory()
        var lines = BoxServices.all.map { service -> String in
            let state = box.states[service.kind] ?? .unknown
            let word = [BoxServices.State.up: "开着", .down: "关着", .starting: "启动中", .stopping: "停止中"][state] ?? "不知道"
            return "\(service.kind.rawValue)（\(service.title)）：\(word) · \(BoxServices.model(service.kind)) · \(BoxServices.base(service.kind).replacingOccurrences(of: "http://", with: ""))"
        }
        if let free = box.memoryFree { lines.append("盒子内存空闲 \(free)%") }
        if let note = box.note { lines.append("⚠︎ \(note)") }
        return (lines.joined(separator: "\n"), box.note != nil && action != "status")
    }

    // MARK: The film studio

    private static func filmMake(_ args: [String: Any]) -> (String, Bool) {
        let shots = ((args["shots"] as? [[String: Any]]) ?? []).compactMap { FilmStudio.Draft($0) }
        let engine = FilmStudio.Engine(rawValue: (args["engine"] as? String) ?? "") ?? .ltx
        // H3 films stories. Asked for H3 without a kind, the film was read as
        // "auto", which is not a story, and filmed on LTX without a word.
        let asked = FilmStudio.Kind(rawValue: (args["kind"] as? String) ?? "") ?? .auto
        let kind = engine == .h3 && asked == .auto ? .story : asked
        let cast = ((args["cast"] as? [[String: Any]]) ?? []).compactMap { row -> FilmStudio.Cast? in
            guard let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return FilmStudio.Cast(name: name, look: ((row["look"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let hold = FilmStudio.hold(args["stop_after"])
        let pin = args["pin"] as? Bool
        // `music`: false for none, or the words for it.
        let withMusic = (args["music"] as? Bool) ?? ((args["music"] as? String).map { !$0.isEmpty } ?? nil)
        let brief = args["music"] as? String
        // An idea and no shots: the studio writes the storyboard itself, with
        // the brain the app already uses. The same road the Film tab takes.
        if shots.isEmpty, let idea = (args["idea"] as? String)?.trimmingCharacters(in: .whitespaces), !idea.isEmpty {
            guard FilmStudio.shared.shooting == nil else { return ("片场正在拍别的，等它拍完", true) }
            FilmStudio.shared.make(from: idea, shots: (args["count"] as? Int) ?? 4, lead: (args["lead"] as? Bool) ?? false,
                                   tongue: args["narration_language"] as? String, retakes: args["retakes"] as? Int,
                                   shape: FilmStudio.Shape(rawValue: (args["shape"] as? String) ?? "") ?? .square,
                                   kind: kind, engine: engine, cast: cast.isEmpty ? nil : cast, hold: hold,
                                   pinFrames: pin, withMusic: withMusic)
            return ("在写分镜了（十几秒到一分钟），写好就开拍" + (engine == .h3 ? "（H3 · 故事）" : "") + "。film_status 看进度", false)
        }
        let seconds = (args["seconds"] as? Double) ?? Double((args["seconds"] as? Int) ?? (engine == .h3 ? 5 : 4))
        // A shot list written by the caller can still be a story, shot on H3,
        // in any shape: what the reading step would have said is said here.
        let source = (args["source"] as? String) ?? ""
        let told: FilmStudio.Understanding? = kind == .auto && source.isEmpty ? nil
            : FilmStudio.Understanding(about: (args["idea"] as? String) ?? "", continuous: kind == .activity,
                                       source: source, lead: (args["lead"] as? Bool) ?? false,
                                       text: (args["source_text"] as? String) ?? "")
        switch FilmStudio.shared.make(title: (args["title"] as? String) ?? "", idea: (args["idea"] as? String) ?? "",
                                      look: (args["look"] as? String) ?? "", place: (args["place"] as? String) ?? "",
                                      wears: (args["wears"] as? String) ?? "",
                                      lead: (args["lead"] as? Bool) ?? false,
                                      seconds: seconds, shots: shots,
                                      tongue: (args["narration_language"] as? String) ?? "",
                                      retakes: args["retakes"] as? Int, read: told,
                                      shape: FilmStudio.Shape(rawValue: (args["shape"] as? String) ?? "") ?? .square,
                                      engine: engine, cast: cast, hold: hold, pinFrames: pin, withMusic: withMusic,
                                      literal: args["as_written"] as? Bool ?? false,
                                      finishing: (args["title_card"] as? Bool, args["grade"] as? Bool, args["upscale"] as? Bool)) {
        case .success(let film):
            FilmStudio.shared.presetSound(film: film.id, voice: args["narrator_voice"] as? String,
                                          voiceover: args["voiceover"] as? String, music: brief)
            let h3 = film.engine == .h3
            let minutes = h3 ? film.shots.count * 13 + max(film.cast?.count ?? 1, 1) * 2
                             : max(1, Int((Double(film.shots.count) * (20 + film.seconds * 21) / 60).rounded()))
            let how = h3 ? "H3 · 故事（每镜从演员的定妆照和布景拍）"
                         : film.continuous == false ? "LTX · 故事（每镜各画各的）" : "LTX · 一镜接一镜"
            return ("开拍了：「\(film.title)」\(film.shots.count) 个镜头，\(how)，\((film.shape ?? .square).title)，大约 \(minutes) 分钟"
                  + (film.hold.map { "；会停在\($0 == "sets" ? "布景" : "首帧")，看过、改过再 film_continue" } ?? "")
                  + "。film_status 看进度；成片会在 \(film.file.path)", false)
        case .failure(let failure):
            return (failure.localizedDescription, true)
        }
    }

    private static func filmStatus(_ args: [String: Any]) async -> (String, Bool) {
        let studio = FilmStudio.shared
        if args["wait"] as? Bool == true {
            // Until something changes — a shot done, a stop, the cut — or as
            // long as a tool may wait: each answer says something new.
            func now() -> String {
                let film = (args["film"] as? String).flatMap { studio.film(named: $0) }
                    ?? studio.shooting.flatMap { studio.film(named: $0) }
                return [studio.shooting ?? "", studio.revising ?? "", studio.writing ?? "",
                        film.map { "\($0.state.rawValue) \($0.note ?? "") " + $0.shots.map(\.state.rawValue).joined(separator: ",") } ?? ""]
                    .joined(separator: "|")
            }
            let before = now()
            for _ in 0..<polls where studio.shooting != nil || studio.revising != nil || studio.writing != nil {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if now() != before { break }
            }
            // The time first. Waiting on an eight-minute take answers the same
            // thing three times running, and the kernel reads three identical
            // answers as a loop going nowhere and tells the agent to give up.
            let clock = DateFormatter()
            clock.dateFormat = "HH:mm:ss"
            let busy = studio.shooting.map { "在拍「\($0)」" } ?? studio.revising ?? studio.writing.map { "在写分镜：\($0)" }
            let (said, failed) = await filmStatus(args.filter { $0.key != "wait" })
            return ("\(clock.string(from: Date()))\(busy.map { " 还在忙：\($0)" } ?? " 手上的事做完了")\n" + said, failed)
        }
        let words: [FilmStudio.Shot.State: String] = [.waiting: "等着", .drawing: "在画", .filming: "在拍", .reviewing: "在把关",
                                                      .done: "好了", .failed: "没拍成"]
        if let wanted = (args["film"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
            guard let film = studio.films.first(where: { $0.id == wanted || $0.title == wanted || $0.id.hasPrefix(wanted) }) else {
                return ("没有这部片子：\(wanted)", true)
            }
            var lines = ["「\(film.title)」\(film.id)：\(describe(film))"]
            // How it is being made, all of it: an agent should not have to
            // guess which of the tab's switches a film took.
            var how = [film.engine == .h3 ? "H3 · 故事" : film.continuous == false ? "LTX · 故事" : "LTX · 一镜接一镜",
                       (film.shape ?? .square).title, "每镜 \(String(format: "%.1f", film.engine == .h3 ? FilmStudio.h3Seconds(film.seconds) : film.seconds)) 秒",
                       "把关 \(film.retakeLimit ?? FilmStudio.retakes) 次"]
            if film.engine == .h3 { how.append("钉帧" + ((film.pinFrames ?? FilmStudio.pinOn) ? "开" : "关") + (film.pinFrames == nil ? "（跟着片场的开关）" : "")) }
            how.append("配乐" + ((film.withMusic ?? FilmStudio.musicOn) ? "开" : "关") + (film.withMusic == nil ? "（跟着片场的开关）" : ""))
            if let hold = film.hold { how.append("会停在" + (hold == "sets" ? "布景" : "首帧")) }
            how.append("片名" + (film.titleCard ?? true ? "开" : "关") + "、调色" + (film.finishGrade ?? true ? "开" : "关")
                       + "、放大" + (film.upscale ?? true ? "开" : "关"))
            lines.append("  " + how.joined(separator: " · "))
            if let place = film.place { lines.append("  地点：\(place)") }
            if let narrator = film.narrator { lines.append("  旁白：\(narrator.voice ?? narrator.speaker)\(narrator.instruct.map { "（\($0)）" } ?? "")") }
            if let passage = film.voiceover { lines.append("  旁白稿：\(passage)") }
            if let score = film.score {
                lines.append("  配乐：\(score)" + (FileManager.default.fileExists(atPath: film.music.path) ? " → \(film.music.path)" : "（还没做）"))
            }
            if film.engine == .h3 {
                let cast = (film.cast ?? []).enumerated().map { "\($0.element.name)（\(film.castPicture($0.offset).path)）" }
                lines.append("  用 H3 拍" + ((film.pinFrames ?? FilmStudio.pinOn) ? "，钉帧（每镜先做好第一帧再拍）" : "")
                             + (cast.isEmpty ? (film.cast == nil ? "，还没选角" : "，没有要选的角色") : "，演员：" + cast.joined(separator: "、")))
            }
            for shot in film.shots {
                let camera = shot.framing.map { "〔\($0)〕" } ?? ""
                lines.append("  \(shot.id). [\(words[shot.state] ?? "?")] \(camera)\(shot.pose.prefix(90))" + (shot.note.map { " —— \($0)" } ?? ""))
                lines.append("     动作：\(shot.action.prefix(120))")
                if film.engine == .h3 || film.continuous == false {
                    var parts = ["拍的是 \(shot.of.rawValue)"]
                    if film.engine == .h3 { parts.append("有谁：" + ((shot.who ?? []).isEmpty ? (shot.who == nil ? "还没分" : "没有人") : shot.who!.joined(separator: "、"))) }
                    if let picture = shot.picture { parts.append("画面描述：\(picture.prefix(80))…") }
                    if film.engine == .h3 { parts.append(shot.h3 == nil ? "H3 提示词还没写" : "H3 提示词已写") }
                    if let given = shot.given, !given.isEmpty { parts.append("照原样：" + given.joined(separator: "、")) }
                    lines.append("     " + parts.joined(separator: " · ") + "（全文：film_shot）")
                }
                if let wish = shot.wish { lines.append("     方向：\(wish)") }
                if let score = shot.score {
                    let again = (shot.retakes ?? 0) > 0 ? "，自动重拍了 \(shot.retakes!) 次" : ""
                    lines.append("     把关：\(score)/10\(again)" + ((shot.review ?? "").isEmpty ? "" : "，\(shot.review!)"))
                }
                for (who, on, numbers) in [("Laya", FilmStudio.layaOn, shot.laya), ("Jev", FilmStudio.jevOn, shot.jev)] {
                    guard on, let read = numbers, !read.isEmpty else { continue }
                    let said = read.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2f", $0.value))" }
                    let weight = who == "Jev" && FilmStudio.jevCounts ? "follows < 0.30 算不过" : "只显示，不参与决定"
                    lines.append("     \(who)（\(weight)）：" + said.joined(separator: " · "))
                }
                if let said = shot.narration { lines.append("     旁白：\(said)") }
                var how: [String] = []
                if let method = shot.method { how.append("拍法 \(method.title)\(shot.glide.map { "（\($0.title)）" } ?? "")") }
                if let checks = shot.checks, !checks.isEmpty { how.append("要数：" + checks.map { "\($0.thing) \($0.count)" }.joined(separator: "、")) }
                if let grade = shot.grade, !grade.neutral {
                    how.append("调色 \(String(format: "%+.2f", grade.exposure)) EV、饱和 ×\(String(format: "%.2f", grade.saturation))\(grade.auto == true ? "（自动）" : "")")
                }
                if FileManager.default.fileExists(atPath: film.start(shot.id).path) { how.append("起始画面 \(film.start(shot.id).path)") }
                if !how.isEmpty { lines.append("     " + how.joined(separator: " · ")) }
            }
            if let busy = studio.revising { lines.append("正在：\(busy)") }
            if film.state == .done {
                lines.append("成片：\(film.file.path)" + (film.loudness.map { "（响度 \(String(format: "%.1f", $0)) LUFS）" } ?? ""))
            }
            if FilmStudio.jevOn, let trouble = studio.jevTrouble { lines.append("Jev 没答上来：\(trouble)") }
            if studio.jevTokens > 0 { lines.append("Jev 这次开机以来读了 \(studio.jevTokens) 个 token（$0.042 / 百万）") }
            return (lines.joined(separator: "\n"), false)
        }
        var header: [String] = []
        // Who would write the next storyboard — discovered, so worth saying.
        if let pick = await FilmStudio.writer(claude: true) {
            let pinned = !(UserDefaults.standard.string(forKey: "kinclaw.film.writer") ?? "").isEmpty
            if pick.model == ClaudeWriter.model, UserDefaults.standard.string(forKey: "kinclaw.film.writer.host") == ClaudeWriter.pick {
                header.append("分镜由 \(ClaudeWriter.title) 写（指定的；看图把关、首帧和配乐的描述也是它）")
            } else {
                header.append("分镜由 \(pick.model) 写（\(pick.host.replacingOccurrences(of: "http://", with: ""))，\(pinned ? "指定的" : "自动挑的")）")
            }
        } else {
            header.append("分镜：找不到可用的模型（配置的 Ollama 和本机上都没有）")
        }
        if let idea = studio.writing { header.append("在写分镜：\(idea)") }
        if let trouble = studio.trouble { header.append("上一次没成：\(trouble)") }
        guard !studio.films.isEmpty else { return ((header + ["还没拍过片子。film_make 拍一部"]).joined(separator: "\n"), false) }
        let lines = header + studio.films.prefix(8).map { "「\($0.title)」\($0.id)：\(describe($0))" }
        return (lines.joined(separator: "\n"), false)
    }

    private static func describe(_ film: FilmStudio.Film) -> String {
        // The note in every state: what a picture change found is written
        // there, and a film waiting to be filmed used to hide it.
        let note = film.note.map { "（\($0)）" } ?? ""
        switch film.state {
        case .waiting:  return "等着开拍" + note
        case .shooting: return "在拍，\(film.finished)/\(film.shots.count) 个镜头好了" + note
        case .cutting:  return "在剪" + note
        case .done:     return "拍好了，\(film.finished) 个镜头" + note
        case .failed:   return "没拍成：" + (film.note ?? "")
        }
    }

    private static func filmReshoot(_ args: [String: Any]) -> (String, Bool) {
        guard let film = args["film"] as? String else { return ("film_reshoot 需要 film", true) }
        // No shot named: carry on with whatever is not finished.
        guard let shot = args["shot"] as? Int else {
            switch FilmStudio.shared.resume(film: film) {
            case .success(let made):
                let left = made.shots.filter { $0.state != .done }.count
                return ("接着拍「\(made.title)」：还有 \(left) 个镜头，拍完重新剪", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        }
        // A new line and nothing else: spoken and cut again, nothing filmed.
        if let line = args["narration"] as? String, args["still"] == nil, args["motion"] == nil, args["hq"] == nil,
           args["framing"] == nil, args["following"] == nil {
            switch FilmStudio.shared.narrate(film: film, shot: shot, line: line) {
            case .success(let made):
                return ("「\(made.title)」第 \(shot) 个镜头的旁白\(line.isEmpty ? "去掉了" : "改了")，在重新剪（十来秒）", false)
            case .failure(let failure): return (failure.localizedDescription, true)
            }
        }
        let fine = (args["hq"] as? Bool) ?? false
        let onward = (args["following"] as? Bool) ?? false
        // A direction in a sentence: the studio rewrites the words itself.
        if let note = (args["direction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            guard FilmStudio.shared.shooting == nil, FilmStudio.shared.revising == nil else { return ("片场正忙，等这一条拍完", true) }
            FilmStudio.shared.redirect(film: film, shot: shot, note: note, following: onward)
            return ("在照「\(note)」改第 \(shot) 个镜头的提示词（十几秒），改好就重拍\(onward ? "，后面的镜头也跟着重拍" : "")。film_status 看进度", false)
        }
        let method = (args["method"] as? String).flatMap { FilmStudio.Method(rawValue: $0.lowercased()) }
        let glide = (args["glide"] as? String).flatMap { FilmStudio.Glide(rawValue: $0.lowercased()) }
        if let asked = args["method"] as? String, method == nil { return ("method 只能是 h3、animate、move：\(asked)", true) }
        if let asked = args["glide"] as? String, glide == nil { return ("glide 只能是 push_in、pull_out、pan_left、pan_right、rise、fall、hold：\(asked)", true) }
        switch FilmStudio.shared.reshoot(film: film, shot: shot, framing: args["framing"] as? String,
                                         still: args["still"] as? String, motion: args["motion"] as? String,
                                         narration: args["narration"] as? String, hq: fine, following: onward,
                                         method: method, glide: glide, h3: args["h3"] as? String,
                                         checks: FilmTools.checks(args["counts"]), match: FilmTools.match(args["match"]),
                                         later: args["later"] as? Bool ?? false) {
        case .success(let made) where args["later"] as? Bool == true:
            return (made.note ?? "第 \(shot) 镜准备好了，等着一起拍", false)
        case .success(let made):
            let redone = onward ? "第 \(shot) 个镜头和它后面的都在重拍" : "第 \(shot) 个镜头\(fine ? "在精修（q8，约 9 分钟）" : "在重拍")"
            let how = made.shots.first { $0.id == shot }.map { taken -> String in
                switch taken.method {
                case .move: return "（在画面上运镜，几秒钟）"
                case .animate:
                    let bare = made.engine == .h3 && !(taken.who ?? []).isEmpty && !FileManager.default.fileExists(atPath: made.start(shot).path)
                    return "（LTX 从一张图拍，约 2 分钟）" + (bare ? "。注意：这一镜有演员，但没有起始画面，会从空布景拍，画里没有人；要人就先 film_fix_picture from: take" : "")
                default: return made.engine == .h3 ? "（H3，约 8 分钟）" : ""
                }
            } ?? ""
            return ("「\(made.title)」\(redone)\(how)，拍完会重新剪一遍。film_status 看进度，拍完用 film_frames 看", false)
        case .failure(let failure): return (failure.localizedDescription, true)
        }
    }

    // MARK: Directing a film

    private static func filmFrames(_ args: [String: Any]) async -> (String, Bool) {
        guard let film = args["film"] as? String, let shot = FilmTools.int(args["shot"]) else { return ("film_frames 需要 film 和 shot", true) }
        switch await FilmStudio.shared.inspect(film: film, shot: shot, every: FilmTools.number(args["every"]) ?? 1,
                                               like: FilmTools.ints(args["like"]), picture: args["picture"] as? Bool ?? false) {
        case .success(let seen):
            // The kernel takes this line out of the text and attaches the
            // picture itself, for a brain that can see.
            return (seen.said + "\nimage://\(seen.sheet.path)", false)
        case .failure(let failure): return (failure.localizedDescription, true)
        }
    }

    private static func filmCount(_ args: [String: Any]) async -> (String, Bool) {
        guard let film = args["film"] as? String, let shot = FilmTools.int(args["shot"]),
              let thing = (args["thing"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !thing.isEmpty else {
            return ("film_count 需要 film、shot 和 thing", true)
        }
        switch await FilmStudio.shared.countThings(film: film, shot: shot, thing: thing, expected: FilmTools.int(args["expected"]),
                                                   picture: args["picture"] as? Bool ?? false, every: FilmTools.number(args["every"])) {
        case .success(let said): return (said, false)
        case .failure(let failure): return (failure.localizedDescription, true)
        }
    }

    private static func filmFixPicture(_ args: [String: Any]) async -> (String, Bool) {
        guard let film = args["film"] as? String, let shot = FilmTools.int(args["shot"]),
              let instruction = args["instruction"] as? String else { return ("film_fix_picture 需要 film、shot 和 instruction", true) }
        let from = (args["from"] as? String).flatMap { FilmStudio.Source(rawValue: $0.lowercased()) }
        if let asked = args["from"] as? String, from == nil { return ("from 只能是 set、take、start：\(asked)", true) }
        let studio = FilmStudio.shared
        // Which picture it changes, decided the way the studio decides it.
        let changes = from ?? (studio.film(named: film).map { FileManager.default.fileExists(atPath: $0.start(shot).path) } == true ? .start : .set)
        // Changing a set for its numbers when its numbers are already right
        // only risks the rest of it.
        let counts = FilmTools.checks(args["counts"]) ?? []
        if !counts.isEmpty, changes == .set || changes == .new,
           await studio.setIsRight(film: film, shot: shot, checks: counts) {
            return ("第 \(shot) 镜的布景数目已经对了（" + counts.map { "\($0.thing) \($0.count)" }.joined(separator: "，")
                    + "），不用改。拍出来的镜头数目不对，就 film_reshoot(shot: \(shot), counts: …) 重拍：片场会数、多了会再拍", false)
        }
        switch studio.fixPicture(film: film, shot: shot, instruction: instruction, from: from,
                                 at: FilmTools.number(args["at"]), like: FilmTools.ints(args["like"]),
                                 counts: FilmTools.checks(args["counts"])) {
        case .failure(let failure): return (failure.localizedDescription, true)
        case .success(let made):
            // A change takes about two minutes: waited for as long as a tool
            // may take, then left to film_status.
            for _ in 0..<polls {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if studio.revising == nil { break }
            }
            guard studio.revising == nil, let done = studio.film(named: made.id) else {
                return ("在改第 \(shot) 镜的画面（两分钟左右），改好了 film_status 会写，再用 film_frames picture: true 看", false)
            }
            let said = done.note ?? ""
            let changed = said.contains("改好了")
            let picture = changes == .set ? done.still(shot) : done.start(shot)
            return (said + (changed ? "\nimage://\(picture.path)" : ""), !changed)
        }
    }

    private static func filmGrade(_ args: [String: Any]) async -> (String, Bool) {
        guard let film = args["film"] as? String else { return ("film_grade 需要 film", true) }
        switch await FilmStudio.shared.regrade(film: film, shot: FilmTools.int(args["shot"]), like: FilmTools.int(args["like"]),
                                               exposure: FilmTools.number(args["exposure"]), saturation: FilmTools.number(args["saturation"]),
                                               off: args["off"] as? Bool ?? false) {
        case .success(let said): return (said, false)
        case .failure(let failure): return (failure.localizedDescription, true)
        }
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

/// What the film tools share: the shape of a count, and reading numbers that
/// arrive as whatever JSON made them.
enum FilmTools {
    /// A JSON value as the text a form takes: a JSON true is "true" — it came
    /// through as the number 1, and a toggle set to it was switched off.
    static func text(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    /// Two-second polls a tool may wait through: the kernel gives a tool 60
    /// seconds and its relay 55, and past that the answer is "timed out".
    static let patience = 22

    static let counts: [String: Any] = [
        "type": "array",
        "description": "Things whose NUMBER matters in this shot — five loaves, twelve baskets: counted in the picture before filming (and the picture fixed if it is wrong) and in the take after (a wrong take is filmed again).",
        "items": [
            "type": "object",
            "properties": [
                "thing": ["type": "string", "description": "What, in English, as it looks: \"round flat barley loaves\"."],
                "count": ["type": "integer", "description": "How many."],
            ] as [String: Any],
            "required": ["thing", "count"],
        ] as [String: Any],
    ]

    static func checks(_ value: Any?) -> [FilmStudio.Check]? {
        guard let rows = value as? [Any] else { return nil }
        return rows.compactMap { row in
            if let row = row as? [String: Any] {
                guard let thing = (row["thing"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !thing.isEmpty,
                      let count = int(row["count"]), count > 0 else { return nil }
                return FilmStudio.Check(thing: thing, count: count)
            }
            // Written as words, the way a model writes it anyway:
            // "five small round barley loaves", "12 woven baskets".
            guard let words = (row as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let first = words.split(separator: " ", maxSplits: 1).first else { return nil }
            let rest = words.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
            let number = Int(first) ?? spelled.firstIndex(of: first.lowercased()).map { $0 + 1 }
            guard let number, number > 0, !rest.isEmpty else { return nil }
            return FilmStudio.Check(thing: rest, count: number)
        }
    }

    private static let spelled = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                                  "eighteen", "nineteen", "twenty"]

    static func match(_ value: Any?) -> FilmStudio.Match? {
        guard let row = value as? [String: Any],
              let thing = (row["thing"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !thing.isEmpty,
              let like = int(row["like"]) else { return nil }
        return FilmStudio.Match(thing: thing, like: like)
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func ints(_ value: Any?) -> [Int] {
        if let list = value as? [Any] { return list.compactMap { int($0) } }
        if let one = int(value) { return [one] }
        return []
    }
}

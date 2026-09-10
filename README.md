# KinClaw Mac

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-black.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

> **Your AI dock. ⌘⌥K to summon. Three modes: Chat any of 98 agents · Cowork with KinClaw on your screen · Code in any repo. Free. Open. Local-first.**

Native macOS Spotlight-style shell for the LocalKin family. One floating window, one hotkey, **three distinct surfaces**:

- 💬 **Chat** — 98 cloud agents (Selah / Heal / Core / Faith) via `api.localkin.dev`
- 👁️ **Cowork** — local [KinClaw](https://github.com/LocalKinAI/kinclaw) kernel + 5 claws (screen / ui / input / record / web). Pilot operates your Mac.
- 💻 **Code** — local [kincode](https://github.com/LocalKinAI/kincode) kernel, repo-aware coding agent. Pick a repo, kincode reads + edits + tests it.

Same window, same agent picker shape, three different brains. Switch tabs to switch modes.

---

## Status

🗣 **Unreleased** — **Companion mode grew a face and a conversation** (⇧⌘M). Sentences are spoken as the model writes them, so the first words land about a second in; you can cut in mid-reply through headphones, or tap to interrupt over speakers. Every reply carries a hidden mood and subject that pick what you are looking at — say "beach" and the background is one. With [localkin-service-avatar](https://github.com/kleinlee/DH_live) checked out it can be a **digital human whose mouth moves with the words** (WASM in a web view, no GPU, driven by the same Kokoro audio the speaker plays). For photos of pets there is no lip sync — a dog does not lip sync — but macOS's animal pose model makes the picture **breathe, blink, perk its ears at your voice and tilt its head**. The gate's questions are read out and answered by voice, and also shown as buttons. See [Companion mode](#companion-mode) below.

🎛 **Unreleased** — **Cowork and Code say what the agent may do.** The composer's bottom-left names the gate — 只看不动 / 先问我 / 放手干 — and switches it live; the workspace sits beside it. Stop is the send button now, red while a turn runs. The top bar keeps connection, search health and new session; everything else is in a ⋯ menu. Code caught up: approval cards (kincode no longer runs `-yolo`), the build it ran after an edit, and an undo button beside what just changed. The file tree is gone from both panels — Finder does that better — but "what did it just change" moved above the composer where it is read.

🌙 **Unreleased** — **Companion mode** (⇧⌘M): the panel becomes a character and a halo, voice only, no text. Art comes from `~/.kinclaw/companion/` or is fetched in-app from Wikimedia Commons (no account) or Pexels (free key).

📚 **Unreleased** — Both Cowork and Code have a **folder pane** that lists the folders you work in, each expanding to the conversations you had there. Click one to restore the folder and the transcript together; each folder has its own New session.

🗂 **Unreleased (night)** — Long tool-call runs fold into one "Ran N tools ›" row (Cowork and Code), and Cowork gains a **folder pane** on the left: the workspace, the files the agent touched this session, and the folder tree, all one click from Finder. ⇧⌘L toggles it.

📁 **Unreleased (evening)** — Cowork gains a **workspace picker** (writes outside the folder ask first), a **question card** for the agent's `ask_user` questions, **diffs** on file edits, macOS **notifications** when the panel is hidden, an **Always** approval that persists, and a **Routines** settings tab for scheduled runs. Needs kinclaw ≥ 1.18 (evening build).

🛡 **Unreleased** — Cowork gets Claude Desktop's manners: an inline **approval card** when the kernel's permission gate stops a call (Allow / Always this session / Deny), a **plan mode** toggle (⇧⌘P — the agent looks and proposes, nothing on your screen changes), a **context meter** fed by per-call usage, and compaction dividers in the transcript. Needs kinclaw ≥ 1.18.

🧩 **Unreleased** — Settings gains **MCP** (tools from external servers), **Harvest** (the nightly skill-harvest job, made visible) and **Skills** (what the active soul actually exposes — 25 of 189 for pilot — with per-soul toggles that never rewrite the soul file).

🎙 **Unreleased** — Hands-free voice conversation: speak, get a spoken reply, keep going without touching the keyboard. Mixed zh/en replies are split per language and spoken by a matching voice; optional wake word filters out speech that wasn't meant for the agent. See [Voice](#voice) below.

✅ **v0.4.0** — Detached spawn: dispatch a long-running task and get its result minutes later in its own bubble. Souls and skills read straight from the source repos (`KINCLAW_SOUL_DIRS`), no `~/.localkin/souls/` copy to drift.

✅ **v0.3.0** — Code mode polish: inline TodoWrite checklist, image drag-and-drop / paperclip, plan-mode toggle, and a stable `make run` build loop that ends TCC re-auth pain.

✅ **v0.2.0** — three-mode integration shipped. Chat / Cowork / Code all live, mode-scoped agent pools, per-repo Code sessions, full TCC permission handling for kinclaw subprocess.

See [CHANGELOG](CHANGELOG.md) for the day-by-day. This is dev-build territory — codesign + DMG land at M6 (blocked on $99 Apple Developer cert).

Forked from [localkin-ios](https://github.com/LocalKinAI/localkin-ios) for the cloud chat layer; the Mac-specific code (NSPanel, global hotkey, menubar, dual subprocess supervision, mode switcher, code surface, diff viewer, screen feed) is new.

---

## Architecture

```
                ┌─────────────────────────────────────────────┐
                │  KinClaw Mac (kinclaw-mac.app)              │
                │                                             │
                │  [💬 Chat] [👁️ Cowork] [💻 Code]   ⚙        │  ← ModeBar (titlebar)
                │  ───────────────────────────────────────    │
                │  agent ▾   📚 history  🗑 clear  🔊 tts     │  ← per-mode picker
                │  ───────────────────────────────────────    │
                │  messages, tool calls, diff viewer          │
                │  Message …                              ⏎    │  ← input
                └─────────────────────────────────────────────┘
                        │            │            │
            ┌───────────┘            │            └────────────┐
            ▼                        ▼                          ▼
  api.localkin.dev/v1         localhost:5001              localhost:5002
  (cloud agents)              (kinclaw kernel,            (kincode kernel,
                               5 claws)                    coding agent)
```

Two subprocess supervisors (`KinClawSupervisor` + `KinCodeSupervisor`) auto-spawn the local kernels at app launch. Both spawn through `DisclaimedProcess` (posix_spawn + `responsibility_spawnattrs_setdisclaim` SPI) so the subprocesses own their TCC identity — `kinclaw` granted Accessibility from your Terminal runs is automatically valid in the Mac app spawn too.

---

## Tech stack

- **SwiftUI** + **AppKit** (NSPanel for the floating window)
- **WKWebView** for embedded chat (no Chromium bundle)
- **macOS 13+** (uses `MenuBarExtra`)
- [**KeyboardShortcuts**](https://github.com/sindresorhus/KeyboardShortcuts) for global hotkey
- **XcodeGen** (`project.yml`) — no committed `.xcodeproj`

---

## Build (when M0+ lands)

```bash
brew install xcodegen
xcodegen generate
open KinClawMac.xcodeproj
# ⌘R in Xcode
```

For local dev, also need `kinclaw` binary on `PATH` (or in `KinClawMac/Resources/`):

```bash
go install github.com/LocalKinAI/kinclaw/cmd/kinclaw@latest
```

---

## Voice

Two ways to talk to an agent, sharing one button in the input bar:

- **Push-to-talk** — click, speak, click again. Transcription lands in the input field for you to edit or send.
- **Hands-free** — the reply is spoken aloud and the mic reopens when it finishes, so a back-and-forth needs no keyboard at all.

Recording stops on its own ~0.5s after you stop talking. The mic measures your room's noise for the first 0.5s of each recording and puts the speech line above *that*, rather than at a fixed dB — a fan or a warm laptop used to hold the detector open until its 15-second safety timer.

**Mixed zh/en replies are split and voiced per language.** Kokoro voices are single-language: `zf_xiaoxiao` reading English produces mangled phonetics, `af_bella` reading Chinese names each glyph out loud ("Chinese letter, Chinese letter…"). A reply like `用 GitHub Actions 部署，成本是 zero` becomes four runs, each synthesized by the matching voice and played back to back. The splitter is a port of localkin's `pkg/tts/split.go`, so both stay in agreement.

**Wake word** (optional, off by default) — set one in Settings → Voice, and hands-free mode ignores everything until you say it, so a conversation happening nearby doesn't reach the agent.

It opens a conversation rather than guarding each sentence:

```
（同事在旁边说话）              → discarded
你：小美，帮我看看日程            → sends「帮我看看日程」, conversation opens
   （回复播了 90 秒）
你：那明天呢                     → sends — no wake word needed
   （你走开，静默 50 秒）          → conversation lapses
（同事说话）                     → discarded again
你：小美，继续                    → sends「继续」
```

The lapse timer (default 45s, adjustable) counts from when the **reply finishes**, not from when you stopped speaking — otherwise a long answer would expire the session while you were still listening to it. Matching ignores case, spacing and punctuation, since STT output for a short name is unstable. The mic turns amber while waiting for the word and red once you're conversing. Push-to-talk ignores the setting entirely — pressing the button is already deliberate.

## Companion mode

⇧⌘M turns the panel into a picture and a voice. No transcript, no
buttons: you talk, it answers out loud, and what you are looking at
responds to the conversation.

**It answers while it is still writing.** Each finished sentence is
synthesized and spoken as it arrives rather than after the whole reply,
so the first words land about a second in. Kokoro pads every clip with
~400ms of silence in front and ~700ms behind — between streamed
sentences that is a 1.1s hole, so it is trimmed to 60/160ms — and the
voices are warmed on entry, because Kokoro's first Chinese sentence
after idle takes 3.4s against 0.5s warm.

**You can interrupt it.** With headphones, talking over it stops the
reply and takes your words. Through the Mac's own speakers the
microphone hears the agent louder than it hears you — measured at
−14…−4 dBFS even with macOS's echo cancellation on — so barge-in is
gated on the output route, and over speakers you tap the face instead.
Settings → Voice forces it either way.

**The background follows the conversation.** Every reply opens with a
bracketed tag that is never spoken: a mood, and a one-word subject.
The mood picks a folder; the subject is matched against the pictures'
own filenames and credits, which already describe them — art arrives
named for the search that found it. Say "beach" and you get the beach
one. A subject with nothing on disk changes nothing, and earns a
background fetch by coming up a second time.

Art lives in `~/.kinclaw/companion/`, with `~/.kinclaw/companion-<name>/`
as alternative sets you can switch between from the face. Files at the
top level rotate; subfolders named for a state (`idle`, `listening`,
`thinking`, `speaking`) or a mood (`开心`, `温柔`, `好奇`, `困`, `担心`)
are used in that state or mood. Short mp4/mov loops work anywhere a
picture does.

**A face that actually talks.** Check out
[localkin-service-avatar](https://github.com/kleinlee/DH_live) beside
this repo and the companion can be a digital human. Its inference is a
WASM module running in a web view — no GPU, and none of its Python
service — driven by the same Kokoro bytes the speaker is playing, so
the mouth moves with the words. With the digital human on, the photographic background steps aside
for a quiet dark ground — a green-screened figure over a picture of
somebody's dog reads as a collage rather than as someone in a room.
Four characters; off unless you turn it on.

**An animal that looks back.** For a photograph of a pet there is no
lip sync: a dog does not lip sync, and one that did would be a cartoon.
What reads as an animal in the room is attention. macOS's animal pose
model finds the eyes and ear tips (0.85+ on ordinary pet photos), and
the picture then breathes, blinks irregularly, perks its ears at your
voice, leans in while the mic is open, and tilts its head while it is
thinking. Photos where the pose is not found stay photos rather than
being animated from a guess.

**Approvals without a keyboard.** When the kernel's gate stops a call,
it is read out — "我想跑一条命令：rm -rf ./build。可以吗？" — and short
affirmations approve it. Only short ones: "把那个文件删了" is an
instruction, not consent, and fails to parse rather than approving
something you did not agree to. The same prompt is also docked at the
bottom of the picture as buttons, because a voice-only question is
invisible if you stepped away while it was speaking.

### Backends

| | Default | Notes |
|---|---|---|
| STT | SenseVoice @ `localhost:8000` | `kin audio serve sensevoice:small` — needs the `[sensevoice]` extra |
| TTS (local agents) | Kokoro @ `localhost:8001` | Direct, no gateway hop |
| TTS (cloud agents) | `https://<host>/v1/tts` | Bearer auth via `TokenManager` |
| Fallback | `SFSpeechRecognizer` / `AVSpeechSynthesizer` | Used whenever a server call fails |

Both local services come from [localkin-service-audio](https://github.com/LocalKinAI/localkin-service-audio). Endpoints are overridable in Settings → Backend.

---

## Default settings

| | Default | Configurable |
|---|---|---|
| Hotkey | ⌘⌥K | ✅ Settings → Hotkey |
| Wake word | Off (empty) | ✅ Settings → Voice |
| MCP servers | None | ✅ Settings → MCP (`~/.localkin/mcp.json`) |
| Extra skills per soul | None | ✅ Settings → Skills (overlay, no soul edit) |
| Conversation stays open | 45s after each reply | ✅ Settings → Voice |
| Speech margin | +12 dB above measured room noise | ✅ Settings → Voice |
| TTS voice | Auto (zh → `zf_xiaoxiao`, en → `af_bella`) | ✅ Settings → Voice |
| Login Item | On | ✅ |
| Window size | 380×600 | ✅ Drag to resize, remembered |
| Window position | Center on first run, remembered after | ✅ |
| WebView origin allow-list | `localhost`, `api.localkin.dev` | 🚫 Hardcoded |

---

## Family

Two stacks — KinClaw (engine + native shells, **all open**) vs LocalKin platform (swarm + cloud + paid clients, closed). Each stack is internally license-consistent.

**KinClaw stack — open, free, your Mac:**

| Repo | Role | License |
|---|---|---|
| [`kinclaw`](https://github.com/LocalKinAI/kinclaw) | Go kernel + 5-claw computer-use + bundled web UI | Apache-2.0 |
| `kinclaw-mac` (this) | macOS Spotlight native shell | **Apache-2.0** |
| `kinclaw-pal` *(planned)* | Tauri Linux + Windows shell | Apache-2.0 |

**LocalKin platform — closed, paid, cloud:**

| Repo | Role | License |
|---|---|---|
| `localkin-core` | swarm orchestration + Genesis Protocol | private |
| `api.localkin.dev` | 98+ cloud agents (Selah / Heal / Core) | private cloud service |
| [`localkin-ios`](https://github.com/LocalKinAI/localkin-ios) | iOS Pro client | proprietary |

---

## Build from source

One repo, one command:

```bash
brew install xcodegen
git clone https://github.com/LocalKinAI/kinclaw-mac
cd kinclaw-mac
make run
```

That's it. `make run` will:

1. **Bootstrap** — find or clone the helper kernels [`kinclaw`](https://github.com/LocalKinAI/kinclaw) and [`kincode`](https://github.com/LocalKinAI/kincode). Search order:
   - `KINCLAW_REPO` / `KINCODE_REPO` env vars (explicit override)
   - `../kinclaw` / `../kincode` (the documented sibling layout)
   - `~/Documents/Workspace/<name>`, `~/code/<name>`, `~/dev/<name>`, `~/src/<name>` (common conventions)
   - Last resort: `git clone` into `../<name>`

   If you already have one or both checked out anywhere on this list, **bootstrap re-uses your existing copy — no second clone**. To override on a one-off basis: `KINCLAW_REPO=/my/path make run`.
2. **Build** — run XcodeGen, then `xcodebuild` for the .app
3. **Sign helpers** — `go build` + ad-hoc codesign `kinclaw` and `kincode` into `~/.localkin/bin/` with stable bundle IDs (`dev.localkin.kinclaw` / `dev.localkin.kincode`)
4. **Sign app** — codesign `KinClawMac.app` with stable ID `dev.localkin.kinclawmac` (NO hardened runtime — would block dlopen of ad-hoc dylibs like libkinrec_writer)
5. **Start helpers** — launch `kinclaw` on `:5001` and `kincode` on `:5002` as detached daemons (PPID=1, survive shell exit), wait for both ports to bind
6. **Launch app** — `open KinClawMac.app`. Each supervisor finds its helper already running and adopts it cleanly (no spawn race)

Skills, souls, and built-in tools come from the sibling repos directly — kinclaw and kincode discover them at runtime via `KINCLAW_SKILL_DIRS` / `KINCODE_SKILL_DIRS` env vars (set by the Makefile) and `~/.localkin/skill-sources.txt` (registered by each install.sh). No copy step, no stale duplicates — edit a SKILL.md in the dev repo, restart the helper, the change is live.

Stable bundle IDs are the whole point of the codesign step: macOS TCC keys Accessibility / Screen Recording grants by bundle identifier + path, so re-signing with the same ID across rebuilds survives the user's "Allow" — no more re-authorizing on every code change.

Other targets (run `make help` for the full list):

| Target          | What it does |
|-----------------|--------------|
| `make bootstrap`| Just clone missing sibling repos — runs automatically as part of `make sign` and `make run` |
| `make sign`     | Bootstrap + build + sign everything, but don't launch |
| `make build`    | Just `xcodebuild`, no signing |
| `make start-helpers` | Start `kinclaw` + `kincode` detached, without launching the GUI |
| `make kill`     | Stop the app + helper subprocesses |
| `make doctor`   | Show signing state + running processes — first thing to run when something looks off |
| `make clean`    | Drop DerivedData + kill (forces a full rebuild next time) |

---

## Contributing

Open issue / PR welcome. Especially:

- macOS-specific bug reports (we're macOS-14+ only)
- New agent suggestions for `Models/AgentSuggestions.swift` welcome chips
- More Kokoro voices in the picker, and wake-word matching for languages beyond zh/en
- Localization (currently bilingual zh/en, needs proper i18n)

For deep changes (NSPanel chrome, supervisor lifecycle, session model) — open an issue first to discuss.

---

## License

[Apache License 2.0](LICENSE) — © 2026 LocalKinAI.

The `KinClaw` name + lobster mark are trademarks of LocalKinAI; you can fork the code freely under Apache, but redistributions under the `KinClaw` name should match upstream behavior or use a different name.

Other inquiries: hello@localkin.dev

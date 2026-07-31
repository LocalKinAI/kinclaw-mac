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

**You can talk over a reply to cut it short.** The mic stays open during playback, so a long answer doesn't have to be waited out. macOS echo cancellation keeps the agent from interrupting itself — though not by level alone: residual echo peaks reach -15.5 dBFS, overlapping ordinary speech. What separates them is persistence (echo spikes for ~130ms, a person talking holds for a second or more), so interruption needs 6 consecutive frames above -22 dBFS. Toggle in Settings → Voice.

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
| Conversation stays open | 45s after each reply | ✅ Settings → Voice |
| Interrupt by talking | On | ✅ Settings → Voice |
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

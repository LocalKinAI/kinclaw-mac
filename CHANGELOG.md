# Changelog

All notable changes to KinClaw Mac.

## [Unreleased] - 2026-07-30 — Hands-free voice conversation

Voice mode was already wired into the UI — a mic button, a waveform, a TTS
toggle — and it produced audio every time you used it. It just never worked,
in three separate ways that each looked like success from the outside.

### Fixed — Chinese replies were spoken as "Chinese letter, Chinese letter…"

Local Kokoro (`/synthesize`) reads `speaker` + `language`. The cloud gateway
(`/v1/tts`) reads `voice` + `speed`. We sent the gateway's shape to both. Kokoro
never saw a speaker, fell back to an English default, and that voice pronounces
Chinese by *naming each glyph*.

Nothing surfaced the mistake: HTTP 200, a valid WAV, audio plays. Confirmed by
sending the output back through SenseVoice — the old payload transcribed as the
recital, the new one as 「施舍是信仰的试金石」, at a third of the bytes because
it stopped narrating every character.

### Fixed — recording kept running long after you stopped talking

The symptom looked like slow transcription. It wasn't; the VAD simply never
fired, so every utterance ran to the 15-second safety timer.

Measured instead of guessed, which mattered — the first hypothesis (room noise
sitting permanently above the threshold) was wrong. Room tone here averages
**-40.5 dBFS**, comfortably under the hardcoded -35 line. But it *peaks* at
**-32.0**, and any tick above the line reset the silence counter to zero. The
average stayed quiet while stray peaks crossed every few ticks, wiping the
count before it could reach the 0.5s stop. That also explains why it felt
intermittent rather than consistently stuck.

Two changes, since either alone is fragile:

- The noise floor is now measured per-recording — median of the first 0.5s, so
  one early cough can't skew the whole session.
- The counter decays (`-2`) instead of resetting, so a single keystroke can't
  undo half a second of accumulated silence.

Replaying recorded audio through both versions: the old logic **never stopped**
in three of four noise profiles; the new one stops at 0.5s in all four,
including a dead-silent room (no regression where the old code did work).

### Fixed — the "Silence threshold" slider did nothing

Settings → Voice wrote to `kinclaw.voice.silenceThresholdDB`. No code read it.
The detector had -35 compiled in, so the slider had never had any effect since
it shipped. It now sets the margin above the *measured* room noise — the knob
that actually helps when the default doesn't suit your room.

### Fixed — silence was being transcribed, and came back as words

Saying nothing produced messages. The recorder sent **every** recording to STT,
including the ones that stopped precisely *because* nobody had spoken —
`hasSpeechStarted` already knew the answer and it was being discarded.

Speech models don't return empty for empty input; they return their most likely
utterance. Feeding this build two seconds of digital silence:

    silence.wav  → SenseVoice returned  「그.」
    roomtone.wav → SenseVoice returned  「그.」

An invented Korean syllable, from a model being used for Chinese and English.
Which is the point: hallucinated output is unpredictable across languages, so a
list of known bad phrases cannot be the fix. Empty rooms were holding
conversations with the agent, and in hands-free mode that loops — the mic
reopens after every reply.

Two changes:

- Recordings where no speech was detected are dropped instead of transcribed.
- `hasSpeechStarted` now needs **3 consecutive ticks** (300ms) above the
  threshold rather than a single one. One spike — a cough, a door, a key — used
  to mark an otherwise-silent recording as worth transcribing.

Simulated against measured room tone: quiet room, a one-frame cough, and a
two-frame door all stay out of STT; a real utterance still goes through.

A short list of known hallucination phrases ("thanks for watching", "谢谢观看",
bare "I") is kept as a backstop for audio that crosses the threshold without
being speech. It is exact-match and deliberately small — "ok" and "嗯" are
excluded despite being common hallucinations, because they're also common
replies, and silently dropping something the user said looks like a broken mic,
which is worse than letting one stray "I." through.

### Added — mixed-language replies get the right voice per language

Kokoro voices are single-language: `zf_xiaoxiao` reading English produces
mangled phonetics, `af_bella` reading Chinese produces the glyph recital above.
Most real replies mix both, since technical terms stay in English.

Replies are now split into language runs, each synthesized by a matching voice
and played back to back. This is a **port of localkin's `pkg/tts/split.go`**,
not a reimplementation — that version is already in production behind
`kin_speak` and carries fixes worth inheriting (neutral punctuation attaching
to the following run; one- and two-letter English labels like multiple-choice
"A"/"B" folded into the surrounding voice instead of voiced alone).

Two refinements on top, both cost-only and verified not to change pronunciation:
punctuation-only runs fold into the preceding segment (CJK punctuation carries a
`zh` tag, so a lone `。` between two English runs would otherwise cost a whole
HTTP round-trip), and the resulting same-voice neighbours merge.

Markdown and emoji are now stripped on **both** output paths. The system-voice
fallback previously handled four markers and let emoji through to be announced
by name ("sparkles", "check mark").

### Added — optional wake word for hands-free mode

Hands-free mode sent everything it heard, including a phone call in the same
room or the recogniser's best guess at an air conditioner. A wake word turns
"always listening" into "always listening, rarely acting".

Empty and **off by default** — a wake word the user hasn't been told about is
indistinguishable from voice mode being broken.

**The wake word opens a conversation; it doesn't guard every sentence.** Say it
once and the session is open: what follows goes straight through, no name
needed, for as long as the exchange keeps going. After a configurable quiet
period (default 45s) the session lapses and the word is required again. Gating
every single utterance would mean a five-turn conversation needs the name five
times, which is not what "hands-free" should feel like.

The lapse timer counts from when the **reply finishes**, not from when the user
stopped speaking. A two-minute answer would otherwise expire the session while
the user was still listening to it, and they would have to say the wake word to
respond to what they had just heard.

Matching folds away case, spacing, and punctuation. STT output for a short name
is unstable (「小美」comes back as 小眉, 小mei, with or without a trailing
comma), and exact comparison would have the user repeating themselves while a
correct match sits one punctuation mark away — a worse failure than the rare
false accept it prevents. The word must lead the utterance, so discussing the
agent mid-sentence doesn't trigger it. Push-to-talk is exempt: pressing the
button is already the deliberate act a wake word exists to require.

Waiting-for-wake and conversing are drawn differently (amber vs red mic, with
the help text naming the word). Both states have the microphone open and only
one of them acts on what it hears; without the distinction the user speaks a
full sentence into what looks like a live mic and gets nothing back.

---

## [Unreleased] - 2026-05-12 — Studio tab (open-core private-soul hosting)

Adds a 4th main tab (`Studio`) for self-hosted private workflows.
KinClaw Mac is Apache 2.0 — the tab framework + UI shell ship in this
public repo. The *souls* the tab lists live in a sibling private repo
(family-private `localkin` checkout, optional) and never enter this
codebase. This is the open-core pattern at solo-founder scale: VS Code
ships the editor, extensions are user-owned; KinClaw Mac ships the
4-tab shell, Studio's contents are user-owned.

### Added

- **`Services/PrivateSoulLoader.swift`** — runtime sibling-repo
  discovery. Mirrors the Makefile's `LOCALKIN_REPO` search order
  (`../localkin`, `$HOME/Documents/Workspace/localkin`, `$HOME/code/localkin`,
  `$HOME/dev/localkin`, `$HOME/src/localkin`). First hit with both
  `.git/` and `souls/private/` wins. Enumerates `*.soul.md` and parses
  just enough YAML frontmatter (`name`, `version`, `description`) for
  the card view — no Yams dependency added.
- **`Views/Studio/StudioView.swift`** — the tab body. Two states:
  - Empty (no sibling repo or no private souls): explains the
    self-hosted contract + lists the 4 candidate paths the loader
    checks. Public clones land here.
  - Populated (sibling found, souls listed): scroll view of
    `PrivateSoulCard`s with name + version + description + mtime +
    Reveal-in-Finder. Run button is wired but disabled in Phase 1
    (spawn integration lands in Phase 2).
- **`LocalKinApp.swift`** — 4th `.tabItem("Studio", "lock.shield")`
  between KinBook and Settings, tinted `AccentGreen` like the others.

### Design notes

- **Why a tab, not a toggle**: Studio's contents are first-class
  workflows (cron-driven, multi-phase pipelines), not a setting.
  Putting it inside Settings or behind a hidden feature flag would
  pretend it's experimental — it's not, it's the *production-tool*
  surface for power users who maintain their own soul library.
- **Why empty state has documentation, not a marketing pitch**: the
  tab is for users with their own private workflows. The empty state
  IS the docs for how to populate it — not a "buy a license to unlock"
  paywall. Anyone can populate it locally; there's nothing to unlock.
- **Why Phase 1 disables the Run button**: shipping a half-wired Run
  that crashes when clicked is worse than shipping it dimmed with a
  clear "Phase 2" tooltip. The full spawn-into-supervised-kinclaw
  wiring (with tail-log + retry + state machine) is its own commit.

### Phase 2 (next)

- Wire the Run button → spawn `kinclaw -soul <path>` via
  `KinClawSupervisor`, surface stdout in a per-soul tail-log panel.
- Per-soul state badge (last run time, success/fail, phase state for
  multi-phase pipelines that write a `.state` file).
- Optional: per-soul custom UI panel (declared via a `ui.json` next
  to the soul file — soul declares "I need a queue.md editor" or "I
  need a progress chart" and the Studio renders it).

## [0.4.1] - 2026-05-06

**Patch — spawn_done bubble was being dropped silently.**

`UI/SpotlightContentView.swift::handleLocalEvent` had a stale-index
guard at the top that early-returned whenever `assistantIndex` no
longer pointed at a valid `messages` row. The guard was correct for
mid-turn events (`text_delta`, `tool_call`) — those need an active
assistant bubble to write deltas into.

But `spawn_done` arrives 3-5 minutes AFTER the turn that dispatched
the spawn has ended (the whole point of detached spawn — pilot's
turn ends in 200µs, the user keeps chatting, and the child returns
later). At delivery time, `assistantIndex` is stale, the guard
fires, the event is dropped, and the user's research deliverable
disappears into the void.

Real bug observed 2026-05-06 19:55:

```
user: "分析一下因信称义"
pilot: "我派 researcher 去了 (job 149370)" (turn ends, OK)
... 1m52s of researcher running ...
user: "?"  (waiting)
pilot: "researcher 已完成 (用时 1分 52秒). 报告应该以独立消息显示在
        你的对话界面上了 ..."
        ↑ pilot's history HAS the synthetic injection
        ↑ but no report bubble ever showed in the UI
```

### Fix

`spawnDone` now handled at the TOP of `handleLocalEvent`, before
the stale-index guard. It appends a fresh standalone bubble (does
not need any active `assistantIndex`) and returns.

Pairs with kinclaw v1.12.0+ — kernel-side queueing into pendingSpawn
+ SSE push were already correct; this was purely a Mac-side UI
plumbing miss.

## [0.4.0] - 2026-05-06

**Cowork delivers deep research end-to-end.** Pairs with kinclaw v1.12.0
to make pilot's spawn-driven research workflow actually usable from
Cowork tab — non-blocking dispatch, live checklist rendering, sticky
brain dropdown, source-of-truth soul handling.

### Added — Detached spawn UI handling

`KinClawAPIClient.swift` adds `spawnDone = "spawn_done"` SSE event
case. `SpotlightContentView.swift` renders the event as an inline
assistant bubble:

```
🔬 researcher (job ab12cd) finished in 287s

[child agent's full markdown report — typically a TL;DR + path]
```

Pairs with kinclaw 1.12's detached-spawn mode: pilot dispatches a
researcher with `spawn(soul=researcher, prompt=…, timeout_s=300)`,
its turn ends within 200µs, the user keeps full chat interactivity
(can ask other things, dispatch parallel researchers, etc.). When
each child finishes minutes later, this code path appears the
result without re-prompting pilot.

`Views/Chat/ChatView.swift` also adds the case to its exhaustive
switch (Chat-mode no-op since spawn is Cowork-only).

### Added — `~/.localkin/souls/` cleanup, repo-as-source-of-truth

`Services/KinClawSupervisor.swift`: soul lookup priority flipped.
Was preferring `~/.localkin/souls/` (legacy install.sh copy) over
the dev repo; now the dev repo at `~/Documents/Workspace/kinclaw/
souls/` wins when present. Multi-day debugging session traced to
exactly this — edits to repo souls weren't reaching the running
helper because install.sh copied with `cp -n` (no-clobber) and
the supervisor's old priority gave the stale family-dir copy
preference.

Pairs with kinclaw 1.12's `install.sh` change which now actively
`rm -rf`s `~/.localkin/souls/` instead of copying into it.

### Added — `KINCLAW_SOUL_DIRS` + `SEARXNG_ENDPOINT` env injection

`Services/KinClawSupervisor.swift` now sets two env vars when
spawning the kinclaw helper subprocess:

- `KINCLAW_SOUL_DIRS=<install.soulsDir>` — kinclaw's spawn skill
  resolves "researcher" / "eye" / "critic" against this. Without
  it (e.g. when launched from `.app` Launch Services rather than
  shell), pilot's `spawn(soul=researcher)` would fail with "soul
  not found in [./souls, ~/.localkin/souls]".
- `SEARXNG_ENDPOINT` — read from `@AppStorage("kinclaw.backend.
  searxng")` (Settings UI value), with `http://localhost:8080`
  Docker default. Without this, `web_search` falls through to the
  now-broken DDG html-scrape path.

### Added — Makefile reads souls + skills directly from repos

`Makefile` `start-helpers` now passes:

- `-soul $(KINCLAW_REPO)/souls/pilot.soul.md` to kinclaw helper
- `-soul $(KINCODE_REPO)/souls/coder.soul.md` to kincode helper
- `KINCLAW_SOUL_DIRS=$(KINCLAW_REPO)/souls` env to kinclaw
- `KINCLAW_SKILL_DIRS=<repo>/skills:<localkin-sibling>/skills` env
- `SEARXNG_ENDPOINT=http://localhost:8080` (auto-detected via
  `curl :8080/`)

`PILOT_SOUL` / `CODER_SOUL` Make vars now point at repo paths
(was `$(HOME)/.localkin/souls/...`).

### Fixed — Cowork "New session" actually clears server history

`SpotlightContentView.swift`'s `startNewSession()` previously
only cleared `messages = []` client-side — kinclaw's per-session
sqlite history kept the prior turn's tape, so a "New session"
click followed by `你好` produced the prior task continuing
(researcher trying to keep finding apartments after we'd asked
something completely different).

Now `startNewSession()` POSTs `/api/session/reset` to kinclaw
(in Cowork mode only — Chat mode is stateless cloud SSE,
already clean). Best-effort: failures don't block the local
clear (user clicked "new" and expects the UI to be empty
regardless), and the endpoint returns 501 on older kernel
builds without exploding.

`Services/KinClawAPIClient.swift` adds `resetSession()`. The
exhaustive SSE event switches in `SpotlightContentView` and
`ChatView` get `case .sessionReset` handlers (no-op for the
local UI — the local clear already happened — but needed so
multi-window setups stay in sync).

### Fixed — TodoChecklistView decode

`UI/TodoChecklistView.swift`: `TodoItem.activeForm` was a non-
optional `String`. After kinclaw 1.12 made activeForm optional
in the kernel-side todo_write skill (auto-falls-back to content
when omitted, which is common for Chinese todos), the SSE
`tool_call` event's params no longer always include
`activeForm` — Swift Codable decode failed silently and the
checklist degraded to the generic "blue pill" tool-call render.

Now `TodoItem` uses an Optional storage with a computed
property that falls back to `content` when missing. The
checklist now renders properly even when the model emits
todos without activeForm.

### Fixed — Cowork brain dropdown reads from Settings

`Services/KinClawSupervisor.swift` SearXNG endpoint resolution
priority changed from "env > hardcoded default" to "env >
Settings UI value > hardcoded default" so the user's customized
endpoint actually gets used. Same pattern will likely apply to
other Backend tab settings as we add more.

### Fixed — KinCodeSupervisor doc

`Services/KinCodeSupervisor.swift` line 18-22 comment used to
say "kincode has no souls / no `-soul` flag — system prompt is
built-in". Outdated: kincode added soul support (cmd/kincode/
main.go takes `-soul`) and ships `coder.soul.md` in its own
repo. Comment updated to match reality + Makefile now passes
`-soul $(KINCODE_REPO)/souls/coder.soul.md` so dev edits to
that file are immediately live.

## [0.3.0] - 2026-05-05

**Code mode polish + stable build loop.** Five additions, four of
them surfacing kincode v0.10.0 capabilities in Code mode plus a
build-infra fix that ends the "我每次都要授权吗" TCC re-auth pain.

### Added — Inline TodoWrite checklist UI

When kincode's agent calls `todo_write`, instead of the generic 🔨
blue tool-call pill we render the todos array as an inline checklist:

  ☐ pending      — outline circle, primary text
  ◐ in_progress  — orange half-filled, uses `activeForm`
                  ("Building ..." instead of "Build ...") for
                  present-continuous reading
  ☑ completed    — green check + strikethrough

Header shows N/M done so progress is visible at a glance.

### Added — Image input (paperclip + drag-and-drop)

Drop a screenshot from Finder onto the input bar, click the new 📎
button to pick from disk, or paste from clipboard. Up to 8 images
per turn. Chips show 28pt thumbnails + media type + × to remove
individually.

Pipeline: Mac encodes each file to base64 → POSTs `{message,
images:[{media_type, data}]}` to kincode's `/api/chat` → kincode
translates to Anthropic image content blocks / OpenAI image_url
parts → vision-capable models (claude-3+, gpt-4o) see the image.

### Added — Plan-mode toggle + banner

📋 list-bullet button next to the paperclip in the input bar. On =
orange icon + thin orange banner above the input ("Plan mode —
read-only, no edits / shell. Tap to disable."). Either path toggles
off — icon and banner are both buttons.

Server-state sync via SSE `plan_mode` events — multi-window UIs
stay in sync. Optimistic update on toggle, revert + error message
if `POST /api/plan_mode` fails.

### Added — Stable `make` build/sign/run loop

`Makefile` + `scripts/sign-app.sh` close the TCC re-auth loop. Every
rebuild ad-hoc-codesigns the .app and the helper binaries (`kinclaw`,
`kincode`) with stable bundle identifiers, so macOS Accessibility /
Screen Recording grants survive across builds.

```
make help     — list targets
make run      — kill old → build all → sign all → launch (the flow)
make sign     — same minus the launch
make build    — just xcodebuild (no signing)
make kill     — stop KinClawMac + kinclaw + kincode
make doctor   — show signing state + running PIDs (first thing
                to run when something looks off)
make clean    — drop DerivedData
```

Stable identifiers re-applied on every signing pass:
  - `dev.localkin.kinclawmac` — KinClawMac.app
  - `dev.localkin.kinclaw`    — `~/.localkin/bin/kinclaw`
  - `dev.localkin.kincode`    — `~/.localkin/bin/kincode`

Helper binaries are signed by their own `scripts/install.sh` in the
sibling repos. The Makefile orchestrates — runs each `install.sh`
inside-out, then signs the .app with hardened runtime + deep mode
via `scripts/sign-app.sh`. `pgrep -x` (executable basename only)
avoids the self-match foot-gun in `make kill` / `make doctor`.

### Why this matters

v0.2.0 shipped the three-mode integration. v0.3.0 makes Code mode
actually pleasant to use day-to-day:

- TodoWrite checklist UI turns kincode's plan-tracking into a real
  artifact you can read at a glance instead of a pill that says
  "todo_write [{...}]".
- Image input lets you drop a screenshot and ask "what's wrong with
  this UI" — the most-cited workflow that was awkward without it.
- Plan mode adds the safety valve: hand kincode a non-trivial task
  and have it research + draft a plan first, instead of yolo-modify.
- Stable build loop = no more re-authorizing AX / Screen Recording
  every rebuild. `make run` is the one command you need.

Paired with [kincode v0.10.0](https://github.com/LocalKinAI/kincode/releases/tag/v0.10.0)
(image input + plan mode kernel-side) and [kincode v0.9.0](https://github.com/LocalKinAI/kincode/releases/tag/v0.9.0)
(named subagents at `~/.kincode/agents/<name>.md`).

---

## [0.2.0] - 2026-05-04

**Three-mode integration shipped.** KinClaw Mac is now the spotlight
shell for the whole kernel family — one window, one hotkey, three
distinct surfaces:

- **Chat** → 98 cloud agents (Selah / Heal / Core / Faith)
- **Cowork** → kinclaw kernel + 5 claws (Pilot / Coder / Critic / etc.)
- **Code** → kincode kernel + repo-aware coding (kimi-k2.6:cloud default)

The three-pill ModeBar lives in the titlebar (mode is the primary
choice — what kind of work). Each tab carries its own agent pool;
switching tabs swaps pools cleanly without bleed-through.

17 kinclaw-mac commits over the day, plus paired changes in
[`kincode`](https://github.com/LocalKinAI/kincode) (rename + serve
mode + soul brain) and [`kinclaw`](https://github.com/LocalKinAI/kinclaw)
(screen capture wiring, orphan watch, boot-time AX prompt).

### Added — Mode infrastructure

- `Models/ChatMode.swift` — Chat / Cowork / Code enum with UserDefaults persistence
- `UI/ModeBar.swift` — three-pill segmented switcher in titlebar
- Per-mode last-agent persistence (`kinclaw.chat.lastAgent`,
  `kinclaw.cowork.lastSoul`)
- Mode-scoped agent picker — Chat shows only cloud groups, Cowork
  shows only KinClaw souls, Code shows static "🦞 kincode" identity
- Synchronous message-clear on mode change so switching tabs feels
  instant, not "old mode's content briefly visible"

### Added — KinCodeSupervisor (`Services/KinCodeSupervisor.swift`)

- Spawns `kincode -serve -port 5002 -soul ...` alongside kinclaw on
  app launch (parallel boot, independent of each other)
- Same lifecycle pattern as KinClawSupervisor (start/stop/State,
  one-shot crash recovery, /api/health probe)
- 5-path binary search (bundle Resources/ → dev repo → Homebrew →
  ~/go/bin)
- Autostart toggle via UserDefaults (`kinclaw.kincode.autostart`,
  default true) — power users can disable from Settings

### Added — `UI/CodePane.swift` (Code mode body)

- Repo picker dropdown with 5 most-recent
- Status dot (green=connected, orange=reconnecting) + tooltip with
  detail (no inline error text crowding the row)
- Streaming text deltas with markdown rendering (same `MarkdownView`
  as Chat surface — fenced code, lists, headings)
- Inline tool-call pills (🔨 hammer + tool name + summary) for bash /
  glob / grep / web_*
- Real diff viewer (`UI/DiffView.swift`) for `file_edit` results —
  parses kincode's ANSI-colored unified diff, renders red/green
  tinted rows with +N/−N counts in the header
- Per-repo session persistence
  (`~/.kinclaw/code-sessions/<repoHash>/<id>.json`) — switching repos
  swaps sessions; "+ new session" button preserves current
- Visual primitives match `chatBody` exactly — same bubble shapes,
  same input bar pill, same welcome-card chips, just with kincode-
  specific contents (🦞 avatar, repo picker, no voice/attachments)

### Added — Settings → Backend → Kincode card

- Autostart toggle (writes `kinclaw.kincode.autostart`)
- Port field (5002 default)
- Live status indicator that probes `/api/health` then `/api/state`
  for the model label ("Running — kimi-k2.6:cloud")
- Both kernels' status probes run concurrently in the same `.task`

### Added — DisclaimedProcess (`Services/DisclaimedProcess.swift`)

The TCC fix that was the day's big debugging arc. macOS's
"responsibility chain" attributes subprocess permission checks back
to the parent .app — so `kinclaw` running under `KinClawMac.app`
was checking against KinClawMac's TCC entries (none) instead of
kinclaw's own (granted from the user's prior CLI runs).

`Services/DisclaimedProcess.swift` is a Foundation.Process replacement
that uses `posix_spawn` directly + the private SPI
`responsibility_spawnattrs_setdisclaim(attrs, 1)`. Subprocesses
spawned through it own their own TCC identity — same identity as
when run from Terminal. Same trick Slack / Tailscale / Karabiner
helper apps use.

KinClawSupervisor + KinCodeSupervisor both updated to use it.
Process-shaped surface (terminate, isRunning, terminationHandler,
processIdentifier) so call sites didn't need rewrites.

### Changed — Layout

- ModeBar promoted to titlebar (was: secondary row below header).
  Hierarchy now matches concept — mode is the primary choice, agent
  is secondary.
- Titlebar reservation 28pt → 22pt; ModeBar internal vertical padding
  4pt → 0pt; titlebar-overlay vertical padding 3pt → 1pt. Net ~10pt
  closer between green Code pill and the secondary row.
- Settings window 540×460 → 620×460 to fit 7 tab labels on one line
  without wrapping. Tab Text views now `.lineLimit(1).fixedSize()`.
- Code mode skips the global agent secondary row; CodePane's own
  repoBar serves that role with same height + paddings as agentBar
  in Chat/Cowork (visual consistency across all three modes).

### Fixed — STT routes local agents to SenseVoice :8000 directly

`VoiceRecorder.serverSTT` was always building
`https://<hostname>/v1/stt`, which produced bogus URLs like
`https://localhost-kinclaw/v1/stt` for local KinClaw souls in
Cowork mode. Now mirrors the existing TTS local-routing fix: detect
`localhost-kinclaw` / localhost-prefix → POST to
`http://localhost:8000/transcribe` (configurable via
`kinclaw.backend.stt`). Cloud STT keeps `/v1/stt` + Bearer auth.

### Fixed — Cowork agent stops getting stuck in cloud-land

When switching from Chat → Cowork before kinclaw souls finished
loading, `applyAgentForMode` returned nil → `selectedAgent` stayed
on Selah (cloud) → menu showed only KinClaw souls but the dropdown
label still read "Selah". Now `applyAgentForMode` always assigns
(even nil), and `loadAgents` re-validates on every catalog refresh —
once souls land, the agent swaps to Pilot.

### Polish

- Removed ScreenFeedView from Cowork: the screen IS the user's
  desktop, embedding a 220pt JPEG copy on top is redundant. Cowork
  is now structurally identical to Chat (different agent pool only).
- Removed file-tree sidebar from Code: kincode navigates the repo via
  `glob`/`grep` tools as it goes, same as Claude Code; no need for
  a 160pt sidebar that broke the three-tab visual symmetry.
- Subprocess orphan-watch — `kill -9` of the parent .app no longer
  leaks kinclaw + kincode children with bound ports (the children
  poll `os.Getppid()` every 2s and self-exit when re-parented to
  launchd). 525 lines of dead code removed alongside.

### Stats

29 commits today across kinclaw-mac (17), kincode (9), kinclaw (3).
Net +~3000 lines of Swift / Go (CodePane + DiffView + DisclaimedProcess +
KinCodeSupervisor + ScreenFeedView-experiment-since-removed).

## [0.1.0] - 2026-05-04

**Open-sourced under Apache-2.0.** Repo flipped public.

Prior to this, KinClaw Mac was a private Proprietary repo while the kinclaw kernel sat public Apache-2.0 nearby. Decision tonight after Jacky asked whether to open it: kinclaw-mac is structurally the **native shell of an already-open kernel** (kinclaw can do everything kinclaw-mac surfaces — kinclaw-mac is just the macOS native packaging). Same stack, should be same license.

LocalKin platform (swarm core, cloud agents, ios Pro client) stays private — that's the moat. KinClaw stack (kernel + Mac shell + future Linux/Win shells) all goes Apache.

License + repo changes:

- `LICENSE` swapped from custom Proprietary text to standard Apache-2.0 (matches kinclaw kernel exactly)
- `Info.plist` `NSHumanReadableCopyright` → "© 2026 LocalKinAI. Apache-2.0 licensed."
- `README.md` rewritten:
  - Apache-2.0 badge + macOS / Swift badges in header
  - Status moved from "Planning" placeholder to "v0.1.0 shipping"
  - Family section split into "KinClaw stack (all open)" vs "LocalKin platform (closed)"
  - Added Build from source section
  - Added Contributing section
- GitHub repo visibility flipped private → public

All 40+ commits between scaffold and v0.1.0 stay in history — fork heritage from localkin-ios is transparent and intentional.

Trademarks: `KinClaw` name + lobster mark held by LocalKinAI; code Apache-licensed for use, name reserved for upstream-faithful builds. Standard OSS pattern.

## [Unreleased]

### Planning kicked off — 2026-05-03

Initial repo scaffolded. No code yet — see [`docs/spotlight-shell-plan.md`](docs/spotlight-shell-plan.md).

**Planned milestones**:
- M0: Fork [`localkin-ios`](https://github.com/LocalKinAI/localkin-ios), retarget to macOS 13+, build green
- M1: `KinClawAPIClient` adapter (`/api/chat` + `/api/events` for local kinclaw serve)
- M2: `SpotlightWindow` (NSPanel + nonactivating + glass blur)
- M3: Global hotkey (⌘⌥K) + menubar (🦞 NSStatusItem)
- M4: `KinClawSupervisor` (subprocess management + auto-restart)
- M5: Polish (animations, position/size memory, settings UI)
- M6: Codesign + notarize + DMG (blocked on $99 Apple Developer cert)

Estimated 4 days of dev + 2 days of signing/distribution work after cert lands.

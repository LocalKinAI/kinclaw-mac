# Changelog

All notable changes to KinClaw Mac.

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

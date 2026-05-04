# KinClaw Mac

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-black.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

> **Your AI dock. ⌘⌥K to summon any of 98 agents — or KinClaw to operate your Mac. Free. Open. Your data stays.**

Native macOS Spotlight-style shell that connects to **two agent sources**:

- 🦞 **Local KinClaw** (`localhost:5001`) — the [KinClaw](https://github.com/LocalKinAI/kinclaw) Go kernel running on your Mac, with full computer-use capability via 5 claws (screen / ui / input / record / web)
- ☁️ **Cloud LocalKin** (`api.localkin.dev`) — 98 specialized agents across spiritual / TCM / language tutoring / research / etc.

Same floating window, same hotkey, same voice mode. Switch between local + cloud agents in one summon.

---

## Status

✅ **v0.1.0** — shipping. M0 → M10 + 10 polish rounds + multi-session history landed.

40+ commits since 2026-05-03. See [CHANGELOG](CHANGELOG.md) and [`docs/spotlight-shell-plan.md`](docs/spotlight-shell-plan.md) for the full milestones.

This project forks heavily from [localkin-ios](https://github.com/LocalKinAI/localkin-ios) (1,756 lines of Swift, generation-tested). Mac-specific layer added ~340 lines (NSPanel floating window, global hotkey, menubar, KinClaw subprocess supervisor) plus all the polish since.

---

## Architecture

```
┌──────────────────────────────────────────┐
│  KinClaw Mac (kinclaw-mac.app)           │
│                                          │
│   ┌─────────────────────────────────┐    │
│   │  AgentSource selector           │    │
│   │  ◉ Local (KinClaw)              │    │
│   │  ○ Cloud (LocalKin)             │    │
│   └─────────────────────────────────┘    │
│                                          │
│   NSPanel (frameless, glass blur)        │
│   ⌘⌥K to toggle, always-on-top           │
│   Voice + streaming markdown             │
└──────────────────────────────────────────┘
              │             │
              ▼             ▼
   localhost:5001      api.localkin.dev/v1
   (kinclaw serve)     (160+ cloud agents)
```

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

## Default settings

| | Default | Configurable |
|---|---|---|
| Hotkey | ⌘⌥K | ✅ Settings → Hotkey |
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

```bash
brew install xcodegen
git clone https://github.com/LocalKinAI/kinclaw-mac
cd kinclaw-mac
xcodegen generate
open KinClawMac.xcodeproj
# ⌘R
```

For local agents you'll also need `kinclaw` on PATH (or in `~/Documents/Workspace/kinclaw/`):

```bash
git clone https://github.com/LocalKinAI/kinclaw
cd kinclaw
go build -o kinclaw ./cmd/kinclaw/
```

The KinClaw Mac supervisor auto-spawns kinclaw at `localhost:5001` on launch.

---

## Contributing

Open issue / PR welcome. Especially:

- macOS-specific bug reports (we're macOS-14+ only)
- New agent suggestions for `Models/AgentSuggestions.swift` welcome chips
- TTS voice routing improvements (Kokoro / system AVSpeech)
- Localization (currently bilingual zh/en, needs proper i18n)

For deep changes (NSPanel chrome, supervisor lifecycle, session model) — open an issue first to discuss.

---

## License

[Apache License 2.0](LICENSE) — © 2026 LocalKinAI.

The `KinClaw` name + lobster mark are trademarks of LocalKinAI; you can fork the code freely under Apache, but redistributions under the `KinClaw` name should match upstream behavior or use a different name.

Other inquiries: hello@localkin.dev

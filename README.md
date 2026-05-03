# KinClaw Mac

> **Your AI dock. ⌘⌥K to summon any of 160+ agents — or KinClaw to operate your Mac.**

Native macOS Spotlight-style shell that connects to **two agent sources**:

- 🦞 **Local KinClaw** (`localhost:5001`) — the [KinClaw](https://github.com/LocalKinAI/kinclaw) Go binary running on your Mac, with full computer-use capability via 5 claws (screen / ui / input / record / web)
- ☁️ **Cloud LocalKin** (`api.localkin.dev`) — 160+ specialized agents across 19 domains for chat, research, debate

Same floating window, same hotkey, same voice mode. Switch between local & cloud agents in one summon.

---

## Status

🚧 **Planning** (2026-05-03). Code not yet imported.

See [`docs/spotlight-shell-plan.md`](docs/spotlight-shell-plan.md) for the full plan — milestones M0 → M6, ~6 day build.

This project forks heavily from [localkin-ios](https://github.com/LocalKinAI/localkin-ios) (1,756 lines of Swift, generation-tested). Mac-specific layer adds ~340 lines (NSPanel floating window, global hotkey, menubar, KinClaw subprocess supervisor).

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

| Repo | Role |
|---|---|
| [`kinclaw`](https://github.com/LocalKinAI/kinclaw) | Go CLI + the 5-claw kernel (open source, Apache-2.0) |
| [`localkin-ios`](https://github.com/LocalKinAI/localkin-ios) | iOS client for cloud LocalKin (proprietary) |
| `kinclaw-mac` (this) | macOS Spotlight shell, dual-source agent dock (proprietary) |

---

## License

Proprietary. See [LICENSE](LICENSE).

For licensing inquiries: hello@localkin.dev

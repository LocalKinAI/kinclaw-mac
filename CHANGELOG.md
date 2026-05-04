# Changelog

All notable changes to KinClaw Mac.

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

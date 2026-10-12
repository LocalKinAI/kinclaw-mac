# KinClawMac — stable build/sign/run loop
#
# The whole point of this Makefile: kill the old process, build the
# .app with the kinclaw kernel inside it, sign it (and the developer's
# kinclaw in ~/.localkin/bin/) with stable bundle identifiers, then
# launch — so macOS TCC remembers the user's accessibility /
# screen-recording grants across rebuilds.
#
# Common workflow:
#   make run        # one-shot: kill + sign everything + launch
#   make sign       # build + sign without launching
#   make kill       # stop the running app + the kernel
#   make doctor     # show what's signed where + what's running
#
# Stable bundle identifiers (re-applied on every signing pass):
#   dev.localkin.kinclawmac   — KinClawMac.app
#   dev.localkin.kinclaw      — kinclaw kernel binary (both copies)
#
# (kincode, the old Code mode's kernel, is gone since 2026-10-10: Code
# is Claude Code and Codex.)

# ─── Paths ─────────────────────────────────────────────────────────────
SHELL              := /bin/bash
REPO_ROOT          := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
SCHEME             := KinClawMac
CONFIGURATION      := Debug
DERIVED_DATA       := $(HOME)/Library/Developer/Xcode/DerivedData
APP_BUNDLE_NAME    := $(SCHEME).app
BUILD_PRODUCTS_DIR := $(shell find $(DERIVED_DATA) -maxdepth 5 -name '$(APP_BUNDLE_NAME)' -path '*/Build/Products/$(CONFIGURATION)/*' -print 2>/dev/null | head -1 | xargs -I{} dirname {})
APP_PATH           := $(BUILD_PRODUCTS_DIR)/$(APP_BUNDLE_NAME)

# The kinclaw repo, built into the app and run from in development.
# Discovery order — first hit wins:
#   1. KINCLAW_REPO env var (explicit override)
#   2. ../kinclaw (sibling layout, the documented one)
#   3. ~/Documents/Workspace/<name> (Jacky's layout)
#   4. ~/code/<name> / ~/dev/<name> / ~/src/<name> (other common
#      conventions)
# If none found → `make bootstrap` clones into ../<name>.
#
# Override on a one-off basis: KINCLAW_REPO=/my/path make run
KINCLAW_REPO       ?= $(shell \
	for d in $(REPO_ROOT)/../kinclaw \
	         $(HOME)/Documents/Workspace/kinclaw \
	         $(HOME)/code/kinclaw \
	         $(HOME)/dev/kinclaw \
	         $(HOME)/src/kinclaw; do \
	  if [ -d "$$d/.git" ]; then echo "$$d"; exit 0; fi; \
	done; echo $(REPO_ROOT)/../kinclaw)
# localkin (private/optional) — if the user has the LocalKin family
# core repo checked out, its skills/ dir holds 130+ cloud-side
# SKILL.md files (knowledge_search wraps grep-is-all-you-need,
# pubmed_search, rag_recall, master-specific teaching skills, ...).
# 95% of them are kinclaw-format compatible — auto-discoverable when
# the repo is on disk. Optional: kinclaw runs fine without it.
LOCALKIN_REPO      ?= $(shell \
	for d in $(REPO_ROOT)/../localkin \
	         $(HOME)/Documents/Workspace/localkin \
	         $(HOME)/code/localkin \
	         $(HOME)/dev/localkin \
	         $(HOME)/src/localkin; do \
	  if [ -d "$$d/.git" ]; then echo "$$d"; exit 0; fi; \
	done)
KINCLAW_REMOTE     := https://github.com/LocalKinAI/kinclaw.git

# Stable install path of the developer's kernel. The supervisor runs it
# before the copy inside the app in a debug build, after it in release.
LOCALKIN_BIN       := $(HOME)/.localkin/bin

# Where the helpers' detached stdout/stderr land. Tail these when
# something looks off (`tail -f $(LOG_DIR)/kinclaw.log`).
LOG_DIR            := /tmp

# Default soul for the kernel. Read directly from the repo so edits
# are immediately live — no install/copy step needed.
# (Earlier this pointed at ~/.localkin/{souls,bin}/ family location
# but install.sh's cp -n meant the copies went stale and never updated;
# repo edits never reached the running kernel. Reading repo paths
# straight is the simpler architecture.)
PILOT_SOUL         := $(KINCLAW_REPO)/souls/pilot.soul.md

# Process names we kill on `make kill` / before re-signing.
PROC_PATTERNS      := KinClawMac kinclaw

.DEFAULT_GOAL := help

# ─── Targets ───────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help (default)
	@printf "\033[1mKinClawMac build targets\033[0m\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@printf "\nCommon flow: \033[33mmake run\033[0m  (kill → sign → launch)\n"

.PHONY: bootstrap
bootstrap: ## Clone the kinclaw repo if it is not found anywhere
	@# Goal: "git clone kinclaw-mac && cd kinclaw-mac && make run" should
	@# yield a fully working app. The KINCLAW_REPO
	@# variable already searched common locations
	@# (../kinclaw, ~/Documents/Workspace/kinclaw, ~/code/kinclaw, etc.)
	@# — bootstrap just clones the *fallback* path if nothing was found.
	@# So if you already have kinclaw at ~/code/kinclaw, this target
	@# won't clone anything; it'll just confirm the existing checkout.
	@if [ -d "$(KINCLAW_REPO)/.git" ]; then \
	  echo "  ✓ kinclaw at $(KINCLAW_REPO)"; \
	else \
	  echo "==> Cloning kinclaw → $(KINCLAW_REPO) ..."; \
	  git clone "$(KINCLAW_REMOTE)" "$(KINCLAW_REPO)"; \
	fi

.PHONY: gen
gen: ## Regenerate KinClawMac.xcodeproj from project.yml (XcodeGen)
	@command -v xcodegen >/dev/null \
	  || { echo "✗ xcodegen not found — install with: brew install xcodegen"; exit 1; }
	@echo "==> XcodeGen ..."
	@cd $(REPO_ROOT) && xcodegen generate

.PHONY: build
build: gen ## Build KinClawMac.app (Debug)
	@echo "==> xcodebuild $(SCHEME) ($(CONFIGURATION)) ..."
	@# The status dance below is because this recipe used to pipe xcodebuild
	@# into grep and end with `|| true`: a FAILED build printed "✓ Built" and
	@# exited 0, so `make run` went on to launch the previous binary.
	@cd $(REPO_ROOT) && xcodebuild \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  build > $(LOG_DIR)/xcodebuild.log 2>&1; \
	  status=$$?; \
	  grep -E "error:|warning:|BUILD " $(LOG_DIR)/xcodebuild.log | tail -20; \
	  if [ $$status -ne 0 ]; then \
	    echo "✗ xcodebuild failed ($$status) — full log: $(LOG_DIR)/xcodebuild.log"; \
	    exit $$status; \
	  fi
	@$(MAKE) -s _refresh-app-path
	@echo "✓ Built: $$(cat .last-app-path 2>/dev/null || echo '<not found>')"

# Recomputes APP_PATH after build (the find above runs at parse time
# and misses just-built artifacts). Stash it for the sign target.
.PHONY: _refresh-app-path
_refresh-app-path:
	@find $(DERIVED_DATA) -maxdepth 5 -name '$(APP_BUNDLE_NAME)' \
	  -path '*/Build/Products/$(CONFIGURATION)/*' -print 2>/dev/null \
	  | head -1 > .last-app-path

.PHONY: bundle-kernel
bundle-kernel: ## Put the kinclaw kernel, its souls and skills inside the built .app
	@APP="$$(cat .last-app-path 2>/dev/null)"; \
	if [[ -z "$$APP" || ! -d "$$APP" ]]; then \
	  echo "✗ No built .app found. Run 'make build' first." >&2; \
	  exit 1; \
	fi; \
	$(REPO_ROOT)/scripts/bundle-kernel.sh "$$APP" "$(KINCLAW_REPO)"

.PHONY: sign-helpers
sign-helpers: ## Build + sign + install the developer's kinclaw into ~/.localkin/bin (sibling repo)
	@echo "==> Signing the developer's kernel (kinclaw) ..."
	@if [[ -x "$(KINCLAW_REPO)/scripts/install.sh" ]]; then \
	  "$(KINCLAW_REPO)/scripts/install.sh" 2>&1 | sed 's/^/    /'; \
	else \
	  echo "  ⚠ skipped kinclaw (sibling repo $(KINCLAW_REPO) not found)"; \
	fi

.PHONY: sign-app
sign-app: ## Sign the built .app with stable identifier (assumes build ran)
	@APP="$$(cat .last-app-path 2>/dev/null)"; \
	if [[ -z "$$APP" || ! -d "$$APP" ]]; then \
	  echo "✗ No built .app found. Run 'make build' first." >&2; \
	  exit 1; \
	fi; \
	echo "==> Signing app at $$APP"; \
	$(REPO_ROOT)/scripts/sign-app.sh "$$APP"

.PHONY: sign
sign: kill-app bootstrap build bundle-kernel sign-helpers sign-app ## Full sign loop: quit the app + bootstrap kinclaw + build + bundle the kernel + sign all
	@printf "\n✓ Signed everything. Launch with: \033[33mmake run\033[0m\n"

# The app alone, not the processes that outlive it well (「重启不打断」, 2026-10-11).
# SIGTERM is a quit for the app: it remembers which agents and Code sessions were
# running and resumes them at the next launch. Its panel relays are the same
# binary run with --mcp-stdio — a pattern anchored at the bare binary path misses
# them, and they reach the next app by themselves (they read ~/.localkin/panel.json
# on every call). The kernel is left to start-helpers, which restarts it only when
# it changed. `make kill` still stops everything.
APP_PROC := /KinClawMac\.app/Contents/MacOS/KinClawMac$$

.PHONY: kill-app
kill-app: ## Quit the KinClawMac app only (its relays and the kernel stay)
	@pids="$$(pgrep -f '$(APP_PROC)' || true)"; \
	if [[ -n "$$pids" ]]; then \
	  echo "  → quitting KinClawMac ($$pids)"; \
	  kill -TERM $$pids 2>/dev/null || true; \
	  for i in $$(seq 1 40); do pgrep -f '$(APP_PROC)' >/dev/null || break; sleep 0.25; done; \
	  if pgrep -f '$(APP_PROC)' >/dev/null; then \
	    echo "  ⚠ still up after 10 s — killing it"; \
	    pkill -9 -f '$(APP_PROC)' || true; \
	  fi; \
	fi

.PHONY: start-helpers
start-helpers: ## Start kinclaw as a detached daemon (PPID=1, survives shell exit)
	@# Start the kernel BEFORE KinClawMac so the supervisor finds it
	@# already on :5001 and adopts it cleanly. No spawn race.
	@#
	@# Detachment: `( cmd >log 2>&1 & )` — subshell-and-fork puts the
	@# helper directly under launchd (PPID=1), bypassing kinclaw's
	@# orphan-watch (which only fires when PPID changes from a non-1
	@# starting value). Without this, the helper would exit ~2s after
	@# `make` returns, when the make shell terminates.
	@# Pass dev-repo skills/ to the kernel via env var. kinclaw at
	@# boot reads $KINCLAW_SKILL_DIRS
	@# (colon-separated) and scans each for SKILL.md files in addition
	@# to ~/.localkin/skills/. So a fresh `git clone kinclaw-mac` →
	@# `make run` gives the user every dev-repo skill (location,
	@# weather, web, music_*, imsg_send...) without any copy step.
	@# Edits to the dev repo's SKILL.md become live on next helper
	@# restart — no install.sh required.
	@# Pre-query corelocationcli so the model's system prompt has
	@# {{location}} filled with real city + lat/lon. Without this,
	@# pilot sees `位置: ` (empty) and replies "I don't have GPS,
	@# tell me your city" — even though the location skill IS
	@# loaded. Empirically reproducible: kimi-k2.5:cloud reads the
	@# empty position field as ground truth ("model has no
	@# location") and refuses to call the skill.
	@#
	@# Format: KINCLAW_LOCATION="lat,lon[,city[,country]]". We pull
	@# all four via corelocationcli's separate -format calls (one
	@# round-trip each, ~80ms total). Silently skip if
	@# corelocationcli isn't installed — pilot still works for
	@# everything except location-aware queries.
	@# corelocationcli's -format flag is broken in current versions
	@# (always returns "lat lon" regardless of format string). --json
	@# is reliable — full structured data including locality, country,
	@# postalCode, etc. Pipe through python3 (always present on
	@# macOS) to extract the lat,lon,city,country tuple kinclaw
	@# expects in $$KINCLAW_LOCATION.
	@# Build kinclaw skill discovery path + GPS env in ONE shell block.
	@# Make recipes run each `@line` as a fresh shell, so cross-line
	@# variables (KINCLAW_SKILL_PATH, KINCLAW_LOCATION_VAL) need to
	@# share a single \-continued block.
	@#
	@# Skill path: dev kinclaw/skills/ (always) + localkin/skills/
	@# (when present, 130+ extra SKILL.md). Optional.
	@KINCLAW_SKILL_PATH="$(KINCLAW_REPO)/skills"; \
	if [ -d "$(LOCALKIN_REPO)/skills" ]; then \
	  KINCLAW_SKILL_PATH="$$KINCLAW_SKILL_PATH:$(LOCALKIN_REPO)/skills"; \
	  echo "  → discovering localkin skills via $(LOCALKIN_REPO)/skills"; \
	fi; \
	KINCLAW_LOCATION_VAL=""; \
	if command -v corelocationcli >/dev/null 2>&1; then \
	  printf "  → fetching GPS for system prompt context..."; \
	  KINCLAW_LOCATION_VAL=$$(corelocationcli -once --json 2>/dev/null | \
	    python3 -c 'import json,sys; \
d=json.load(sys.stdin); \
parts=[d.get("latitude",""), d.get("longitude",""), d.get("locality",""), d.get("country","")]; \
print(",".join(parts).rstrip(","))' 2>/dev/null); \
	  if [[ -n "$$KINCLAW_LOCATION_VAL" ]]; then \
	    echo " ✓ ($$KINCLAW_LOCATION_VAL)"; \
	  else \
	    echo " ✗ (corelocationcli failed — Location Services denied?)"; \
	  fi; \
	else \
	  echo "  → corelocationcli not installed (skip GPS context; \`brew install corelocationcli\` to enable)"; \
	fi; \
	STT_VAL=$$(defaults read dev.localkin.kinclawmac kinclaw.backend.stt 2>/dev/null); \
	TTS_VAL=$$(defaults read dev.localkin.kinclawmac kinclaw.backend.tts 2>/dev/null); \
	[[ -n "$$STT_VAL$$TTS_VAL" ]] && echo "  → voice from Settings: STT=$${STT_VAL:-default} TTS=$${TTS_VAL:-default}"; \
	SEARXNG_VAL=""; \
	SEARXNG_TRY="$${SEARXNG_ENDPOINT:-$$(defaults read dev.localkin.kinclawmac kinclaw.backend.searxng 2>/dev/null)}"; \
	SEARXNG_TRY="$${SEARXNG_TRY:-http://localhost:8080}"; \
	if curl -s -o /dev/null -m 2 -w "%{http_code}" "$$SEARXNG_TRY/" 2>/dev/null | grep -q "^[23]"; then \
	  SEARXNG_VAL="$$SEARXNG_TRY"; \
	  printf "  → SearXNG ✓ ($$SEARXNG_VAL)\n"; \
	else \
	  printf "  → SearXNG :8080 not reachable — web_search will degrade to web_scrape\n"; \
	fi; \
	KERNEL_PRINT="$$( { shasum -a 256 "$(LOCALKIN_BIN)/kinclaw"; \
	  find "$(KINCLAW_REPO)/souls" -type f -name '*.md' -exec shasum -a 256 {} + ; } 2>/dev/null | shasum -a 256 | cut -c1-16 )"; \
	if pgrep -x kinclaw >/dev/null 2>&1 && \
	   [[ "$$(cat $(LOG_DIR)/kinclaw.fingerprint 2>/dev/null)" != "$$KERNEL_PRINT" ]]; then \
	  echo "  → kinclaw changed since it started (its binary or souls) — restarting it"; \
	  pkill -x kinclaw 2>/dev/null || true; \
	  for i in $$(seq 1 20); do pgrep -x kinclaw >/dev/null || break; sleep 0.25; done; \
	fi; \
	if pgrep -x kinclaw >/dev/null 2>&1; then \
	  echo "  → kinclaw running on :5001, unchanged — kept (its conversations and brain stay)"; \
	else \
	  echo "$$KERNEL_PRINT" > $(LOG_DIR)/kinclaw.fingerprint; \
	  echo "  → starting kinclaw on :5001 (log: $(LOG_DIR)/kinclaw.log)"; \
	  if [[ -f "$(PILOT_SOUL)" ]]; then \
	    ( KINCLAW_SKILL_DIRS="$$KINCLAW_SKILL_PATH" \
	      KINCLAW_SOUL_DIRS="$(KINCLAW_REPO)/souls" \
	      KINCLAW_LOCATION="$$KINCLAW_LOCATION_VAL" \
	      SEARXNG_ENDPOINT="$$SEARXNG_VAL" \
	      STT_ENDPOINT="$$STT_VAL" TTS_ENDPOINT="$$TTS_VAL" \
	      "$(LOCALKIN_BIN)/kinclaw" serve -port 5001 -no-record \
	      -soul "$(PILOT_SOUL)" >$(LOG_DIR)/kinclaw.log 2>&1 & ); \
	  else \
	    ( KINCLAW_SKILL_DIRS="$$KINCLAW_SKILL_PATH" \
	      KINCLAW_SOUL_DIRS="$(KINCLAW_REPO)/souls" \
	      KINCLAW_LOCATION="$$KINCLAW_LOCATION_VAL" \
	      SEARXNG_ENDPOINT="$$SEARXNG_VAL" \
	      STT_ENDPOINT="$$STT_VAL" TTS_ENDPOINT="$$TTS_VAL" \
	      "$(LOCALKIN_BIN)/kinclaw" serve -port 5001 -no-record \
	      >$(LOG_DIR)/kinclaw.log 2>&1 & ); \
	  fi; \
	fi
	@# Wait for the port to bind before returning. Without this,
	@# the immediately-following `open KinClawMac.app` could race
	@# the kernel's bind() and the supervisor fail its initial
	@# ping → spawn a duplicate kernel → port-in-use cascade.
	@printf "  → waiting for :5001 to bind"
	@deadline=$$(($$(date +%s) + 15)); \
	while [[ $$(date +%s) -lt $$deadline ]]; do \
	  k=$$(lsof -ti :5001 -sTCP:LISTEN 2>/dev/null | head -1); \
	  if [[ -n "$$k" ]]; then \
	    printf " ✓ (kinclaw=%s)\n" "$$k"; \
	    exit 0; \
	  fi; \
	  printf "."; \
	  sleep 0.5; \
	done; \
	printf "\n  ⚠ the kernel didn't bind within 15s — check $(LOG_DIR)/kinclaw.log\n"

.PHONY: run
run: sign start-helpers ## quit the app + sign + start the kernel (or keep it, unchanged) + launch app
	@# Kernel-first ordering: by the time KinClawMac launches, kinclaw
	@# is already serving. The supervisor's adoption path picks it up
	@# immediately (state = .adoptedExternal). No spawn race, no
	@# orphan-watch confusion.
	@APP="$$(cat .last-app-path 2>/dev/null)"; \
	echo "==> Launching $$APP"; \
	open "$$APP"
	@sleep 1
	@$(MAKE) -s doctor

.PHONY: kill
kill: ## Stop KinClawMac + the kernel (kinclaw)
	@# pgrep -x matches the executable's basename exactly — avoids the
	@# self-match foot-gun where `pgrep -f kinclaw` also matches this
	@# shell's command line which contains the word "kinclaw".
	@for p in $(PROC_PATTERNS); do \
	  pids="$$(pgrep -x "$$p" 2>/dev/null || true)"; \
	  if [[ -n "$$pids" ]]; then \
	    echo "  → killing $$p ($$pids)"; \
	    pkill -x "$$p" 2>/dev/null || true; \
	  fi; \
	done
	@# Give them a moment to drop ports / file handles before re-signing.
	@sleep 1
	@echo "✓ Stopped"

.PHONY: test
test: ## Tests that need neither the app nor the box: pv.py's waits, the Montage bridge's jobs, the machine check in WebKit
	@python3 -I scripts/tests/test_pv.py
	@python3 -I scripts/tests/test_om_bridge.py
	@scripts/tests/machinecheck/run.sh

.PHONY: doctor
doctor: ## Show signing state + running processes (diagnostic)
	@printf "\033[1m─── Signing state ───\033[0m\n"
	@# Resolve APP_PATH lazily — if .last-app-path doesn't exist (fresh
	@# checkout, never built), fall back to a live find. Lets `make
	@# doctor` work as a first-touch diagnostic before any build.
	@APP="$$(cat .last-app-path 2>/dev/null)"; \
	if [[ -z "$$APP" || ! -d "$$APP" ]]; then \
	  APP="$$(find $(DERIVED_DATA) -maxdepth 5 -name '$(APP_BUNDLE_NAME)' \
	    -path '*/Build/Products/$(CONFIGURATION)/*' -print 2>/dev/null | head -1)"; \
	fi; \
	if [[ -d "$$APP" ]]; then \
	  printf "  %-15s " "KinClawMac.app"; \
	  codesign -dv "$$APP" 2>&1 | awk -F= '/^Identifier=/{printf "id=%s ", $$2} /^Signature/{printf "sig=%s\n", $$2}'; \
	  printf "  %-15s %s\n" "  → at" "$$APP"; \
	else \
	  printf "  %-15s not built yet\n" "KinClawMac.app"; \
	fi; \
	if [[ -x "$$APP/Contents/Helpers/kinclaw" ]]; then \
	  printf "  %-15s " "kinclaw (app)"; \
	  codesign -dv "$$APP/Contents/Helpers/kinclaw" 2>&1 | awk -F= '/^Identifier=/{printf "id=%s ", $$2} /^Signature/{printf "sig=%s ", $$2}'; \
	  printf "%s\n" "$$(cat "$$APP/Contents/Resources/kinclaw/VERSION" 2>/dev/null)"; \
	else \
	  printf "  %-15s not bundled (make bundle-kernel)\n" "kinclaw (app)"; \
	fi
	@path="$(LOCALKIN_BIN)/kinclaw"; \
	if [[ -x "$$path" ]]; then \
	  printf "  %-15s " "kinclaw (dev)"; \
	  codesign -dv "$$path" 2>&1 | awk -F= '/^Identifier=/{printf "id=%s ", $$2} /^Signature/{printf "sig=%s\n", $$2}'; \
	else \
	  printf "  %-15s not installed\n" "kinclaw (dev)"; \
	fi
	@printf "\n\033[1m─── Running processes ───\033[0m\n"
	@found=0; \
	for p in $(PROC_PATTERNS); do \
	  pids="$$(pgrep -x "$$p" 2>/dev/null || true)"; \
	  if [[ -n "$$pids" ]]; then \
	    for pid in $$pids; do \
	      cmd="$$(ps -o comm= -p $$pid 2>/dev/null)"; \
	      printf "  %-7s %s\n" "$$pid" "$$cmd"; \
	      found=1; \
	    done; \
	  fi; \
	done; \
	[[ $$found -eq 0 ]] && echo "  (none running)" || true
	@printf "\n\033[1m─── TCC permissions (actual state) ───\033[0m\n"
	@# Accessibility: read kinclaw's startup log. kinclaw queries
	@# AXIsProcessTrusted() at boot and prints ✓ / ✗ — most reliable
	@# signal we have without reading TCC.db (which needs Full Disk
	@# Access).
	@if [ -f "$(LOG_DIR)/kinclaw.log" ]; then \
	  ax="$$(grep 'Accessibility' $(LOG_DIR)/kinclaw.log | tail -1)"; \
	  if echo "$$ax" | grep -q "✓"; then \
	    printf "  Accessibility:    \033[32m✓ granted\033[0m (kinclaw verified at boot)\n"; \
	  elif echo "$$ax" | grep -q "✗"; then \
	    printf "  Accessibility:    \033[31m✗ NOT granted\033[0m — open System Settings → Privacy → Accessibility, toggle %s/kinclaw\n" "$(LOCALKIN_BIN)"; \
	  else \
	    printf "  Accessibility:    \033[33m? unknown\033[0m (no log entry — restart helpers)\n"; \
	  fi; \
	else \
	  printf "  Accessibility:    \033[33m? unknown\033[0m (no log; run \033[36mmake run\033[0m first)\n"; \
	fi
	@# Screen Recording: read kinclaw's log. kinclaw probes via
	@# sckit.ListDisplays at boot and prints ✓/✗. This is what the
	@# AGENT actually has, not what the calling terminal has — the
	@# previous /usr/sbin/screencapture probe tested the wrong
	@# process (made the user think their grant didn't work).
	@if [ -f "$(LOG_DIR)/kinclaw.log" ]; then \
	  sr="$$(grep 'Screen Recording' $(LOG_DIR)/kinclaw.log | tail -1)"; \
	  if echo "$$sr" | grep -q "✓"; then \
	    printf "  Screen Recording: \033[32m✓ granted\033[0m (kinclaw verified at boot)\n"; \
	  elif echo "$$sr" | grep -q "✗"; then \
	    printf "  Screen Recording: \033[31m✗ NOT granted\033[0m — open System Settings → Privacy → Screen Recording, toggle %s/kinclaw\n" "$(LOCALKIN_BIN)"; \
	  else \
	    printf "  Screen Recording: \033[33m? unknown\033[0m (no log entry — restart helpers to re-probe)\n"; \
	  fi; \
	else \
	  printf "  Screen Recording: \033[33m? unknown\033[0m (no log; run \033[36mmake run\033[0m first)\n"; \
	fi
	@# CDHash exposes WHY macOS may re-prompt across rebuilds: every
	@# rebuild changes this. Apple Developer cert at M6 will fix
	@# (Designated Requirement based on Team ID, cdhash-agnostic).
	@printf "\n  Current cdhash: %s\n" \
	  "$$(codesign -dvvvv $(LOCALKIN_BIN)/kinclaw 2>&1 | awk -F= '/^CDHash=/{print $$2}')"
	@printf "  \033[2m(every \`make sign\` changes this; ad-hoc TCC may re-prompt for Screen Recording in particular)\033[0m\n"

.PHONY: tcc-reset
tcc-reset: ## Wipe TCC entries for kinclaw + KinClawMac (forces clean re-grant)
	@# When ad-hoc TCC entries get stale (multiple cdhashes accumulated,
	@# user denied once and macOS suppresses re-prompts), tccutil reset
	@# clears the slate. Next launch fires fresh dialogs.
	@echo "==> Resetting Accessibility for the LocalKin family..."
	@tccutil reset Accessibility dev.localkin.kinclaw 2>&1 | sed 's/^/  /' || true
	@tccutil reset Accessibility dev.localkin.kinclawmac 2>&1 | sed 's/^/  /' || true
	@echo "==> Resetting Screen Recording for the LocalKin family..."
	@tccutil reset ScreenCapture dev.localkin.kinclaw 2>&1 | sed 's/^/  /' || true
	@tccutil reset ScreenCapture dev.localkin.kinclawmac 2>&1 | sed 's/^/  /' || true
	@echo "==> Resetting Apple Events for the LocalKin family..."
	@tccutil reset AppleEvents dev.localkin.kinclaw 2>&1 | sed 's/^/  /' || true
	@tccutil reset AppleEvents dev.localkin.kinclawmac 2>&1 | sed 's/^/  /' || true
	@printf "\n✓ TCC reset. Next \033[33mmake run\033[0m will re-prompt fresh.\n"

.PHONY: clean
clean: kill ## Drop DerivedData for KinClawMac (forces full rebuild next time)
	@echo "==> Cleaning DerivedData ..."
	@find $(DERIVED_DATA) -maxdepth 1 -name 'KinClawMac-*' -type d -print0 \
	  | xargs -0 -I{} sh -c 'echo "  → rm {}"; rm -rf "{}"'
	@rm -f .last-app-path
	@echo "✓ Cleaned"

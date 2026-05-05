# KinClawMac — stable build/sign/run loop
#
# The whole point of this Makefile: kill the old process, build the
# .app, sign it (and the kinclaw + kincode helpers in ~/.localkin/bin/)
# with stable bundle identifiers, then launch — so macOS TCC remembers
# the user's accessibility / screen-recording grants across rebuilds.
#
# Common workflow:
#   make run        # one-shot: kill + sign everything + launch
#   make sign       # build + sign without launching
#   make kill       # stop the running app + helper subprocesses
#   make doctor     # show what's signed where + what's running
#
# Stable bundle identifiers (re-applied on every signing pass):
#   dev.localkin.kinclawmac   — KinClawMac.app
#   dev.localkin.kinclaw      — kinclaw kernel binary
#   dev.localkin.kincode      — kincode coding agent binary

# ─── Paths ─────────────────────────────────────────────────────────────
SHELL              := /bin/bash
REPO_ROOT          := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
SCHEME             := KinClawMac
CONFIGURATION      := Debug
DERIVED_DATA       := $(HOME)/Library/Developer/Xcode/DerivedData
APP_BUNDLE_NAME    := $(SCHEME).app
BUILD_PRODUCTS_DIR := $(shell find $(DERIVED_DATA) -maxdepth 5 -name '$(APP_BUNDLE_NAME)' -path '*/Build/Products/$(CONFIGURATION)/*' -print 2>/dev/null | head -1 | xargs -I{} dirname {})
APP_PATH           := $(BUILD_PRODUCTS_DIR)/$(APP_BUNDLE_NAME)

# Sibling repos for the helper binaries. `make bootstrap` (and `make
# run`) auto-clones these from GitHub if they're not already next to
# kinclaw-mac on disk — so a user who only pulled kinclaw-mac can
# `make run` once and have the whole LocalKin family wired up.
KINCLAW_REPO       := $(REPO_ROOT)/../kinclaw
KINCODE_REPO       := $(REPO_ROOT)/../kincode
KINCLAW_REMOTE     := https://github.com/LocalKinAI/kinclaw.git
KINCODE_REMOTE     := https://github.com/LocalKinAI/kincode.git

# Stable install path. Both supervisors look here first (priority 2,
# after the in-bundle Resources/ which we don't currently use).
LOCALKIN_BIN       := $(HOME)/.localkin/bin

# Where the helpers' detached stdout/stderr land. Tail these when
# something looks off (`tail -f $(LOG_DIR)/kinclaw.log`).
LOG_DIR            := /tmp

# Default soul for kinclaw. supervisor would auto-pick the same one
# but starting helpers from the Makefile means we need to do it
# explicitly.
PILOT_SOUL         := $(HOME)/.localkin/souls/pilot.soul.md

# Process names we kill on `make kill` / before re-signing.
PROC_PATTERNS      := KinClawMac kinclaw kincode

.DEFAULT_GOAL := help

# ─── Targets ───────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help (default)
	@printf "\033[1mKinClawMac build targets\033[0m\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@printf "\nCommon flow: \033[33mmake run\033[0m  (kill → sign → launch)\n"

.PHONY: bootstrap
bootstrap: ## Clone missing sibling repos (kinclaw, kincode) — run once after first `git clone kinclaw-mac`
	@# Goal: "git clone kinclaw-mac && cd kinclaw-mac && make run" should
	@# yield a fully working app. This target ensures the helper kernels
	@# are checked out at $(KINCLAW_REPO) / $(KINCODE_REPO) where the
	@# rest of the Makefile expects to find them. Idempotent — already-
	@# cloned repos are left untouched (use `git -C ../kinclaw pull` if
	@# you want updates).
	@if [ ! -d "$(KINCLAW_REPO)/.git" ]; then \
	  echo "==> Cloning kinclaw → $(KINCLAW_REPO) ..."; \
	  git clone "$(KINCLAW_REMOTE)" "$(KINCLAW_REPO)"; \
	else \
	  echo "  ✓ kinclaw already at $(KINCLAW_REPO)"; \
	fi
	@if [ ! -d "$(KINCODE_REPO)/.git" ]; then \
	  echo "==> Cloning kincode → $(KINCODE_REPO) ..."; \
	  git clone "$(KINCODE_REMOTE)" "$(KINCODE_REPO)"; \
	else \
	  echo "  ✓ kincode already at $(KINCODE_REPO)"; \
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
	@cd $(REPO_ROOT) && xcodebuild \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  build 2>&1 \
	  | grep -E "error:|warning:|BUILD " | tail -20 || true
	@$(MAKE) -s _refresh-app-path
	@echo "✓ Built: $$(cat .last-app-path 2>/dev/null || echo '<not found>')"

# Recomputes APP_PATH after build (the find above runs at parse time
# and misses just-built artifacts). Stash it for the sign target.
.PHONY: _refresh-app-path
_refresh-app-path:
	@find $(DERIVED_DATA) -maxdepth 5 -name '$(APP_BUNDLE_NAME)' \
	  -path '*/Build/Products/$(CONFIGURATION)/*' -print 2>/dev/null \
	  | head -1 > .last-app-path

.PHONY: sign-helpers
sign-helpers: ## Build + sign + install kinclaw and kincode binaries (sibling repos)
	@echo "==> Signing helper binaries (kinclaw + kincode) ..."
	@if [[ -x "$(KINCLAW_REPO)/scripts/install.sh" ]]; then \
	  echo "  → kinclaw ..."; \
	  "$(KINCLAW_REPO)/scripts/install.sh" 2>&1 | sed 's/^/    /'; \
	else \
	  echo "  ⚠ skipped kinclaw (sibling repo $(KINCLAW_REPO) not found)"; \
	fi
	@if [[ -x "$(KINCODE_REPO)/scripts/install.sh" ]]; then \
	  echo "  → kincode ..."; \
	  "$(KINCODE_REPO)/scripts/install.sh" 2>&1 | sed 's/^/    /'; \
	else \
	  echo "  ⚠ skipped kincode (sibling repo $(KINCODE_REPO) not found)"; \
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
sign: kill bootstrap build sign-helpers sign-app ## Full sign loop: bootstrap siblings + kill + build + sign all
	@printf "\n✓ Signed everything. Launch with: \033[33mmake run\033[0m\n"

.PHONY: start-helpers
start-helpers: ## Start kinclaw + kincode as detached daemons (PPID=1, survive shell exit)
	@# Start helpers BEFORE KinClawMac so the supervisors find them
	@# already on :5001 / :5002 and adopt them cleanly. No spawn race.
	@#
	@# Detachment: `( cmd >log 2>&1 & )` — subshell-and-fork puts the
	@# helper directly under launchd (PPID=1), bypassing kinclaw's
	@# orphan-watch (which only fires when PPID changes from a non-1
	@# starting value). Without this, the helper would exit ~2s after
	@# `make` returns, when the make shell terminates.
	@# Pass dev-repo skills/ to the helpers via env var. kinclaw and
	@# kincode at boot read $KINCLAW_SKILL_DIRS / $KINCODE_SKILL_DIRS
	@# (colon-separated) and scan each for SKILL.md files in addition
	@# to ~/.localkin/skills/. So a fresh `git clone kinclaw-mac` →
	@# `make run` gives the user every dev-repo skill (location,
	@# weather, web, music_*, imsg_send...) without any copy step.
	@# Edits to the dev repo's SKILL.md become live on next helper
	@# restart — no install.sh required.
	@KINCLAW_DEV_SKILLS="$(KINCLAW_REPO)/skills"; \
	KINCODE_DEV_SKILLS="$(KINCODE_REPO)/skills"; \
	if pgrep -x kinclaw >/dev/null 2>&1; then \
	  echo "  → kinclaw already running on :5001 (skipping)"; \
	else \
	  echo "  → starting kinclaw on :5001 (log: $(LOG_DIR)/kinclaw.log)"; \
	  if [[ -f "$(PILOT_SOUL)" ]]; then \
	    ( KINCLAW_SKILL_DIRS="$$KINCLAW_DEV_SKILLS" \
	      "$(LOCALKIN_BIN)/kinclaw" serve -port 5001 -no-record \
	      -soul "$(PILOT_SOUL)" >$(LOG_DIR)/kinclaw.log 2>&1 & ); \
	  else \
	    ( KINCLAW_SKILL_DIRS="$$KINCLAW_DEV_SKILLS" \
	      "$(LOCALKIN_BIN)/kinclaw" serve -port 5001 -no-record \
	      >$(LOG_DIR)/kinclaw.log 2>&1 & ); \
	  fi; \
	fi; \
	if pgrep -x kincode >/dev/null 2>&1; then \
	  echo "  → kincode already running on :5002 (skipping)"; \
	else \
	  echo "  → starting kincode on :5002 (log: $(LOG_DIR)/kincode.log)"; \
	  ( KINCODE_SKILL_DIRS="$$KINCODE_DEV_SKILLS" \
	    "$(LOCALKIN_BIN)/kincode" -serve -port 5002 -yolo \
	    >$(LOG_DIR)/kincode.log 2>&1 & ); \
	fi
	@# Wait for both ports to bind before returning. Without this,
	@# the immediately-following `open KinClawMac.app` could race
	@# the helpers' bind() and the supervisors fail their initial
	@# ping → spawn duplicate helpers → port-in-use cascade.
	@printf "  → waiting for :5001 + :5002 to bind"
	@deadline=$$(($$(date +%s) + 15)); \
	while [[ $$(date +%s) -lt $$deadline ]]; do \
	  k=$$(lsof -ti :5001 -sTCP:LISTEN 2>/dev/null | head -1); \
	  c=$$(lsof -ti :5002 -sTCP:LISTEN 2>/dev/null | head -1); \
	  if [[ -n "$$k" && -n "$$c" ]]; then \
	    printf " ✓ (kinclaw=%s kincode=%s)\n" "$$k" "$$c"; \
	    exit 0; \
	  fi; \
	  printf "."; \
	  sleep 0.5; \
	done; \
	printf "\n  ⚠ helpers didn't bind within 15s — check $(LOG_DIR)/kinclaw.log + $(LOG_DIR)/kincode.log\n"

.PHONY: run
run: sign start-helpers ## kill + sign + start helpers detached + launch app
	@# Helper-first ordering: by the time KinClawMac launches, kinclaw
	@# and kincode are already serving. Each supervisor's adoption
	@# path picks them up immediately (state = .adoptedExternal). No
	@# spawn race, no orphan-watch confusion.
	@APP="$$(cat .last-app-path 2>/dev/null)"; \
	echo "==> Launching $$APP"; \
	open "$$APP"
	@sleep 1
	@$(MAKE) -s doctor

.PHONY: kill
kill: ## Stop KinClawMac + all helper subprocesses (kinclaw + kincode)
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
	fi
	@for bin in kinclaw kincode; do \
	  path="$(LOCALKIN_BIN)/$$bin"; \
	  if [[ -x "$$path" ]]; then \
	    printf "  %-15s " "$$bin"; \
	    codesign -dv "$$path" 2>&1 | awk -F= '/^Identifier=/{printf "id=%s ", $$2} /^Signature/{printf "sig=%s\n", $$2}'; \
	  else \
	    printf "  %-15s not installed\n" "$$bin"; \
	  fi; \
	done
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
	@printf "\n\033[1m─── TCC permissions ───\033[0m\n"
	@printf "  (open System Settings → Privacy & Security to verify)\n"
	@printf "  Accessibility:    grant to %s/kinclaw\n" "$(LOCALKIN_BIN)"
	@printf "  Screen Recording: grant to %s/kinclaw\n" "$(LOCALKIN_BIN)"

.PHONY: clean
clean: kill ## Drop DerivedData for KinClawMac (forces full rebuild next time)
	@echo "==> Cleaning DerivedData ..."
	@find $(DERIVED_DATA) -maxdepth 1 -name 'KinClawMac-*' -type d -print0 \
	  | xargs -0 -I{} sh -c 'echo "  → rm {}"; rm -rf "{}"'
	@rm -f .last-app-path
	@echo "✓ Cleaned"

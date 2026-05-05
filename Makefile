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

# Sibling repos for the helper binaries. Optional — `make sign` skips
# helper signing if the sibling repo isn't checked out next to this one.
KINCLAW_REPO       := $(REPO_ROOT)/../kinclaw
KINCODE_REPO       := $(REPO_ROOT)/../kincode

# Stable install path. Both supervisors look here first (priority 2,
# after the in-bundle Resources/ which we don't currently use).
LOCALKIN_BIN       := $(HOME)/.localkin/bin

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
sign: kill build sign-helpers sign-app ## Full sign loop: kill + build + sign helpers + sign app
	@printf "\n✓ Signed everything. Launch with: \033[33mmake run\033[0m\n"

.PHONY: run
run: sign ## kill + sign + launch the app
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

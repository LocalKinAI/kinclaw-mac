#!/usr/bin/env bash
# sign-app.sh — ad-hoc codesign the built KinClawMac.app with a stable
# bundle identifier, in a single `--deep` pass so embedded frameworks
# / dylibs / helpers all share signing parentage.
#
# Why a stable identifier:
#   TCC (accessibility, screen recording) keys permissions by bundle
#   identifier + path. Re-applying the same identifier on every
#   rebuild keeps macOS thinking it's the same app, so the user's
#   "Allow" survives. Without this you re-authorize every time you
#   change a Swift file — the "我每次都要授权吗" pain.
#
# Why NO hardened runtime here:
#   Hardened runtime turns on library validation, which requires
#   embedded dylibs to have the same Team ID as the host executable.
#   Ad-hoc signatures don't have a Team ID — macOS synthesizes one
#   per file from the cdhash, so two separately-signed ad-hoc files
#   look like "different teams" and the loader rejects them with
#   "mapping process and mapped file have different Team IDs".
#
#   For dev builds without an Apple Developer cert ($99/year) we
#   can't notarize anyway, so hardened runtime gains nothing and
#   only risks breaking dylib loading. We add it back when the cert
#   lands at M6.
#
# Why a single `--deep` pass:
#   --deep recursively signs every nested binary (frameworks, dylibs,
#   helpers in Contents/MacOS) under one parent invocation. That
#   keeps signing metadata consistent across the bundle. Calling
#   `codesign --sign -` on each piece separately produces a fresh
#   synthetic team ID per call, breaking any inter-binary checks.
#
# Helper binaries (kinclaw + kincode) get signed by their own
# install.sh in sibling repos — those handle stable identifiers
# (dev.localkin.kinclaw / dev.localkin.kincode) and place the result
# in ~/.localkin/bin/ where the supervisors look first.
#
# Usage:
#   scripts/sign-app.sh <path-to-KinClawMac.app>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-KinClawMac.app>" >&2
  exit 1
fi

APP="$1"
IDENTIFIER="dev.localkin.kinclawmac"

if [[ ! -d "$APP" ]]; then
  echo "✗ Not a directory: $APP" >&2
  exit 1
fi

# Single-pass deep ad-hoc resign with the stable identifier. macOS
# walks the bundle, signs every Mach-O it finds (Contents/Frameworks,
# Contents/MacOS helpers, embedded packages from SwiftPM), and seals
# the bundle with the parent identifier on top.
echo "  → codesign --deep --force --sign - --identifier $IDENTIFIER"
codesign --force --deep --sign - \
  --identifier "$IDENTIFIER" \
  "$APP"

# Verify the signature is valid + the identifier stuck. Without this
# check a corrupted Info.plist would silently produce an unverifiable
# bundle that fails to launch later (silent dyld error, no obvious
# log).
echo
echo "Verifying signature..."
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

ACTUAL_ID="$(codesign -dv "$APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')"
if [[ "$ACTUAL_ID" != "$IDENTIFIER" ]]; then
  echo "✗ Identifier mismatch: expected $IDENTIFIER, got $ACTUAL_ID" >&2
  exit 1
fi

# Also verify the .app actually launches: dyld errors (e.g. missing
# embedded dylib, library-validation failure under hardened runtime)
# don't surface in `codesign --verify`. We catch them here so the
# user sees a build-time failure instead of a silent app-doesn't-
# open-from-the-Dock failure.
echo
echo "Verifying executable loads (dyld smoke test)..."
EXECUTABLE="$APP/Contents/MacOS/$(basename "$APP" .app)"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "✗ No executable at $EXECUTABLE" >&2
  exit 1
fi
# DYLD_PRINT_LIBRARIES would dump too much; we just need to know if
# the linker can resolve everything. Spawn-and-kill, with cleanup
# of orphaned helper subprocesses (kinclaw + kincode) afterward.
#
# Why the helper cleanup matters: KinClawMac's supervisors auto-spawn
# kinclaw on :5001 and kincode on :5002 within ~1s of launch. When we
# SIGTERM the smoke-test KinClawMac, those helpers see their parent
# go away and self-exit via their own orphan-watch — but that takes
# 0-2s (orphan-watch ticks every 2s in kinclaw v1.11.0+).
#
# Without the wait, `make run`'s subsequent `open $APP` triggers a
# new KinClawMac whose supervisor pings :5001 and finds the dying
# orphan still answering — supervisor moves to .adoptedExternal,
# does NOT spawn its own kinclaw. ~1s later the orphan exits, :5001
# goes empty, but supervisor is stuck in .adoptedExternal forever.
# User clicks Cowork → "kinclaw not reachable". This is the race
# we hit immediately after every `make run`.
#
# The fix: after killing KinClawMac, explicitly wait until kinclaw
# and kincode have actually exited. Up to 5s timeout — orphan-watch
# tick is 2s, plus jitter.
( "$EXECUTABLE" >/dev/null 2>&1 & echo $! > /tmp/.kinclawmac-smoketest-pid )
SMOKE_PID="$(cat /tmp/.kinclawmac-smoketest-pid)"
sleep 1
if kill -0 "$SMOKE_PID" 2>/dev/null; then
  kill "$SMOKE_PID" 2>/dev/null || true
  wait "$SMOKE_PID" 2>/dev/null || true
  echo "  ✓ executable loaded cleanly (no dyld errors)"
else
  echo "✗ Executable died on launch — likely dyld error." >&2
  echo "  Run directly to see the error:" >&2
  echo "    $EXECUTABLE" >&2
  rm -f /tmp/.kinclawmac-smoketest-pid
  exit 1
fi
rm -f /tmp/.kinclawmac-smoketest-pid

# Wait for the orphan helpers to clean themselves up. Without this
# the next `make run` adopts a dying kinclaw and gets stuck.
echo "  → waiting for orphan helpers to exit..."
deadline=$(($(date +%s) + 5))
while [[ $(date +%s) -lt $deadline ]]; do
  if ! pgrep -x kinclaw >/dev/null 2>&1 && \
     ! pgrep -x kincode >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
# If they're still alive past the deadline (orphan-watch broken /
# disabled / kinclaw didn't notice yet), force them down. The next
# `make run` deserves a clean slate either way.
if pgrep -x kinclaw >/dev/null 2>&1 || pgrep -x kincode >/dev/null 2>&1; then
  echo "  → helpers didn't self-exit, sending SIGTERM"
  pkill -x kinclaw 2>/dev/null || true
  pkill -x kincode 2>/dev/null || true
  sleep 0.5
fi
echo "  ✓ helper cleanup complete"

echo
echo "✓ Signed: $APP"
echo "  Identifier: $ACTUAL_ID"
echo "  Hash type:  $(codesign -dv "$APP" 2>&1 | awk -F= '/^CodeDirectory/{print}' | head -1)"

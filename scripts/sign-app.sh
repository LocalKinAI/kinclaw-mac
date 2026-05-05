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
# the linker can resolve everything. Run with --help / a flag the
# app handles, or just spawn-and-kill — for a SwiftUI app we send
# SIGINT immediately to avoid actually showing the UI.
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

echo
echo "✓ Signed: $APP"
echo "  Identifier: $ACTUAL_ID"
echo "  Hash type:  $(codesign -dv "$APP" 2>&1 | awk -F= '/^CodeDirectory/{print}' | head -1)"

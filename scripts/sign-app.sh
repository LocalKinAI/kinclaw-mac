#!/usr/bin/env bash
# sign-app.sh — ad-hoc codesign the built KinClawMac.app with a stable
# bundle identifier + hardened runtime, signing every embedded
# framework/dylib/helper deeply (inside-out, as macOS requires).
#
# Why a stable identifier:
#   TCC (accessibility, screen recording) keys permissions by bundle
#   identifier + code requirement. Without a stable identifier, every
#   rebuild looks like a different app and macOS forgets the user's
#   "Allow" — leading to the "我每次都要授权吗" pain.
#
#   `dev.localkin.kinclawmac` is what project.yml sets via
#   PRODUCT_BUNDLE_IDENTIFIER. We re-apply it explicitly in case Xcode
#   stripped the signature on copy (DerivedData/Build/Products) or
#   regenerated under a different ad-hoc identity.
#
# Helper binaries (kinclaw + kincode) get signed via their own
# install.sh scripts in sibling repos — those handle their own stable
# identifiers (dev.localkin.kinclaw / dev.localkin.kincode) and place
# the result in ~/.localkin/bin/ where the supervisors look first.
#
# Usage:
#   scripts/sign-app.sh <path-to-KinClawMac.app>
#
# Exits non-zero on any signing failure; quiet on success.

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

# Sign embedded frameworks first (inside-out is mandatory). KinClawMac
# embeds KeyboardShortcuts via SwiftPM. Future SPM additions land in
# Contents/Frameworks/ automatically and pick up this loop.
FW_DIR="$APP/Contents/Frameworks"
if [[ -d "$FW_DIR" ]]; then
  while IFS= read -r -d '' fw; do
    echo "  → signing framework: $(basename "$fw")"
    codesign --force --sign - \
      --options=runtime \
      --timestamp=none \
      "$fw"
  done < <(find "$FW_DIR" -maxdepth 1 -mindepth 1 \
    \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi

# Sign any standalone helper executables under Contents/MacOS/ besides
# the main one. KinClawMac doesn't currently ship helpers in-bundle
# (kinclaw + kincode are in ~/.localkin/bin/), but if someone later
# bundles a helper this picks it up automatically.
MACOS_DIR="$APP/Contents/MacOS"
if [[ -d "$MACOS_DIR" ]]; then
  while IFS= read -r -d '' helper; do
    name="$(basename "$helper")"
    # Skip the main binary — it gets signed below as part of the .app.
    if [[ "$name" == "KinClawMac" ]]; then
      continue
    fi
    echo "  → signing helper: $name"
    codesign --force --sign - \
      --options=runtime \
      --timestamp=none \
      "$helper"
  done < <(find "$MACOS_DIR" -maxdepth 1 -type f -perm +111 -print0)
fi

# Now sign the app itself with the stable identifier. --deep is
# defensive — we already signed inside-out above, but --deep ensures
# any nested Resources/ binaries we missed get re-signed too.
echo "  → signing app: $(basename "$APP")"
codesign --force --deep --sign - \
  --identifier "$IDENTIFIER" \
  --options=runtime \
  --timestamp=none \
  "$APP"

# Verify the signature is valid + the identifier stuck. Without this
# check a corrupted Info.plist or missing entitlements would silently
# produce an unverifiable bundle.
echo
echo "Verifying signature..."
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/  /'

ACTUAL_ID="$(codesign -dv "$APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')"
if [[ "$ACTUAL_ID" != "$IDENTIFIER" ]]; then
  echo "✗ Identifier mismatch: expected $IDENTIFIER, got $ACTUAL_ID" >&2
  exit 1
fi

echo
echo "✓ Signed: $APP"
echo "  Identifier: $ACTUAL_ID"
echo "  Hash type:  $(codesign -dv "$APP" 2>&1 | awk -F= '/^CodeDirectory/{print}' | head -1)"

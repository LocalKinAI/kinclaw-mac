#!/bin/bash
# bundle-kernel.sh — put the kinclaw kernel inside a built KinClawMac.app.
#
# Usage: scripts/bundle-kernel.sh <path-to-KinClawMac.app> <kinclaw-repo>
#
# So that the app is the only thing anybody downloads: the kernel binary at
# Contents/Helpers/kinclaw, and the souls and skills it reads side by side
# under Contents/Resources/kinclaw/ — the kernel looks for ./skills from its
# working directory, and for skills/ next to the folder its soul is in, so
# that layout needs nothing from it. KinClawSupervisor runs this copy first in
# a release build; a debug build keeps preferring the developer's own repo,
# where an edited soul is live on the next restart.
#
# Only the files git tracks go in: the repo's skills/ also holds about 450 MB
# of indexes and caches. It is the working tree that goes in, uncommitted
# edits and all — VERSION says which commit, and "-dirty" when there were any.
#
# The binary is signed here, with the identifier install.sh gives the
# developer's copy; scripts/sign-app.sh signs the app around it afterwards
# (inside out — the app's seal covers this signature, so not the other way).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <path-to-KinClawMac.app> <kinclaw-repo>" >&2
  exit 1
fi
APP="$1"
REPO="$2"
IDENTIFIER="dev.localkin.kinclaw"

if [[ ! -d "$APP/Contents" ]]; then
  echo "✗ Not an app bundle: $APP" >&2
  exit 1
fi
if [[ ! -d "$REPO/cmd/kinclaw" ]]; then
  echo "  ⚠ skipped: no kinclaw repo at $REPO (the app will look for an installed kernel instead)"
  exit 0
fi

VERSION="$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null || echo unknown)"
echo "==> Bundling kinclaw $VERSION into $(basename "$APP")"

mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/kinclaw"
(cd "$REPO" && go build -o "$APP/Contents/Helpers/kinclaw" ./cmd/kinclaw/)
codesign --force --sign - --identifier "$IDENTIFIER" "$APP/Contents/Helpers/kinclaw"

# Staged first, then mirrored in, so a soul or skill deleted from the repo
# leaves the bundle too.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
(cd "$REPO" && git ls-files -z souls skills | rsync -a --from0 --files-from=- ./ "$STAGE/")
echo "$VERSION" > "$STAGE/VERSION"
rsync -a --delete "$STAGE/" "$APP/Contents/Resources/kinclaw/"

souls=$(find "$APP/Contents/Resources/kinclaw/souls" -name '*.soul.md' | wc -l | tr -d ' ')
skills=$(find "$APP/Contents/Resources/kinclaw/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
echo "  ✓ kernel $(du -h "$APP/Contents/Helpers/kinclaw" | cut -f1 | tr -d ' '), $souls souls, $skills skills, $(du -sh "$APP/Contents/Resources/kinclaw" | cut -f1 | tr -d ' ') of them"

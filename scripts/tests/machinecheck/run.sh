#!/bin/zsh
# Compile MachineCheck with the test harness and run it on the fixture page (no app, no box).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/../../.."
work="$(mktemp -d -t kinclaw-machinecheck)"
swiftc -O "$repo/KinClawMac/Services/MachineCheck.swift" "$here/main.swift" -o "$work/test" -framework AppKit -framework WebKit
"$work/test" "$here" "$repo/KinClawMac/Resources/anatomy" "$work/shots"

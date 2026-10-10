#!/bin/bash
set -euo pipefail

# Rebuild, relaunch from build/, open the popover, screenshot: the edit -> look -> edit loop without Xcode.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${REPO_DIR}/build/OpenFan.app"
OUT="${1:-/tmp/openfan-preview.png}"

"${REPO_DIR}/scripts/build-app.sh" >/dev/null
echo "PASS: bundle rebuilt"

pkill -f "OpenFan.app/Contents/MacOS/OpenFan" 2>/dev/null || true
sleep 1
open "${BUNDLE}"
sleep 3

osascript -e 'tell application "System Events" to tell process "OpenFan" to click menu bar item 1 of menu bar 2' >/dev/null
sleep 2

screencapture -x "${OUT}"
echo "PASS: screenshot at ${OUT}"

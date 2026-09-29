#!/bin/bash
# Installs (or updates) Evoo from the latest GitHub release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/chndr-prksh/evoo/main/install.sh | bash
#
# Downloading with curl (instead of a browser) means macOS doesn't quarantine the app, so it opens
# without the "Apple could not verify" prompt. Later updates happen inside Evoo (menu > Install Update).
set -euo pipefail

REPO="chndr-prksh/evoo"
BASE="https://github.com/$REPO/releases/latest/download"
APP="/Applications/Evoo.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$(uname -m)" != "arm64" ]; then
  echo "Evoo needs an Apple Silicon Mac (M1 or newer)." >&2
  exit 1
fi

echo "==> Downloading the latest Evoo..."
curl -fsSL "$BASE/Evoo.zip" -o "$WORK/Evoo.zip"
curl -fsSL "$BASE/Evoo.zip.sha256" -o "$WORK/Evoo.zip.sha256"

echo "==> Verifying..."
expected="$(tr -d '[:space:]' < "$WORK/Evoo.zip.sha256")"
actual="$(shasum -a 256 "$WORK/Evoo.zip" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
  echo "Download didn't verify (checksum mismatch). Please try again." >&2
  exit 1
fi

echo "==> Installing to ${APP}..."
pkill -x Evoo 2>/dev/null || true
ditto -x -k "$WORK/Evoo.zip" "$WORK"
rm -rf "$APP"
mv "$WORK/Evoo.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "Done: Evoo is installed and running (look for the waveform in the menu bar)."
echo "  First run: grant Microphone, Input Monitoring and Accessibility when asked, and set"
echo "  System Settings > Keyboard > 'Press globe key to' > Do Nothing."

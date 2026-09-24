#!/usr/bin/env bash
# Builds build/Evoo.app from the Swift package. Works with just the Command Line Tools (no Xcode needed).
#
#   scripts/bundle.sh                         # release build, ad-hoc signed
#   EVOO_SIGN_IDENTITY="Evoo Dev" scripts/bundle.sh   # sign with a stable identity (keeps permissions across rebuilds)
#   CONFIG=debug scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${EVOO_SIGN_IDENTITY:--}"
APP="build/Evoo.app"

swift build -c "$CONFIG" --product Evoo
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/Evoo" "$APP/Contents/MacOS/Evoo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ditto "$BIN/llama.framework" "$APP/Contents/Frameworks/llama.framework"
for bundle in "$BIN"/*.bundle; do
  [ -e "$bundle" ] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Evoo"

# Sign inside-out. Hardened runtime only with a real identity: it rejects ad-hoc-signed frameworks.
SIGN_OPTS=(--force --sign "$IDENTITY" --timestamp=none)
[ "$IDENTITY" != "-" ] && SIGN_OPTS+=(--options runtime)
codesign "${SIGN_OPTS[@]}" "$APP/Contents/Frameworks/llama.framework"
codesign "${SIGN_OPTS[@]}" "$APP"

echo "Built $APP (signed: $IDENTITY)"

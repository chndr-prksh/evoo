#!/usr/bin/env bash
# Builds build/Evoo.app from the Swift package. Works with just the Command Line Tools (no Xcode needed).
#
#   scripts/bundle.sh                         # release build, ad-hoc signed
#   EVOO_SIGN_IDENTITY="Evoo Dev" scripts/bundle.sh   # sign with a stable identity (keeps permissions across rebuilds)
#   CONFIG=debug scripts/bundle.sh
#   EVOO_BUILD=42 EVOO_REPO=owner/evoo scripts/bundle.sh   # what CI sets: build number + repo for updates
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
# Version stamping: the updater compares CFBundleVersion (the CI build number) with the latest release.
BUILD="${EVOO_BUILD:-0}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.$BUILD" "$APP/Contents/Info.plist"
if [ -n "${EVOO_REPO:-}" ]; then
  /usr/libexec/PlistBuddy -c "Add :EvooRepository string $EVOO_REPO" "$APP/Contents/Info.plist"
fi
ditto "$BIN/llama.framework" "$APP/Contents/Frameworks/llama.framework"
for bundle in "$BIN"/*.bundle; do
  [ -e "$bundle" ] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Evoo"

# Sign inside-out. Hardened runtime only with a real identity: it rejects ad-hoc-signed frameworks.
SIGN_OPTS=(--force --sign "$IDENTITY" --timestamp=none)
APP_OPTS=()
if [ "$IDENTITY" = "-" ]; then
  # Ad-hoc builds get a new code hash every time, so macOS would forget Microphone / Input Monitoring /
  # Accessibility after each rebuild. Pin the designated requirement to the bundle ID instead, so
  # permissions survive rebuilds. (Dev builds only — releases are signed with a real identity.)
  APP_OPTS+=(--requirements '=designated => identifier "app.evoo.Evoo"')
else
  SIGN_OPTS+=(--options runtime)
fi
codesign "${SIGN_OPTS[@]}" "$APP/Contents/Frameworks/llama.framework"
codesign "${SIGN_OPTS[@]}" "${APP_OPTS[@]}" "$APP"

echo "Built $APP (signed: $IDENTITY)"

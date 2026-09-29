#!/usr/bin/env bash
# Zips build/Evoo.app for a GitHub release, plus a SHA-256 the installer and in-app updater verify.
#   scripts/package.sh   → build/Evoo.zip, build/Evoo.zip.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f build/Evoo.zip build/Evoo.zip.sha256
ditto -c -k --sequesterRsrc --keepParent build/Evoo.app build/Evoo.zip
shasum -a 256 build/Evoo.zip | awk '{print $1}' > build/Evoo.zip.sha256
echo "Packaged build/Evoo.zip ($(du -h build/Evoo.zip | cut -f1)), sha256 $(cat build/Evoo.zip.sha256)"

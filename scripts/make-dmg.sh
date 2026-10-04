#!/usr/bin/env bash
# Builds build/Reader.app, then packs it into build/Reader.dmg with a link to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh
STAGE="build/dmg"
rm -rf "$STAGE" build/Reader.dmg
mkdir -p "$STAGE"
cp -R build/Reader.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Reader -srcfolder "$STAGE" -ov -format UDZO build/Reader.dmg >/dev/null
rm -rf "$STAGE"
echo "Built build/Reader.dmg"

#!/usr/bin/env bash
# Builds build/Scholia.app, then packs it into build/Scholia.dmg with a link to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/make-app.sh
STAGE="build/dmg"
rm -rf "$STAGE" build/Scholia.dmg
mkdir -p "$STAGE"
cp -R build/Scholia.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Scholia -srcfolder "$STAGE" -ov -format UDZO build/Scholia.dmg >/dev/null
rm -rf "$STAGE"
echo "Built build/Scholia.dmg"

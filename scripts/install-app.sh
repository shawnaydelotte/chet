#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Chet.app"
DEST="/Applications/Chet.app"

if [ ! -d "$APP" ]; then
  echo "==> No app bundle found; building first"
  "$ROOT/scripts/build-app.sh"
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Installed $DEST"
echo "Launch from Finder, Spotlight, or: open -a Chet"
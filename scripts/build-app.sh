#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/dist/Chet.app"
BINARY="$ROOT/.build/$CONFIG/Chet"

echo "==> Building icon"
"$ROOT/scripts/make-icon.sh"

echo "==> Building Chet ($CONFIG)"
swift build -c "$CONFIG"

if [ ! -x "$BINARY" ]; then
  echo "ERROR: executable not found at $BINARY" >&2
  exit 1
fi

echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Chet"
chmod +x "$APP/Contents/MacOS/Chet"
cp "$ROOT/AppSupport/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/AppIcon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if command -v codesign >/dev/null 2>&1; then
  codesign --sign - --force --deep "$APP" >/dev/null 2>&1 || true
fi

echo "Built $APP"
echo "Install with: cp -R \"$APP\" /Applications/"
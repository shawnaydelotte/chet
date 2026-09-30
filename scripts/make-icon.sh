#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/AppIcon/ChetIcon-1024.png"
ICONSET="$ROOT/AppIcon/Chet.iconset"
ICNS="$ROOT/AppIcon/AppIcon.icns"

if [ ! -f "$MASTER" ]; then
  echo "ERROR: missing master icon at $MASTER" >&2
  exit 1
fi

# iconutil requires PNG inputs; normalize JPEG masters in place.
if file -b --mime-type "$MASTER" | grep -q 'image/jpeg'; then
  tmp="$MASTER.tmp.png"
  sips -s format png "$MASTER" --out "$tmp" >/dev/null
  mv -f "$tmp" "$MASTER"
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

make_icon() {
  name="$1"
  size="$2"
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

make_icon icon_16x16.png 16
make_icon icon_16x16@2x.png 32
make_icon icon_32x32.png 32
make_icon icon_32x32@2x.png 64
make_icon icon_128x128.png 128
make_icon icon_128x128@2x.png 256
make_icon icon_256x256.png 256
make_icon icon_256x256@2x.png 512
make_icon icon_512x512.png 512
make_icon icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Wrote $ICNS"
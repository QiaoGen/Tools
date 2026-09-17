#!/bin/bash
# 生成 AppIcon.icns：1024 png -> iconset -> icns
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Resources/AppIcon.icns"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swift Scripts/make-icon.swift "$TMP/icon_1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$TMP/icon_1024.png" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$TMP/icon_1024.png" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$TMP/icon_1024.png" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$TMP/icon_1024.png" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$TMP/icon_1024.png" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$TMP/icon_1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$TMP/icon_1024.png" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$TMP/icon_1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$TMP/icon_1024.png" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$TMP/icon_1024.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT"
echo "已生成 $OUT"

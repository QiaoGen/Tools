#!/bin/bash
# 构建 release 二进制并组装 LiteModbus.app bundle
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

APP="build/LiteModbus.app"
BIN=".build/arm64-apple-macosx/$CONFIG/LiteModbus"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LiteModbus"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
else
    echo "提示: 未找到 Resources/AppIcon.icns，先运行 Scripts/make-icon.sh"
fi
codesign --force --sign - "$APP" 2>/dev/null || true
touch "$APP"
echo "已生成 $APP"
echo "运行: open $APP"

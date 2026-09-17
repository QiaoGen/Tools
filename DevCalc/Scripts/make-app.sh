#!/bin/bash
# 构建 release 二进制并组装 DevCalc.app bundle 到 dist/
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

DIST="dist"
APP="$DIST/DevCalc.app"
BIN=".build/arm64-apple-macosx/$CONFIG/DevCalc"

rm -rf "$APP"
mkdir -p "$DIST" "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DevCalc"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
else
    echo "提示: 未找到 Resources/AppIcon.icns，先运行 Scripts/make-icon.sh"
fi
codesign --force --sign - "$APP" 2>/dev/null || true
touch "$APP"
echo "已生成 $APP"

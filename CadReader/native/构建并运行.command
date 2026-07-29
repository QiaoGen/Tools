#!/bin/zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "正在配置原生 CadReader…"
cmake -S . -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release

echo "正在构建 CadReader.app…"
cmake --build build --parallel

APP_PATH="$SCRIPT_DIR/build/CadReader.app"
echo "构建完成：$APP_PATH"
open "$APP_PATH"

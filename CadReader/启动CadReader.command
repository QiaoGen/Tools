#!/bin/zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "未找到 Node.js，请先安装 Node.js 后再启动。"
  read -r "REPLY?按回车键关闭…"
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "首次启动，正在安装运行组件…"
  npm install
fi

echo "正在启动 CadReader…"
(sleep 1.5; open "http://127.0.0.1:5173/") &
npm run dev -- --host 127.0.0.1

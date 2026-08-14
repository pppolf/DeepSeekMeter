#!/bin/bash
# 构建并安装到 /Applications，然后启动
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/build-app.sh release

APP_DIR="build/DeepSeekMeter.app"
echo "==> 安装到 /Applications"
rm -rf "/Applications/DeepSeekMeter.app"
cp -R "$APP_DIR" "/Applications/DeepSeekMeter.app"

echo "==> 启动"
open "/Applications/DeepSeekMeter.app"
echo "✅ 已安装并启动，点击菜单栏 🐳 图标查看悬浮窗"

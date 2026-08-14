#!/bin/bash
# 生成应用图标（build/AppIcon.icns），供 build-app.sh 使用
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

swift Scripts/generate-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o build/AppIcon.icns
rm -rf "$ICONSET"
echo "✅ 应用图标已生成：build/AppIcon.icns"

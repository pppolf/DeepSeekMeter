#!/bin/bash
# 生成应用图标（build/AppIcon.icns），供 build-app.sh 使用
# 优先使用 windows/assets/whale-girl-main.png（鲸鱼娘，与 Windows 版一致），
# 素材缺失时回退 generate-icon.swift 程序化生成（深蓝鲸鱼尾）
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="windows/assets/whale-girl-main.png"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

if [ -f "$SRC" ]; then
  echo "==> 使用鲸鱼娘图标：$SRC"
  # iconset 标准尺寸（@1x/@2x）
  sips -z 16 16 "$SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  # 1024 由 512 源图放大（@2x 大图标，轻微放大可接受）
  sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
else
  echo "==> 未找到鲸鱼娘素材，回退程序化生成"
  swift Scripts/generate-icon.swift "$ICONSET"
fi

iconutil -c icns "$ICONSET" -o build/AppIcon.icns
rm -rf "$ICONSET"
echo "✅ 应用图标已生成：build/AppIcon.icns"

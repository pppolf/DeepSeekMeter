#!/bin/bash
# 构建菜单栏 App：swift build + 组装 .app + ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="DeepSeekMeter"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/$APP_NAME"
[ -f "$BIN" ] || { echo "error: 未找到构建产物 $BIN" >&2; exit 1; }

echo "==> 组装 $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Scripts/Info.plist "$APP_DIR/Contents/Info.plist"

# 应用图标（若已生成）
if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
  echo "==> 打包应用图标"
  cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
fi

# 签名：优先 Developer ID（消除 Gatekeeper 提示），否则 ad-hoc
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -n "$DEV_ID" ]; then
  echo "==> Developer ID 签名：$DEV_ID"
  codesign --force --deep --options runtime --timestamp --sign "$DEV_ID" "$APP_DIR"
  echo "    已用开发者证书签名；运行 ./Scripts/notarize.sh 完成公证后即可免 Gatekeeper 提示"
else
  echo "==> ad-hoc 签名（未检测到 Developer ID 证书；用户下载后需右键→打开）"
  codesign --force --sign - "$APP_DIR" 2>/dev/null || true
fi

echo
echo "✅ 构建完成：$APP_DIR"
echo "   运行：open $APP_DIR"
echo "   安装到 /Applications：./Scripts/install.sh"
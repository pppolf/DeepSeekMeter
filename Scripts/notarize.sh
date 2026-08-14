#!/bin/bash
# 用 Developer ID 签名 + Apple 公证 + 装订，彻底消除 Gatekeeper 提示
# 前提：已加入 Apple Developer Program（$99/年）且钥匙串里有 Developer ID Application 证书
#
# 用法：
#   APPLE_ID=you@example.com \
#   APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#   TEAM_ID=ABCDE12345 \
#   ./Scripts/notarize.sh build/DeepSeekMeter.app
#
# APP_PASSWORD 是 Apple ID 的「App 专用密码」：
#   appleid.apple.com → 登录与安全 → App 专用密码 → 生成
set -euo pipefail

APP="${1:?用法: notarize.sh <path/to.app>}"
APPLE_ID="${APPLE_ID:?需要 APPLE_ID 环境变量}"
APP_PASSWORD="${APP_PASSWORD:?需要 APP_PASSWORD(App专用密码) 环境变量}"
TEAM_ID="${TEAM_ID:?需要 TEAM_ID 环境变量}"

# 1. 找 Developer ID 证书
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$DEV_ID" ] || { echo "错误：钥匙串中没有 Developer ID Application 证书" >&2; exit 1; }

# 2. 签名（公证必需的 runtime + timestamp）
echo "==> Developer ID 签名：$DEV_ID"
codesign --force --deep --options runtime --timestamp --sign "$DEV_ID" "$APP"

# 3. 打 zip（notarytool 只接受 zip/dmg 等）
ZIP="$(dirname "$APP")/notarize-$(basename "$APP" .app).zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 4. 提交公证（--wait 会等待 Apple 审核结果，通常几分钟）
echo "==> 提交公证（等待审核，约 2~10 分钟）…"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID" --wait 2>&1 | tail -6

# 5. 装订票据到 App（之后离线也信任）
echo "==> 装订公证票据"
xcrun stapler staple "$APP"
echo "✅ 完成：$APP 已公证并装订，用户可直接双击打开"

#!/bin/bash
# 本地跑 iOS 模拟器：核心自测 + 工程校验 + 构建 + 启动模拟器 + 安装运行 + 截图
# 前置：已安装 Xcode（App Store 或开发者网站，需 Apple ID）；首次还需下载 iOS 模拟器运行时
# 用法：bash Scripts/run-ios-simulator.sh [模拟器名称，默认自动选第一个 iPhone]
set -euo pipefail
cd "$(dirname "$0")/.."

# 无 sudo 也能用新装的 Xcode：DEVELOPER_DIR 仅对本次命令链生效
if [ -d "/Applications/Xcode.app" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ 未检测到可用的 Xcode。请先安装（App Store 搜 Xcode，或 https://developer.apple.com/xcode/ 下载 .xip）"
  exit 1
fi

echo "==> 1/5 核心自测"
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest

echo "==> 2/5 工程结构校验"
python3 Scripts/check-ios-project.py

echo "==> 3/5 构建（模拟器，无签名）"
xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

APP="ios/build/Build/Products/Debug-iphonesimulator/DeepSeekMeter.app"
if [ ! -d "$APP" ]; then
  echo "❌ 构建产物缺失：$APP"; exit 1
fi

echo "==> 4/5 准备模拟器"
# 检查是否有 iOS 运行时
if ! xcrun simctl list runtimes | grep -qi "iOS"; then
  echo "❌ 未安装 iOS 模拟器运行时。请先下载（Xcode 菜单 Settings → Components，或命令行：xcodebuild -downloadPlatform iOS，约 7GB）"
  exit 1
fi
# 选设备：优先环境变量，否则取第一个可用 iPhone
if [ -n "${SIMULATOR_NAME:-}" ]; then
  DEVICE_ID=$(xcrun simctl list devices available | grep "$SIMULATOR_NAME" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
else
  DEVICE_ID=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
fi
if [ -z "$DEVICE_ID" ]; then
  echo "❌ 无可用 iPhone 模拟器。请在 Xcode 中创建一个模拟器（Window → Devices and Simulators）"
  exit 1
fi
echo "  使用设备: $DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1 || true
open -a Simulator
xcrun simctl install "$DEVICE_ID" "$APP"
xcrun simctl launch "$DEVICE_ID" com.deepseek.meter.ios

echo "==> 5/5 等待启动并截图"
sleep 8
mkdir -p build/simulator-screenshots
xcrun simctl io "$DEVICE_ID" screenshot "build/simulator-screenshots/DeepSeekMeter.png"
echo "✅ 模拟器已运行，截图：build/simulator-screenshots/DeepSeekMeter.png"

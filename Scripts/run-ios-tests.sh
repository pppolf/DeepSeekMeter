#!/bin/bash
# iOS 版验证脚本：核心包自测（必跑）+ 有 Xcode 时构建 App 冒烟
# 用法：bash Scripts/run-ios-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> iOS 核心包自测"
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest

# 注意：CLT 环境下也有 xcodebuild 存根（会报错），必须用 -version 探测真实 Xcode
if xcodebuild -version >/dev/null 2>&1; then
  echo "==> 构建 iOS App（模拟器，无签名）"
  xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath ios/build \
    CODE_SIGNING_ALLOWED=NO build
else
  echo "==> 未检测到 Xcode，跳过 App 构建（仅核心自测）"
fi

echo "✅ iOS 验证通过"

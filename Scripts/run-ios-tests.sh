#!/bin/bash
# iOS 版验证脚本：核心包自测（必跑）+ 有 Xcode 时构建 App 冒烟
# 用法：bash Scripts/run-ios-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 核心文件漂移检查（macOS 侧改动需同步到 iOS 核心包）"
bash Scripts/check-core-drift.sh

echo "==> iOS 核心包自测"
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest

echo "==> iOS 工程结构校验（静态，无需 Xcode）"
python3 Scripts/check-ios-project.py

# 探测真实 Xcode：xcode-select 指向 /Applications/Xcode.app（而非 CommandLineTools）
if xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode"; then
  echo "==> 构建 iOS App（模拟器，无签名）"
  xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath ios/build \
    CODE_SIGNING_ALLOWED=NO build
else
  echo "==> 未检测到 Xcode，跳过 App 构建（仅核心自测）"
fi

echo "✅ iOS 验证通过"

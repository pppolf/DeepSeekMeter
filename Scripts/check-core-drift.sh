#!/bin/bash
# 检查 macOS 核心文件与 ios/DeepSeekMeterCore 是否漂移。
# 原则：两份核心逻辑必须逐文件对应（防三端漂移，见 MOBILE-PLAN.md 3.3 / AGENTS.md 红线 13）。
# 若 macOS 侧改动但指纹未更新，说明 iOS 核心包可能未同步，CI 应拦截。
# 用法：bash Scripts/check-core-drift.sh
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(
  "Sources/DeepSeekMeter/PlatformService.swift"
  "Sources/DeepSeekMeter/Models.swift"
  "Sources/DeepSeekMeter/Formatting.swift"
)
FINGER="ios/DeepSeekMeterCore/CORE_FINGERPRINT"

if [ ! -f "$FINGER" ]; then
  echo "缺少指纹文件 $FINGER，请先运行：bash Scripts/fingerprint-core.sh"
  exit 1
fi

TMP=$(mktemp)
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "文件不存在: $f"; rm -f "$TMP"; exit 1
  fi
  shasum -a 256 "$f" >> "$TMP"
done

if diff -q "$TMP" "$FINGER" >/dev/null; then
  rm -f "$TMP"
  echo "核心文件与指纹一致，无漂移"
  exit 0
fi

rm -f "$TMP"
echo "macOS 核心文件有改动但 CORE_FINGERPRINT 未更新（iOS 核心包可能未同步移植！）"
echo "处理：1) 将改动同步到 ios/DeepSeekMeterCore/Sources/DeepSeekMeterCore/"
echo "      2) 运行 bash Scripts/fingerprint-core.sh 更新指纹"
echo "      3) 运行 bash Scripts/run-ios-tests.sh 确认核心自测全绿"
exit 1

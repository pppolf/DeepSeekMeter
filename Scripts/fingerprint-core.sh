#!/bin/bash
# 生成 macOS 核心文件指纹（Sources/DeepSeekMeter/ 下与 ios/DeepSeekMeterCore 逐文件对应的文件）。
# 用法：bash Scripts/fingerprint-core.sh
# 说明：macOS 核心逻辑改动后，需同步移植到 ios/DeepSeekMeterCore 并重新生成指纹（见 check-core-drift.sh）
set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(
  "Sources/DeepSeekMeter/PlatformService.swift"
  "Sources/DeepSeekMeter/Models.swift"
  "Sources/DeepSeekMeter/Formatting.swift"
)
OUT="ios/DeepSeekMeterCore/CORE_FINGERPRINT"
TMP=$(mktemp)

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "文件不存在: $f"; rm -f "$TMP"; exit 1
  fi
  shasum -a 256 "$f" >> "$TMP"
done
mv "$TMP" "$OUT"
echo "指纹已写入 $OUT"
cat "$OUT"

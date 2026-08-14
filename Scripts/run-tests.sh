#!/bin/bash
# 轻量自测（无需 Xcode / XCTest）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
swiftc Scripts/selftest/main.swift \
  Sources/DeepSeekMeter/Models.swift \
  Sources/DeepSeekMeter/Formatting.swift \
  -o build/selftest

./build/selftest
echo "✅ 自测通过：./build/selftest"

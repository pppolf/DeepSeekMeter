# DeepSeekMeter · iOS 🐳

The **iOS version** of DeepSeekMeter (in development): view your DeepSeek account balance, spending and token usage on your iPhone — feature-aligned with the [macOS](../README.md) and [Windows](../windows/README.md) versions, using the same platform API contract.

> 总体规划（里程碑、决策点、红线适配）见 [MOBILE-PLAN.md](../MOBILE-PLAN.md)。当前进度：M1 骨架 ✅ / M2 核心包 + 自测 ✅（80 项断言全绿）/ M3 App 主体代码 ✅（状态机已本地自测；App 层待真机与 CI 验证）/ M4-M5 待启动。

## ✨ Features (target)

- 💰 **Balance card** on the overview tab (orange below 10, red below 1 — same semantics as the desktop menu bar)
- 🔑 **One-click login**: embedded official sign-in page (WKWebView) with automatic token capture; manual paste fallback
- 📊 **Usage details**: monthly / today cost, request count, output tokens, cache-hit tokens, per-model breakdown
- 📈 **Token trend**: daily bar chart for the current month (output / cache-hit / total, switchable)
- ⏱️ **Refresh**: on-open + pull-to-refresh + foreground timer (15s – 10min); BGAppRefreshTask best-effort background refresh
- 🔔 (optional milestone) WidgetKit balance widget + local balance-threshold notification

## 📋 Requirements

- Xcode 16+ (the project uses the Xcode 16 synchronized-folder format)
- iOS 17.0+ deployment target
- No third-party dependencies (system frameworks only)

## 🛠 Structure

```
ios/
  DeepSeekMeterCore/               Shared core Swift Package (zero third-party deps)
    Sources/DeepSeekMeterCore/     PlatformService / Models / Formatting / TokenStoring / AppModel
    Sources/DeepSeekMeterCoreSelftest/   Lightweight self-tests (no XCTest needed)
  DeepSeekMeter/                   iOS app sources (SwiftUI)
    TokenStore.swift               Keychain-backed TokenStoring
    Views/                         Overview / Usage / Trend (Swift Charts) / Settings / Login (WKWebView)
  DeepSeekMeter.xcodeproj          Xcode project (local package dependency on DeepSeekMeterCore)
```

## 🚀 Build & Test

Core self-tests (runs on macOS, no Xcode needed):

```bash
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest
```

App (requires Xcode 16):

```bash
open ios/DeepSeekMeter.xcodeproj          # run from Xcode
# or build from CLI without signing:
xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## ⚠️ Known limitations (M3)

- The login page's `window.open` popups (some OAuth/QR flows) are not hosted in-app yet and fall back to the system browser; regular password / in-page QR login works, and the manual-paste fallback covers the rest. Fix planned for M4 (in-app popup WKWebView layer sharing the same data store).
- Background refresh relies on the foreground timer + pull-to-refresh; BGAppRefreshTask is planned for M4.

## 🔒 Privacy

Identical to the desktop versions: all data comes from DeepSeek's official platform APIs using **your own login token**; nothing is sent to any third party. On iOS the token is stored in the **Keychain** (the macOS app stores it in UserDefaults only because of ad-hoc signing; iOS apps are properly signed, so the Keychain does not prompt).

## 🖼️ Icon assets

Planned: reuse the whale-girl money theme artwork from `windows/assets` (AI-generated for this project, not official DeepSeek material) — see [ATTRIBUTION](../windows/assets/ATTRIBUTION.md).

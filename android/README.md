# DeepSeekMeter · Android 🐳

The **Android version** of DeepSeekMeter (in development): check your DeepSeek balance, spending and token usage on the go — feature-aligned with the [macOS](../README.md), [Windows](../windows/README.md) and [iOS](../ios/README.md) versions, using the same platform API contract.

> Full plan (milestones, migration spec, decision points): [MOBILE-PLAN.md](../MOBILE-PLAN.md) section 4.

## ✨ Features (target)

- Balance card (orange below 10, red below 1 — same semantics as the desktop menu bar)
- One-click login: embedded official sign-in page (WebView) with automatic token capture; manual-paste fallback
- Usage details: monthly / today cost, request count, tokens (output / cache-hit), per-model breakdown
- Token trend: daily bar chart (output / cache-hit / total, switchable)
- Foreground timed refresh + pull-to-refresh; background refresh planned
- Low-balance local notification (pure local, no third-party push)

## 🛠 Structure (mirrors the windows/ parallel-implementation pattern)

```
android/
  settings.gradle.kts / build.gradle.kts   Gradle project (wrapper committed)
  core/                                    Pure-logic core module (zero third-party business deps)
    src/main/kotlin/com/deepseek/meter/core/
      Formatting.kt                        Formatting / currency symbols / units
      Models.kt                            API models (org.json, mirrors iOS Models.swift)
      MonthUsage.kt                        Aggregation + data status (UTC+8 calendar)
      PlatformService.kt                   Platform API client (HttpURLConnection + error mapping)
      TokenStore.kt                        Token storage abstraction (Keystore impl lives in app layer)
      AppModel.kt                          State machine (synchronous core; scheduling in app layer)
    src/test/kotlin/...                    Local JVM unit tests (no device needed)
  app/                                     (milestone A3) Compose app
```

## 🚀 Build & test (local)

Prerequisites: JDK 17, Android SDK (platform 35), Gradle 8.14+.

```bash
cd android
./gradlew :core:test          # core unit tests (JVM, no device)
./gradlew :core:assembleDebug # compile the core module
```

## 🔒 Privacy

Same as the desktop/iOS versions: all data comes from DeepSeek's official APIs using **your own login token**; nothing is sent to any third party. The token will be stored encrypted (Android Keystore, AES/GCM) in SharedPreferences — mirroring Windows DPAPI / iOS Keychain semantics.

## macOS ↔ Android mapping

| macOS | Android |
| :--- | :--- |
| PlatformService.swift | PlatformService.kt (HttpURLConnection + injected interface) |
| Models.swift | Models.kt + MonthUsage.kt (org.json mapping) |
| Formatting.swift | Formatting.kt |
| AppModel.swift | AppModel.kt (synchronous core; polling in app layer) |
| SettingsStore (UserDefaults) | Keystore + SharedPreferences (planned) |
| WKWebView login | WebView + JS extraction (planned) |

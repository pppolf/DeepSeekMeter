# DeepSeekMeter · Android 🐳

The **Android version** of DeepSeekMeter: check your DeepSeek balance, spending and token usage on the go — feature-aligned with the [macOS](../README.md), [Windows](../windows/README.md) and [iOS](../ios/README.md) versions, using the same platform API contract.

> Full plan (milestones, migration spec, decision points): [MOBILE-PLAN.md](../MOBILE-PLAN.md) section 4.

## ✨ Features

- Balance card (orange below 10, red below 1 — same semantics as the desktop menu bar)
- One-click login: embedded official sign-in page (WebView) with automatic token capture; manual-paste fallback
- Usage details: monthly / today cost, request count, tokens (output / cache-hit), per-model breakdown
- Token trend: daily bar chart (output / cache-hit / total, switchable)
- Foreground timed refresh (15s/30s/1m/5m/10m) that follows the app lifecycle (paused in background)
- Background refresh via WorkManager (unique periodic work, ≥15 min, best effort, network-gated)
- Low-balance local notification (0 < balance < 1.0 of the wallet currency; deduplicated per cycle; pure local, no third-party push)
- Debug builds include a "send test notification" QA entry (removed from release)

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
  app/                                     Compose app (thin shell)
    src/main/kotlin/com/deepseek/meter/app/
      MainActivity.kt                       Entry + lifecycle bridge (start/pause/close polling)
      HomeScreen.kt / SettingsScreen.kt      Balance / usage / trend / settings (notification toggle)
      LoginScreen.kt                        WebView login + localStorage polling + popup handling
      KeystoreTokenStore.kt                 Token encrypted with Android Keystore (AES/GCM)
      background/                           BackgroundRefreshWorker + Scheduler (WorkManager)
      notification/                         LowBalanceNotifier (channel / permission / local notification)
```

## 🚀 Build & test (local)

Prerequisites: JDK 17, Android SDK (platform 35), Gradle 8.14+.

```bash
cd android
./gradlew :core:test :app:assembleDebug   # core unit tests + Compose app build
./gradlew :app:assembleRelease             # release APK (debug-signed, see build.gradle.kts)
```

PR CI runs `:core:test :app:assembleDebug` and uploads the debug APK as an artifact (direct install on device/emulator).

## 🔒 Privacy

Same as the desktop/iOS versions: all data comes from DeepSeek's official APIs using **your own login token**; nothing is sent to any third party. The token is stored encrypted (Android Keystore, AES/GCM) in SharedPreferences — ciphertext only, mirroring Windows DPAPI / iOS Keychain semantics. It never enters WorkManager input data, logs, or UI.

## macOS ↔ Android mapping

| macOS | Android |
| :--- | :--- |
| PlatformService.swift | PlatformService.kt (HttpURLConnection + injected interface) |
| Models.swift | Models.kt + MonthUsage.kt (org.json mapping) |
| Formatting.swift | Formatting.kt |
| AppModel.swift | AppModel.kt (synchronous core; polling in app layer) |
| SettingsStore (UserDefaults) | Android Keystore (AES/GCM) + SharedPreferences (ciphertext only) |
| WKWebView login | WebView + JS extraction + popup/onCreateWindow handling |
| Background refresh (iOS BGTask) | WorkManager unique periodic work (D6 decided, see MOBILE-PLAN.md) |
| NotificationService | LowBalanceNotifier (local, POST_NOTIFICATIONS handled) |

## Progress

A1 skeleton ✅ | A2 core + JVM tests ✅ | A3 Compose app ✅ | **A4 polish ✅ (lifecycle-aware foreground polling, WorkManager background refresh, low-balance notifications, Android 13+ permission UX, popup handling, PR CI app build, real-device QA matrix)** | A5 planned (widget, store distribution).

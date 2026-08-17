# DeepSeekMeter · Android 🐳

The Android version of DeepSeekMeter lets you check your DeepSeek balance, spending and token usage on the go. It is feature-aligned with the [macOS app](../README.md), [Windows app](../windows/README.md) and [iOS source build](../ios/README.md), using the same platform API contract.

The current release is **[v0.3.1](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1)**. The Release page contains a direct-install APK named DeepSeekMeter-v0.3.1-android.apk.

> **Status:** A1 skeleton ✅ / A2 core + JVM tests ✅ / A3 Compose app ✅ / **A4 polish ✅** (lifecycle-aware foreground polling, WorkManager background refresh, low-balance notifications, Android 13+ permission UX, WebView popups, PR CI app build and maintainer-recorded real-device QA matrix). A5 widget and store distribution are planned. See [MOBILE-PLAN.md](../MOBILE-PLAN.md), section 4, for the full plan and D6 WorkManager decision.

Build metadata: versionName 0.3.1, versionCode 2, minSdk 26, targetSdk/compileSdk 35. The Android version is managed independently from the iOS project version.

## Features

- Balance card with orange below 10 and red below 1, matching desktop semantics
- One-click login in the official DeepSeek WebView, automatic token capture and manual-paste fallback
- WebView popup/onCreateWindow handling inside the login flow
- Monthly and today cost, request count, output tokens, cache-hit tokens and per-model breakdown
- Daily current-month token chart for output, cache-hit or total tokens
- Foreground timed refresh at 15 seconds, 30 seconds, 1 minute, 5 minutes or 10 minutes; polling pauses when the app is backgrounded
- WorkManager unique periodic background refresh, network-gated and best-effort at the 15-minute platform minimum
- Low-balance local notification when 0 < balance < 1.0 in the wallet currency, with per-cycle deduplication and Android 13+ permission handling
- A debug-only test-notification entry for QA; release builds remove it

## Requirements and installation

- Android 8.0 / API 26 or later
- For source builds: JDK 17 and Android SDK platform 35
- The committed Gradle wrapper downloads Gradle 8.14.2; a separate Gradle installation is not needed

### Install the latest APK

1. Download DeepSeekMeter-v0.3.1-android.apk from the [v0.3.1 Release](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1).
2. Install it as a sideloaded APK. Android may ask you to allow the file manager or browser to install unknown apps.
3. The APK is signed with the Gradle debug key for reproducible direct installation. It is not a Play Store or publisher-identity build.
4. Open the app, allow notifications if you want low-balance alerts, and choose **Log in**.

### Build and install from source

Run these commands from the repository root:

~~~bash
cd android
./gradlew :core:test
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease

# Optional device/emulator install
adb install -r app/build/outputs/apk/debug/app-debug.apk
~~~

The release APK is written to app/build/outputs/apk/release/app-release.apk. The debug APK is useful for QA because it contains the test-notification entry.

## Project structure

~~~text
android/
  settings.gradle.kts / build.gradle.kts   Gradle project and version catalog setup
  gradle/wrapper/                          committed Gradle 8.14.2 wrapper
  core/                                    pure-logic module, zero AndroidX dependency
    src/main/kotlin/com/deepseek/meter/core/
      Formatting.kt                        formatting, currency symbols and units
      Models.kt                            API models and JSON mapping
      MonthUsage.kt                         aggregation and UTC+8 data status
      PlatformService.kt                    HttpURLConnection client and error mapping
      TokenStore.kt                         token-storage abstraction
      AppModel.kt                           synchronous state machine
    src/test/kotlin/...                     JVM tests, no device required
  app/                                     Compose application shell
    src/main/kotlin/com/deepseek/meter/app/
      MainActivity.kt                       lifecycle bridge
      AppController.kt                      polling and refresh orchestration
      HomeScreen.kt / SettingsScreen.kt     balance, usage, trend and settings
      LoginScreen.kt                         WebView login, JS extraction and popups
      KeystoreTokenStore.kt                 Android Keystore AES/GCM storage
      background/                            WorkManager worker and scheduler
      notification/                          local low-balance notifier
~~~

## Tests, CI and release builds

~~~bash
cd android
# Fast core test
./gradlew :core:test

# PR-equivalent core test plus Compose debug build
./gradlew :core:test :app:assembleDebug --no-daemon

# Release APK
./gradlew :app:assembleRelease --no-daemon
~~~

The pull-request and main CI job runs :core:test plus :app:assembleDebug and uploads the debug APK. Pushing a v* tag runs the release workflow, which runs :core:test plus :app:assembleRelease and attaches the versioned APK to the GitHub Release alongside the macOS DMG and Windows ZIP. CI does not run hardware tests; the real-device QA matrix is a maintainer-recorded manual verification record.

## Privacy and storage

- Requests go directly to DeepSeek private endpoints: /auth-api/v0/users/current, /api/v0/users/get_user_summary, /api/v0/usage/by_api_key/amount and /api/v0/usage/by_api_key/cost. The app has no analytics SDK, proxy or third-party upload service.
- The token is encrypted with Android Keystore using AES/GCM and stored as ciphertext in SharedPreferences. It is never stored in plain text.
- The token is not placed in WorkManager input data, logs, notification text or UI state intended for sharing. The iOS widget and Android background worker receive only the data they need for their local task.
- Low-balance notifications are generated locally; Android notification permission and channel settings are controlled by the user.
- These platform endpoints are private and may have aggregation delay; this project does not claim a public API SLA.

## Dependency boundary

- The core module is pure Kotlin business logic and keeps zero AndroidX dependency.
- The app module uses official Android/Google components: Jetpack Compose for UI and androidx.work WorkManager for best-effort background refresh. WorkManager is the explicitly approved D6 exception described in [MOBILE-PLAN.md](../MOBILE-PLAN.md) and Issue [#11](https://github.com/pppolf/DeepSeekMeter/issues/11).
- No analytics, push provider, backend or third-party business service is included.

## macOS mapping

| macOS | Android |
| :--- | :--- |
| PlatformService.swift | PlatformService.kt using HttpURLConnection and injection |
| Models.swift | Models.kt + MonthUsage.kt using org.json mapping |
| Formatting.swift | Formatting.kt |
| AppModel.swift | AppModel.kt synchronous core; polling in app layer |
| UserDefaults settings | Android Keystore AES/GCM + SharedPreferences ciphertext |
| WKWebView login | WebView + JavaScript extraction + popup handling |
| iOS BGTask-style refresh | WorkManager unique periodic work, network-gated |
| NotificationService | LowBalanceNotifier with Android 13+ permission handling |

## Known limitations and next steps

- WorkManager runs no more often than the platform's 15-minute periodic minimum and is best-effort; it is not an exact alarm.
- Foreground polling stops when the app goes into the background; the background worker only performs the minimal balance check needed for notification.
- The v0.3.1 APK is debug-signed and distributed by direct download, not through Google Play.
- A5 widget work and store distribution remain planned.

See the repository [contribution guide](../CONTRIBUTING.md) before changing shared API models, storage or platform behavior.

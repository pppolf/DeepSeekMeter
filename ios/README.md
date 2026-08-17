# DeepSeekMeter · iOS 🐳

The iOS implementation of DeepSeekMeter lets you view your DeepSeek balance, spending and token usage on an iPhone. It shares the same platform API contract as the [macOS app](../README.md), [Windows app](../windows/README.md) and [Android app](../android/README.md).

> **Status:** M1 skeleton ✅ / M2 shared core + self-tests ✅ (82 assertions) / M3 app ✅ / M4 polish ✅ / M5 notifications + WidgetKit widget ✅. The repository records simulator build/run verification with Xcode 26.6 and iOS 26.5, plus free-signed device installation/run. TestFlight and App Store distribution still require an Apple Developer Program account. See [MOBILE-PLAN.md](../MOBILE-PLAN.md) for milestones, decisions and boundary rules.

There is no public iOS binary in the Release page yet. Build the app from source with your own simulator or signing team.

## Features

- Balance card with orange below 10 and red below 1, matching desktop semantics
- One-click login in an official WKWebView, automatic token capture and manual-paste fallback
- Monthly and today cost, request count, output tokens, cache-hit tokens and per-model breakdown
- Daily current-month token chart for output, cache-hit or total tokens
- Refresh on open, pull-to-refresh and a configurable foreground timer from 15 seconds to 10 minutes
- Best-effort BGAppRefreshTask background refresh
- Low-balance local notification; no push provider or third-party notification service
- Snapshot-driven WidgetKit balance widget; the widget never receives or shares the token

## Requirements

- Xcode 16 or later; the project uses the Xcode 16 synchronized-folder format
- iOS 17.0 or later deployment target
- A simulator build needs no signing. A physical-device build needs a development team and signing configuration.
- System frameworks only; no third-party package dependency
- Formal Team builds use DeepSeekMeter.entitlements for App Group group.com.deepseek.meter. Free personal-team builds use DeepSeekMeter.Free.entitlements, which deliberately has no App Group capability.

## Install and run from source

1. Install Xcode and an iOS Simulator runtime.
2. Open ios/DeepSeekMeter.xcodeproj in Xcode.
3. Select the DeepSeekMeter scheme and an iOS 17+ simulator, then Run. For a device, choose your own signing team under Signing & Capabilities.
4. Log in on the official DeepSeek page. The app stores the token in Keychain.

The project can also be built from the repository root without signing:

~~~bash
# Core self-test, drift check, project structure check and optional app build
bash Scripts/run-ios-tests.sh

# Full simulator build without signing
xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

# Build, boot, install, launch and capture a simulator screenshot
bash Scripts/run-ios-simulator.sh
# Or select a device by name
SIMULATOR_NAME='iPhone 17' bash Scripts/run-ios-simulator.sh
~~~

Core tests can run on macOS without Xcode:

~~~bash
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest
python3 Scripts/check-ios-project.py
~~~

Scripts/run-ios-tests.sh also runs the macOS-to-iOS core drift check. If the macOS shared core changes, the corresponding files in ios/DeepSeekMeterCore must be synchronized before CI can pass.

## Project structure

~~~text
ios/
  DeepSeekMeterCore/                    shared Swift Package, zero third-party dependencies
    Sources/DeepSeekMeterCore/          PlatformService / Models / Formatting / TokenStoring / AppModel
    Sources/DeepSeekMeterCoreSelftest/  lightweight self-tests, no XCTest
  DeepSeekMeter/                        SwiftUI app
    TokenStore.swift                     Keychain-backed TokenStoring implementation
    BackgroundRefreshService.swift       BGAppRefreshTask scheduling and handler
    NotificationService.swift            local low-balance notification
    Views/                               Home, usage/trend, settings and WKWebView login
  DeepSeekMeterWidget/                  WidgetKit balance widget extension
    BalanceWidget.swift                  snapshot-only balance presentation
  DeepSeekMeter.entitlements             formal Team App Group group.com.deepseek.meter
  DeepSeekMeter.Free.entitlements        free personal-team configuration without App Group
  DeepSeekMeterWidgetInfo.plist          widget extension configuration
  Info.plist                             background modes and permitted task identifier
  DeepSeekMeter.xcodeproj                app and widget targets
~~~

## Recorded verification

- Xcode 26.6 with the iOS 26.5 SDK built both DeepSeekMeter.app and DeepSeekMeterWidget.appex, including the embedded widget extension.
- The app was installed and run in an iPhone 17 simulator. See [simulator-home-v2.png](screenshots/simulator-home-v2.png) and [simulator-first-run.png](screenshots/simulator-first-run.png).
- The current UI uses two tabs: an integrated home view for balance/usage/trend and a settings view.
- A free-signed physical-device install/run is recorded in MOBILE-PLAN.md; App Store/TestFlight distribution is intentionally not claimed.

## Known limitations

- BGAppRefreshTask is system-scheduled and best-effort. Reliable refresh paths are app open, pull-to-refresh and the foreground timer.
- The widget shows the latest balance snapshot written by the app. It is not live, does not call the network and does not contain a token.
- Widget testing on a physical device requires enabling the App Group capability for both app and extension with a formal signing team. The free personal-team configuration intentionally omits App Group, so the app can run but the widget snapshot is unavailable or empty. Unsigned CI simulator builds are unaffected.
- Notifications also require user authorization; disabling notification permission prevents local alerts.
- No TestFlight/App Store package is published yet; distribution is the remaining account/signing step.

## Privacy and storage

All data comes from DeepSeek private platform endpoints using the user's own login session; the app has no third-party analytics, proxy or upload service. On iOS, the token is stored in the Keychain. The App Group contains only non-sensitive balance/usage snapshot data for the widget; the token never enters it. Local notifications require user authorization, and BGAppRefreshTask is system-scheduled best effort rather than a guaranteed refresh.

## Icon assets

The app icon is the flattened whale-girl money-themed artwork in DeepSeekMeter/Assets.xcassets. It is AI-generated for this project and is not an official DeepSeek icon or character asset. See [ATTRIBUTION](../windows/assets/ATTRIBUTION.md).

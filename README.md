# DeepSeekMeter 🐳

[![Release](https://img.shields.io/github/v/release/pppolf/DeepSeekMeter)](https://github.com/pppolf/DeepSeekMeter/releases)
[![License](https://img.shields.io/github/license/pppolf/DeepSeekMeter)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
[中文版](README.zh-CN.md)

A lightweight **macOS menu bar app** that keeps an eye on your DeepSeek account: balance, spending and token usage at a glance. Click the menu bar icon to open a popover with real-time stats.

## ✨ Features

- 🖥️ **Menu bar balance**: shows your current balance right in the menu bar; turns orange below 10, red below 1
- 🔑 **One-click login**: embedded official sign-in page — log in once, the app captures and stores your session token automatically (no developer tools needed)
- 📊 **Usage details**: monthly / today's cost, request count, output tokens, cache-hit tokens, per-model breakdown
- 📈 **Token usage trend**: daily token usage chart for the current month (output / cache-hit / total, switchable)
- ⏱️ **Auto refresh**: 15s – 10min intervals
- 🚀 **Launch at login**

## 📋 Requirements

- macOS 14+ (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`) — only needed to build from source

## ⬇️ Install

### From Releases (recommended)

1. Download the latest `DeepSeekMeter-<version>-macOS.zip` or `.dmg` from the [Releases page](https://github.com/pppolf/DeepSeekMeter/releases)
2. Unzip and move `DeepSeekMeter.app` to `/Applications`
3. First launch: right-click the app → **Open** (the app is ad-hoc signed, so Gatekeeper asks once)

### Build from source

```bash
swift run                       # run in dev mode
./Scripts/build-app.sh          # build build/DeepSeekMeter.app
./Scripts/install.sh            # build, install to /Applications and launch
```

## 🚀 Quick Start

1. Launch the app — the 🐳 icon appears in the menu bar
2. Click the icon → click **Log in**
3. Sign in to the embedded official page ([platform.deepseek.com](https://platform.deepseek.com)) — password or QR code
4. Done. The popover now shows your balance and this month's usage

> The session token is stored locally in the app's preferences; when it expires the app shows **Log in again** — one click re-authenticates.

## 🔒 Privacy & Data

- All data comes from DeepSeek's own platform endpoints (`get_user_summary`, `usage/amount`, `usage/cost`) using **your own login token** — nothing is sent anywhere else
- The token is stored only in `~/Library/Preferences/com.deepseek.meter.plist` on your machine; use **Sign out** in the popover to remove it
- Token usage data may lag the dashboard by a few minutes

## 🛠 Development

```
Sources/DeepSeekMeter/           App sources (SwiftUI + AppKit)
  Views/                         Popover UI
  LoginWindowController.swift    Embedded login page + token capture
  PlatformService.swift          Platform API client
Scripts/                         Info.plist / build / install / icon / tests
Scripts/selftest/                Lightweight unit tests (no Xcode needed)
```

```bash
./Scripts/run-tests.sh           # run self-tests
```

## ❓ FAQ

- **Token expired?** Click **Log in again** in the popover — one click re-login.
- **Menu bar icon missing?** Check Activity Monitor for a `DeepSeekMeter` process, or re-run `./Scripts/install.sh`.
- **How to quit?** Menu bar icon → **Quit** in the popover.
- **How to uninstall?** Remove `/Applications/DeepSeekMeter.app` and `~/Library/Preferences/com.deepseek.meter.plist`.

## 📄 License

[MIT](LICENSE) © 2026 pppolf

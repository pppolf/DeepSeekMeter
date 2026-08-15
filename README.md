# DeepSeekMeter 🐳

[![Release](https://img.shields.io/github/v/release/pppolf/DeepSeekMeter)](https://github.com/pppolf/DeepSeekMeter/releases)
[![License](https://img.shields.io/github/license/pppolf/DeepSeekMeter)](LICENSE)
[![CI](https://github.com/pppolf/DeepSeekMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/pppolf/DeepSeekMeter/actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Windows](https://img.shields.io/badge/Windows-10%2B-blue)
[中文版](README.zh-CN.md)

A lightweight **macOS menu bar app** that keeps an eye on your DeepSeek account: balance, spending and token usage at a glance. Click the menu bar icon to open a popover with real-time stats. A **Windows version** (system tray) with the same features lives in [`windows/`](windows/README.md).

## ✨ Features

- 🖥️ **Menu bar balance**: shows your current balance right in the menu bar; turns orange below 10, red below 1
- 🔑 **One-click login**: embedded official sign-in page — log in once, the app captures and stores your session token automatically (no developer tools needed)
- 📊 **Usage details**: monthly / today's cost, request count, output tokens, cache-hit tokens, per-model breakdown
- 📈 **Token usage trend**: daily token usage chart for the current month (output / cache-hit / total, switchable)
- ⏱️ **Auto refresh**: 15s – 10min intervals
- 🚀 **Launch at login**

## 📸 Screenshots

| Logged in — balance, usage & token trend | Not logged in — one-click login guide |
| :---: | :---: |
| ![Logged in](images/pic-1.png) | ![Not logged in](images/pic-2.png) |

## 📋 Requirements

- **macOS**: macOS 14+ (Apple Silicon or Intel); Xcode Command Line Tools (`xcode-select --install`) — only needed to build from source
- **Windows**: Windows 10 (1809+) or 11; the Release ZIP is self-contained (no install needed; WebView2 Runtime ships with the OS); [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) only needed to build from source

## ⬇️ Install

### From Releases (recommended)

1. Download the latest `DeepSeekMeter-<version>-macOS.dmg` from the [Releases page](https://github.com/pppolf/DeepSeekMeter/releases)
2. Open the DMG, **drag `DeepSeekMeter.app` onto the `Applications` shortcut**
3. First launch: right-click the app → **Open** (the app is ad-hoc signed, so Gatekeeper asks once; alternatively `xattr -dr com.apple.quarantine /Applications/DeepSeekMeter.app`)

### Build from source

```bash
swift run                       # run in dev mode
./Scripts/build-app.sh          # build build/DeepSeekMeter.app
./Scripts/install.sh            # build, install to /Applications and launch
```

### Windows (download)

1. Download `DeepSeekMeter-win-x64.zip` from the [Releases page](https://github.com/pppolf/DeepSeekMeter/releases)
2. Extract anywhere and run `DeepSeekMeter.exe` (no .NET SDK required)

### Windows (from source)

```powershell
dotnet build windows/DeepSeekMeter.sln -c Release
dotnet run --project windows/src/DeepSeekMeter -c Release
pwsh Scripts/publish-windows.ps1   # produce windows/publish/DeepSeekMeter-win-x64.zip
```

See [`windows/README.md`](windows/README.md) for details.

> The Windows whale-girl money-themed icon is AI-generated for this project, not an official DeepSeek icon or character asset. DeepSeek names, trademarks, and official brand assets belong to their respective owners (see [`windows/assets/ATTRIBUTION.md`](windows/assets/ATTRIBUTION.md)).

## 🚀 Quick Start

1. Launch the app — the 🐳 icon appears in the menu bar
2. Click the icon → click **Log in**
3. Sign in to the embedded official page ([platform.deepseek.com](https://platform.deepseek.com)) — password or QR code
4. Done. The popover now shows your balance and this month's usage

> The session token is stored locally in the app's preferences; when it expires the app shows **Log in again** — one click re-authenticates.

## 🔒 Privacy & Data

- All data comes from DeepSeek's own platform endpoints (`get_user_summary`, `usage/by_api_key/amount`, `usage/by_api_key/cost`) using **your own login token** — nothing is sent anywhere else
- The token is stored only in `~/Library/Preferences/com.deepseek.meter.plist` on your machine; use **Sign out** in the popover to remove it
- Usage/cost statistics are **real-time** (via the `usage/by_api_key/*` endpoints); the balance is deducted in real time as well

## 🛠 Development

```
Sources/DeepSeekMeter/           App sources (SwiftUI + AppKit)
  Views/                         Popover UI
  LoginWindowController.swift    Embedded login page + token capture
  PlatformService.swift          Platform API client
Scripts/                         Info.plist / build / install / icon / tests
Scripts/selftest/                Lightweight unit tests (no Xcode needed)
windows/                         Windows version (.NET 8 + WPF, see windows/README.md)
```

```bash
./Scripts/run-tests.sh           # run macOS self-tests
dotnet run --project windows/tests/DeepSeekMeter.Selftest -c Release   # run Windows self-tests
```

## ❓ FAQ

- **Token expired?** Click **Log in again** in the popover — one click re-login.
- **Menu bar icon missing?** Check Activity Monitor for a `DeepSeekMeter` process, or re-run `./Scripts/install.sh`.
- **How to quit?** Menu bar icon → **Quit** in the popover.
- **How to uninstall?** Remove `/Applications/DeepSeekMeter.app` and `~/Library/Preferences/com.deepseek.meter.plist`.

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first — it covers build/test commands, code & commit conventions, and the project's boundaries ([中文版](CONTRIBUTING.zh-CN.md)). If you use an AI coding agent, it will follow the operating rules in [AGENTS.md](AGENTS.md).

## 📄 License

[MIT](LICENSE) © 2026 pppolf
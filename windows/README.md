# DeepSeekMeter · Windows 🐳

The Windows version of DeepSeekMeter is a lightweight **system-tray app** for viewing your DeepSeek balance, spending and token usage. It follows the same platform API contract as the [macOS app](../README.md), [iOS source build](../ios/README.md) and [Android app](../android/README.md).

The latest Windows artifact is available in the [v0.3.1 Release](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1) as DeepSeekMeter-win-x64.zip.

## Features

- **Tray balance**: the tray icon reflects the balance state (green normally, orange below 10, red below 1, and an error state in red); hovering shows the balance and last update time
- **One-click login**: embedded official DeepSeek login through WebView2 / Edge Chromium, with automatic session-token capture
- **Manual token fallback**: paste a token when WebView2 is unavailable or automatic extraction fails
- **Usage details**: monthly and today cost, request count, output tokens, cache-hit tokens and per-model breakdown
- **Token trend**: daily current-month chart for output, cache-hit or total tokens
- **Refresh interval**: 15 seconds to 10 minutes
- **Launch at login**: current-user Registry Run entry, no administrator permission required

## Requirements

- Windows 10 version 1809 or later, or Windows 11
- Release users do not need the .NET SDK: the ZIP is self-contained
- The embedded login view needs the WebView2 Runtime. It is usually available on supported Windows versions; if it is missing, install the Runtime or use the manual token fallback.
- Source builds need the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

## Install and start

### From the Release

1. Download DeepSeekMeter-win-x64.zip from the [Releases page](https://github.com/pppolf/DeepSeekMeter/releases).
2. Extract it to a directory where the current user can write WebView2 data.
3. Run DeepSeekMeter.exe. No installer or .NET SDK is required.
4. Click the tray icon, choose **Log in**, and sign in on platform.deepseek.com.

The release executable is self-contained but is not an installer and is not code-signed by a commercial publisher. Keep the ZIP and extracted directory from untrusted sources out of sensitive locations.

### From source

Run these commands from the repository root:

~~~powershell
dotnet build windows/DeepSeekMeter.sln -c Release
dotnet run --project windows/src/DeepSeekMeter -c Release

# Build the self-contained x64 ZIP used for releases
pwsh Scripts/publish-windows.ps1
~~~

The packaging script writes the ZIP to windows/publish/DeepSeekMeter-win-x64.zip. It uses a single-file self-contained publish while keeping the native WebView2 loader available as needed.

## Quick start

1. The tray icon appears after launch; gray indicates that no account is logged in.
2. Left-click the icon to open the popover, then choose **Log in**.
3. Complete password or QR-code login on the official DeepSeek page.
4. The popover loads the balance and current-month usage automatically.
5. If the session expires, choose **Log in again**. **Sign out** clears the stored token and WebView2 login data.

## Project structure

~~~text
windows/
  DeepSeekMeter.sln                solution
  src/DeepSeekMeter.Core/          pure logic library, no UI dependency
    Formatting.cs                  formatting, currency symbols and token units
    Models.cs                      API models and month aggregation
    PlatformService.cs             platform API client and error mapping
    SettingsStore.cs               DPAPI-backed settings persistence
  src/DeepSeekMeter/               WPF application
    MainViewModel.cs               state and refresh orchestration
    TrayIconController.cs          tray icon and popover host
    PopoverWindow.xaml(.cs)         main UI
    SparklineControl.cs             daily token chart
    LoginWindow.xaml(.cs)          WebView2 login and token extraction
    TokenInputDialog.xaml(.cs)     manual token fallback
    StartupService.cs              current-user launch-at-login
  tests/DeepSeekMeter.Selftest/    lightweight console self-tests
~~~

Run the Windows self-tests with:

~~~powershell
dotnet run --project windows/tests/DeepSeekMeter.Selftest -c Release
~~~

## macOS mapping

| macOS | Windows |
| :--- | :--- |
| NSStatusItem menu bar | NotifyIcon system tray |
| NSPopover + SwiftUI | Borderless WPF popover |
| WKWebView + localStorage polling | WebView2 + ExecuteScriptAsync polling |
| UserDefaults / plist | DPAPI-protected settings JSON |
| SMAppService launch at login | HKCU Registry Run entry |
| URLSession + async/await | HttpClient + async/await |
| swiftc self-test | Lightweight console self-test |

## Privacy and data

- Requests go directly to DeepSeek private endpoints: /auth-api/v0/users/current, /api/v0/users/get_user_summary, /api/v0/usage/by_api_key/amount and /api/v0/usage/by_api_key/cost. The token belongs to the signed-in user; the app has no telemetry or third-party upload service.
- The session token is encrypted with Windows DPAPI, bound to the current Windows user, and stored in %APPDATA%/DeepSeekMeter/settings.json.
- WebView2 login data is stored locally under %LOCALAPPDATA%/DeepSeekMeter/WebView2 and is removed when the app successfully signs out.
- Tokens are not written to logs, screenshots or third-party services. Do not paste real tokens into issues or source code.
- The endpoints are private and platform aggregation can have reporting delay; this app does not promise a public API SLA.

## Dependencies and licensing notes

- WPF and the Windows tray integration use .NET platform components.
- Microsoft.Web.WebView2 is the only Windows-side NuGet dependency. It is Microsoft's official WebView2 interop package; the repository's Swift/macOS core remains zero-dependency.
- The whale-girl money-themed artwork is AI-generated for this project and is not an official DeepSeek icon or character. See [assets/ATTRIBUTION.md](assets/ATTRIBUTION.md).

## FAQ

- **The token expired.** Choose **Log in again**, or use **Paste Token** if WebView2 cannot initialize.
- **The tray icon is missing.** Check Task Manager for DeepSeekMeter.exe and launch the executable again.
- **How do I quit?** Right-click the tray icon and choose **Quit**.
- **How do I uninstall?** Exit the app, remove the application directory, then remove %APPDATA%/DeepSeekMeter and %LOCALAPPDATA%/DeepSeekMeter if you also want to clear settings and WebView2 data.

See the repository [contribution guide](../CONTRIBUTING.md) before changing shared API models or platform behavior.

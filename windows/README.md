# DeepSeekMeter · Windows 版 🐳

DeepSeekMeter 的 **Windows 版本**：一个轻量的**系统托盘小工具**，实时查看 DeepSeek 账户的余额、消费和 Token 用量——与 [macOS 版](../README.zh-CN.md) 功能对齐，同一套平台接口契约。

## ✨ 功能

- 🖥️ **托盘余额**：托盘图标直接反映余额状态（正常绿、低于 10 橙、低于 1 红、异常红），悬停显示余额与最后更新时间
- 🔑 **一键登录**：内嵌官方登录页（WebView2 / Edge Chromium），登录一次即可自动获取并保存登录态，全程不用开发者工具；WebView2 不可用时支持「手动粘贴 Token」兜底
- 📊 **用量明细**：本月/今日费用、请求数、输出 Token、缓存命中，按模型拆分
- 📈 **Token 用量趋势**：本月按天的 Token 用量柱状图（输出 / 缓存命中 / 总量可切换）
- ⏱️ **定时刷新**：15 秒 ~ 10 分钟可选
- 🚀 **开机自启**（注册表 Run 键，当前用户，无需管理员权限）

## 📋 环境要求

- Windows 10（1809+）或 Windows 11
- **从 Release 下载 ZIP 的用户无需安装任何东西**（自包含版本已打包 .NET 运行时；WebView2 Runtime 随系统预装）
- 仅源码构建需要 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

## 🚀 快速开始

### 从 Release 下载（推荐）

1. 在仓库 [Releases 页面](https://github.com/pppolf/DeepSeekMeter/releases) 下载 `DeepSeekMeter-win-x64.zip`
2. 解压到任意目录，双击 `DeepSeekMeter.exe` 运行（无需安装 .NET SDK）
3. 托盘出现仪表盘图标，登录即可使用

### 从源码构建运行

```powershell
dotnet build DeepSeekMeter.sln -c Release            # 构建
dotnet run --project src/DeepSeekMeter -c Release    # 开发模式运行
```

发布自包含 ZIP：

```powershell
pwsh ../Scripts/publish-windows.ps1                    # 生成 windows/publish/DeepSeekMeter-win-x64.zip
```

运行后：

1. 托盘出现 🐳 仪表盘图标（默认灰色 = 未登录）
2. 左键点击图标 → 悬浮窗弹出 → 点「**登录**」
3. 在内嵌的官方页面（platform.deepseek.com）登录（密码或扫码）
4. 完成！悬浮窗立即显示余额和本月用量

> 登录态 Token 保存在本机 `%APPDATA%\DeepSeekMeter\settings.json`；悬浮窗「退出登录」可随时清除。过期后悬浮窗会提示「平台登录已过期」，点「重新登录」一键恢复。

## 🛠 开发

```
windows/
  DeepSeekMeter.sln                解决方案
  src/
    DeepSeekMeter.Core/            纯逻辑库（零 UI 依赖，可单独测试）
      Formatting.cs                格式化 / 币种符号 / Token 单位
      Models.cs                    网络模型（对齐 Swift Models.swift）+ 聚合
      PlatformService.cs           平台接口客户端（对齐 Swift PlatformService.swift）
      SettingsStore.cs             设置持久化（%APPDATA% JSON，对齐 UserDefaults）
    DeepSeekMeter/                 WPF 应用（对齐 Sources/DeepSeekMeter/）
      MainViewModel.cs             状态中枢（对齐 AppModel.swift）
      TrayIconController.cs        托盘图标 + 悬浮窗宿主（对齐 StatusItemController.swift）
      PopoverWindow.xaml(.cs)      悬浮窗主界面（对齐 Views/PopoverView.swift）
      SparklineControl.cs          按天柱状图（对齐 Views/SparklineView.swift）
      LoginWindow.xaml(.cs)        WebView2 登录窗 + Token 提取（对齐 LoginWindowController.swift）
      TokenInputDialog.xaml(.cs)   手动粘贴 Token 兜底
      StartupService.cs            开机自启（注册表 Run 键，对齐 SMAppService）
  tests/
    DeepSeekMeter.Selftest/        轻量自测（对齐 Scripts/selftest，不引入 xUnit）
```

```powershell
dotnet run --project tests/DeepSeekMeter.Selftest -c Release   # 运行自测
```

### 与 macOS 版对应关系

| macOS（SwiftUI + AppKit） | Windows（.NET 8 + WPF） |
| :--- | :--- |
| `NSStatusItem` 菜单栏 | 托盘图标（`NotifyIcon`，运行时绘制、颜色随状态） |
| `NSPopover` + SwiftUI | WPF 无边框悬浮窗（点击外部自动关闭） |
| `WKWebView` + localStorage 轮询 | WebView2 + `ExecuteScriptAsync` 轮询 |
| UserDefaults / plist | `%APPDATA%\DeepSeekMeter\settings.json` |
| `SMAppService` 开机自启 | 注册表 `HKCU\...\Run` |
| `URLSession` + async/await | `HttpClient` + async/await |
| swiftc 轻量自测 | 控制台轻量自测（零测试框架） |

## 🔒 隐私与数据

- 所有数据均来自 DeepSeek 官方平台接口（`get_user_summary` / `usage/amount` / `usage/cost`），使用你自己的登录态获取，**不会发送到任何第三方**
- Token 使用 **Windows DPAPI 加密**（绑定当前 Windows 用户）后保存在本机 `%APPDATA%\DeepSeekMeter\settings.json`；WebView2 登录数据在 `%LOCALAPPDATA%\DeepSeekMeter\WebView2`
- Token 用量数据与控制台可能有数分钟延迟

## 📦 依赖说明

- **WPF / WinForms（NotifyIcon）**：.NET 平台自带组件，非第三方包
- **Microsoft.Web.WebView2**：微软官方 Web 控件包（仅互操作层；WebView2 Runtime 随系统预装）。这是 Windows 侧实现「一键登录」所需的唯一 NuGet 依赖，理由已在 PR 中说明；仓库 Swift 侧保持零第三方依赖不变。

## 🖼️ 图标素材

Windows 端鲸鱼娘金钱主题图标由 **AI 为本项目生成**，并非 DeepSeek 官方图标或官方角色素材。DeepSeek 相关名称、商标及官方品牌资产归其权利人所有。详见 [`assets/ATTRIBUTION.zh-CN.md`](assets/ATTRIBUTION.zh-CN.md)。

## ❓ 常见问题

- **Token 过期了？** 悬浮窗点「重新登录」，一键重登即可；或「手动粘贴 Token」。
- **托盘没有图标？** 检查任务管理器里是否有 `DeepSeekMeter` 进程，或重新构建运行。
- **如何退出？** 托盘右键菜单 → 「退出」。
- **如何卸载？** 删除构建产物与 `%APPDATA%\DeepSeekMeter`、`%LOCALAPPDATA%\DeepSeekMeter`。

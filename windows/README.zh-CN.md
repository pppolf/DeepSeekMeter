# DeepSeekMeter · Windows 版 🐳

DeepSeekMeter 的 Windows 版本是一个轻量的**系统托盘 App**，用于查看 DeepSeek 账户余额、消费和 Token 用量。它与 [macOS 版](../README.zh-CN.md)、[iOS 源码版](../ios/README.zh-CN.md)、[Android 版](../android/README.zh-CN.md)使用同一套平台接口契约。

最新 Windows 产物位于 [v0.3.1 Release](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1)：DeepSeekMeter-win-x64.zip。

## 功能

- **托盘余额**：托盘图标反映余额状态（正常绿色、低于 10 橙色、低于 1 红色、错误状态红色）；悬停显示余额和最后更新时间
- **一键登录**：通过 WebView2 / Edge Chromium 内嵌 DeepSeek 官方登录页，自动提取登录态 Token
- **手动 Token 兜底**：WebView2 不可用或自动提取失败时可粘贴 Token
- **用量明细**：本月/今日费用、请求数、输出 Token、缓存命中 Token 和按模型拆分
- **Token 趋势**：本月按天展示输出、缓存命中或总 Token
- **刷新间隔**：15 秒至 10 分钟
- **开机自启**：当前用户 Registry Run 项，无需管理员权限

## 环境要求

- Windows 10 1809+ 或 Windows 11
- Release 用户无需 .NET SDK：ZIP 是自包含版本
- 内嵌登录页需要 WebView2 Runtime。受支持的 Windows 通常可用；如果缺失，请安装 Runtime，或使用手动 Token 兜底
- 源码构建需要 [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

## 安装与启动

### 从 Release 下载

1. 在 [Releases 页面](https://github.com/pppolf/DeepSeekMeter/releases)下载 DeepSeekMeter-win-x64.zip。
2. 解压到当前用户可写入 WebView2 数据的目录。
3. 运行 DeepSeekMeter.exe，无需安装程序或 .NET SDK。
4. 点击托盘图标，选择「登录」，在 platform.deepseek.com 官方页面完成登录。

Release 可执行文件是自包含版本，但不是安装程序，也不是商业发布者签名版本。不要把来自不可信来源的 ZIP 或解压目录放入敏感目录。

### 从源码构建

以下命令在仓库根目录执行：

~~~powershell
dotnet build windows/DeepSeekMeter.sln -c Release
dotnet run --project windows/src/DeepSeekMeter -c Release

# 构建发布用的自包含 x64 ZIP
pwsh Scripts/publish-windows.ps1
~~~

打包脚本会生成 windows/publish/DeepSeekMeter-win-x64.zip。它使用自包含单文件发布，并在需要时保留原生 WebView2 loader。

## 快速开始

1. 启动后托盘出现图标；灰色表示尚未登录。
2. 左键点击图标打开悬浮窗，选择「登录」。
3. 在 DeepSeek 官方页面使用密码或扫码完成登录。
4. 悬浮窗会自动加载余额和本月用量。
5. 如果登录态过期，选择「重新登录」；「退出登录」会清除已保存 Token 和 WebView2 登录数据。

## 项目结构

~~~text
windows/
  DeepSeekMeter.sln                解决方案
  src/DeepSeekMeter.Core/          纯逻辑库，无 UI 依赖
    Formatting.cs                  格式化、币种符号和 Token 单位
    Models.cs                      网络模型与本月聚合
    PlatformService.cs             平台接口客户端与错误映射
    SettingsStore.cs               DPAPI 设置持久化
  src/DeepSeekMeter/               WPF 应用
    MainViewModel.cs               状态与刷新编排
    TrayIconController.cs          托盘图标与悬浮窗宿主
    PopoverWindow.xaml(.cs)         主界面
    SparklineControl.cs             按天 Token 图表
    LoginWindow.xaml(.cs)          WebView2 登录与 Token 提取
    TokenInputDialog.xaml(.cs)     手动 Token 兜底
    StartupService.cs              当前用户开机自启
  tests/DeepSeekMeter.Selftest/    轻量控制台自测
~~~

运行 Windows 自测：

~~~powershell
dotnet run --project windows/tests/DeepSeekMeter.Selftest -c Release
~~~

## 与 macOS 版对应关系

| macOS | Windows |
| :--- | :--- |
| NSStatusItem 菜单栏 | NotifyIcon 系统托盘 |
| NSPopover + SwiftUI | 无边框 WPF 悬浮窗 |
| WKWebView + localStorage 轮询 | WebView2 + ExecuteScriptAsync 轮询 |
| UserDefaults / plist | DPAPI 保护的 settings.json |
| SMAppService 开机自启 | HKCU Registry Run 项 |
| URLSession + async/await | HttpClient + async/await |
| swiftc 轻量自测 | 轻量控制台自测 |

## 隐私与数据

- 请求直接发往 DeepSeek 私有接口：/auth-api/v0/users/current、/api/v0/users/get_user_summary、/api/v0/usage/by_api_key/amount、/api/v0/usage/by_api_key/cost。Token 属于登录用户，App 没有遥测或第三方上报服务。
- 登录态 Token 使用 Windows DPAPI 加密，绑定当前 Windows 用户，保存在 %APPDATA%/DeepSeekMeter/settings.json。
- WebView2 登录数据保存在本机 %LOCALAPPDATA%/DeepSeekMeter/WebView2；成功退出登录时会清理相关数据。
- Token 不会写入日志、截图或第三方服务。不要把真实 Token 粘贴到 Issue 或源码中。
- 这些接口是私有接口，平台聚合可能存在统计延迟；本项目不承诺公开 API 的 SLA。

## 依赖与素材说明

- WPF 与 Windows 托盘集成使用 .NET 平台组件。
- Microsoft.Web.WebView2 是 Windows 侧唯一 NuGet 依赖，为微软官方 WebView2 互操作包；仓库 Swift/macOS 核心仍保持零依赖。
- Windows 端鲸鱼娘金钱主题素材由 AI 为本项目生成，并非 DeepSeek 官方图标或角色。详见 [assets/ATTRIBUTION.zh-CN.md](assets/ATTRIBUTION.zh-CN.md)。

## 常见问题

- **Token 过期了。** 点「重新登录」；如果 WebView2 初始化失败，可使用「手动粘贴 Token」。
- **托盘图标不见了。** 在任务管理器检查 DeepSeekMeter.exe 是否运行，再重新启动程序。
- **如何退出？** 右键托盘图标，选择「退出」。
- **如何卸载？** 退出 App 后删除程序目录；如需同时清理设置和 WebView2 数据，再删除 %APPDATA%/DeepSeekMeter 与 %LOCALAPPDATA%/DeepSeekMeter。

修改共享接口模型或平台行为前，请先阅读仓库的[贡献指南](../CONTRIBUTING.zh-CN.md)。

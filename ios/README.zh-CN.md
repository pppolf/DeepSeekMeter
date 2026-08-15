# DeepSeekMeter · iOS 版 🐳

DeepSeekMeter 的 **iOS 版**（开发中）：在 iPhone 上实时查看 DeepSeek 账户余额、消费与 Token 用量——与 [macOS 版](../README.zh-CN.md) 和 [Windows 版](../windows/README.md) 功能对齐，使用同一套平台接口契约。

> 总体规划（里程碑、决策点、红线适配）见 [MOBILE-PLAN.md](../MOBILE-PLAN.md)。当前进度：M1 骨架 ✅ / M2 核心包 + 自测 ✅（82 项断言全绿）/ M3 App 主体 ✅ / M4 打磨 ✅ / M5 ✅（通知 + WidgetKit 小组件）。**本地模拟器验证通过**（Xcode 26.6 + iOS 26.5：构建 + 运行 + 截图，见 [screenshots/simulator-first-run.png](screenshots/simulator-first-run.png)）；真机与 TestFlight 待开发者账号。

## ✨ 目标功能

- 💰 **余额卡片**（概览 Tab；低于 10 变橙、低于 1 变红，与桌面菜单栏配色语义一致）
- 🔑 **一键登录**：内嵌官方登录页（WKWebView）+ 自动提取 Token；手动粘贴兜底
- 📊 **用量明细**：本月/今日费用、请求数、输出 Token、缓存命中，按模型拆分
- 📈 **Token 趋势**：本月按天柱状图（输出 / 缓存命中 / 总量可切换）
- ⏱️ **刷新**：进入即刷 + 下拉刷新 + 前台定时器（15s~10min）；BGAppRefreshTask 尽力而为的后台预刷新
- 🔔（可选里程碑）WidgetKit 余额小组件 + 余额低阈值本地通知

## 📋 环境要求

- Xcode 16+（工程使用 Xcode 16 同步文件夹格式）
- 部署目标 iOS 17.0+
- 零第三方依赖（仅系统框架）

## 🛠 结构

```
ios/
  DeepSeekMeterCore/              共享核心 Swift Package（零第三方依赖）
    Sources/DeepSeekMeterCore/    PlatformService / Models / Formatting / TokenStoring / AppModel
    Sources/DeepSeekMeterCoreSelftest/  轻量自测（无需 XCTest）
  DeepSeekMeter/                  iOS App 源码（SwiftUI）
    TokenStore.swift              Keychain 实现 TokenStoring
    BackgroundRefreshService.swift BGAppRefreshTask 调度与处理
    NotificationService.swift       余额低阈值本地通知（纯本地，无推送）
  DeepSeekMeterWidget/             WidgetKit 余额小组件扩展（快照驱动，不共享 Token）
  DeepSeekMeter.entitlements       App Group（group.com.deepseek.meter），小组件读快照用
  DeepSeekMeterWidgetInfo.plist    小组件扩展 Info.plist（NSExtensionPointIdentifier=com.apple.widgetkit-extension）
    Views/                        HomeView（余额/用量/趋势集成）+ TokenDailyChart + 设置 + 登录（WKWebView + 弹窗内嵌）
    Assets.xcassets               AppIcon（1024，鲸鱼娘深蓝底扁平化）
  DeepSeekMeter.xcodeproj         Xcode 工程（本地包依赖 DeepSeekMeterCore）
  Info.plist                      App Info.plist（UIBackgroundModes fetch + BGTaskSchedulerPermittedIdentifiers）
```

## 🚀 构建与测试

核心自测（macOS 上直接跑，无需 Xcode）：

```bash
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest
```

App（需要 Xcode 16）：

```bash
open ios/DeepSeekMeter.xcodeproj          # Xcode 中运行
# 或命令行无签名构建：
xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## ✅ 本地验证（2026-08-15）

- Xcode 26.6（iOS 26.5 SDK）构建通过：**DeepSeekMeter.app 与 DeepSeekMeterWidget.appex 均编译成功**（App + 小组件扩展 + 内嵌 PlugIns）。
- App 已安装并在 **iPhone 17 模拟器**运行；主页（余额/用量/趋势集成）截图：[simulator-home-v2.png](screenshots/simulator-home-v2.png)；首次运行旧版：[simulator-first-run.png](screenshots/simulator-first-run.png)。
- 布局改为 **两个 Tab**（主页集成 + 设置），视觉对齐 macOS 悬浮窗（状态胶囊、渐变余额卡、万/亿格式化、按模型拆分、按天趋势图带今日/峰值标注）。
- 首次真实构建发现并修复了 2 处盲写问题（Xcode 26 后台任务 API 签名变化；带标签元组兜底）。

## ⚠️ M5 已知限制

- 后台刷新使用 BGAppRefreshTask（系统调度、尽力而为、**不保证触发**）；可靠路径是前台刷新（进入即刷 + 下拉刷新 + 前台定时器）。
- 小组件展示**最近一次刷新到的余额快照**（App 刷新后更新，非实时）；Token 不进 App Group 共享容器。
- 真机测试小组件前需在 Xcode「Signing & Capabilities」为 App 与扩展启用 App Group（需要 Team）；CI 无签名构建不受影响。
- TestFlight / App Store 分发需要 Apple Developer Program 账号（MOBILE-PLAN.md 决策点 D1）。

## 🔒 隐私

与桌面版一致：所有数据来自 DeepSeek 官方平台接口，使用**你自己的登录态**，不向任何第三方上报。iOS 上 Token 存 **Keychain**（macOS 版存 UserDefaults 仅因 ad-hoc 签名；iOS App 有正式签名，钥匙串不会弹窗）。

## 🖼️ 图标素材

计划沿用 windows/assets 的鲸鱼娘金钱主题素材（AI 为本项目生成，并非 DeepSeek 官方素材），见 [ATTRIBUTION](../windows/assets/ATTRIBUTION.zh-CN.md)。

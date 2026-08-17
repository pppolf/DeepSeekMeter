# DeepSeekMeter · iOS 版 🐳

DeepSeekMeter 的 iOS 实现用于在 iPhone 上查看 DeepSeek 余额、消费和 Token 用量。它与 [macOS 版](../README.zh-CN.md)、[Windows 版](../windows/README.zh-CN.md)、[Android 版](../android/README.zh-CN.md)使用同一套平台接口契约。

> **当前状态：** M1 骨架 ✅ / M2 共享核心 + 自测 ✅（82 项断言）/ M3 App ✅ / M4 打磨 ✅ / M5 通知 + WidgetKit 小组件 ✅。仓库记录了 Xcode 26.6、iOS 26.5 模拟器构建运行验证，以及免费签名真机安装运行验证。TestFlight 和 App Store 分发仍需要 Apple Developer Program 账号。里程碑、决策和边界规则见 [MOBILE-PLAN.md](../MOBILE-PLAN.md)。

Release 页面目前没有公开 iOS 二进制包，需要使用自己的模拟器或签名 Team 从源码构建。

## 功能

- 余额卡片：低于 10 变橙、低于 1 变红，与桌面端语义一致
- 官方 WKWebView 一键登录、自动提取 Token 和手动粘贴兜底
- 本月/今日费用、请求数、输出 Token、缓存命中 Token 和按模型拆分
- 本月按天 Token 图表，可切换输出、缓存命中或总量
- 进入即刷新、下拉刷新、15 秒至 10 分钟可配置的前台定时刷新
- BGAppRefreshTask 后台预刷新（系统调度、尽力而为）
- 余额低阈值本地通知；无推送服务或第三方通知服务
- 快照驱动的 WidgetKit 余额小组件；小组件不会接收或共享 Token

## 环境要求

- Xcode 16+；工程使用 Xcode 16 同步文件夹格式
- 部署目标 iOS 17.0+
- 模拟器构建不需要签名；真机构建需要自己的开发 Team 和签名配置
- 仅使用系统框架，无第三方包依赖
- 正式 Team 构建使用 DeepSeekMeter.entitlements，启用 App Group group.com.deepseek.meter；免费个人 Team 使用 DeepSeekMeter.Free.entitlements，明确不启用 App Group。

## 从源码安装与运行

1. 安装 Xcode 和 iOS 模拟器运行时。
2. 用 Xcode 打开 ios/DeepSeekMeter.xcodeproj。
3. 选择 DeepSeekMeter scheme 和 iOS 17+ 模拟器后运行；真机运行需在 Signing & Capabilities 中选择自己的 Team。
4. 在官方 DeepSeek 页面登录，App 会将 Token 保存到 Keychain。

也可以在仓库根目录用命令行无签名构建：

~~~bash
# 核心自测、漂移检查、工程结构校验，以及可用时的 App 构建
bash Scripts/run-ios-tests.sh

# 模拟器无签名构建
xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build

# 构建、启动、安装、运行模拟器并截图
bash Scripts/run-ios-simulator.sh
# 也可以按名称选择设备
SIMULATOR_NAME='iPhone 17' bash Scripts/run-ios-simulator.sh
~~~

核心包可以在 macOS 上无需 Xcode 直接自测：

~~~bash
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest
python3 Scripts/check-ios-project.py
~~~

Scripts/run-ios-tests.sh 还会执行 macOS 到 iOS 核心文件漂移检查。macOS 共享核心发生改动时，必须同步 ios/DeepSeekMeterCore 中的对应文件，否则 CI 无法通过。

## 工程结构

~~~text
ios/
  DeepSeekMeterCore/                    共享 Swift Package，零第三方依赖
    Sources/DeepSeekMeterCore/          PlatformService / Models / Formatting / TokenStoring / AppModel
    Sources/DeepSeekMeterCoreSelftest/  轻量自测，无 XCTest
  DeepSeekMeter/                        SwiftUI App
    TokenStore.swift                     基于 Keychain 的 TokenStoring 实现
    BackgroundRefreshService.swift       BGAppRefreshTask 调度与处理
    NotificationService.swift            余额低阈值本地通知
    Views/                               主页、用量/趋势、设置和 WKWebView 登录
  DeepSeekMeterWidget/                  WidgetKit 余额小组件扩展
    BalanceWidget.swift                  只展示快照的余额界面
  DeepSeekMeter.entitlements             正式 Team 的 App Group：group.com.deepseek.meter
  DeepSeekMeter.Free.entitlements        免费个人 Team 配置，不启用 App Group
  DeepSeekMeterWidgetInfo.plist          小组件扩展配置
  Info.plist                             后台模式与允许的任务标识
  DeepSeekMeter.xcodeproj                App 与小组件 targets
~~~

## 已记录的验证

- 使用 Xcode 26.6 和 iOS 26.5 SDK 构建成功：DeepSeekMeter.app、DeepSeekMeterWidget.appex 以及内嵌小组件扩展均成功编译。
- App 已在 iPhone 17 模拟器安装运行，见 [simulator-home-v2.png](screenshots/simulator-home-v2.png) 和 [simulator-first-run.png](screenshots/simulator-first-run.png)。
- 当前 UI 使用两个 Tab：集成余额/用量/趋势的主页，以及设置页。
- MOBILE-PLAN.md 记录了免费签名真机安装运行；这里不宣称已经具备 App Store/TestFlight 分发能力。

## 已知限制

- BGAppRefreshTask 由系统调度，属于尽力而为。可靠刷新路径是打开 App、下拉刷新和前台定时器。
- 小组件展示 App 最近写入的余额快照，不是实时数据，不联网，也不包含 Token。
- 真机测试小组件需要使用正式签名 Team 为 App 与扩展启用 App Group；免费个人 Team 配置明确不启用 App Group，因此 App 主体可以运行，但小组件快照不可用或为空；CI 无签名模拟器构建不受影响。
- 本地通知需要用户授权，关闭通知权限后不会发送提醒。
- 当前没有 TestFlight/App Store 包；剩余工作主要是账号、签名和分发配置。

## 隐私与存储

所有数据来自 DeepSeek 私有平台接口，使用用户自己的登录态；App 没有第三方分析、代理或上报服务。iOS 上 Token 存储在 Keychain。App Group 只保存供小组件读取的非敏感余额/用量快照，Token 不会进入其中。本地通知需要用户授权，BGAppRefreshTask 由系统调度、属于尽力而为，不保证每次触发。

## 图标素材

App 图标是 DeepSeekMeter/Assets.xcassets 中的鲸鱼娘金钱主题扁平化素材，由 AI 为本项目生成，并非 DeepSeek 官方图标或角色素材。详见 [ATTRIBUTION](../windows/assets/ATTRIBUTION.zh-CN.md)。

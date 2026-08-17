# DeepSeekMeter · Android 版 🐳

DeepSeekMeter 的 Android 版用于随时查看 DeepSeek 账户余额、消费和 Token 用量。它与 [macOS 版](../README.zh-CN.md)、[Windows 版](../windows/README.zh-CN.md)、[iOS 源码版](../ios/README.zh-CN.md)功能对齐，使用同一套平台接口契约。

当前版本为 **[v0.3.1](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1)**。Release 页面提供可直装 APK：DeepSeekMeter-v0.3.1-android.apk。

> **当前状态：** A1 骨架 ✅ / A2 核心 + JVM 单测 ✅ / A3 Compose App ✅ / **A4 打磨 ✅**（生命周期前台轮询、WorkManager 后台刷新、余额低阈值通知、Android 13+ 权限 UX、WebView popup、PR CI App 构建、维护者记录的真机 QA 矩阵）。A5 小组件和商店分发规划中。完整规划与 D6 WorkManager 决策见 [MOBILE-PLAN.md](../MOBILE-PLAN.md) 第 4 节。

构建元数据：versionName 0.3.1、versionCode 2、minSdk 26、targetSdk/compileSdk 35。Android 版本号与 iOS 工程版本独立维护。

## 功能

- 余额卡片：低于 10 变橙、低于 1 变红，与桌面端语义一致
- 官方 DeepSeek WebView 一键登录、自动提取 Token 和手动粘贴兜底
- 登录流程在 App 内承接 WebView popup/onCreateWindow
- 本月/今日费用、请求数、输出 Token、缓存命中 Token 和按模型拆分
- 本月按天 Token 图表，可切换输出、缓存命中或总量
- 前台定时刷新：15 秒、30 秒、1 分钟、5 分钟、10 分钟；App 进入后台后暂停轮询
- WorkManager 唯一周期后台刷新，有网络约束，使用平台 15 分钟下限，属于尽力而为
- 余额低阈值本地通知：当前钱包币种中 0 < 余额 < 1.0，按周期去重，含 Android 13+ 通知权限处理
- debug 构建含 QA「发送测试通知」入口，release 构建自动剔除

## 环境要求与安装

- Android 8.0 / API 26+
- 源码构建需要 JDK 17 和 Android SDK platform 35
- 仓库提交了 Gradle wrapper，会自动下载 Gradle 8.14.2，不需要单独安装 Gradle

### 安装最新 APK

1. 在 [v0.3.1 Release](https://github.com/pppolf/DeepSeekMeter/releases/tag/v0.3.1) 下载 DeepSeekMeter-v0.3.1-android.apk。
2. 以侧载 APK 方式安装；Android 可能要求允许文件管理器或浏览器安装未知来源应用。
3. APK 使用 Gradle debug key 签名，便于可重复直装；它不是 Google Play 或发布者身份认证版本。
4. 打开 App；需要余额提醒时允许通知权限，然后选择「登录」。

### 从源码构建并安装

以下命令在仓库根目录执行：

~~~bash
cd android
./gradlew :core:test
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease

# 可选：安装到真机/模拟器
adb install -r app/build/outputs/apk/debug/app-debug.apk
~~~

Release APK 输出到 app/build/outputs/apk/release/app-release.apk。debug APK 适合 QA，因为包含测试通知入口。

## 工程结构

~~~text
android/
  settings.gradle.kts / build.gradle.kts   Gradle 工程与版本配置
  gradle/wrapper/                          提交入库的 Gradle 8.14.2 wrapper
  core/                                    纯逻辑模块，零 AndroidX 依赖
    src/main/kotlin/com/deepseek/meter/core/
      Formatting.kt                        格式化、币种符号和单位
      Models.kt                            网络模型与 JSON 映射
      MonthUsage.kt                         聚合与 UTC+8 数据状态
      PlatformService.kt                    HttpURLConnection 客户端与错误映射
      TokenStore.kt                         Token 存储抽象
      AppModel.kt                           同步状态机
    src/test/kotlin/...                     JVM 单测，无需设备
  app/                                     Compose App 薄壳
    src/main/kotlin/com/deepseek/meter/app/
      MainActivity.kt                       生命周期桥接
      AppController.kt                      轮询与刷新编排
      HomeScreen.kt / SettingsScreen.kt     余额、用量、趋势与设置
      LoginScreen.kt                         WebView 登录、JS 提取与 popup
      KeystoreTokenStore.kt                 Android Keystore AES/GCM 存储
      background/                            WorkManager Worker 与 Scheduler
      notification/                          余额低阈值本地通知
~~~

## 测试、CI 与 Release 构建

~~~bash
cd android
# 快速核心单测
./gradlew :core:test

# 等价 PR 的核心单测 + Compose debug 构建
./gradlew :core:test :app:assembleDebug --no-daemon

# Release APK
./gradlew :app:assembleRelease --no-daemon
~~~

Pull Request 和 main 的 CI 会执行 :core:test 与 :app:assembleDebug，并上传 debug APK。推送 v* 标签会运行发布流水线，执行 :core:test 与 :app:assembleRelease，将带版本号的 APK 与 macOS DMG、Windows ZIP 一起附加到 GitHub Release。CI 不执行硬件测试；真机 QA 矩阵属于维护者记录的人工验证。

## 隐私与存储

- 请求直接发往 DeepSeek 私有接口：/auth-api/v0/users/current、/api/v0/users/get_user_summary、/api/v0/usage/by_api_key/amount、/api/v0/usage/by_api_key/cost。App 没有分析 SDK、代理或第三方上报服务。
- Token 使用 Android Keystore 的 AES/GCM 加密后，以密文存入 SharedPreferences，不保存明文。
- Token 不会进入 WorkManager 输入数据、日志、通知文本或用于共享的 UI 状态；iOS 小组件与 Android 后台 Worker 只接收各自任务所需的数据。
- 余额低阈值通知完全在本地生成；通知权限和通知渠道由用户控制。
- 这些平台接口是私有接口，可能存在聚合延迟；本项目不承诺公开 API SLA。

## 依赖边界

- core 模块是纯 Kotlin 业务逻辑，保持零 AndroidX 依赖。
- app 模块使用 Android/Google 官方组件：Jetpack Compose 负责 UI，androidx.work WorkManager 负责尽力而为的后台刷新。WorkManager 是 [MOBILE-PLAN.md](../MOBILE-PLAN.md) 和 Issue [#11](https://github.com/pppolf/DeepSeekMeter/issues/11) 中明确批准的 D6 例外。
- 不包含分析服务、推送服务、后端或第三方业务服务。

## 与 macOS 版对应关系

| macOS | Android |
| :--- | :--- |
| PlatformService.swift | PlatformService.kt（HttpURLConnection + 接口注入） |
| Models.swift | Models.kt + MonthUsage.kt（org.json 映射） |
| Formatting.swift | Formatting.kt |
| AppModel.swift | AppModel.kt（同步核心，轮询在 App 层） |
| UserDefaults 设置 | Android Keystore AES/GCM + SharedPreferences 密文 |
| WKWebView 登录 | WebView + JavaScript 提取 + popup 承接 |
| iOS BGTask 类刷新 | WorkManager 唯一周期任务（有网络约束） |
| NotificationService | LowBalanceNotifier（含 Android 13+ 权限处理） |

## 已知限制与后续计划

- WorkManager 周期任务不短于平台 15 分钟下限，且属于尽力而为，不是精确定时闹钟。
- App 进入后台后前台轮询停止；后台 Worker 只做通知所需的最小余额检查。
- v0.3.1 APK 使用 debug 签名，通过直链下载，不通过 Google Play 分发。
- A5 小组件和商店分发仍在规划中。

修改共享接口模型、存储或平台行为前，请先阅读仓库的[贡献指南](../CONTRIBUTING.zh-CN.md)。

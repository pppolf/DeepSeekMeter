# DeepSeekMeter · Android 版 🐳

DeepSeekMeter 的 **Android 版**（开发中）：在手机上实时查看 DeepSeek 账户余额、消费与 Token 用量——与 [macOS 版](../README.zh-CN.md)、[Windows 版](../windows/README.md)、[iOS 版](../ios/README.zh-CN.md) 功能对齐，同一套平台接口契约。

> 总体规划（里程碑、迁移规格、决策点）见 [MOBILE-PLAN.md](../MOBILE-PLAN.md) 第 4 节。

## ✨ 目标功能

- 余额卡片（低于 10 橙、低于 1 红，与桌面菜单栏语义一致）
- 一键登录：内嵌官方登录页（WebView）+ 自动提取 Token；手动粘贴兜底
- 用量明细：本月/今日费用、请求数、Token（输出/缓存命中），按模型拆分
- Token 趋势：本月按天柱状图（输出/缓存命中/总量可切换）
- 前台定时刷新 + 下拉刷新；后台刷新（AlarmManager/WorkManager，规划中）
- 余额低阈值本地通知（纯本地，无第三方推送）

## 🛠 结构（对齐 windows/ 平行实现模式）

```
android/
  settings.gradle.kts / build.gradle.kts   Gradle 工程（wrapper 提交入库）
  core/                                    纯逻辑核心模块（零第三方业务依赖）
    src/main/kotlin/com/deepseek/meter/core/
      Formatting.kt                        格式化 / 币种符号 / 万/亿单位
      Models.kt                            网络模型（org.json 手写映射，对齐 iOS Models.swift）
      MonthUsage.kt                        聚合 + 数据可信度状态（UTC+8 口径）
      PlatformService.kt                   平台接口客户端（HttpURLConnection + 错误归一化）
      TokenStore.kt                        Token 存取抽象（Keystore 实现放 App 层）
      AppModel.kt                          状态中枢（同步执行，调度交给 App 层）
    src/test/kotlin/...                    本地 JVM 单测（org.json 可用，无需设备）
  app/                                     （A3 里程碑）Compose App
```

## 🚀 构建与测试（本地）

前置：JDK 17、Android SDK（platform 35）、Gradle 8.14+。

```bash
cd android
./gradlew :core:test          # 核心单测（JVM，无需设备/模拟器）
./gradlew :core:assembleDebug # 编译核心模块
```

## 🔒 隐私

与桌面/iOS 版一致：数据只来自 DeepSeek 官方接口、使用你自己的登录态，不向任何第三方上报。Token 计划用 **Android Keystore（AES/GCM）加密后存 SharedPreferences**（对齐 Windows DPAPI / iOS Keychain 语义）。

## 与 macOS 版对应关系

| macOS | Android |
| :--- | :--- |
| PlatformService.swift | PlatformService.kt（HttpURLConnection + 接口注入） |
| Models.swift | Models.kt + MonthUsage.kt（org.json 手写映射） |
| Formatting.swift | Formatting.kt |
| AppModel.swift | AppModel.kt（同步核心；轮询在 App 层） |
| SettingsStore（UserDefaults） | Keystore + SharedPreferences（规划） |
| WKWebView 登录 | WebView + JS 提取（规划） |

## App 层（A3，Compose）

```
app/
  src/main/AndroidManifest.xml          INTERNET 权限 + MainActivity
  src/main/res/                         主题（平台 Material，零 appcompat）+ 鲸鱼娘图标（各密度 mipmap）
  src/main/kotlin/com/deepseek/meter/app/
    MainActivity.kt                     入口 + AppController 装配
    DeepSeekMeterApp.kt                 两 Tab（主页 + 设置）+ 登录全屏页
    HomeScreen.kt                       余额渐变卡 / 本月用量 / Canvas 趋势图（对齐 iOS HomeView）
    SettingsScreen.kt                   账号 / 刷新间隔 / 隐私
    LoginScreen.kt                      WebView 登录 + localStorage 轮询提取 Token + 手动粘贴兜底
    KeystoreTokenStore.kt               Keystore AES/GCM 加密 Token（对齐 iOS Keychain 语义）
    AppController.kt                    状态桥接 + 前台定时刷新（核心保持同步纯逻辑）
```

构建：

```bash
cd android
./gradlew :app:assembleDebug      # 产出 app/build/outputs/apk/debug/app-debug.apk
./gradlew :core:test              # 核心单测
```

进度：A1 骨架 ✅ / A2 核心 ✅ / **A3 Compose App 层 ✅（本地构建 APK 通过，待真机验收）** / A4 打磨（后台刷新、通知、深色模式）待启动。

# DeepSeekMeter 移动端规划（iOS 先行，Android 后续）

> 本文档是 iOS / Android 移动端的**规划与实施方案**，供维护者评审后按里程碑执行。
> 目标：与 macOS / Windows 版功能对齐，延续「平行实现 + 零第三方业务依赖 + 隐私承诺」的项目基因。

**进度**：M1 骨架 ✅（2026-08，ios/ 目录、核心包、Xcode 工程空壳、CI ios-build、.gitignore、AGENTS.md 红线适配）｜ M2 核心包 + 自测 ✅（80 项断言全绿，退出码 0）｜ M3 App 主体代码 ✅（AppModel 状态机 + Keychain + WKWebView 登录 + 四 Tab，状态机已本地自测；App 层待真机/CI 验证）｜ M4 打磨代码 ✅（BGAppRefreshTask 后台刷新、App 图标、OAuth 弹窗 App 内承接、刷新间隔持久化；TestFlight 待决策点 D1）｜ M5 ✅（余额低阈值本地通知 + WidgetKit 余额小组件，快照驱动、不共享 Token）｜ A1-A5 待启动（规划见第 4 节）。

---

## 1. 背景与目标

- 现状：macOS 菜单栏版（SwiftUI + AppKit，Swift 6 工具链 / Swift 5 语言模式）+ Windows 托盘版（.NET 8 + WPF，功能对齐）。
- 目标：新增 **iOS 手机 App**（先行），并规划 **Android 版**（后续），让用户随时在手机上查看 DeepSeek 账户余额、消费与 Token 用量。
- 原则：
  1. 功能与桌面版对齐：余额、本月/今日费用、请求数、Token（输出/缓存命中/缓存未命中）、按模型拆分、按天趋势图。
  2. 同一套平台接口契约：platform.deepseek.com 私有接口（4 个，均已用真实响应验证）。
  3. 数据只来自 DeepSeek 官方接口，使用用户自己的登录态；**不向任何第三方上报**。
  4. 业务逻辑零第三方依赖（沿用红线第 1 条；系统框架与平台官方工具不视为第三方，与 Windows 版 WebView2 例外同理）。
  5. 不臆造接口：新端先抓真实响应验证，再定模型与自测样例。

---

## 2. 总体策略：延续 windows/ 的「平行实现」模式

仓库已有一个成熟的平行实现先例（windows/：C# 重写核心 + WPF）。移动端沿用同一思路，但 iOS 与现有代码**同语言（Swift）**，共享成本更低：

```
仓库根
|-- Sources/DeepSeekMeter/        macOS 版（保持不动，红线「零依赖单 target」不破坏）
|-- windows/                      Windows 版（已存在，不动）
|-- ios/                          本次新增：iOS 版
|   |-- DeepSeekMeterCore/        共享核心 Swift Package（纯逻辑 + 网络，零第三方依赖）
|   |-- DeepSeekMeter.xcodeproj   iOS App 工程
|   +-- README.md                 iOS 版说明（双语惯例：README.md EN + README.zh-CN.md ZH）
+-- android/                      未来新增：Android 版（Kotlin + Compose，零第三方依赖）
```

**关键决策（默认推荐）**：核心逻辑放 ios/DeepSeekMeterCore 独立 Swift Package，iOS App 通过本地包依赖引用；**macOS 包保持单 target 不动**。是否让 macOS 后续也引用同一核心包，作为独立的可选重构任务（见第 6 节决策点 D4），不阻塞 iOS 上线。

> 为什么不让 macOS 直接引用共享核心？macOS 单 target 是刻意设计（AGENTS.md 红线），重构会动 macOS 构建链与 CI，回归风险与本次目标无关。iOS 核心包先与现有 Swift 逻辑保持**逐文件对应**，用自测锁住一致性。

---

## 3. iOS 端方案（先行）

### 3.1 技术选型

| 维度 | 选型 | 理由 |
| :--- | :--- | :--- |
| 语言 / UI | SwiftUI（Swift 5 语言模式，与仓库一致） | 系统原生，零第三方 |
| 部署目标 | **iOS 17.0+**（决策点 D2） | Swift Charts、现代 SwiftUI API 可用，覆盖 2024 年后设备 |
| 网络 | URLSession（Foundation） | 与 macOS PlatformService 完全同构 |
| 登录 | WKWebView 内嵌官方登录页 + localStorage 轮询提取 Token | 复用 macOS LoginWindowController 的成熟机制 |
| Token 存储 | **Keychain**（Security 框架） | 见 3.4，与 macOS 的 UserDefaults 选择**刻意不同** |
| 图表 | Swift Charts（系统内置） | 柱状图/趋势图零依赖 |
| 后台刷新 | BGAppRefreshTask + 前台定时器 + 下拉刷新 | iOS 无「开机自启/常驻轮询」概念，明示预期 |
| 小组件（可选阶段） | WidgetKit | 锁屏/桌面显示余额，对齐「菜单栏余额」心智 |
| 本地通知（可选） | UserNotifications | 余额低于阈值提醒（纯本地，无第三方推送） |

### 3.2 目录结构（ios/）

```
ios/
|-- DeepSeekMeterCore/                     # 共享核心 Swift Package（零第三方依赖）
|   |-- Package.swift                      # swift-tools-version 6.0，Swift 5 语言模式（对齐仓库）
|   |-- Sources/DeepSeekMeterCore/
|   |   |-- PlatformService.swift          # 平台接口客户端 + PlatformError（对齐 Sources/.../PlatformService.swift）
|   |   |-- Models.swift                   # 网络模型 + MonthUsage 聚合 + DataStatus（对齐 Models.swift）
|   |   |-- Formatting.swift               # format() / currencySymbol()（对齐 Formatting.swift）
|   |   |-- TokenStoring.swift             # TokenStore 协议（注入式，Keychain 实现放 App target）
|   |   +-- AppModel.swift                 # 状态中枢（对齐 macOS AppModel.swift；注入 TokenStoring+URLSession，可在 macOS 上自测）
|   +-- Sources/DeepSeekMeterCoreSelftest/ # 轻量自测（可执行 target，不依赖 XCTest；CLT 环境可直接 swift run）
|-- DeepSeekMeter/                         # iOS App target（SwiftUI）
|   |-- DeepSeekMeterApp.swift             # @main
|   |-- AppModel.swift                     # 状态中枢（对齐 macOS AppModel.swift：轮询/拉取/错误态）
|   |-- TokenStore.swift                   # Keychain 实现 TokenStoring
|   |-- LoginView.swift                    # WKWebView 登录页 + 「手动粘贴 Token」兜底（对齐 Windows 版）
|   |-- Views/
|   |   |-- OverviewView.swift             # 余额卡片 + 今日概览
|   |   |-- UsageView.swift                # 本月/今日费用、请求数、Token，按模型拆分
|   |   |-- TrendView.swift                # 按天柱状图（Swift Charts，输出/缓存命中/总量可切换）
|   |   +-- SettingsView.swift             # 刷新间隔、账号信息、退出登录
|   |-- Assets.xcassets                    # AppIcon（1024 无障碍图标）+ 配色
|   +-- Info.plist / entitlements          # Keychain Access Group 等
|-- DeepSeekMeter.xcodeproj                # Xcode 工程（提交入库；红线第 6 条限定 macOS 包，见 3.7）
+-- README.md                              # 双语说明（对齐 windows/README.md 的结构：功能/快速开始/与 macOS 对应表/隐私）
```

### 3.3 核心逻辑迁移清单（逐文件对应，防漂移）

| macOS（Sources/DeepSeekMeter/） | iOS（ios/DeepSeekMeterCore/） | 说明 |
| :--- | :--- | :--- |
| PlatformService.swift | PlatformService.swift | **照搬**：URLSession、User-Agent/Referer/Origin/Authorization 头、15s 超时、错误归一化为 PlatformError（中文 message）。仅将 URLSession.shared 换成可注入的 URLSession（便于测试） |
| Models.swift | Models.swift | **照搬**：Envelope/BizWrapper 解包、APIKeyAmount/Cost 模型、MonthUsage.aggregated()（UTC+8 平台时区口径）、DataStatus 判定 |
| Formatting.swift | Formatting.swift | **照搬**：format() / currencySymbol() |
| AppModel.swift | AppModel.swift | **移植 + 注入化**：UI 逻辑收进核心包；注入 TokenStoring 与 PlatformService（URLSession 可注入），状态机可在 macOS 上跑自测（selftest 第 12 节） |
| （新增） | TokenStoring.swift | protocol TokenStore { load/save/clear }，核心不依赖 Keychain；iOS 用 Keychain、自测用内存实现 |

> 与 windows/ 的做法区别：Windows 是**另一种语言必须重写**；iOS 与 macOS 同语言，核心直接复制 + 微调，用自测保证两份核心行为一致。后续若做 D4（macOS 引用同一核心包），漂移风险自然消除。

### 3.4 登录与 Token 存储（移动端关键差异）

**登录流程**（复用 macOS 成熟机制，完全照搬逻辑）：
1. WKWebView 加载 https://platform.deepseek.com/，WKWebsiteDataStore.nonPersistent()（不留浏览器态）。
2. 每 1.5s 轮询执行 JS：仅当域名是 *.deepseek.com 才读 localStorage（白名单限制，避免在第三方页面读取登录数据）。
3. 候选提取：userToken 优先 -> 键名含 token 的长值 -> 40~512 字符长值兜底；fetchCurrentUser 逐一校验，命中即回传。
4. OAuth 弹窗（扫码/社交登录）**必须留在 WebView 内**继续（历史教训：跳系统浏览器后 App 永远收不到 Token）。
5. 兜底：手动粘贴 Token + 校验（对齐 Windows 版 TokenInputDialog）。

**M4 已处理**：登录页 window.open 弹窗在 App 内承接（LoginWebView 容器内叠加共享 nonPersistent dataStore 的 popup WKWebView 覆盖层 + 关闭按钮），不再落到系统浏览器。
**M5 设计说明**：小组件采用「余额快照」而非「共享 Token」——Token 不进 App Group 容器，小组件只读最近一次刷新到的余额；刷新时机依赖 App 前台刷新 + 写入后 WidgetCenter.reloadTimelines（与后台 BGTask 刷新互补）。

**Token 存储 —— Keychain（与 macOS 刻意不同）**：
- macOS 存 UserDefaults 是因为 ad-hoc 签名下钥匙串每次启动弹密码授权（红线第 2 条的背景）。
- iOS 侧 App 均有正式签名（App Store / TestFlight / 个人团队），**Keychain 不会弹窗**；且 iOS 没有「钥匙串弹窗」问题，明文放 UserDefaults 反而违背安全直觉。
- 实现：kSecClassGenericPassword + kSecAttrAccessibleAfterFirstUnlock（后台刷新也能读）；小组件如需读余额，用 Keychain Access Group（同 TeamID 共享，kSecAttrAccessGroup），**不放 App Group UserDefaults 明文**。
- 退出登录：设置页清除 Keychain 项。

### 3.5 UI 界面规划（Tab 式，手机单窗）

| Tab | 内容 | 对齐桌面功能 |
| :--- | :--- | :--- |
| 概览 | 余额卡片（低于 10 橙、低于 1 红，同桌面配色语义）、今日费用/请求数/Token、最后更新时间、下拉刷新 | 菜单栏余额 + 悬浮窗摘要 |
| 用量 | 本月费用合计、按模型拆分（请求数/输出/缓存命中/缓存未命中）、今日 vs 本月 | 用量明细 |
| 趋势 | 本月按天 Token 柱状图（输出/缓存命中/总量切换）+ 按天费用 | SparklineView |
| 设置 | 登录/重新登录、刷新间隔（15s~10min）、账号邮箱、退出登录、隐私说明 | SettingsStore |

- 数据状态沿用 DataStatus：未登录 / 加载中 / 最新 / 过期(stale) / 错误 / 登录已过期(tokenExpired) 六态，错误文案复用 PlatformError 中文 message。
- 本地化：中文为主，英文跟随（对齐仓库双语惯例）。

### 3.6 刷新与后台（iOS 能力边界，文档需明示）

- 前台：进入 App 立即刷新 + 下拉刷新 + 前台定时器（15s~10min，沿用桌面设置）。
- 后台：BGAppRefreshTask（系统调度、不保证触发，仅作「下次打开前的预刷新」）；不做常驻轮询（iOS 不允许）。
- 可选增值：余额低于阈值触发**本地通知**（纯本地计算，无推送服务，不违反隐私承诺）。

### 3.7 测试、CI 与分发

**测试策略**（对齐「轻量自测」精神；已落地为可执行自测 target）：
- 核心包：**可执行自测 target**（DeepSeekMeterCoreSelftest，`swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest`）——不使用 XCTest（CLT 环境无 XCTest，且仓库红线 6 的精神是零测试框架），用例**直接移植** Scripts/selftest/main.swift 的现有断言（聚合、格式化、币种、DataStatus、错误归一化）+ 原有样例 JSON（真实响应）+ URLProtocol Mock 用例（请求头与错误归一化，验证 URLSession 可注入）。跑在 macOS 上，**不需要模拟器**，CI 成本低。
- App 层：SwiftUI 视图薄，状态逻辑全部收在 AppModel（可注入 TokenStore / URLSession），关键路径用核心包自测覆盖；不引入 UI 测试框架。

**CI（.github/workflows/ci.yml 增加 ios-build job）**：

```yaml
ios-build:
  name: Build & Test (iOS)
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - name: Core tests
      run: swift test --package-path ios/DeepSeekMeterCore
    - name: Build app (simulator, no signing)
      run: xcodebuild -project ios/DeepSeekMeter.xcodeproj -scheme DeepSeekMeter \
            -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
            CODE_SIGNING_ALLOWED=NO build
```

- PR 全绿才可合入；发布沿用 v* 标签流程（后续可加 iOS archive 步骤）。

**分发（决策点 D3）**：
- 阶段 1：Xcode 本地签名（免费个人团队即可真机调试）；内测用 **TestFlight**（需 Apple Developer Program，$99/年）。
- 阶段 2（可选）：fastlane 自动化 TestFlight/上架（fastlane 是**开发工具**，不是 App 运行时依赖；证书存 CI secrets）。
- 上架风险：App 使用 DeepSeek **私有接口**读取用户本人数据，App Store 审核需在「App 审核信息」与隐私政策中如实说明（只读本人账号、Token 存本机 Keychain、无第三方上报）；备选路径为 TestFlight / 企业分发 / 侧载。**不因上架风险阻塞开发**，先出可侧载/TestFlight 的版本。

### 3.8 AGENTS.md 红线适配（随 iOS 落地同步更新）

| 红线 | 适配说明 |
| :--- | :--- |
| 1. 零第三方依赖 | 明确「移动端业务逻辑零第三方依赖；系统框架（URLSession/SwiftUI/WebKit/Security/WidgetKit）与平台官方工具不视为第三方」，与 Windows 版 WebView2 例外同列 |
| 2. Token 存储 | 限定为「macOS 场景 UserDefaults」；**iOS 用 Keychain、Android 用 Keystore 加密**（签名模型不同，理由见 3.4），需在红线条目中注明适用范围 |
| 6. 不引入 Xcode 工程 | 限定「macOS 包」；iOS 必须提交 .xcodeproj（无法避免），核心逻辑测试仍走 swift test，不依赖 Xcode UI 测试 |
| 4. 不臆造接口 | 沿用：仅 4 个已验证接口；新端任何字段改动前必须抓真实响应，并同步更新核心包自测样例 JSON |
| 5. 数据流向 | iOS 无第三方统计 SDK；通知为纯本地 |

---

## 4. Android 端方案（未来，规划先行）

### 4.1 技术选型（零第三方依赖策略）

| 维度 | 选型 | 理由 |
| :--- | :--- | :--- |
| 语言 / UI | Kotlin + Jetpack Compose | Android 官方现代 UI，对齐 SwiftUI 的开发体验 |
| 网络 | HttpURLConnection（平台内置） | 零依赖；封装为 PlatformService（URL/参数/请求头/错误码与 Swift/C# 契约一致） |
| JSON | org.json（Android 内置） | 零依赖 |
| Token 存储 | Android Keystore（AES/GCM）加密后密文存 SharedPreferences | 对齐「系统级安全存储」思路（macOS UserDefaults 例外 / Win DPAPI / iOS Keychain），零第三方 |
| 登录 | WebView + JS 提取 localStorage userToken（同 macOS/iOS 机制）+ 手动粘贴兜底 | 三端一致 |
| 刷新 | 前台刷新 + AlarmManager（零依赖）或 WorkManager（androidx 官方，视决策 D6） | iOS 用 BGTask 的对应物 |
| 图表 | Compose Canvas 自绘柱状图 | 官方 Charts 库无稳定版，自绘零依赖 |
| 小组件（可选） | AppWidgetProvider 原生（零依赖） | 桌面余额小组件 |

### 4.2 目录结构（android/，对齐 windows/ 模式）

```
android/
|-- settings.gradle.kts / build.gradle.kts    # Gradle（wrapper 提交入库）
|-- core/                                      # 纯逻辑模块（JVM，零 Android 依赖，可单测）
|   +-- src/main/kotlin/...                    # PlatformService / Models / Formatting / MonthUsage 聚合 / DataStatus
|-- app/                                       # Android App（Compose UI，薄壳）
|   +-- src/main/kotlin/...                    # AppModel / LoginScreen / Overview / Usage / Trend / Settings
+-- README.md                                  # 双语说明 + 与 macOS 版对应表
```

### 4.3 功能对齐与里程碑

与 iOS 功能**逐项对齐**（3.5 的四个界面 + 六态数据状态 + 错误文案）；里程碑序列同 iOS（A1 骨架与 CI -> A2 核心与单测 -> A3 登录与主界面 -> A4 打磨与 APK -> A5 可选小组件/上架）。详见 4.4 的迁移规格。

### 4.4 Android 核心迁移规格（Swift -> Kotlin 逐文件映射，A2 实施时直接照此执行）

核心原则：**零第三方依赖**。JSON 用 Android 内置 org.json（设备与 JVM 单测均可用——android.jar 的 mockable 版本含 org.json 真实实现）；网络用 java.net.HttpURLConnection（JDK 自带）；测试沿用仓库「零测试框架」精神（main 函数断言 + 非零退出码），样例 JSON 直接复用 ios selftest 的字符串。

| Swift（ios/DeepSeekMeterCore/） | Kotlin（android/core/src/main/kotlin/） | 说明 |
| :--- | :--- | :--- |
| Formatting.swift | Formatting.kt | format() / currencySymbol() 纯函数直译（Kotlin top-level fun）；移植自测第 1、5 节 |
| PlatformService.swift（含 PlatformError） | PlatformService.kt（含 PlatformException） | HttpURLConnection 封装；错误归一化为 PlatformException（中文 message，40002/40003 视为过期）；请求头一致（UA 用 Android 移动端、Authorization Bearer、Referer/Origin）；4 个接口签名与 URL 参数完全一致；网络层抽象为 interface（JVM 测试注入 stub，对应 iOS 的 URLSession 可注入） |
| Models.swift | Models.kt | data class：PlatformEnvelope/BizWrapper 解包、APIKeyAmount/Cost 模型、UserSummary、MonthUsage 聚合（UTC+8 口径，MonthUsage.aggregated 逻辑逐行对应）、DataStatus + dataStatus()；JSON 用 org.json 手写映射（不用 kotlinx.serialization——第三方） |
| TokenStoring.swift | TokenStore.kt（interface） | 核心只依赖接口；Android 实现 KeystoreTokenStore：Keystore AES/GCM 加密密文存 SharedPreferences（对应 KeychainTokenStore / DPAPI TokenProtector 语义；解密失败按「需要重新登录」） |
| AppModel.swift | AppModel.kt（ViewModel + StateFlow） | 注入 TokenStore + PlatformService 接口；前台轮询用协程（定时刷新 15s~10min）；savePlatformToken 校验流程、performRefresh、clearPlatformToken 逐方法对应；状态机自测第 12 节移植 |
| 自测（Selftest 第 1~12 节） | core 自测（main 断言） | 每个 Swift 断言一一对应到 Kotlin（80 项）；样例 JSON 字符串直接复用；网络 stub 用接口注入 |

里程碑 A2 验收：Kotlin 核心编译通过 + 80 项断言移植全绿；A3 用 Compose 实现四 Tab 与 WebView 登录（JS 提取逻辑从 LoginView.swift 直译）。

### 4.5 测试与 CI

- 核心：JVM 单元测试（JUnit，Google 随 SDK 分发，视同平台工具；若坚持零测试框架可用纯 main 断言，决策点 D5）。
- CI：android-build job（ubuntu + JDK 17 + Gradle）：./gradlew :core:test :app:assembleDebug + 上传 APK artifact。
- 分发：APK 直装（侧载）/ Play Store（$25 一次性开发者账号；同样需说明私有接口使用方式）/ 国内应用商店可选。

---

## 5. 里程碑（不承诺日期，按工作量排序）

| 阶段 | 内容 | 验收 |
| :--- | :--- | :--- |
| **M1 骨架** ✅ | 创建 ios/ 目录、核心包 Package.swift、Xcode 工程空壳、CI ios-build job（空壳构建通过）、.gitignore 补 iOS 产物 | CI 绿；本地核心自测可跑 |
| **M2 核心** ✅ | 移植 PlatformService/Models/Formatting/MonthUsage/DataStatus + 自测全绿（移植 selftest 用例与样例 JSON，另加 URLProtocol Mock 请求头/错误归一化用例与 AppModel 状态机用例） | 核心自测 80 项断言全绿（退出码 0），覆盖与 macOS selftest 对齐 |
| **M3 App 主体** ✅（代码） | 登录（WKWebView + 手动兜底 + Keychain）、概览/用量/趋势/设置四 Tab、AppModel 状态机（收进核心包，注入 TokenStoring+URLSession，本地可测） | 状态机 80 项断言自测全绿；App 层待 CI（macos-15 xcodebuild）与真机验证 |
| **M4 打磨与分发** ✅（代码） | 后台刷新（BGAppRefreshTask + 前台 + 下拉）、错误六态、图标（鲸鱼娘扁平化 1024）、OAuth 弹窗 App 内承接、刷新间隔持久化、隐私说明；TestFlight 内测（需开发者账号，决策点 D1） | 代码就绪；TestFlight 待 D1，App 层待 CI/真机验证 |
| **M4 打磨与分发** | 刷新（前台+BGTask+下拉）、错误六态、本地化、图标、隐私说明；TestFlight 内测（需开发者账号，决策点 D1） | TestFlight 可分发 |
| **M5 可选增值** ✅ | 余额阈值本地通知（NotificationService，设置页开关 + 刷新后检测，纯本地无推送）；WidgetKit 余额小组件（DeepSeekMeterWidget 扩展 target，**快照驱动**：App 刷新后写入 App Group UserDefaults，小组件只读展示、不联网、不共享 Token；App Group 标识 group.com.deepseek.meter） | 代码与工程结构就绪；待 CI/真机验证 |
| **A1–A5** | Android 版同序列（核心 -> App -> 打磨 -> APK/上架 -> 可选小组件）；核心迁移规格见 4.5，iOS 自测用例与样例 JSON 直接复用 | 与 iOS 功能对齐 |

**推荐顺序**：iOS 先行（与现有代码同语言，核心共享成本最低）；Android 在 iOS M3 稳定后启动，可复用 iOS 的测试用例清单与文档。

---

## 6. 决策点（需要维护者拍板，均有默认推荐）

| 编号 | 决策 | 默认推荐 |
| :--- | :--- | :--- |
| D1 | Apple Developer Program 账号（$99/年） | 需要；用于 TestFlight 与后续上架；没有则先 Xcode 真机直装开发 |
| D2 | iOS 最低版本 | iOS 17.0（平衡设备覆盖与 Swift Charts/新 API）；若需覆盖 iOS 16 设备可降级（图表需自绘） |
| D3 | iOS 分发渠道 | 先 TestFlight（决策点 D1 通过后）；App Store 审核风险如实说明（见 3.7） |
| D4 | macOS 是否复用共享核心包 | **暂不**（独立可选重构，避免动 macOS 构建链）；先靠自测锁一致性 |
| D5 | Android 测试框架 | 用 JUnit（平台工具视角）或纯 main 断言，二选一，倾向 JUnit |
| D6 | Android 后台刷新 | 倾向 AlarmManager（零依赖）；如需系统级节电调度再上 WorkManager（androidx 官方） |
| D7 | Android 分发 | 先 APK 直装；Play Store / 国内商店视需求 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
| :--- | :--- | :--- |
| App Store 审核（私有接口） | 上架被拒 | 如实填写审核信息与隐私政策；备选 TestFlight/企业分发/侧载；功能与审核解耦，先出可内测版 |
| iOS 后台刷新不可靠 | 打开 App 时数据过期 | 前台必刷 + 下拉刷新 + BGTask 预刷新 + 界面标注最后更新时间（stale 态） |
| 核心逻辑三端漂移 | 行为不一致 | iOS 与 macOS 同语言直接复用 + 单测；Android 用同一套测试用例清单；红线 4 要求改动前抓真实响应 |
| Keychain/Keystore 迁移与失败 | 登录态丢失 | TokenStore 抽象 + 失败按「需要重新登录」处理（对齐 Windows TokenProtector 语义） |
| macOS 包被误改 | 回归 | M1~M4 全程不触碰 Sources/ 与 Package.swift；CI 保持 macOS job 全绿 |
| 移动端 CI 时长 | 拖慢 PR | 核心测试跑 macOS（快），App 仅编译冒烟，不跑模拟器 UI 测试 |

---

## 8. 下一步（M1 的具体动作清单）

1. 创建 ios/DeepSeekMeterCore（Package.swift：swift-tools-version 6.0 + Swift 5 语言模式，platforms iOS 17 / macOS 13）。
2. 从 Sources/DeepSeekMeter/ 移植 PlatformService.swift / Models.swift / Formatting.swift，新增 TokenStoring.swift 协议；URLSession 改为可注入。
3. 移植 Scripts/selftest/main.swift 用例与样例 JSON 到 Tests/DeepSeekMeterCoreTests/，swift test 全绿。
4. 创建 ios/DeepSeekMeter.xcodeproj 空壳（SwiftUI App + 本地包依赖 + Keychain entitlement）。
5. ci.yml 增加 ios-build job（见 3.7）；.gitignore 增加 iOS 产物（xcuserdata/、DerivedData/）。
6. 更新 AGENTS.md 红线适配表（见 3.8）与 README 双语文档。
7. 提交（Conventional Commits，中文描述，小步提交），PR 触发 CI 全绿后合入。

> 移动端 UI 图标沿用现有鲸鱼娘金钱主题素材（windows/assets 有 PNG，需为 iOS 生成 AppIcon 各尺寸与 Android 各密度 mipmap）；ATTRIBUTION 双语标注沿用 windows 版做法。

# AGENTS.md — DeepSeekMeter 仓库操作规范

> This file is the operating manual for AI coding agents (Claude Code, Cursor, Codex, etc.).
> 开始在本仓库修改代码之前，请先完整阅读本文件，并严格遵守其中的规范与边界。

## 1. 项目是什么

DeepSeekMeter 是一个 **macOS 菜单栏小工具**（SwiftUI + AppKit）：实时展示 DeepSeek 平台账户的余额、本月费用、Token 用量与按天趋势。

- 工具链：Swift 6（swift-tools-version 6.0），**Swift 5 语言模式**（Package.swift 中显式设置）
- 平台：macOS 14+（Apple Silicon / Intel 均可），仅 macOS，无 iOS/iPadOS
- 移动端：iOS 版（`ios/`，开发中）与 Android 版（规划中），总体方案见 MOBILE-PLAN.md
- 构建：Swift Package Manager，**无 Xcode 工程、无任何第三方依赖、单 target**（仅指 macOS 包；iOS 工程在 `ios/` 内，见第 8 节红线 13）
- 测试：轻量自测（swiftc 直接编译运行，**不依赖 XCTest**）
- CI：GitHub Actions（push main / PR 触发）；发布：打 `v*` 标签自动出 DMG Release
- 用户文档：README.md（英文）+ README.zh-CN.md（中文），双语惯例

## 2. 常用命令（改动后必须本地验证）

```bash
swift run                        # 开发模式运行（无 .app 外壳）
swift build                      # debug 构建
swift build -c release           # release 构建
bash Scripts/run-tests.sh        # 运行自测（全绿才算通过）
bash Scripts/build-app.sh release # 组装 build/DeepSeekMeter.app 并签名
bash Scripts/install.sh          # 构建 + 安装到 /Applications 并启动

# iOS 核心包自测（ios/DeepSeekMeterCore，改动核心逻辑后必须跑）
swift run --package-path ios/DeepSeekMeterCore DeepSeekMeterCoreSelftest
```

CI 的验证链：`swift build` → `swift build -c release` → `run-tests.sh` → `build-app.sh release` → 冒烟启动 6 秒。
**任何改动都必须保证这条链全部通过。**

注意：`swift run` 时 `Bundle.main.bundleIdentifier` 为 nil，开机自启注册会被跳过（SettingsStore 中已处理），这是预期行为，不是 Bug。

## 3. 仓库结构

```
Sources/DeepSeekMeter/
  AppMain.swift                  @main 入口；.accessory 激活策略（仅菜单栏，无 Dock 图标）
  AppDelegate.swift              生命周期组装：SettingsStore → AppModel → StatusItemController
  StatusItemController.swift     菜单栏 NSStatusItem + NSPopover 宿主（内容尺寸自适应）
  AppModel.swift                 状态中枢：@MainActor ObservableObject；轮询、拉取、错误状态
  PlatformService.swift          DeepSeek 平台私有接口客户端 + PlatformError
  Models.swift                   网络模型（Decodable）+ MonthUsage 聚合模型
  SettingsStore.swift            设置持久化（UserDefaults）+ 开机自启 + 旧钥匙串一次性迁移
  Formatting.swift               format() / currencySymbol() 等纯函数
  LoginWindowController.swift    内嵌官方登录页（WKWebView）+ Token 自动提取
  Views/
    PopoverView.swift            悬浮窗主界面（SwiftUI）
    SparklineView.swift          Token 按天用量柱状图
windows/                         Windows 版（.NET 8 + WPF，与 macOS 版功能对齐）
  src/DeepSeekMeter.Core/        纯逻辑库：Models / Formatting / PlatformService / SettingsStore
  src/DeepSeekMeter/             WPF 应用：MainViewModel / TrayIconController / PopoverWindow / LoginWindow 等
  tests/DeepSeekMeter.Selftest/  轻量自测（控制台，零测试框架）
  README.md                      Windows 版说明（含与 macOS 版对应关系）
ios/                             iOS 版（开发中，详见 MOBILE-PLAN.md）
  DeepSeekMeterCore/             共享核心 Swift Package（PlatformService / Models / Formatting / TokenStoring / AppModel，零第三方依赖；AppModel 注入 TokenStoring+URLSession，可在 macOS 上自测）
  DeepSeekMeter.xcodeproj        iOS App 工程（SwiftUI，Xcode 16 同步文件夹格式）
  DeepSeekMeter/                 iOS App 源码（AppMain / TokenStore(Keychain) / Views/）
  DeepSeekMeterCore/Sources/DeepSeekMeterCoreSelftest/  核心轻量自测（swift run 直接跑，不依赖 XCTest）
Scripts/
  build-app.sh / install.sh / notarize.sh / run-tests.sh / make-icon.sh / generate-icon.swift
  Info.plist                     应用包信息（**版本号在这里改**）
  selftest/main.swift            轻量自测源码（swiftc 编译运行）
.github/workflows/
  ci.yml                         push main / PR：macOS（构建+自测+打包+冒烟）+ Windows（构建+自测+冒烟）
  release.yml                    打 v* 标签：构建 DMG 并发布 GitHub Release
```

## 4. 架构分层（改动必须遵循）

依赖方向只允许自上而下：

```
UI（Views / StatusItemController / LoginWindowController）
        ↓ 读写 @Published 状态
AppModel / SettingsStore（@MainActor，状态与持久化）
        ↓ 调用
PlatformService（网络唯一入口） + Models（解码模型）
        ↓
Foundation / AppKit / SwiftUI / WebKit
```

- 所有网络请求只能经过 `PlatformService`；错误统一转为 `PlatformError`（带用户可读的中文 message）
- UI 只读模型层的 `@Published` 状态，**不直接发起网络请求**
- 新接口的响应模型写成 `Decodable` struct 放进 Models.swift，沿用平台 `{code, msg, data: {biz_code, biz_msg, biz_data}}` 包裹结构（注意 `biz_data` 有时是对象、有时是数组，以真实响应为准）
- 纯函数（格式化、币种符号、聚合计算）放 Formatting.swift / Models.swift 计算属性，并补自测
- 代码注释用中文 `///`；分组用 `// MARK: -`；UI 文案用中文

## 5. 提交规范（Conventional Commits，中文描述）

```
<type>(<scope>): <中文描述>
```

- type：`feat` / `fix` / `docs` / `refactor` / `chore` / `ci` / `test` / `perf`
- scope 可选（如 `ci`、`ui`、`api`）；描述用中文，一句话说清改了什么、为什么
- 示例：`fix(ci): build-app.sh 在无开发者证书环境下不再被 set -e 中断`

要求：
- 小步提交，一次提交只做一件事
- 不提交构建产物：`.build/`、`build/`、`.DS_Store` 已被 .gitignore 忽略，不要 `git add -f` 强加
- 提交信息与 diff 中不得出现真实 Token / 凭据

## 6. 分支与 PR 流程

1. 从 `main` 切分支，命名建议 `feat/xxx`、`fix/xxx`
2. 本地验证完整链（见第 2 节）
3. 提 PR 到 `main`，按 .github/pull_request_template.md 逐项填写勾选
4. PR 触发 CI，**CI 全绿才可合入**（建议 squash 合并）
5. PR 还会触发「AI Review」workflow（.github/workflows/ai-review.yml）：基于本文件规范与边界用 DeepSeek API 自动审查并提交 COMMENT 意见（更新式，只删旧 review 不发重复）；**它是顾问不是把关者，合并仍由维护者手动决定**。fork PR 同样审查（pull_request_target + API 获取 diff，不执行 PR 代码，secrets 安全）
6. 合入 main 的 push 也会触发 CI 验证

## 7. 发布流程（维护者）

1. 更新 `Scripts/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`
2. 本地 `bash Scripts/build-app.sh release` 验证
3. 打标签推送：`git tag v0.1.0 && git push origin v0.1.0`
4. release.yml 自动构建 DMG 并发布 Release（notes 自动生成）
5. （可选）有 Developer ID 证书时用 `Scripts/notarize.sh` 公证后重新发布

## 8. 边界（红线，AI 不得越界）

以下行为视为违规，即使看起来"更完善"：

1. **不引入任何第三方依赖**。零依赖单 target 是刻意设计；新增依赖需先开 Issue 讨论
2. **不把 Token 存回钥匙串**。Token 刻意存 UserDefaults（ad-hoc 签名下钥匙串会每次启动弹密码授权）；SettingsStore 中已有一次性迁移逻辑，保留即可
3. **不把真实 Token / 凭据写进代码、日志、截图或提交**。调试一律用占位符
4. **不臆造平台接口**。PlatformService 访问的是 platform.deepseek.com 的**私有接口**（`get_user_summary` / `usage/by_api_key/amount` / `usage/by_api_key/cost`，参数 `start`/`end` 为 Unix 秒、`tz` 为秒偏移、`bucket` 分桶粒度），无公开文档；不要凭空猜测 URL、参数或响应字段——改动前抓真实响应验证，并同步更新 selftest 的样例 JSON
5. **不改数据流向**。所有数据只能来自 DeepSeek 官方接口，不得上报任何第三方；隐私承诺见 README「隐私与数据」
6. **不引入 Xcode 工程或 XCTest**。测试保持 swiftc 轻量自测（Scripts/selftest/main.swift）；需要更重的测试设施先开 Issue
7. **不破坏平台与语言模式约束**：macOS 14+、Swift 5 语言模式（Package.swift）
8. **不改语言基调**：代码注释、UI 文案用中文；文档遵循 README.md（EN）+ README.zh-CN.md（ZH）双语惯例
9. **不破坏 CI**。合入前本地跑完整验证链；CI 红了先修复再继续
10. **不提交产物与本地文件**：`.build/`、`build/`、`.DS_Store`、`*.xcuserstate`

### 移动端红线（iOS / Android，追加条款）

11. **移动端同样零第三方依赖**：iOS/Android 业务逻辑零第三方依赖；系统框架（URLSession / SwiftUI / WebKit / Security / WidgetKit，以及 Android 的 Compose / HttpURLConnection 等）与平台官方工具不视为第三方（与 Windows 版 WebView2 例外同理）
12. **Token 存储分平台**：红线第 2 条仅适用于 macOS（ad-hoc 签名下钥匙串每次启动弹密码授权）；**iOS 用 Keychain（kSecClassGenericPassword）、Android 用 Keystore 加密后存 SharedPreferences**——移动端 App 有正式签名，钥匙串不会弹窗；同样不得把真实 Token 写进代码/日志/截图
13. **移动端核心逻辑统一在 `ios/DeepSeekMeterCore`**（Swift 5 语言模式，与 Sources/DeepSeekMeter/ 逐文件对应，防三端漂移）；改动后必须跑核心自测（第 2 节命令）；`.xcodeproj` 只允许存在于 `ios/` 内，macOS 包保持无 Xcode 工程；新接口改动前先抓真实响应验证并同步更新自测样例 JSON（红线 4 同样适用于移动端）

## 9. 完成标准（Definition of Done）

- [ ] `swift build` 与 `swift build -c release` 均通过
- [ ] `bash Scripts/run-tests.sh` 全绿（新增纯逻辑请补自测）
- [ ] `bash Scripts/build-app.sh release` 打包成功
- [ ] 未触碰第 8 节任何红线
- [ ] 提交信息符合第 5 节规范，小步提交
- [ ] PR 描述完整、按模板勾选；CI 全绿

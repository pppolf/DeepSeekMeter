# 本机安装 Xcode 并本地运行 iOS 版

> 目标：在这台 Mac 上装好 Xcode，然后用 [Scripts/run-ios-simulator.sh](../Scripts/run-ios-simulator.sh) 一键把 DeepSeekMeter iOS 版跑进模拟器（含截图验证）。
> 全程**不需要上架、不需要开发者账号**（模拟器路径）；真机路径需要免费 Apple ID，见文末。

## 为什么需要你手动装一次

Xcode 只能通过 Apple ID 获取（App Store 或 developer.apple.com），这一步**必须本人登录 Apple ID 操作**，无法由脚本/代理代办（也不要把 Apple ID 密码给任何人）。
下载约 12GB、解压后占用 30GB+（本机当前剩余约 69GB，足够）。

## 步骤 1：安装 Xcode（二选一）

**方式 A：App Store（推荐）**
1. 打开 App Store -> 搜索 **Xcode**（或直接打开 https://apps.apple.com/app/id497799835）
2. 点击「获取 / 安装」，等待下载完成（12GB+，需几分钟到半小时）
3. 安装完成后 Xcode 出现在「启动台 / 应用程序」

**方式 B：开发者网站**
1. 浏览器打开 https://developer.apple.com/xcode/ -> 登录 Apple ID -> 下载最新 Xcode .xip
2. 双击 .xip 解压，把 Xcode.app 拖进「应用程序」

> 装完顺手跑一次 `xcodebuild -version` 确认版本（Xcode 26.x 匹配本机 macOS 26）。

## 步骤 2（可选）：切换命令行工具

脚本会自动使用 /Applications/Xcode.app（无需这一步）；如果想全局切过去，执行一次：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 步骤 3（首次需要）：下载 iOS 模拟器运行时（约 7GB）

- 命令行：`xcodebuild -downloadPlatform iOS`（后台下载）
- 或 GUI：Xcode -> Settings -> Components -> iOS 模拟器运行时 -> 下载

## 步骤 4：一键跑进模拟器

```bash
bash Scripts/run-ios-simulator.sh
```

脚本依次完成：核心自测 -> 工程结构校验 -> 无签名构建 -> 启动模拟器 -> 安装并启动 App -> 截图到 `build/simulator-screenshots/DeepSeekMeter.png`。

装好后如需我接手：直接说「Xcode 装好了」，我来跑脚本、看截图、修编译错误。

## 真机路径（可选，免费）

1. iPhone 设置 -> 隐私与安全性 -> 开发者模式 -> 开启（重启）
2. 数据线连接 Mac；Xcode -> Settings -> Accounts -> 登录你的免费 Apple ID
3. 顶部选你的 iPhone -> Run（首次需在手机上信任此电脑）

**免费签名限制（重要）**：
- 证书 **7 天过期**，需每 7 天连电脑重签一次
- **App Group 不可用** -> 小组件（WidgetKit）能装但读不到余额快照（显示 0）；Keychain 登录不受影响
- 想长期稳定用（小组件 + 不用重签）：Apple Developer Program $99/年 -> TestFlight 分发，见 MOBILE-PLAN.md 决策点 D1


## 发布到 GitHub（推分支 + PR）

1. 推送分支（CI 会在 PR 上跑 macOS/Windows/iOS 全部构建与自测）：
   ```bash
   git switch -c feat/ios-mobile-app
   git push -u origin feat/ios-mobile-app
   ```
2. 浏览器打开 GitHub 仓库 -> 会出现「Compare & pull request」按钮 -> 创建 PR（模板见 .github/pull_request_template.md）
3. 等 CI 全绿后合入（建议 squash）；合入后本地 `git switch main && git pull`

## 真机安装（二选一）

> 前提：iPhone 需 iOS 17+（iPhone XS 及以上）；先连数据线并在 iPhone 上开启「设置 -> 隐私与安全性 -> 开发者模式」。

### 路径 A：免费 Apple ID（零成本，7 天重签）

1. Xcode -> Settings -> Accounts -> 添加你的免费 Apple ID
2. 打开 ios/DeepSeekMeter.xcodeproj -> 选中 DeepSeekMeter target -> Signing & Capabilities -> Team 选你的 Apple ID
3. **关键**：免费个人团队不支持 App Group（小组件要的）。两种处理任选：
   - 命令行构建：`DEEPSEEK_ENTITLEMENTS=DeepSeekMeter.Free.entitlements xcodebuild ... CODE_SIGNING_ALLOWED=YES`
   - 或 Xcode 里 target Build Settings -> User-Defined -> 新增 `DEEPSEEK_ENTITLEMENTS` = `DeepSeekMeter.Free.entitlements`（App 与 Widget 两个 target 都要）
   - 或直接删掉 Signing & Capabilities 里的 App Group 能力（Xcode 会改 entitlements 文件）
4. 顶部选择你的 iPhone -> Run；手机上点「信任此电脑」
5. 结果：App 主体（登录/余额/用量/趋势/通知）全部可用；**小组件显示 0**（App Group 不可用，属预期）；证书 7 天过期，需每 7 天连电脑重签

### 路径 B：Apple Developer Program（$99/年，推荐长期用）

1. 注册 https://developer.apple.com/programs/ （需 Apple ID + 付款）
2. Xcode -> Accounts 添加账号；Signing & Capabilities 选择你的 Team
3. 在开发者后台注册 App Group ID（`group.com.deepseek.meter`）并勾选到 App 与 Widget 的 profile
4. 直接 Run 即可；小组件、推送、7 天免重签全部可用
5. 想正式分发（亲友/上架）：TestFlight / Ad-hoc，见 MOBILE-PLAN.md 决策点 D1

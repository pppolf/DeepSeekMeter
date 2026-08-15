# 为 DeepSeekMeter 贡献代码

感谢你的贡献！🐳

[English](CONTRIBUTING.md)

**使用 AI 编码助手？** 请先阅读仓库根目录的 [AGENTS.md](AGENTS.md) —— 这是 AI 的操作手册，包含本仓库的硬性边界（红线）。

## 快速开始

- 仓库：https://github.com/pppolf/DeepSeekMeter
- 默认分支：`main`
- 用户文档：[README.zh-CN.md](README.zh-CN.md) / [README.md](README.md)

## 开发环境

- macOS 14+（Apple Silicon / Intel 均可）
- 只需 Xcode Command Line Tools：`xcode-select --install`
- 无 Xcode 工程、无第三方依赖——纯 Swift Package Manager

## 常用命令

```bash
swift run                        # 开发模式直接跑（无 .app 外壳）
swift build                      # debug 构建
swift build -c release           # release 构建
bash Scripts/run-tests.sh        # 运行轻量自测（swiftc，无 XCTest）
bash Scripts/build-app.sh release # 组装 build/DeepSeekMeter.app 并签名
bash Scripts/install.sh          # 构建 + 安装到 /Applications 并启动
```

CI 验证链（每次 push/PR 都会跑）：`swift build` → `swift build -c release` → `run-tests.sh` → `build-app.sh release` → 冒烟启动 6 秒。**提 PR 前必须在本地全部通过。**

## 仓库结构

```
Sources/DeepSeekMeter/           App 源码（SwiftUI + AppKit）
  Views/                         悬浮窗 UI
  AppModel.swift                 状态中枢（@MainActor ObservableObject）
  PlatformService.swift          平台接口客户端
  Models.swift                   Decodable 模型 + 聚合
  SettingsStore.swift            UserDefaults 持久化 + 开机自启
windows/                         Windows 版（.NET 8 + WPF，功能与 macOS 版对齐）
  src/DeepSeekMeter.Core/        纯逻辑库（Models / Formatting / PlatformService / SettingsStore）
  src/DeepSeekMeter/             WPF 应用（MainViewModel / TrayIconController / PopoverWindow / LoginWindow）
  tests/DeepSeekMeter.Selftest/  轻量自测（控制台，零测试框架）
Scripts/                         构建 / 安装 / 公证 / 图标 / 自测脚本
  selftest/                      轻量单元测试（swiftc，无需 Xcode）
.github/workflows/               ci.yml（push/PR：macOS + Windows）+ release.yml（v* 标签）
```

## 代码规范

- **单 target、零第三方依赖**——刻意设计；新增依赖请先开 Issue 讨论。例外：`windows/` 的 Windows 版（.NET 8 + WPF）使用微软官方 `Microsoft.Web.WebView2` 包实现内嵌登录页（运行时随 Win10 1809+/11 预装），是 Windows 侧刻意允许的唯一 NuGet 依赖；Swift 侧保持零依赖不变
- Swift 6 工具链，**Swift 5 语言模式**（Package.swift 中显式设置）
- 分层：UI（Views/StatusItemController）→ AppModel/SettingsStore（状态）→ PlatformService（网络）→ Foundation。UI 不直接发网络请求；所有请求经 `PlatformService`，错误统一转 `PlatformError`（用户可读中文 message）
- 响应模型：Models.swift 中的 `Decodable` struct，沿用平台包裹结构 `{code, msg, data: {biz_code, biz_msg, biz_data}}`（注意 `biz_data` 有时是对象、有时是数组，以真实响应为准）
- 纯函数（格式化、币种符号、聚合）放 Formatting.swift / 计算属性，并补自测
- 注释与 UI 文案用**中文**（`///` 文档注释、`// MARK: -` 分组），保持现状
- 新增纯逻辑请在 Scripts/selftest/main.swift 中补检查

## 提交信息

Conventional Commits + 中文描述：

```
<type>(<scope>): <中文描述>
```

- type：`feat` / `fix` / `docs` / `refactor` / `chore` / `ci` / `test` / `perf`（scope 可选，如 `ci`、`ui`、`api`）
- 示例：`fix(ci): build-app.sh 在无开发者证书环境下不再被 set -e 中断`
- 小步提交，一次只做一件事；不提交构建产物（`.build/`、`build/`、`.DS_Store`），不夹带真实 Token / 凭据

## 分支与 PR 流程

1. 从 `main` 切分支，命名建议 `feat/xxx`、`fix/xxx`
2. 本地验证（debug + release 构建、run-tests.sh、build-app.sh）
3. 向 `main` 提 PR，按 [PR 模板](.github/pull_request_template.md) 逐项填写勾选
4. PR 触发 CI，**CI 全绿才可合入**（建议 squash 合并）
5. 同仓库分支的 PR 还会触发「AI Review」（DeepSeek API，遵循 AGENTS.md 审查）：以 `github-actions[bot]` 身份提交 COMMENT 意见，仅供参考，**合并仍由维护者手动决定**；fork PR 因拿不到 secrets 自动跳过
6. 合入 main 的 push 同样会触发 CI

## 项目边界

以下红线请勿触碰——它们关系到隐私承诺与稳定性：

1. **不引入第三方依赖**——零依赖单 target 是刻意设计
2. **Token 保持存 UserDefaults**——不要存回钥匙串（ad-hoc 签名下每次启动会弹密码授权；SettingsStore 已有一次性迁移逻辑）
3. **不提交真实 Token / 凭据**——代码、日志、截图、提交信息都不行
4. **不臆造平台接口**——PlatformService 访问 platform.deepseek.com 的**私有接口**（`get_user_summary` / `usage/by_api_key/amount` / `usage/by_api_key/cost`，参数 `start`/`end` 为 Unix 秒、`tz` 为秒偏移、`bucket` 分桶粒度）；改 URL、参数或响应结构前先抓真实响应验证，并同步更新自测样例
5. **不改数据流向**——数据只来自 DeepSeek 官方接口，不上报任何第三方
6. **不引入 Xcode 工程 / XCTest**——测试保持 swiftc 轻量自测；需要更重的测试设施先开 Issue
7. **保持平台约束**——macOS 14+、Swift 5 语言模式
8. **保持语言基调**——中文注释 / UI 文案；文档遵循双语惯例（README.md 英文 + README.zh-CN.md 中文）

## 发布流程（维护者）

1. 更新 `Scripts/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`
2. 本地验证 `bash Scripts/build-app.sh release`
3. 打标签推送：`git tag v0.1.0 && git push origin v0.1.0`
4. [release.yml](.github/workflows/release.yml) 自动构建 DMG 并发布 GitHub Release
5. （可选）有付费 Developer ID 证书时用 `Scripts/notarize.sh` 签名公证后重新发布

## 开源协议

提交即表示你同意你的贡献遵循 [MIT License](LICENSE)。

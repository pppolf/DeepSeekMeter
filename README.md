# DeepSeek Meter 🐳

一个常驻 macOS 菜单栏的小工具：**实时查看 DeepSeek 余额 / 额度情况**，点击菜单栏图标即弹出悬浮窗。

## 功能

- 🖥️ **菜单栏常驻**：状态栏直接显示当前余额（如 `¥110.00`），余额过低变橙色、不足 1 元变红色
- 🪟 **点击弹悬浮窗**：余额卡片（总余额 / 赠送 / 充值）、币种、账户可用状态
- 📈 **使用趋势**：近 24 小时余额折线图 + 「1小时 / 今日 / 24小时」消耗统计
- ⏱️ **定时刷新**：15 秒 ~ 10 分钟可选，启动即拉取
- 🔐 **Key 安全存储**：API Key 存入 macOS 钥匙串，不落明文
- 🚀 **开机自启**：一键开关（需安装到 /Applications）

## 环境要求

- macOS 14+（Apple Silicon / Intel 均可）
- Xcode Command Line Tools（`xcode-select --install`）

## 快速开始

### 1. 获取 DeepSeek API Key

打开 [platform.deepseek.com](https://platform.deepseek.com) → 左侧「API Keys」→ 创建新 Key（以 `sk-` 开头）。

### 2. 构建并运行

```bash
# 方式一：开发模式（直接从源码跑，不需要 .app）
swift run

# 方式二：构建 .app 并打开
./Scripts/build-app.sh
open build/DeepSeekMeter.app

# 方式三：构建 + 安装到 /Applications + 启动（推荐，支持开机自启）
./Scripts/install.sh
```

### 3. 填入 API Key

首次启动会自动弹出悬浮窗 → 在「API Key」处粘贴 Key → 点「保存」，立即校验并开始显示余额。

## 使用说明

- 点击菜单栏图标 ⇄ 打开 / 关闭悬浮窗；点击窗口外任意处自动关闭
- 「刷新间隔」切换后立即生效
- 菜单栏文字含义：正常=黑色，余额 < 10 = 橙色，余额 < 1 = 红色，获取失败 = 红色「—」
- 数据说明：DeepSeek 官方 API 目前只提供**余额查询**（`/user/balance`），不提供 token 用量明细，因此「使用情况」通过余额变化趋势体现（消耗 = 余额下降）

## 目录结构

```
Sources/DeepSeekMeterCore/   核心逻辑：模型 / 网络请求 / 钥匙串 / 设置 / 趋势
Sources/DeepSeekMeter/       应用层：入口 / 菜单栏状态项 / 悬浮窗 UI
Scripts/                     Info.plist / 构建 / 安装 / 图标生成 / 自测
Scripts/selftest/             轻量自测（JSON 解码、格式化，无 XCTest 依赖）
```

## 自测

无需 Xcode 即可运行单元级验证（JSON 解码 / 格式化）：

```bash
./Scripts/run-tests.sh
```

## 常见问题

**菜单栏没图标？** 首次启动可能没有立即出现，检查：`活动监视器` 里是否已有 `DeepSeekMeter` 进程；或重新 `./Scripts/install.sh`。

**提示 API Key 无效？** 确认 Key 没有多余空格、没有过期；DeepSeek 平台可随时重新生成 Key。

**开机自启不生效？** 开机自启依赖「安装到 /Applications」后的登录项注册，请使用 `./Scripts/install.sh` 安装，并在「系统设置 → 通用 → 登录项」确认。

**如何退出？** 点击菜单栏图标 → 悬浮窗右下角「退出」；或右键 Dock（无 Dock 图标时用活动监视器结束进程）。

## 卸载

```bash
rm -rf /Applications/DeepSeekMeter.app
# 如需删除钥匙串中的 Key：打开「钥匙串访问」搜索 deepseek.meter 删除
```
## 描述

<!-- 这个 PR 做了什么？解决了什么问题？ -->

## 关联

- Closes #<!-- Issue 编号（如有） -->

## 变更类型

<!-- 勾选并简述 -->

- [ ] ✨ 新功能
- [ ] 🐛 Bug 修复
- [ ] ♻️ 重构
- [ ] 📝 文档
- [ ] ⚙️ CI / 构建脚本
- [ ] 🧹 其他

## 本地验证

<!-- 提交前请逐项勾选（对应仓库 AGENTS.md 的完成标准） -->

- [ ] `swift build` 通过
- [ ] `swift build -c release` 通过
- [ ] `bash Scripts/run-tests.sh` 全部通过
- [ ] `bash Scripts/build-app.sh release` 打包成功
- [ ] 手动运行验证过相关场景（UI 改动请附截图）

## 边界检查

<!-- 仓库红线（详见 CONTRIBUTING.md / AGENTS.md），逐项确认 -->

- [ ] 未引入任何第三方依赖
- [ ] 未改动平台接口契约（URL / 参数 / 响应结构），或已抓真实响应验证并更新自测样例
- [ ] 未在代码 / 日志 / 截图 / 提交中夹带真实 Token 或凭据
- [ ] 未提交构建产物（`.build/`、`build/`、`.DS_Store`）
- [ ] 未改变 Token 存储方式（保持 UserDefaults）
- [ ] 注释与 UI 文案保持中文；文档遵循双语惯例
- [ ] 提交信息符合 Conventional Commits + 中文描述

## 备注

<!-- 其他需要 reviewer 注意的地方 -->

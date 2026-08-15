import Foundation

/// Token 存取抽象：核心逻辑不关心具体实现，由各端 App target 提供。
/// - iOS：Keychain（kSecClassGenericPassword，见 TokenStore.swift）
/// - macOS：UserDefaults（仓库红线 2 的背景：ad-hoc 签名下钥匙串会弹密码授权）
/// - Android（未来）：Keystore 加密后存 SharedPreferences
/// 读取失败统一按「需要重新登录」处理（对齐 Windows TokenProtector 语义）。
public protocol TokenStoring {
    /// 读取已保存的平台 Token；无或不可用时返回 nil
    func loadToken() -> String?
    /// 保存平台 Token
    func saveToken(_ token: String)
    /// 清除平台 Token
    func clearToken()
}

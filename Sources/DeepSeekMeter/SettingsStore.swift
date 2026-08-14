import Foundation
import Combine
import ServiceManagement
import Security

/// 用户设置：平台 Token（UserDefaults）+ 刷新间隔 + 开机自启
/// 说明：Token 是登录态会话凭证，存偏好文件即可避免钥匙串每次启动弹密码授权
@MainActor
final class SettingsStore: ObservableObject {
    @Published var platformToken: String {
        didSet {
            UserDefaults.standard.set(platformToken, forKey: Keys.platformToken)
        }
    }
    @Published var platformUserName: String {
        didSet { UserDefaults.standard.set(platformUserName, forKey: Keys.platformUserName) }
    }
    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: Keys.refreshInterval)
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// 可选的刷新间隔（秒）
    static let intervalOptions: [TimeInterval] = [15, 30, 60, 300, 600]

    private enum Keys {
        static let platformToken = "settings.platformToken"
        static let platformUserName = "settings.platformUserName"
        static let refreshInterval = "settings.refreshInterval"
        static let launchAtLogin = "settings.launchAtLogin"
    }

    init() {
        let defaults = UserDefaults.standard
        // 先初始化全部存储属性（init 中赋值不会触发 didSet）
        platformToken = defaults.string(forKey: Keys.platformToken) ?? ""
        platformUserName = defaults.string(forKey: Keys.platformUserName) ?? ""
        let saved = defaults.double(forKey: Keys.refreshInterval)
        // 刷新间隔只接受项目已有合法选项，损坏/非法值回退 1 分钟
        refreshInterval = Self.intervalOptions.contains(saved) ? saved : 60
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        // 一次性迁移：旧版本把 Token 存在钥匙串（ad-hoc 签名导致每次启动都要密码授权）
        // 迁到 UserDefaults 后删除钥匙串条目，此后不再访问钥匙串
        if platformToken.isEmpty, let legacy = Self.loadLegacyKeychainToken(), !legacy.isEmpty {
            platformToken = legacy
        }
        Self.deleteLegacyKeychainToken()

        if launchAtLogin { applyLaunchAtLogin(true) } // 确保注册状态与设置一致
    }

    func clearPlatformToken() {
        platformToken = ""
        platformUserName = ""
    }

    // MARK: - 旧版钥匙串迁移（一次性）

    private static func loadLegacyKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.deepseek.meter",
            kSecAttrAccount as String: "deepseek-platform-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacyKeychainToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.deepseek.meter",
            kSecAttrAccount as String: "deepseek-platform-token"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return } // 非 .app 运行时跳过
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("launch at login error: \(error)")
        }
    }
}
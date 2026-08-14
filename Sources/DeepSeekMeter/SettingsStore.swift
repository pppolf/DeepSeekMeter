import Foundation
import Combine
import ServiceManagement

/// 用户设置：API Key / 平台 Token（钥匙串）+ 刷新间隔 + 开机自启（UserDefaults）
@MainActor
final class SettingsStore: ObservableObject {
    @Published var apiKey: String {
        didSet { KeychainStore.saveAPIKey(apiKey) }
    }
    @Published var platformToken: String {
        didSet { KeychainStore.savePlatformToken(platformToken) }
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
        static let refreshInterval = "settings.refreshInterval"
        static let launchAtLogin = "settings.launchAtLogin"
        static let platformUserName = "settings.platformUserName"
    }

    init() {
        let defaults = UserDefaults.standard
        apiKey = KeychainStore.loadAPIKey() ?? ""
        platformToken = KeychainStore.loadPlatformToken() ?? ""
        platformUserName = defaults.string(forKey: Keys.platformUserName) ?? ""
        let saved = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = saved > 0 ? saved : 60
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        if launchAtLogin { applyLaunchAtLogin(true) } // 确保注册状态与设置一致
    }

    func clearAPIKey() {
        apiKey = ""
        KeychainStore.deleteAPIKey()
    }

    func clearPlatformToken() {
        platformToken = ""
        platformUserName = ""
        KeychainStore.deletePlatformToken()
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

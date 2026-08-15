import Foundation
import UserNotifications
import DeepSeekMeterCore

/// 余额低阈值本地通知（纯本地计算，无第三方推送服务，不违反隐私承诺）。
/// 通知只在本机弹，不向任何第三方上报数据。
enum NotificationService {
    /// 设置开关（UserDefaults key，与 SettingsView 的 @AppStorage 共用）
    static let enabledKey = "settings.lowBalanceAlert"
    /// 低余额提醒阈值（对齐桌面「低于 1 变红」语义）
    static let lowBalanceThreshold = 1.0

    /// 请求通知权限（首次打开开关时调用）
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 刷新成功后调用：余额低于阈值且本档未提醒过则弹本地通知（避免每次轮询都弹）。
    /// 开关关闭时不提示。
    static func notifyLowBalanceIfNeeded(balance: Double, currency: String) {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              balance > 0, balance < lowBalanceThreshold else { return }
        let flagKey = "notified.lowBalance.\(Int(lowBalanceThreshold))"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = "余额不足提醒"
        content.body = "当前余额 \(currencySymbol(currency))\(format(balance))，低于 \(format(lowBalanceThreshold))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "low-balance", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// 重置提醒标记（退出登录 / 关闭开关时调用，余额回升后可再次提醒）
    static func resetLowBalanceFlag() {
        UserDefaults.standard.removeObject(forKey: "notified.lowBalance.\(Int(lowBalanceThreshold))")
    }
}

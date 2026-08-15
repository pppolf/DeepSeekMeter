import Foundation

/// 小组件余额快照（App Group UserDefaults）：App 每次刷新后写入，Widget 只读展示。
/// 刻意不把 Token 放进共享容器——小组件无需联网、不扩大凭证暴露面；
/// 刷新时机依赖 App 前台刷新 + 写入后主动 reload，与后台 BGTask 刷新互补。
public enum BalanceSnapshot {
    public static let suiteName = "group.com.deepseek.meter"
    public static let balanceKey = "widget.balance"
    public static let currencyKey = "widget.currency"
    public static let updatedKey = "widget.updatedAt"

    /// App 侧在余额变化时调用
    public static func save(balance: Double, currency: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(balance, forKey: balanceKey)
        defaults?.set(currency, forKey: currencyKey)
        defaults?.set(Date(), forKey: updatedKey)
    }

    /// Widget 侧读取快照（无写入权限时返回默认值）
    public static func load() -> (balance: Double, currency: String, updated: Date?) {
        let defaults = UserDefaults(suiteName: suiteName)
        return (
            defaults?.double(forKey: balanceKey) ?? 0,
            defaults?.string(forKey: currencyKey) ?? "CNY",
            defaults?.object(forKey: updatedKey) as? Date
        )
    }
}

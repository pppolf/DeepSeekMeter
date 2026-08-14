import Foundation

// MARK: - DeepSeek 余额 API 响应（GET https://api.deepseek.com/user/balance）

struct BalanceResponse: Codable, Equatable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceInfo: Codable, Equatable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    var total: Double { Double(totalBalance) ?? 0 }
    var granted: Double { Double(grantedBalance) ?? 0 }
    var toppedUp: Double { Double(toppedUpBalance) ?? 0 }
}

// MARK: - 余额快照（用于趋势 / 消耗统计）

struct BalanceSnapshot: Codable, Equatable, Identifiable {
    let time: Date
    let total: Double
    let granted: Double
    let toppedUp: Double
    var id: Date { time }
}

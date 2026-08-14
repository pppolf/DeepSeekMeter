import Foundation

// MARK: - 余额信息（由平台 get_user_summary 构造，供 UI 展示）

struct BalanceInfo: Equatable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    var total: Double { Double(totalBalance) ?? 0 }
    var granted: Double { Double(grantedBalance) ?? 0 }
    var toppedUp: Double { Double(toppedUpBalance) ?? 0 }
}

// MARK: - 平台用量模型（platform.deepseek.com 私有接口，需登录 userToken）

/// 通用平台响应包装：{code, msg, data}
struct PlatformEnvelope<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?
}

/// data 的业务包装：{biz_code, biz_msg, biz_data}
struct BizWrapper<T: Decodable>: Decodable {
    let bizCode: Int
    let bizMsg: String
    let bizData: T
}

/// usage/amount 的 biz_data：{total, days}
struct UsageData: Decodable {
    let total: [ModelUsage]
    let days: [UsageDay]?
}

/// 单个模型的用量/费用条目
struct ModelUsage: Decodable, Identifiable {
    let model: String
    let usage: [UsageItem]
    var id: String { model }

    func value(for type: String) -> Double {
        usage.first { $0.type == type }?.value ?? 0
    }

    var requests: Int { Int(value(for: "REQUEST").rounded()) }
}

struct UsageItem: Decodable {
    let type: String   // PROMPT_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN / RESPONSE_TOKEN / REQUEST
    let amount: String
    var value: Double { Double(amount) ?? 0 }
}

/// 某一天的用量
struct UsageDay: Decodable, Identifiable {
    let date: String   // "2026-08-01"
    let data: [ModelUsage]
    var id: String { date }
}

/// get_user_summary 的 biz_data
struct UserSummary: Decodable {
    let normalWallets: [WalletBalance]
    let bonusWallets: [WalletBalance]
    let totalCosts: [WalletCost]
}

struct WalletBalance: Decodable {
    let currency: String
    let balance: String
    let tokenEstimation: String?
    var value: Double { Double(balance) ?? 0 }
}

struct WalletCost: Decodable {
    let currency: String
    let amount: String
    var value: Double { Double(amount) ?? 0 }
}

/// 聚合后的本月用量（UI 直接使用）
struct MonthUsage: Identifiable {
    let year: Int
    let month: Int
    let amountModels: [ModelUsage]
    let costModels: [ModelUsage]
    let costDays: [UsageDay]
    let amountDays: [UsageDay]

    var id: String { "\(year)-\(month)" }

    // MARK: - 本月汇总

    var totalCost: Double {
        costModels.reduce(0) { $0 + $1.usage.reduce(0) { $0 + $1.value } }
    }

    var promptTokens: Double { sumAmount("PROMPT_TOKEN") }
    var cacheHitTokens: Double { sumAmount("PROMPT_CACHE_HIT_TOKEN") }
    var cacheMissTokens: Double { sumAmount("PROMPT_CACHE_MISS_TOKEN") }
    var responseTokens: Double { sumAmount("RESPONSE_TOKEN") }
    var totalRequests: Int { amountModels.reduce(0) { $0 + $1.requests } }

    // MARK: - 按日查询

    func cost(on date: Date) -> Double {
        let key = Self.dayKey(date)
        guard let day = costDays.first(where: { $0.date == key }) else { return 0 }
        return day.data.reduce(0) { $0 + $1.usage.reduce(0) { $0 + $1.value } }
    }

    func tokens(on date: Date) -> (requests: Int, response: Double, cacheHit: Double, cacheMiss: Double) {
        let key = Self.dayKey(date)
        guard let day = amountDays.first(where: { $0.date == key }) else { return (0, 0, 0, 0) }
        return (
            day.data.reduce(0) { $0 + $1.requests },
            day.data.reduce(0) { $0 + $1.value(for: "RESPONSE_TOKEN") },
            day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_HIT_TOKEN") },
            day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_MISS_TOKEN") }
        )
    }

    // MARK: - 工具

    private func sumAmount(_ type: String) -> Double {
        amountModels.reduce(0) { $0 + $1.value(for: type) }
    }

    private static func dayKey(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

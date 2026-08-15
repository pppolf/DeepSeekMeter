import Foundation

// MARK: - 余额信息（由平台 get_user_summary 构造，供 UI 展示）

public struct BalanceInfo: Equatable {
    public let currency: String
    public let totalBalance: String
    public let grantedBalance: String
    public let toppedUpBalance: String

    public init(currency: String, totalBalance: String, grantedBalance: String, toppedUpBalance: String) {
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }

    public var total: Double { Double(totalBalance) ?? 0 }
    public var granted: Double { Double(grantedBalance) ?? 0 }
    public var toppedUp: Double { Double(toppedUpBalance) ?? 0 }
}

// MARK: - 平台用量模型（platform.deepseek.com 私有接口，需登录 userToken）

/// 通用平台响应包装：{code, msg, data}
public struct PlatformEnvelope<T: Decodable>: Decodable {
    public let code: Int
    public let msg: String
    public let data: T?
}

/// data 的业务包装：{biz_code, biz_msg, biz_data}
public struct BizWrapper<T: Decodable>: Decodable {
    public let bizCode: Int
    public let bizMsg: String
    public let bizData: T
}

/// usage/amount 的 biz_data：{total, days}
public struct UsageData: Decodable {
    public let total: [ModelUsage]
    public let days: [UsageDay]?
}

/// 单个模型的用量/费用条目
public struct ModelUsage: Decodable, Identifiable {
    public let model: String
    public let usage: [UsageItem]
    public var id: String { model }

    public func value(for type: String) -> Double {
        usage.first { $0.type == type }?.value ?? 0
    }

    public var requests: Int { Int(value(for: "REQUEST").rounded()) }
}

public struct UsageItem: Decodable {
    public let type: String   // PROMPT_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN / RESPONSE_TOKEN / REQUEST
    public let amount: String
    public var value: Double { Double(amount) ?? 0 }
}

/// 某一天的用量
public struct UsageDay: Decodable, Identifiable {
    public let date: String   // "2026-08-01"
    public let data: [ModelUsage]
    public var id: String { date }
}

// MARK: - by_api_key 用量（实时接口：usage/by_api_key/amount、usage/by_api_key/cost）
// 参数 start/end 为 Unix 秒，tz 为秒偏移（UTC+8 = 28800），bucket 传 86400 按天分桶

/// usage/by_api_key/amount 的 biz_data
public struct APIKeyAmountData: Decodable {
    public let start: Int
    public let end: Int
    public let bucket: Int
    public let models: [String]
    public let series: [APIKeyAmountSeries]
}

public struct APIKeyAmountSeries: Decodable {
    public let apiKey: APIKeyInfo
    public let model: String
    public let buckets: [APIKeyUsageBucket]
}

/// usage/by_api_key/cost 的 biz_data
public struct APIKeyCostData: Decodable {
    public let start: Int
    public let end: Int
    public let bucket: Int
    public let models: [String]
    public let data: [APIKeyCostGroup]
}

public struct APIKeyCostGroup: Decodable {
    public let currency: String
    public let series: [APIKeyCostSeries]
}

public struct APIKeyCostSeries: Decodable {
    public let apiKey: APIKeyInfo
    public let model: String
    public let buckets: [APIKeyCostBucket]
}

public struct APIKeyInfo: Decodable {
    public let trackingId: String
    public let name: String
    public let sensitiveId: String
    public let valid: Bool
}

/// 按天桶的 token 用量：type -> 数值（REQUEST / RESPONSE_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN）
/// 注意：真实响应中值为 JSON 数字（非字符串），必须用 Double 解码
public struct APIKeyUsageBucket: Decodable {
    public let time: Int
    public let usage: [String: Double]
}

/// 按天桶的费用
public struct APIKeyCostBucket: Decodable {
    public let time: Int
    public let cost: String
}

/// get_user_summary 的 biz_data
public struct UserSummary: Decodable {
    public let normalWallets: [WalletBalance]
    public let bonusWallets: [WalletBalance]
    public let totalCosts: [WalletCost]
}

public struct WalletBalance: Decodable {
    public let currency: String
    public let balance: String
    public let tokenEstimation: String?
    public var value: Double { Double(balance) ?? 0 }
}

public struct WalletCost: Decodable {
    public let currency: String
    public let amount: String
    public var value: Double { Double(amount) ?? 0 }
}

/// 聚合后的本月用量（UI 直接使用）
public struct MonthUsage: Identifiable {
    public let year: Int
    public let month: Int
    public let amountModels: [ModelUsage]
    public let costModels: [ModelUsage]
    public let costDays: [UsageDay]
    public let amountDays: [UsageDay]

    public var id: String { "\(year)-\(month)" }

    public init(year: Int, month: Int, amountModels: [ModelUsage], costModels: [ModelUsage], costDays: [UsageDay], amountDays: [UsageDay]) {
        self.year = year
        self.month = month
        self.amountModels = amountModels
        self.costModels = costModels
        self.costDays = costDays
        self.amountDays = amountDays
    }

    // MARK: - 本月汇总

    public var totalCost: Double {
        costModels.reduce(0) { $0 + $1.usage.reduce(0) { $0 + $1.value } }
    }

    public var promptTokens: Double { sumAmount("PROMPT_TOKEN") }
    public var cacheHitTokens: Double { sumAmount("PROMPT_CACHE_HIT_TOKEN") }
    public var cacheMissTokens: Double { sumAmount("PROMPT_CACHE_MISS_TOKEN") }
    public var responseTokens: Double { sumAmount("RESPONSE_TOKEN") }
    public var totalRequests: Int { amountModels.reduce(0) { $0 + $1.requests } }

    // MARK: - 按日查询

    public func cost(on date: Date) -> Double {
        let key = Self.dayKey(date)
        guard let day = costDays.first(where: { $0.date == key }) else { return 0 }
        return day.data.reduce(0) { $0 + $1.usage.reduce(0) { $0 + $1.value } }
    }

    public func tokens(on date: Date) -> (requests: Int, response: Double, cacheHit: Double, cacheMiss: Double) {
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

    /// 平台统计口径时区：北京时间（UTC+8）
    public static let platformTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    /// 平台按北京时间（UTC+8）计日与计月；App 统一用此时区判定「今日/本月」，
    /// 避免用户本地时区 ≠ UTC+8 时（跨时区旅行等）出现日期错位
    public static let platformCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = platformTimeZone
        return calendar
    }()

    public static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = platformTimeZone
        return formatter
    }()

    // MARK: - by_api_key 序列聚合

    /// 把 by_api_key 的天桶序列聚合成 MonthUsage。
    /// - startTs/endTs：查询窗口（Unix 秒），窗口外的桶会被忽略（防御越界数据）；
    ///   year/month 取自 startTs，调用方需保证 startTs 为本月 1 日
    /// - tzSeconds：桶所属时区的秒偏移（UTC+8 = 28800），决定日期归属与年月
    /// - 费用只聚合 data 中第一个币种分组；若平台未来返回多币种需扩展，当前不混加
    public static func aggregated(
        startTs: Int,
        endTs: Int,
        tzSeconds: Int,
        amountData: APIKeyAmountData?,
        costData: APIKeyCostData?
    ) -> MonthUsage {
        let timeZone = TimeZone(secondsFromGMT: tzSeconds) ?? platformTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        let startDate = Date(timeIntervalSince1970: Double(startTs))
        let year = calendar.component(.year, from: startDate)
        let month = calendar.component(.month, from: startDate)

        func dayString(_ ts: Int) -> String {
            formatter.string(from: Date(timeIntervalSince1970: Double(ts)))
        }
        func inWindow(_ ts: Int) -> Bool { ts >= startTs && ts < endTs }

        // 1. token/请求：day -> model -> type -> value
        var amountByDay: [String: [String: [String: Double]]] = [:]
        var amountByModel: [String: [String: Double]] = [:]
        for series in amountData?.series ?? [] {
            for bucket in series.buckets where inWindow(bucket.time) {
                let day = dayString(bucket.time)
                for (type, value) in bucket.usage {
                    amountByDay[day, default: [:]][series.model, default: [:]][type, default: 0] += value
                    amountByModel[series.model, default: [:]][type, default: 0] += value
                }
            }
        }

        // 2. 费用：只取第一个币种分组，day -> model -> 金额（统一记为 COST 类型）
        var costByDay: [String: [String: Double]] = [:]
        var costByModel: [String: Double] = [:]
        if let group = costData?.data.first {
            for series in group.series {
                for bucket in series.buckets where inWindow(bucket.time) {
                    let day = dayString(bucket.time)
                    let value = Double(bucket.cost) ?? 0
                    costByDay[day, default: [:]][series.model, default: 0] += value
                    costByModel[series.model, default: 0] += value
                }
            }
        }

        // 3. 组装（key 与 model 均排序，保证输出稳定）
        let amountDays = amountByDay.keys.sorted().map { day -> UsageDay in
            UsageDay(date: day, data: amountByDay[day]!.keys.sorted().map { model in
                ModelUsage(model: model, usage: amountByDay[day]![model]!.sorted { $0.key < $1.key }
                    .map { UsageItem(type: $0.key, amount: String($0.value)) })
            })
        }
        let amountModels = amountByModel.keys.sorted().map { model in
            ModelUsage(model: model, usage: amountByModel[model]!.sorted { $0.key < $1.key }
                .map { UsageItem(type: $0.key, amount: String($0.value)) })
        }
        let costDays = costByDay.keys.sorted().map { day -> UsageDay in
            UsageDay(date: day, data: costByDay[day]!.keys.sorted().map { model in
                ModelUsage(model: model, usage: [UsageItem(type: "COST", amount: String(costByDay[day]![model]!))])
            })
        }
        let costModels = costByModel.keys.sorted().map { model in
            ModelUsage(model: model, usage: [UsageItem(type: "COST", amount: String(costByModel[model]!))])
        }

        return MonthUsage(
            year: year,
            month: month,
            amountModels: amountModels,
            costModels: costModels,
            costDays: costDays,
            amountDays: amountDays
        )
    }
}

// MARK: - 数据可信度状态（托盘/悬浮窗/错误提示共用，保证一致）

public enum DataStatus: Equatable {
    case notLoggedIn  // 未登录
    case loading      // 已登录但尚无数据
    case fresh        // 最新数据，无错误
    case stale        // 刷新失败，正在显示旧数据
    case error        // 错误且无数据
    case tokenExpired // 登录已过期
}

/// 数据状态判定（纯函数，可测）
public func dataStatus(token: String?, tokenExpired: Bool, hasData: Bool, hasError: Bool) -> DataStatus {
    if token?.isEmpty ?? true { return .notLoggedIn }
    if tokenExpired { return .tokenExpired }
    if hasError { return hasData ? .stale : .error }
    if hasData { return .fresh }
    return .loading
}

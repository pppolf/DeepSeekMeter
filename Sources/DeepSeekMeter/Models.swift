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

// MARK: - by_api_key 用量（实时接口：usage/by_api_key/amount、usage/by_api_key/cost）
// 参数 start/end 为 Unix 秒，tz 为秒偏移（UTC+8 = 28800），bucket 传 86400 按天分桶；
// 与 usage/amount、usage/cost（延迟数小时～次日）不同，该接口数据实时

/// usage/by_api_key/amount 的 biz_data
struct APIKeyAmountData: Decodable {
    let start: Int
    let end: Int
    let bucket: Int
    let models: [String]
    let series: [APIKeyAmountSeries]
}

struct APIKeyAmountSeries: Decodable {
    let apiKey: APIKeyInfo
    let model: String
    let buckets: [APIKeyUsageBucket]
}

/// usage/by_api_key/cost 的 biz_data
struct APIKeyCostData: Decodable {
    let start: Int
    let end: Int
    let bucket: Int
    let models: [String]
    let data: [APIKeyCostGroup]
}

struct APIKeyCostGroup: Decodable {
    let currency: String
    let series: [APIKeyCostSeries]
}

struct APIKeyCostSeries: Decodable {
    let apiKey: APIKeyInfo
    let model: String
    let buckets: [APIKeyCostBucket]
}

struct APIKeyInfo: Decodable {
    let trackingId: String
    let name: String
    let sensitiveId: String
    let valid: Bool
}

/// 按天桶的 token 用量：type -> 数值（REQUEST / RESPONSE_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN）
/// 注意：真实响应中值为 JSON 数字（非字符串），必须用 Double 解码
struct APIKeyUsageBucket: Decodable {
    let time: Int
    let usage: [String: Double]
}

/// 按天桶的费用
struct APIKeyCostBucket: Decodable {
    let time: Int
    let cost: String
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

    /// 平台统计口径时区：北京时间（UTC+8）。macOS 14+ 系统内置该时区，无需回退；
    /// 已通过真实响应验证 usage/by_api_key/* 的桶时间按北京时间计日
    static let platformTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    /// 平台按北京时间（UTC+8）计日与计月；App 统一用此时区判定「今日/本月」，
    /// 避免用户本地时区 ≠ UTC+8 时（跨时区旅行等）出现日期错位
    static let platformCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = platformTimeZone
        return calendar
    }()

    static let dayFormatter: DateFormatter = {
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
    /// - 费用只聚合 data 中第一个币种分组（与 usage/cost 旧实现「取第一个」一致）；
    ///   若平台未来返回多币种需扩展，当前不混加
    static func aggregated(
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

enum DataStatus: Equatable {
    case notLoggedIn  // 未登录
    case loading      // 已登录但尚无数据
    case fresh        // 最新数据，无错误
    case stale        // 刷新失败，正在显示旧数据
    case error        // 错误且无数据
    case tokenExpired // 登录已过期
}

/// 数据状态判定（纯函数，可测）
func dataStatus(token: String?, tokenExpired: Bool, hasData: Bool, hasError: Bool) -> DataStatus {
    if token?.isEmpty ?? true { return .notLoggedIn }
    if tokenExpired { return .tokenExpired }
    if hasError { return hasData ? .stale : .error }
    if hasData { return .fresh }
    return .loading
}

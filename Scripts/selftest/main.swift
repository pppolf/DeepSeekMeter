import Foundation

// 轻量自测（不依赖 XCTest，命令行工具环境可直接运行）
var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("✅ \(name)")
    } else {
        failures += 1
        print("❌ \(name)")
    }
}

// 1. 格式化与币种符号
check(format(110.0) == "110.00", "format(110.0) -> 110.00")
check(format(0.35) == "0.35", "format(0.35) -> 0.35")
check(format(1234.5) == "1234.5", "format(1234.5) -> 1234.5")
check(currencySymbol("CNY") == "¥", "CNY -> ¥")
check(currencySymbol("USD") == "$", "USD -> $")
check(currencySymbol("EUR") == "€", "EUR -> €")
check(currencySymbol("HKD") == "HK$", "HKD -> HK$")
check(currencySymbol("GBP") == "£", "GBP -> £")
check(currencySymbol("XXX") == "XXX", "未知币种原样返回")

// 1.5 平台时区对齐：北京时间（UTC+8）计日，与 usage/cost、usage/amount 的 days 口径一致
// 用例 1（跨日边界）：UTC 8/14 16:30 即北京时间 8/15 00:30，必须归入 8/15（本地时区为 UTC 时会错位成 8/14）
let cnMidnight = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 8, day: 14, hour: 16, minute: 30))!
check(MonthUsage.dayFormatter.string(from: cnMidnight) == "2026-08-15", "UTC 8/14 16:30 按北京时间归入 8/15")
// 用例 2（当日末尾）：北京 8/15 23:30 仍属 8/15（本地时区快于 UTC+8 时会错位成 8/16）
let shLate = Calendar(identifier: .gregorian)
    .date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Shanghai"), year: 2026, month: 8, day: 15, hour: 23, minute: 30))!
check(MonthUsage.dayFormatter.string(from: shLate) == "2026-08-15", "北京 8/15 23:30 仍归入 8/15")

func XCTUnwrapSafe<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "unwrap", code: 1) }
    return value
}

func PopoverViewHelpersCountString(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

// 2. usage/amount 解码（真实返回结构）
let amountJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_TOKEN","amount":"0"},{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"311932800"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1584089"},{"type":"RESPONSE_TOKEN","amount":"950284"},{"type":"REQUEST","amount":"1130"}]}],"days":[{"date":"2026-08-01","data":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100"},{"type":"RESPONSE_TOKEN","amount":"50"},{"type":"REQUEST","amount":"2"}]}]}]}}}
"""
do {
    struct AmountBiz: Decodable { let bizData: UsageData }
    struct AmountResp: Decodable { let code: Int; let data: AmountBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(AmountResp.self, from: Data(amountJSON.utf8))
    check(resp.code == 0, "amount 外层 code")
    let usage = try XCTUnwrapSafe(resp.data?.bizData)
    check(usage.total.count == 1, "amount 模型数")
    let model = usage.total[0]
    check(model.model == "deepseek-v4-pro", "amount 模型名")
    check(abs(model.value(for: "PROMPT_CACHE_HIT_TOKEN") - 311932800) < 1, "amount 缓存命中")
    check(abs(model.value(for: "RESPONSE_TOKEN") - 950284) < 1, "amount 输出 token")
    check(model.requests == 1130, "amount 请求数")
    check(usage.days?.count == 1, "amount days")
    if let day = usage.days?.first {
        check(day.date == "2026-08-01", "amount 日期")
        check(day.data[0].requests == 2, "amount 当日请求")
    }
} catch {
    check(false, "amount 解码抛错：\(error)")
}

// 3. usage/cost 解码（biz_data 是数组）
let costJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":[{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"7.7983200000000000"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"4.7522670000000000"},{"type":"RESPONSE_TOKEN","amount":"5.7017040000000000"}]}],"days":[]}]}}
"""
do {
    struct CostBiz: Decodable { let bizData: [UsageData] }
    struct CostResp: Decodable { let code: Int; let data: CostBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(CostResp.self, from: Data(costJSON.utf8))
    let data = try XCTUnwrapSafe(resp.data?.bizData.first)
    let total = data.total[0].usage.reduce(0) { $0 + $1.value }
    check(abs(total - 18.252291) < 0.001, "cost 费用合计 18.252291")
} catch {
    check(false, "cost 解码抛错：\(error)")
}

// 4. get_user_summary 解码（snake_case）
let summaryJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[{"currency":"CNY","balance":"40.2492316400000000","token_estimation":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"0","token_estimation":"0"}],"total_costs":[{"currency":"CNY","amount":"19.7507683600000000"}]}}}
"""
do {
    struct SummaryBiz: Decodable { let bizData: UserSummary }
    struct SummaryResp: Decodable { let code: Int; let data: SummaryBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(SummaryResp.self, from: Data(summaryJSON.utf8))
    let summary = try XCTUnwrapSafe(resp.data?.bizData)
    check(abs(summary.normalWallets[0].value - 40.24923164) < 0.0001, "summary 余额 40.25")
    check(abs(summary.totalCosts[0].value - 19.75076836) < 0.0001, "summary 累计消费 19.75")
} catch {
    check(false, "summary 解码抛错：\(error)")
}

// 5. 格式化工具
check(format(311932800.0) == "311932800.0", "大数格式化")
check(PopoverViewHelpersCountString(1130) == "1,130", "千分位")

// 6. biz_code != 0 解码（业务错误识别）
let bizErrJSON = """
{"code":0,"msg":"","data":{"biz_code":10001,"biz_msg":"业务错误","biz_data":null}}
"""
do {
    struct BizErrBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: UsageData? }
    struct BizErrResp: Decodable { let code: Int; let data: BizErrBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(BizErrResp.self, from: Data(bizErrJSON.utf8))
    check(resp.data?.bizCode == 10001, "biz_code 非 0 正确解码")
} catch {
    check(false, "biz_code 解码抛错：\(error)")
}

// 7. 空 data / 空 biz_data
let emptyDataJSON = """
{"code":0,"msg":"","data":null}
"""
do {
    struct EmptyBiz: Decodable { let bizData: UsageData? }
    struct EmptyResp: Decodable { let code: Int; let data: EmptyBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(EmptyResp.self, from: Data(emptyDataJSON.utf8))
    check(resp.data == nil, "空 data 解码为 nil")
} catch {
    check(false, "空 data 解码抛错：\(error)")
}

let emptyBizDataJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":null}}
"""
do {
    struct EmptyBiz2: Decodable { let bizData: UsageData? }
    struct EmptyResp2: Decodable { let code: Int; let data: EmptyBiz2? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(EmptyResp2.self, from: Data(emptyBizDataJSON.utf8))
    check(resp.data != nil && resp.data?.bizData == nil, "空 biz_data 解码为 nil")
} catch {
    check(false, "空 biz_data 解码抛错：\(error)")
}

// 8. 数据可信度状态判定
check(dataStatus(token: "", tokenExpired: false, hasData: false, hasError: false) == .notLoggedIn, "空 token 未登录")
check(dataStatus(token: "tok", tokenExpired: true, hasData: true, hasError: false) == .tokenExpired, "登录过期优先于旧数据")
check(dataStatus(token: "tok", tokenExpired: false, hasData: true, hasError: true) == .stale, "有数据有错误为 stale")
check(dataStatus(token: "tok", tokenExpired: false, hasData: true, hasError: false) == .fresh, "有数据无错误为 fresh")
check(dataStatus(token: "tok", tokenExpired: false, hasData: false, hasError: true) == .error, "无数据有错误为 error")
check(dataStatus(token: "tok", tokenExpired: false, hasData: false, hasError: false) == .loading, "已登录无数据为 loading")

// 9. 空钱包（UserSummary normal_wallets 为空）
let emptyWalletJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[],"bonus_wallets":[],"total_costs":[]}}}
"""
do {
    struct SummaryBiz2: Decodable { let bizData: UserSummary }
    struct SummaryResp2: Decodable { let code: Int; let data: SummaryBiz2? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let resp = try decoder.decode(SummaryResp2.self, from: Data(emptyWalletJSON.utf8))
    check(resp.data?.bizData.normalWallets.isEmpty == true, "空钱包正确解码")
} catch {
    check(false, "空钱包解码抛错：\(error)")
}

// 10. by_api_key 实时接口：解码 + 聚合（start/end 为 Unix 秒，tz=28800，bucket=86400 按天）
// 时间戳：1785513600 = 北京 8/1 00:00，1785600000 = 北京 8/2 00:00
let byKeyAmountJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"usage":{"REQUEST":"2","RESPONSE_TOKEN":"100"}},{"time":1785600000,"usage":{"REQUEST":"5","RESPONSE_TOKEN":"200"}}]}]}}}
"""
let byKeyCostJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.5"},{"time":1785600000,"cost":"2.5"}]}]}]}}}
"""
do {
    struct AKBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyAmountData }
    struct AKResp: Decodable { let code: Int; let data: AKBiz? }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let amountResp = try decoder.decode(AKResp.self, from: Data(byKeyAmountJSON.utf8))
    let amountData = amountResp.data?.bizData
    check(amountData?.series.count == 1, "by_api_key amount series 数")
    check(amountData?.series.first?.buckets.count == 2, "by_api_key amount 桶数")
    check(amountData?.series.first?.apiKey.name == "test-key" && amountData?.series.first?.apiKey.trackingId == "test-tracking", "by_api_key api_key 元信息（占位符）")

    struct CKBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyCostData }
    struct CKResp: Decodable { let code: Int; let data: CKBiz? }
    let costResp = try decoder.decode(CKResp.self, from: Data(byKeyCostJSON.utf8))
    let costData = costResp.data?.bizData
    check(costData?.data.first?.currency == "CNY", "by_api_key cost 币种")

    // 聚合：按天 + 按模型
    let usage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: amountData, costData: costData)
    check(usage.year == 2026 && usage.month == 8, "聚合年月（北京时间）")
    check(usage.amountDays.count == 2, "聚合 amount 天数")
    check(usage.amountDays.first?.date == "2026-08-01", "聚合 amount 首日")
    check(usage.amountDays.last?.date == "2026-08-02", "聚合 amount 末日")
    check(usage.amountModels.first?.requests == 7, "聚合本月请求 2+5")
    check(abs((usage.amountModels.first?.value(for: "RESPONSE_TOKEN") ?? 0) - 300) < 0.001, "聚合本月输出 100+200")
    check(usage.costDays.count == 2, "聚合 cost 天数")
    check(abs(usage.cost(on: Date(timeIntervalSince1970: 1785513600)) - 1.5) < 0.001, "聚合 8/1 费用 1.5")
    check(abs(usage.totalCost - 4.0) < 0.001, "聚合本月费用 1.5+2.5")
    // 空数据聚合不崩溃
    let emptyUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: nil, costData: nil)
    check(emptyUsage.amountDays.isEmpty && emptyUsage.totalCost == 0, "空数据聚合为 0")
    // 边界 1：窗口外（下月）的桶被忽略；窗口内 8/31 的桶正常计入
    // 1788105600 = 北京 8/31 00:00，1788192000 = 北京 9/1 00:00（= endTs，窗口外）
    let monthEdgeJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1788105600,"usage":{"REQUEST":"3"}},{"time":1788192000,"usage":{"REQUEST":"99"}}]}]}}}
"""
    struct EdgeBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyAmountData }
    struct EdgeResp: Decodable { let code: Int; let data: EdgeBiz? }
    let edge = try decoder.decode(EdgeResp.self, from: Data(monthEdgeJSON.utf8)).data?.bizData
    let edgeUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: edge, costData: nil)
    check(edgeUsage.amountDays.count == 1 && edgeUsage.amountDays.first?.date == "2026-08-31", "窗口内 8/31 桶计入")
    check(edgeUsage.amountModels.first?.requests == 3, "窗口外 9/1 桶被忽略（99 不计入）")
    // 边界 2：多币种分组只聚合第一个（CNY），USD 组不混加
    let multiCurrencyJSON = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.0"}]}]},{"currency":"USD","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"5.0"}]}]}]}}}
"""
    struct MCBiz: Decodable { let bizCode: Int; let bizMsg: String; let bizData: APIKeyCostData }
    struct MCResp: Decodable { let code: Int; let data: MCBiz? }
    let mc = try decoder.decode(MCResp.self, from: Data(multiCurrencyJSON.utf8)).data?.bizData
    let mcUsage = MonthUsage.aggregated(startTs: 1785513600, endTs: 1788192000, tzSeconds: 28800, amountData: nil, costData: mc)
    check(abs(mcUsage.totalCost - 1.0) < 0.001, "多币种只聚合第一个分组（CNY 1.0，USD 5.0 不混加）")
} catch {
    check(false, "by_api_key 解码抛错：\(error)")
}

if failures > 0 {
    print("\n❌ \(failures) 项未通过")
    exit(1)
}
print("\n✅ 全部通过")
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
check(currencySymbol("XXX") == "XXX", "未知币种原样返回")

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

if failures > 0 {
    print("\n❌ \(failures) 项未通过")
    exit(1)
}
print("\n✅ 全部通过")
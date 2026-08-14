using System.Text.Json;
using DeepSeekMeter.Core;

// 轻量自测（对齐 Scripts/selftest/main.swift，不依赖 xUnit / XCTest）
var failures = 0;

void Check(bool cond, string name)
{
    if (cond)
    {
        Console.WriteLine($"✅ {name}");
    }
    else
    {
        failures++;
        Console.WriteLine($"❌ {name}");
    }
}

// 1. 格式化与币种符号
Check(Formatting.Format(110.0) == "110.00", "Format(110.0) -> 110.00");
Check(Formatting.Format(0.35) == "0.35", "Format(0.35) -> 0.35");
Check(Formatting.Format(1234.5) == "1234.5", "Format(1234.5) -> 1234.5");
Check(Formatting.CurrencySymbol("CNY") == "¥", "CNY -> ¥");
Check(Formatting.CurrencySymbol("USD") == "$", "USD -> $");
Check(Formatting.CurrencySymbol("EUR") == "€", "EUR -> €");
Check(Formatting.CurrencySymbol("XXX") == "XXX", "未知币种原样返回");

// 2. usage/amount 解码（真实返回结构，biz_data 是对象）
var amountJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_TOKEN","amount":"0"},{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"311932800"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1584089"},{"type":"RESPONSE_TOKEN","amount":"950284"},{"type":"REQUEST","amount":"1130"}]}],"days":[{"date":"2026-08-01","data":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100"},{"type":"RESPONSE_TOKEN","amount":"50"},{"type":"REQUEST","amount":"2"}]}]}]}}}
""";
try
{
    var resp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<UsageData>>>(amountJson, Json.Options)!;
    Check(resp.Code == 0, "amount 外层 code");
    var usage = resp.Data?.BizData;
    Check(usage != null, "amount biz_data 非空");
    Check(usage!.Total.Count == 1, "amount 模型数");
    var model = usage.Total[0];
    Check(model.Model == "deepseek-v4-pro", "amount 模型名");
    Check(Math.Abs(model.ValueFor("PROMPT_CACHE_HIT_TOKEN") - 311932800) < 1, "amount 缓存命中");
    Check(Math.Abs(model.ValueFor("RESPONSE_TOKEN") - 950284) < 1, "amount 输出 token");
    Check(model.Requests == 1130, "amount 请求数");
    Check(usage.Days?.Count == 1, "amount days");
    var day = usage.Days![0];
    Check(day.Date == "2026-08-01", "amount 日期");
    Check(day.Data[0].Requests == 2, "amount 当日请求");
}
catch (Exception ex)
{
    Check(false, $"amount 解码抛错：{ex.Message}");
}

// 3. usage/cost 解码（biz_data 是数组，取第一个）
var costJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":[{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"7.7983200000000000"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"4.7522670000000000"},{"type":"RESPONSE_TOKEN","amount":"5.7017040000000000"}]}],"days":[]}]}}
""";
try
{
    var resp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<List<UsageData>>>>(costJson, Json.Options)!;
    var data = resp.Data?.BizData?.FirstOrDefault();
    Check(data != null, "cost biz_data 数组取第一个");
    var total = data!.Total.Sum(m => m.Usage.Sum(i => i.Value));
    Check(Math.Abs(total - 18.252291) < 0.001, $"cost 费用合计 18.252291（实际 {total}）");
}
catch (Exception ex)
{
    Check(false, $"cost 解码抛错：{ex.Message}");
}

// 4. get_user_summary 解码（snake_case）
var summaryJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[{"currency":"CNY","balance":"40.2492316400000000","token_estimation":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"0","token_estimation":"0"}],"total_costs":[{"currency":"CNY","amount":"19.7507683600000000"}]}}}
""";
try
{
    var resp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<UserSummary>>>(summaryJson, Json.Options)!;
    var summary = resp.Data?.BizData;
    Check(summary != null, "summary biz_data 非空");
    Check(Math.Abs(summary!.NormalWallets[0].Value - 40.24923164) < 0.0001, "summary 余额 40.25");
    Check(Math.Abs(summary.TotalCosts[0].Value - 19.75076836) < 0.0001, "summary 累计消费 19.75");
}
catch (Exception ex)
{
    Check(false, $"summary 解码抛错：{ex.Message}");
}

// 4b. 业务层 biz_code 非 0：应被识别为错误（不被当成成功数据）
var bizErrJson = """
{"code":0,"msg":"","data":{"biz_code":10001,"biz_msg":"业务层错误","biz_data":null}}
""";
try
{
    var bizResp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<UsageData>>>(bizErrJson, Json.Options)!;
    Check(bizResp.Data is not null && bizResp.Data.BizCode == 10001, "biz_code 非 0 正确解码");
    try
    {
        PlatformService.EnsureBizSuccess(bizResp.Data!.BizCode, bizResp.Data.BizMsg);
        Check(false, "biz_code 非 0 应抛 Api 异常");
    }
    catch (PlatformException ex)
    {
        Check(ex.ApiCode == 10001 && ex.Kind == PlatformErrorKind.Api, "biz_code 非 0 抛 Api(code=10001)");
    }
}
catch (Exception ex)
{
    Check(false, $"biz_code 样例抛错：{ex.Message}");
}

// 5. MonthUsage 聚合（本月汇总 / 按日查询）
var month = new MonthUsage
{
    Year = 2026,
    Month = 8,
    AmountModels =
    [
        new ModelUsage
        {
            Model = "deepseek-v4-pro",
            Usage =
            [
                new UsageItem { Type = "RESPONSE_TOKEN", Amount = "1000" },
                new UsageItem { Type = "PROMPT_CACHE_HIT_TOKEN", Amount = "5000" },
                new UsageItem { Type = "REQUEST", Amount = "10" },
            ],
        },
    ],
    CostModels =
    [
        new ModelUsage
        {
            Model = "deepseek-v4-pro",
            Usage = [new UsageItem { Type = "RESPONSE_TOKEN", Amount = "1.5" }],
        },
    ],
    CostDays = [],
    AmountDays =
    [
        new UsageDay
        {
            Date = "2026-08-01",
            Data =
            [
                new ModelUsage
                {
                    Model = "deepseek-v4-pro",
                    Usage =
                    [
                        new UsageItem { Type = "RESPONSE_TOKEN", Amount = "200" },
                        new UsageItem { Type = "REQUEST", Amount = "3" },
                    ],
                },
            ],
        },
    ],
};
Check(Math.Abs(month.TotalCost - 1.5) < 0.001, "MonthUsage 本月费用合计");
Check(Math.Abs(month.ResponseTokens - 1000) < 0.001, "MonthUsage 本月输出 token");
Check(Math.Abs(month.CacheHitTokens - 5000) < 0.001, "MonthUsage 本月缓存命中");
Check(month.TotalRequests == 10, "MonthUsage 本月请求数");
var today = new DateTime(2026, 8, 1);
var tokens = month.TokensOn(today);
Check(tokens.Requests == 3, "MonthUsage 当日请求");
Check(Math.Abs(tokens.Response - 200) < 0.001, "MonthUsage 当日输出");
Check(Math.Abs(month.CostOn(today) - 0) < 0.001, "MonthUsage 当日费用（无数据返回 0）");
Check(Math.Abs(month.CostOn(new DateTime(2026, 8, 2)) - 0) < 0.001, "MonthUsage 无数据日期返回 0");

// 5b. 空 AmountDays（无用量 / 空 days / 新账号）不得抛异常
var emptyMonth = new MonthUsage
{
    Year = 2026,
    Month = 8,
    AmountModels = [],
    CostModels = [],
    CostDays = [],
    AmountDays = [],
};
try
{
    Check(emptyMonth.LatestAmountDate is null, "空 AmountDays 的 LatestAmountDate 为 null");
    Check(Math.Abs(emptyMonth.TotalCost - 0) < 0.001, "空 AmountDays 本月费用为 0");
    Check(emptyMonth.TotalRequests == 0, "空 AmountDays 请求数为 0");
    var emptyTokens = emptyMonth.TokensOn(DateTime.Now);
    Check(emptyTokens.Requests == 0 && emptyTokens.Response == 0, "空 AmountDays TokensOn 返回 0");
}
catch (Exception ex)
{
    Check(false, $"空 AmountDays 抛异常：{ex.Message}");
}

// 6. 设置持久化（临时目录往返）
var tmpFile = Path.Combine(Path.GetTempPath(), $"dsm-settings-{Guid.NewGuid():N}.json");
try
{
    var store = new SettingsStore(tmpFile);
    store.PlatformToken = "test-token";
    store.PlatformUserName = "test@example.com";
    store.RefreshInterval = 300;
    store.LaunchAtLogin = true;

    var reloaded = new SettingsStore(tmpFile);
    Check(reloaded.PlatformToken == "test-token", "设置往返：Token");
    Check(reloaded.PlatformUserName == "test@example.com", "设置往返：用户名");
    Check(Math.Abs(reloaded.RefreshInterval - 300) < 0.001, "设置往返：刷新间隔");
    Check(reloaded.LaunchAtLogin, "设置往返：开机自启");

    reloaded.ClearPlatformToken();
    Check(reloaded.PlatformToken == "" && reloaded.PlatformUserName == "", "清除 Token");
}
finally
{
    if (File.Exists(tmpFile)) File.Delete(tmpFile);
    if (File.Exists(tmpFile + ".tmp")) File.Delete(tmpFile + ".tmp");
}

// 7. 格式化工具
Check(Formatting.Format(311932800.0) == "311932800.0", "大数格式化");
Check(Formatting.CountString(1130) == "1,130", "千分位");
Check(Formatting.TokenString(123456789) == "1.23亿", "Token 亿单位");
Check(Formatting.TokenString(23456) == "2.3万", "Token 万单位");
Check(Formatting.ModelDisplayName("deepseek-v4-pro") == "v4-pro", "模型显示名");

// 8. 数据可信度状态（旧数据掩盖错误的判定）
Check(DataState.Evaluate("", false, false, false) == DataStatus.NotLoggedIn, "空 Token 未登录");
Check(DataState.Evaluate(null, false, false, false) == DataStatus.NotLoggedIn, "null Token 未登录");
Check(DataState.Evaluate("tok", true, true, false) == DataStatus.TokenExpired, "登录过期优先于旧数据");
Check(DataState.Evaluate("tok", true, false, true) == DataStatus.TokenExpired, "登录过期优先于普通错误");
Check(DataState.Evaluate("tok", false, true, false) == DataStatus.Fresh, "有数据无错误为最新");
Check(DataState.Evaluate("tok", false, true, true) == DataStatus.Stale, "有数据有错误为旧数据（Stale）");
Check(DataState.Evaluate("tok", false, false, true) == DataStatus.Error, "无数据有错误为异常");
Check(DataState.Evaluate("tok", false, false, false) == DataStatus.Loading, "已登录无数据为加载中");

// 9. 非人民币币种（费用展示不写死 ¥）
Check(Formatting.CurrencySymbol("USD") == "$", "USD -> $");
Check(Formatting.CurrencySymbol("EUR") == "€", "EUR -> €");
Check(Formatting.CurrencySymbol("CNY") == "¥", "CNY -> ¥");
Check(Formatting.Format(12.5) == "12.50", "USD 金额格式化");
Check($"累计 {Formatting.CurrencySymbol("USD")}{Formatting.Format(12.5)}" == "累计 $12.50", "USD 费用文案");

// 10. 空 data / 空 biz_data / 非法刷新间隔 / 设置保存失败
var emptyDataResp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<UsageData>>>(
    """{"code":0,"msg":"","data":null}""", Json.Options)!;
Check(emptyDataResp.Data is null, "空 data 解码为 null");

var emptyBizResp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<UsageData>>>(
    """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":null}}""", Json.Options)!;
Check(emptyBizResp.Data is not null && emptyBizResp.Data.BizData is null, "空 biz_data 解码为 null");

var badIntervalFile = Path.Combine(Path.GetTempPath(), $"dsm-badinterval-{Guid.NewGuid():N}.json");
try
{
    File.WriteAllText(badIntervalFile, """{"RefreshInterval": 3}""");
    var s = new SettingsStore(badIntervalFile);
    Check(Math.Abs(s.RefreshInterval - 60) < 0.001, "非法刷新间隔回退 60 秒");
    File.WriteAllText(badIntervalFile, """{"RefreshInterval": 300}""");
    var s2 = new SettingsStore(badIntervalFile);
    Check(Math.Abs(s2.RefreshInterval - 300) < 0.001, "合法刷新间隔保留 300 秒");
}
finally
{
    if (File.Exists(badIntervalFile)) File.Delete(badIntervalFile);
}

// 设置保存失败：把设置文件路径指向一个已存在的目录，File.Move 到目录会失败
var dirAsFile = Path.Combine(Path.GetTempPath(), $"dsm-dir-{Guid.NewGuid():N}");
Directory.CreateDirectory(dirAsFile);
try
{
    var store3 = new SettingsStore(dirAsFile);
    var failed = false;
    store3.SaveFailed += _ => failed = true;
    store3.RefreshInterval = 300; // 触发保存
    Check(failed, "设置保存失败触发 SaveFailed 事件");
    Check(!store3.LastSaveSucceeded, "设置保存失败后 LastSaveSucceeded 为 false");
}
finally
{
    if (Directory.Exists(dirAsFile)) Directory.Delete(dirAsFile, true);
}

// 11. 趋势日期排序与未来过滤（用真实今天，不用数据最大日期）
var trendToday = DateTime.Today;
var tomorrow = trendToday.AddDays(1).ToString("yyyy-MM-dd");
var sortedDates = new List<UsageDay>
{
    new() { Date = "2026-08-03", Data = [] },
    new() { Date = "2026-08-01", Data = [] },
    new() { Date = tomorrow, Data = [] }, // 未来日期应被过滤
};
var sorted = sortedDates
    .Where(d => string.CompareOrdinal(d.Date, trendToday.ToString("yyyy-MM-dd")) <= 0)
    .OrderBy(d => d.Date, StringComparer.Ordinal)
    .ToList();
Check(sorted.Count == 2, "未来日期被过滤");
Check(sorted[0].Date == "2026-08-01" && sorted[1].Date == "2026-08-03", "日期升序排序");

if (failures > 0)
{
    Console.WriteLine($"\n❌ {failures} 项未通过");
    return 1;
}
Console.WriteLine("\n✅ 全部通过");
return 0;

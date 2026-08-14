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

if (failures > 0)
{
    Console.WriteLine($"\n❌ {failures} 项未通过");
    return 1;
}
Console.WriteLine("\n✅ 全部通过");
return 0;

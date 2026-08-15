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
    Check(store.TrySetPlatformCredentials("test-token", "test@example.com", out _), "原子设置凭据成功");
    store.RefreshInterval = 300;
    store.LaunchAtLogin = true;

    var reloaded = new SettingsStore(tmpFile);
    Check(reloaded.PlatformToken == "test-token", "设置往返：Token");
    Check(reloaded.PlatformUserName == "test@example.com", "设置往返：用户名");
    Check(Math.Abs(reloaded.RefreshInterval - 300) < 0.001, "设置往返：刷新间隔");
    Check(reloaded.LaunchAtLogin, "设置往返：开机自启");

    Check(reloaded.TryClearPlatformCredentials(out _), "原子清除凭据成功");
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
    store3.RefreshInterval = 300; // 触发保存失败
    Check(failed, "设置保存失败触发 SaveFailed 事件");
    Check(Math.Abs(store3.RefreshInterval - 60) < 0.001, "保存失败后刷新间隔回滚");

    // 凭据落盘失败不会报告成功
    var setOk = store3.TrySetPlatformCredentials("secret", "u@x.com", out var setErr);
    Check(!setOk, "凭据落盘失败返回 false");
    Check(!string.IsNullOrEmpty(setErr), "凭据落盘失败返回脱敏错误");
    Check(store3.PlatformToken == "", "凭据落盘失败不更新内存 Token");
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

// 12. Token 显示单位（紧凑格式 + 完整千分位）
Check(Formatting.TokenString(0) == "0", "TokenString(0) 显示 0");
Check(Formatting.TokenString(5000) == "5000.0", "TokenString 小于 1 万（千位 1 位小数）");
Check(Formatting.TokenString(500) == "500.00", "TokenString 小于 1 千（两位小数）");
Check(Formatting.TokenString(14000) == "1.4万", "TokenString 1.4万");
Check(Formatting.TokenString(350000000) == "3.50亿", "TokenString 3.50亿");
Check(Formatting.TokenFullString(84217000) == "84,217,000", "TokenFullString 完整千分位");
Check(Formatting.TokenFullString(0) == "0", "TokenFullString(0) 为 0");
Check($"今日 {Formatting.TokenString(14000)} Token" == "今日 1.4万 Token", "今日 Token 文案");
Check($"峰值 {Formatting.TokenString(288000)} Token" == "峰值 28.8万 Token", "峰值 Token 文案");
Check($"84,217,000 Token" == $"{Formatting.TokenFullString(84217000)} Token", "悬停详情完整数值文案");

// 13. 趋势指标名称映射（输出/缓存命中/总量）
Check(TrendMetric.Output.Label() == "输出", "指标名 输出");
Check(TrendMetric.CacheHit.Label() == "缓存命中", "指标名 缓存命中");
Check(TrendMetric.Total.Label() == "总量", "指标名 总量");
Check(TrendMetric.Output.Description() == "模型生成的输出 Token", "指标说明 输出");
Check(TrendMetric.CacheHit.Description() == "从缓存直接复用的输入 Token", "指标说明 缓存命中");
Check(TrendMetric.Total.Description() == "输出 + 缓存命中 + 缓存未命中 Token", "指标说明 总量");

// 14. Token DPAPI 加密往返与设置文件不落明文
var encToken = "test-token-value-123";
var encBytes = TokenProtector.Protect(encToken);
Check(TokenProtector.Unprotect(encBytes) == encToken, "Token 加密解密往返");
Check(!Convert.ToBase64String(encBytes).Contains(encToken), "密文不含明文 Token");

var encFile = Path.Combine(Path.GetTempPath(), $"dsm-enc-{Guid.NewGuid():N}.json");
try
{
    var store = new SettingsStore(encFile);
    store.TrySetPlatformCredentials(encToken, "", out _);
    var json = File.ReadAllText(encFile);
    Check(!json.Contains(encToken), "设置文件不含明文 Token");
    Check(json.Contains("PlatformTokenProtected"), "设置文件含加密字段 PlatformTokenProtected");
    Check(!json.Contains("\"PlatformToken\""), "设置文件不再写 PlatformToken 明文字段");

    // 旧明文配置自动迁移
    var legacyFile = Path.Combine(Path.GetTempPath(), $"dsm-legacy-{Guid.NewGuid():N}.json");
    try
    {
        File.WriteAllText(legacyFile, """{"PlatformToken":"legacy-plain-token","PlatformUserName":"u@x.com"}""");
        var migrated = new SettingsStore(legacyFile);
        Check(migrated.PlatformToken == "legacy-plain-token", "旧明文迁移后内存 Token 正确");
        var migratedJson = File.ReadAllText(legacyFile);
        Check(!migratedJson.Contains("legacy-plain-token"), "迁移后文件不含明文");
        Check(migratedJson.Contains("PlatformTokenProtected"), "迁移后含加密字段");
    }
    finally { if (File.Exists(legacyFile)) File.Delete(legacyFile); }

    // 损坏密文安全回退（不崩溃，Token 视为空 = 需要重新登录，且给出警告）
    var corruptFile = Path.Combine(Path.GetTempPath(), $"dsm-corrupt-{Guid.NewGuid():N}.json");
    try
    {
        File.WriteAllText(corruptFile, """{"PlatformTokenProtected":"!!not-base64!!"}""");
        var corrupt = new SettingsStore(corruptFile);
        Check(corrupt.PlatformToken == "", "损坏密文回退为空 Token");
        Check(!string.IsNullOrEmpty(corrupt.StartupWarning), "损坏密文给出需要重新登录警告");
    }
    finally { if (File.Exists(corruptFile)) File.Delete(corruptFile); }

    // 退出登录后 Token 无法恢复
    var clearFile = Path.Combine(Path.GetTempPath(), $"dsm-clear-{Guid.NewGuid():N}.json");
    try
    {
        var clear = new SettingsStore(clearFile);
        clear.TrySetPlatformCredentials("token-to-clear-456", "", out _);
        Check(clear.TryClearPlatformCredentials(out _), "退出登录清除凭据成功");
        var clearedJson = File.ReadAllText(clearFile);
        Check(!clearedJson.Contains("token-to-clear-456"), "退出登录后文件不含 Token");
        Check(!clearedJson.Contains("PlatformTokenProtected"), "退出登录后无加密字段");
        Check(clear.PlatformToken == "", "退出登录后内存 Token 为空");
    }
    finally
    {
        if (File.Exists(clearFile)) File.Delete(clearFile);
        if (File.Exists(clearFile + ".tmp")) File.Delete(clearFile + ".tmp");
    }
}
finally
{
    if (File.Exists(encFile)) File.Delete(encFile);
    if (File.Exists(encFile + ".tmp")) File.Delete(encFile + ".tmp");
}

// 15. URL 安全校验（内嵌页仅 https + deepseek.com 真实域名；外链仅 https）
Check(UrlSafety.IsAllowedDeepSeekUrl("https://platform.deepseek.com"), "合法子域名");
Check(UrlSafety.IsAllowedDeepSeekUrl("https://deepseek.com"), "合法主域名");
Check(UrlSafety.IsAllowedDeepSeekUrl("https://platform.deepseek.com/usage"), "合法子域名+路径");
Check(!UrlSafety.IsAllowedDeepSeekUrl("http://platform.deepseek.com"), "HTTP 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("https://deepseek.com.example.com"), "伪造后缀域名拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("https://notdeepseek.com"), "相似域名拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("https://deepseek.com.evil.com"), "攻击后缀拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("javascript:alert(1)"), "javascript 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("file:///etc/passwd"), "file 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("data:text/html,hi"), "data 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("ms-settings:bluetooth"), "ms-settings 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("shell:startup"), "shell 拒绝");
Check(!UrlSafety.IsAllowedDeepSeekUrl("not-a-url"), "无效 URL 拒绝");
Check(UrlSafety.IsAllowedExternalUrl("https://example.com"), "外链 https 允许");
Check(!UrlSafety.IsAllowedExternalUrl("http://example.com"), "外链 http 拒绝");
Check(!UrlSafety.IsAllowedExternalUrl("file:///c:/x"), "外链 file 拒绝");
Check(!UrlSafety.IsAllowedExternalUrl("javascript:x"), "外链 javascript 拒绝");
Check(!UrlSafety.IsAllowedExternalUrl("ms-settings:x"), "外链 ms-settings 拒绝");

// 16. by_api_key 实时接口：解码 + 聚合（start/end 为 Unix 秒，tz=28800，bucket=86400 按天）
// 时间戳：1785513600 = 北京 8/1 00:00，1785600000 = 北京 8/2 00:00
var byKeyAmountJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"usage":{"REQUEST":2,"RESPONSE_TOKEN":100}},{"time":1785600000,"usage":{"REQUEST":5,"RESPONSE_TOKEN":200}}]}]}}}
""";
var byKeyCostJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.5"},{"time":1785600000,"cost":"2.5"}]}]}]}}}
""";
try
{
    var amountResp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<ApiKeyAmountData>>>(byKeyAmountJson, Json.Options)!;
    var amountData = amountResp.Data?.BizData;
    Check(amountData?.Series.Count == 1, "by_api_key amount series 数");
    Check(amountData?.Series[0].Buckets.Count == 2, "by_api_key amount 桶数");
    Check(amountData?.Series[0].ApiKey.Name == "test-key" && amountData?.Series[0].ApiKey.TrackingId == "test-tracking", "by_api_key api_key 元信息（占位符）");

    var costResp = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<ApiKeyCostData>>>(byKeyCostJson, Json.Options)!;
    var costData = costResp.Data?.BizData;
    Check(costData?.Data[0].Currency == "CNY", "by_api_key cost 币种");

    var usage = MonthUsage.Aggregated(1785513600, 1788192000, 28800, amountData, costData);
    Check(usage.Year == 2026 && usage.Month == 8, "聚合年月（北京时间）");
    Check(usage.AmountDays.Count == 2, "聚合 amount 天数");
    Check(usage.AmountDays[0].Date == "2026-08-01", "聚合 amount 首日");
    Check(usage.AmountDays[1].Date == "2026-08-02", "聚合 amount 末日");
    Check(usage.AmountModels[0].Requests == 7, "聚合本月请求 2+5");
    Check(Math.Abs(usage.AmountModels[0].ValueFor("RESPONSE_TOKEN") - 300) < 0.001, "聚合本月输出 100+200");
    Check(usage.CostDays.Count == 2, "聚合 cost 天数");
    Check(Math.Abs(usage.CostOn(new DateTime(2026, 8, 1)) - 1.5) < 0.001, "聚合 8/1 费用 1.5");
    Check(Math.Abs(usage.TotalCost - 4.0) < 0.001, "聚合本月费用 1.5+2.5");

    // 空数据聚合不崩溃
    var emptyUsage = MonthUsage.Aggregated(1785513600, 1788192000, 28800, null, null);
    Check(emptyUsage.AmountDays.Count == 0 && Math.Abs(emptyUsage.TotalCost) < 0.001, "空数据聚合为 0");

    // 边界：窗口外（下月）桶被忽略；窗口内 8/31 桶计入
    var monthEdgeJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1788105600,"usage":{"REQUEST":3}},{"time":1788192000,"usage":{"REQUEST":99}}]}]}}}
""";
    var edgeData = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<ApiKeyAmountData>>>(monthEdgeJson, Json.Options)!.Data?.BizData;
    var edgeUsage = MonthUsage.Aggregated(1785513600, 1788192000, 28800, edgeData, null);
    Check(edgeUsage.AmountDays.Count == 1 && edgeUsage.AmountDays[0].Date == "2026-08-31", "窗口内 8/31 桶计入");
    Check(edgeUsage.AmountModels[0].Requests == 3, "窗口外 9/1 桶被忽略（99 不计入）");

    // 边界：多币种分组只聚合第一个（CNY），USD 组不混加
    var multiCurrencyJson = """
{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.0"}]}]},{"currency":"USD","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"5.0"}]}]}]}}}
""";
    var mcData = JsonSerializer.Deserialize<PlatformEnvelope<BizWrapper<ApiKeyCostData>>>(multiCurrencyJson, Json.Options)!.Data?.BizData;
    var mcUsage = MonthUsage.Aggregated(1785513600, 1788192000, 28800, null, mcData);
    Check(Math.Abs(mcUsage.TotalCost - 1.0) < 0.001, "多币种只聚合第一个分组（CNY 1.0，USD 5.0 不混加）");
}
catch (Exception ex)
{
    Check(false, $"by_api_key 解码/聚合抛错：{ex.Message}");
}

// 17. 明文迁移失败状态（.tmp 被目录占用导致写失败，保留旧明文并给出警告）
var migrateFailFile = Path.Combine(Path.GetTempPath(), $"dsm-migfail-{Guid.NewGuid():N}.json");
var migrateFailTmp = migrateFailFile + ".tmp";
try
{
    File.WriteAllText(migrateFailFile, """{"PlatformToken":"migrate-fail-token","PlatformUserName":"u@x.com"}""");
    Directory.CreateDirectory(migrateFailTmp); // 让 .tmp 路径成为目录，写文件失败
    var s = new SettingsStore(migrateFailFile);
    Check(s.PlatformToken == "", "迁移失败后 Token 为空");
    Check(!string.IsNullOrEmpty(s.StartupWarning), "迁移失败给出警告");
    Check(File.ReadAllText(migrateFailFile).Contains("migrate-fail-token"), "迁移失败保留旧明文文件");
}
finally
{
    if (Directory.Exists(migrateFailTmp)) Directory.Delete(migrateFailTmp, true);
    if (File.Exists(migrateFailFile)) File.Delete(migrateFailFile);
}

// 18. 超大 Token 数值格式化（不用 long 强转，避免溢出）
var huge = Formatting.TokenFullString(1e20);
Check(huge.Length > 0, "超大数值格式化非空");
Check(!huge.Contains("E+") && !huge.Contains("e+"), "超大数值不用科学计数法");
Check(Formatting.TokenFullString(84217000) == "84,217,000", "正常千分位不变");

if (failures > 0)
{
    Console.WriteLine($"\n❌ {failures} 项未通过");
    return 1;
}
Console.WriteLine("\n✅ 全部通过");
return 0;

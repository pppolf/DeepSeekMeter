using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeepSeekMeter.Core;

// MARK: - 余额信息（由平台 get_user_summary 构造，供 UI 展示）

/// <summary>余额信息。</summary>
public sealed class BalanceInfo : IEquatable<BalanceInfo>
{
    public string Currency { get; init; } = "CNY";
    public string TotalBalance { get; init; } = "0";
    public string GrantedBalance { get; init; } = "0";
    public string ToppedUpBalance { get; init; } = "0";

    public double Total => Parse(TotalBalance);
    public double Granted => Parse(GrantedBalance);
    public double ToppedUp => Parse(ToppedUpBalance);

    private static double Parse(string s) => double.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0;

    public bool Equals(BalanceInfo? other) =>
        other is not null &&
        Currency == other.Currency &&
        TotalBalance == other.TotalBalance &&
        GrantedBalance == other.GrantedBalance &&
        ToppedUpBalance == other.ToppedUpBalance;

    public override bool Equals(object? obj) => Equals(obj as BalanceInfo);
    public override int GetHashCode() => HashCode.Combine(Currency, TotalBalance, GrantedBalance, ToppedUpBalance);
}

// MARK: - 平台用量模型（platform.deepseek.com 私有接口，需登录 userToken）
// 响应包裹：{code, msg, data: {biz_code, biz_msg, biz_data}}
// 注意：biz_data 有时是对象、有时是数组，以真实响应为准（与 macOS 版一致）

/// <summary>通用平台响应外层：{code, msg, data}。</summary>
public sealed class PlatformEnvelope<T>
{
    [JsonPropertyName("code")] public int Code { get; set; }
    [JsonPropertyName("msg")] public string Msg { get; set; } = "";
    [JsonPropertyName("data")] public T? Data { get; set; }
}

/// <summary>data 的业务包装：{biz_code, biz_msg, biz_data}。</summary>
public sealed class BizWrapper<T>
{
    [JsonPropertyName("biz_code")] public int BizCode { get; set; }
    [JsonPropertyName("biz_msg")] public string BizMsg { get; set; } = "";
    [JsonPropertyName("biz_data")] public T? BizData { get; set; }
}

/// <summary>usage/amount 的 biz_data：{total, days}。</summary>
public sealed class UsageData
{
    [JsonPropertyName("total")] public List<ModelUsage> Total { get; set; } = [];
    [JsonPropertyName("days")] public List<UsageDay>? Days { get; set; }
}

/// <summary>单个模型的用量/费用条目。</summary>
public sealed class ModelUsage
{
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("usage")] public List<UsageItem> Usage { get; set; } = [];

    public double ValueFor(string type) =>
        Usage.FirstOrDefault(i => i.Type == type)?.Value ?? 0;

    public int Requests => (int)Math.Round(ValueFor("REQUEST"));
}

/// <summary>单条用量：PROMPT_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN / RESPONSE_TOKEN / REQUEST。</summary>
public sealed class UsageItem
{
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("amount")] public string Amount { get; set; } = "0";

    public double Value =>
        double.TryParse(Amount, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0;
}

/// <summary>某一天的用量。</summary>
public sealed class UsageDay
{
    [JsonPropertyName("date")] public string Date { get; set; } = ""; // "2026-08-01"
    [JsonPropertyName("data")] public List<ModelUsage> Data { get; set; } = [];
}

// MARK: - by_api_key 用量（实时接口：usage/by_api_key/amount、usage/by_api_key/cost）
// 参数 start/end 为 Unix 秒，tz 为秒偏移（UTC+8 = 28800），bucket=86400 按天分桶；
// 与 usage/amount、usage/cost（当日数据延迟数小时～次日）不同，该接口数据实时

/// <summary>usage/by_api_key/amount 的 biz_data。</summary>
public sealed class ApiKeyAmountData
{
    [JsonPropertyName("start")] public long Start { get; set; }
    [JsonPropertyName("end")] public long End { get; set; }
    [JsonPropertyName("bucket")] public int Bucket { get; set; }
    [JsonPropertyName("models")] public List<string> Models { get; set; } = [];
    [JsonPropertyName("series")] public List<ApiKeyAmountSeries> Series { get; set; } = [];
}

public sealed class ApiKeyAmountSeries
{
    [JsonPropertyName("api_key")] public ApiKeyInfo ApiKey { get; set; } = new();
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("buckets")] public List<ApiKeyUsageBucket> Buckets { get; set; } = [];
}

/// <summary>usage/by_api_key/cost 的 biz_data。</summary>
public sealed class ApiKeyCostData
{
    [JsonPropertyName("start")] public long Start { get; set; }
    [JsonPropertyName("end")] public long End { get; set; }
    [JsonPropertyName("bucket")] public int Bucket { get; set; }
    [JsonPropertyName("models")] public List<string> Models { get; set; } = [];
    [JsonPropertyName("data")] public List<ApiKeyCostGroup> Data { get; set; } = [];
}

public sealed class ApiKeyCostGroup
{
    [JsonPropertyName("currency")] public string Currency { get; set; } = "";
    [JsonPropertyName("series")] public List<ApiKeyCostSeries> Series { get; set; } = [];
}

public sealed class ApiKeyCostSeries
{
    [JsonPropertyName("api_key")] public ApiKeyInfo ApiKey { get; set; } = new();
    [JsonPropertyName("model")] public string Model { get; set; } = "";
    [JsonPropertyName("buckets")] public List<ApiKeyCostBucket> Buckets { get; set; } = [];
}

public sealed class ApiKeyInfo
{
    [JsonPropertyName("tracking_id")] public string TrackingId { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("sensitive_id")] public string SensitiveId { get; set; } = "";
    [JsonPropertyName("valid")] public bool Valid { get; set; }
}

/// <summary>按天桶的 token 用量：type -> 数值（REQUEST / RESPONSE_TOKEN / PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN）。
/// 注意：真实响应中值为 JSON 数字（非字符串），必须用 double 解码。</summary>
public sealed class ApiKeyUsageBucket
{
    [JsonPropertyName("time")] public long Time { get; set; }
    [JsonPropertyName("usage")] public Dictionary<string, double> Usage { get; set; } = [];
}

/// <summary>按天桶的费用。</summary>
public sealed class ApiKeyCostBucket
{
    [JsonPropertyName("time")] public long Time { get; set; }
    [JsonPropertyName("cost")] public string Cost { get; set; } = "0";
}

/// <summary>get_user_summary 的 biz_data。</summary>
public sealed class UserSummary
{
    [JsonPropertyName("normal_wallets")] public List<WalletBalance> NormalWallets { get; set; } = [];
    [JsonPropertyName("bonus_wallets")] public List<WalletBalance> BonusWallets { get; set; } = [];
    [JsonPropertyName("total_costs")] public List<WalletCost> TotalCosts { get; set; } = [];
}

public sealed class WalletBalance
{
    [JsonPropertyName("currency")] public string Currency { get; set; } = "";
    [JsonPropertyName("balance")] public string Balance { get; set; } = "0";
    [JsonPropertyName("token_estimation")] public string? TokenEstimation { get; set; }

    public double Value =>
        double.TryParse(Balance, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0;
}

public sealed class WalletCost
{
    [JsonPropertyName("currency")] public string Currency { get; set; } = "";
    [JsonPropertyName("amount")] public string Amount { get; set; } = "0";

    public double Value =>
        double.TryParse(Amount, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : 0;
}

/// <summary>某一天 token 用量快照（MonthUsage.TokensOn 的返回）。</summary>
public readonly record struct DayTokens(int Requests, double Response, double CacheHit, double CacheMiss);

/// <summary>聚合后的本月用量（UI 直接使用）。</summary>
public sealed class MonthUsage
{
    public int Year { get; init; }
    public int Month { get; init; }
    public List<ModelUsage> AmountModels { get; init; } = [];
    public List<ModelUsage> CostModels { get; init; } = [];
    public List<UsageDay> CostDays { get; init; } = [];
    public List<UsageDay> AmountDays { get; init; } = [];

    public string Id => $"{Year}-{Month}";

    // MARK: - 本月汇总

    public double TotalCost =>
        CostModels.Sum(m => m.Usage.Sum(i => i.Value));

    public double PromptTokens => SumAmount("PROMPT_TOKEN");
    public double CacheHitTokens => SumAmount("PROMPT_CACHE_HIT_TOKEN");
    public double CacheMissTokens => SumAmount("PROMPT_CACHE_MISS_TOKEN");
    public double ResponseTokens => SumAmount("RESPONSE_TOKEN");
    public int TotalRequests => AmountModels.Sum(m => m.Requests);

    /// <summary>最新用量日期；amountDays 为空时为 null（避免空集合 Max 崩溃）。</summary>
    public string? LatestAmountDate => AmountDays.Count == 0 ? null : AmountDays.Max(d => d.Date);

    // MARK: - 按日查询

    public double CostOn(DateTime date)
    {
        var key = DayKey(date);
        var day = CostDays.FirstOrDefault(d => d.Date == key);
        if (day is null) return 0;
        return day.Data.Sum(m => m.Usage.Sum(i => i.Value));
    }

    public DayTokens TokensOn(DateTime date)
    {
        var key = DayKey(date);
        var day = AmountDays.FirstOrDefault(d => d.Date == key);
        if (day is null) return new DayTokens(0, 0, 0, 0);
        return new DayTokens(
            Requests: day.Data.Sum(m => m.Requests),
            Response: day.Data.Sum(m => m.ValueFor("RESPONSE_TOKEN")),
            CacheHit: day.Data.Sum(m => m.ValueFor("PROMPT_CACHE_HIT_TOKEN")),
            CacheMiss: day.Data.Sum(m => m.ValueFor("PROMPT_CACHE_MISS_TOKEN")));
    }

    // MARK: - 工具

    private double SumAmount(string type) => AmountModels.Sum(m => m.ValueFor(type));

    /// <summary>平台统计口径时区：北京时间（UTC+8）。App 统一用此时区判定「今日/本月」，
    /// 避免用户本地时区 ≠ UTC+8 时（跨时区旅行等）出现日期错位（对齐 macOS 版）。</summary>
    public static readonly TimeZoneInfo PlatformTimeZone =
        TimeZoneInfo.FindSystemTimeZoneById("China Standard Time");

    private static string DayKey(DateTime date) =>
        TimeZoneInfo.ConvertTime(date, PlatformTimeZone).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);

    // MARK: - by_api_key 序列聚合

    /// <summary>
    /// 把 by_api_key 的天桶序列聚合成 MonthUsage。
    /// startTs/endTs 为查询窗口（Unix 秒），窗口外的桶会被忽略（防御越界数据）；
    /// year/month 取自 startTs，调用方需保证 startTs 为本月 1 日；
    /// 费用只聚合 data 中第一个币种分组（与旧 usage/cost 实现「取第一个」一致），避免多币种混加。
    /// </summary>
    public static MonthUsage Aggregated(
        long startTs,
        long endTs,
        int tzSeconds,
        ApiKeyAmountData? amountData,
        ApiKeyCostData? costData)
    {
        var tz = tzSeconds == 28800
            ? PlatformTimeZone
            : TimeZoneInfo.CreateCustomTimeZone("CustomTz", TimeSpan.FromSeconds(tzSeconds), "CustomTz", "CustomTz");
        var startDate = TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeSeconds(startTs).UtcDateTime, tz);

        string DayString(long ts) =>
            TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeSeconds(ts).UtcDateTime, tz)
                .ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
        bool InWindow(long ts) => ts >= startTs && ts < endTs;

        // 1. token/请求：day -> model -> type -> value
        var amountByDay = new Dictionary<string, Dictionary<string, Dictionary<string, double>>>();
        var amountByModel = new Dictionary<string, Dictionary<string, double>>();
        foreach (var series in amountData?.Series ?? [])
        {
            foreach (var bucket in series.Buckets)
            {
                if (!InWindow(bucket.Time)) continue;
                var day = DayString(bucket.Time);
                foreach (var kv in bucket.Usage)
                {
                    var value = kv.Value; // 已按 double 解码
                    if (!amountByDay.TryGetValue(day, out var byModel))
                    {
                        byModel = new Dictionary<string, Dictionary<string, double>>();
                        amountByDay[day] = byModel;
                    }
                    if (!byModel.TryGetValue(series.Model, out var byType))
                    {
                        byType = new Dictionary<string, double>();
                        byModel[series.Model] = byType;
                    }
                    byType[kv.Key] = byType.GetValueOrDefault(kv.Key) + value;
                    if (!amountByModel.TryGetValue(series.Model, out var modelTotals))
                    {
                        modelTotals = new Dictionary<string, double>();
                        amountByModel[series.Model] = modelTotals;
                    }
                    modelTotals[kv.Key] = modelTotals.GetValueOrDefault(kv.Key) + value;
                }
            }
        }

        // 2. 费用：只取第一个币种分组（day -> model -> 金额，统一记为 COST 类型）
        var costByDay = new Dictionary<string, Dictionary<string, double>>();
        var costByModel = new Dictionary<string, double>();
        var costGroup = costData?.Data.FirstOrDefault();
        if (costGroup is not null)
        {
            foreach (var series in costGroup.Series)
            {
                foreach (var bucket in series.Buckets)
                {
                    if (!InWindow(bucket.Time)) continue;
                    var day = DayString(bucket.Time);
                    var value = double.TryParse(bucket.Cost, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : 0;
                    if (!costByDay.TryGetValue(day, out var byModel))
                    {
                        byModel = new Dictionary<string, double>();
                        costByDay[day] = byModel;
                    }
                    byModel[series.Model] = byModel.GetValueOrDefault(series.Model) + value;
                    costByModel[series.Model] = costByModel.GetValueOrDefault(series.Model) + value;
                }
            }
        }

        // 3. 组装（key 与 model 均排序，保证输出稳定）
        static List<UsageItem> ToItems(Dictionary<string, double> dict) =>
            dict.OrderBy(kv => kv.Key)
                .Select(kv => new UsageItem { Type = kv.Key, Amount = kv.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) })
                .ToList();

        var amountDays = amountByDay.OrderBy(kv => kv.Key).Select(kv => new UsageDay
        {
            Date = kv.Key,
            Data = kv.Value.OrderBy(m => m.Key).Select(m => new ModelUsage
            {
                Model = m.Key,
                Usage = ToItems(m.Value),
            }).ToList(),
        }).ToList();

        var amountModels = amountByModel.OrderBy(kv => kv.Key).Select(kv => new ModelUsage
        {
            Model = kv.Key,
            Usage = ToItems(kv.Value),
        }).ToList();

        var costDays = costByDay.OrderBy(kv => kv.Key).Select(kv => new UsageDay
        {
            Date = kv.Key,
            Data = kv.Value.OrderBy(m => m.Key).Select(m => new ModelUsage
            {
                Model = m.Key,
                Usage = [new UsageItem { Type = "COST", Amount = m.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) }],
            }).ToList(),
        }).ToList();

        var costModels = costByModel.OrderBy(kv => kv.Key).Select(kv => new ModelUsage
        {
            Model = kv.Key,
            Usage = [new UsageItem { Type = "COST", Amount = kv.Value.ToString(System.Globalization.CultureInfo.InvariantCulture) }],
        }).ToList();

        return new MonthUsage
        {
            Year = startDate.Year,
            Month = startDate.Month,
            AmountModels = amountModels,
            CostModels = costModels,
            CostDays = costDays,
            AmountDays = amountDays,
        };
    }
}

/// <summary>JSON 解码选项：snake_case 键名自动映射到 CamelCase 属性（对齐 Swift convertFromSnakeCase）。</summary>
public static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
    };
}

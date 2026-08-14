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

    private static string DayKey(DateTime date) => date.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
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

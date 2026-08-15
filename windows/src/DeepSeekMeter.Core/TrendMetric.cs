namespace DeepSeekMeter.Core;

/// <summary>Token 趋势指标（输出 / 缓存命中 / 总量）。</summary>
public enum TrendMetric
{
    Output,   // 模型生成的输出 Token
    CacheHit, // 从缓存直接复用的输入 Token
    Total,    // 输出 + 缓存命中 + 缓存未命中
}

/// <summary>趋势指标的名称与含义说明（UI 与测试共用，避免文案漂移）。</summary>
public static class TrendMetricText
{
    public static string Label(this TrendMetric m) => m switch
    {
        TrendMetric.Output => "输出",
        TrendMetric.CacheHit => "缓存命中",
        _ => "总量",
    };

    public static string Description(this TrendMetric m) => m switch
    {
        TrendMetric.Output => "模型生成的输出 Token",
        TrendMetric.CacheHit => "从缓存直接复用的输入 Token",
        _ => "输出 + 缓存命中 + 缓存未命中 Token",
    };
}

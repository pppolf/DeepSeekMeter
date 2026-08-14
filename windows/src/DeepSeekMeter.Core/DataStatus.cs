namespace DeepSeekMeter.Core;

/// <summary>数据可信度状态（托盘/悬浮窗/错误提示共用，保证一致）。</summary>
public enum DataStatus
{
    NotLoggedIn,  // 未登录
    Loading,      // 已登录但尚无数据（首次加载或已清空）
    Fresh,        // 最新数据，无错误
    Stale,        // 刷新失败，正在显示旧数据
    Error,        // 错误且无数据
    TokenExpired, // 登录已过期
}

/// <summary>
/// 数据状态判定（纯函数，可测）。
/// 规则：未登录 → 过期 → 有错误（有旧数据=Stale / 无数据=Error）→ 有数据=Fresh → 加载中。
/// </summary>
public static class DataState
{
    public static DataStatus Evaluate(string? token, bool tokenExpired, bool hasData, bool hasError)
    {
        if (string.IsNullOrEmpty(token)) return DataStatus.NotLoggedIn;
        if (tokenExpired) return DataStatus.TokenExpired;
        if (hasError) return hasData ? DataStatus.Stale : DataStatus.Error;
        if (hasData) return DataStatus.Fresh;
        return DataStatus.Loading;
    }
}

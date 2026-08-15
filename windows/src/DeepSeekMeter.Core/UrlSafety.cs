namespace DeepSeekMeter.Core;

/// <summary>
/// URL 安全校验（内嵌登录页与外部链接共用，避免规则不一致）。
/// 规则：仅 https；内嵌页仅允许 deepseek.com 或其真实子域名；拒绝 file:/javascript:/data:/ms-settings:/shell: 等协议。
/// </summary>
public static class UrlSafety
{
    /// <summary>是否允许作为 DeepSeek 内嵌页：必须 https 且域名为 deepseek.com 或 *.deepseek.com。</summary>
    public static bool IsAllowedDeepSeekUrl(string? url)
    {
        if (!TryParseHttps(url, out var host)) return false;
        return host.Equals("deepseek.com", StringComparison.OrdinalIgnoreCase)
            || host.EndsWith(".deepseek.com", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>是否允许交给系统浏览器打开：仅 https（拒绝危险协议与自定义协议）。</summary>
    public static bool IsAllowedExternalUrl(string? url)
    {
        if (!TryParseHttps(url, out _)) return false;
        return true;
    }

    private static bool TryParseHttps(string? url, out string host)
    {
        host = "";
        if (string.IsNullOrWhiteSpace(url)) return false;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        if (!uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase)) return false;
        if (string.IsNullOrEmpty(uri.Host)) return false;
        host = uri.Host;
        return true;
    }
}

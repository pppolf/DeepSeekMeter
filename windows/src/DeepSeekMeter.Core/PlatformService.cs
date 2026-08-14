using System.Net;
using System.Text.Json;

namespace DeepSeekMeter.Core;

/// <summary>平台错误类型（对齐 macOS 版 PlatformError）。</summary>
public enum PlatformErrorKind
{
    EmptyToken,
    Network,
    Http,
    Api,
    Decoding,
}

/// <summary>
/// 平台接口错误（带用户可读的中文 message，对齐 macOS 版 PlatformError.message）。
/// </summary>
public sealed class PlatformException : Exception
{
    public PlatformErrorKind Kind { get; }
    public int? HttpCode { get; }
    public int? ApiCode { get; }

    public PlatformException(PlatformErrorKind kind, string message, int? httpCode = null, int? apiCode = null)
        : base(message)
    {
        Kind = kind;
        HttpCode = httpCode;
        ApiCode = apiCode;
    }

    /// <summary>平台 Token 无效或已过期（40002 / 40003）。</summary>
    public bool IsTokenExpired => ApiCode is 40002 or 40003;

    /// <summary>根据错误类型构造中文提示（对齐 Swift PlatformError.message）。</summary>
    public static string BuildMessage(PlatformErrorKind kind, string detail, int? httpCode = null, int? apiCode = null)
    {
        switch (kind)
        {
            case PlatformErrorKind.EmptyToken:
                return "请先在设置中填写平台 Token";
            case PlatformErrorKind.Network:
                return $"用量获取失败：{detail}";
            case PlatformErrorKind.Http:
                return $"用量获取失败（HTTP {httpCode}）";
            case PlatformErrorKind.Api:
                if (apiCode is 40002 or 40003)
                    return "平台 Token 无效或已过期，请重新获取";
                return $"平台接口错误（{apiCode}）：{detail}";
            case PlatformErrorKind.Decoding:
                return $"用量解析失败：{detail}";
            default:
                return detail;
        }
    }

    public static PlatformException EmptyToken() =>
        new(PlatformErrorKind.EmptyToken, BuildMessage(PlatformErrorKind.EmptyToken, ""));

    public static PlatformException Network(string detail) =>
        new(PlatformErrorKind.Network, BuildMessage(PlatformErrorKind.Network, detail));

    public static PlatformException Http(int code) =>
        new(PlatformErrorKind.Http, BuildMessage(PlatformErrorKind.Http, "", httpCode: code), httpCode: code);

    public static PlatformException Api(int code, string msg) =>
        new(PlatformErrorKind.Api, BuildMessage(PlatformErrorKind.Api, msg, apiCode: code), apiCode: code);

    public static PlatformException Decoding(string detail) =>
        new(PlatformErrorKind.Decoding, BuildMessage(PlatformErrorKind.Decoding, detail));
}

/// <summary>
/// 平台私有接口客户端（platform.deepseek.com，用浏览器登录态 userToken 鉴权）。
/// 对齐 macOS 版 PlatformService.swift，接口契约一致：
///   /auth-api/v0/users/current、/api/v0/users/get_user_summary、
///   /api/v0/usage/amount、/api/v0/usage/cost
/// </summary>
public sealed class PlatformService
{
    private const string BaseUrl = "https://platform.deepseek.com";
    private const string UserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

    private static readonly HttpClient Http = CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
        };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/json, text/plain, */*");
        return client;
    }

    /// <summary>当前用户信息。</summary>
    public readonly record struct UserInfo(string Email, string Currency);

    // MARK: - 接口

    /// <summary>校验 Token 并返回用户信息（email、currency）。</summary>
    public async Task<UserInfo> FetchCurrentUserAsync(string token, CancellationToken ct = default)
    {
        var response = await GetAsync<CurrentUserResponse>("/auth-api/v0/users/current", token, ct);
        EnsureSuccess(response.Code, response.Msg);
        var user = response.Data?.BizData;
        return new UserInfo(user?.Email ?? "", user?.Currency ?? "CNY");
    }

    /// <summary>平台侧账户汇总（余额 / 累计消费）。</summary>
    public async Task<UserSummary> FetchSummaryAsync(string token, CancellationToken ct = default)
    {
        var response = await GetAsync<SummaryResponse>("/api/v0/users/get_user_summary", token, ct);
        EnsureSuccess(response.Code, response.Msg);
        return response.Data?.BizData
            ?? throw PlatformException.Api(response.Code, "summary 为空");
    }

    /// <summary>本月 token 用量（biz_data 是对象）。</summary>
    public async Task<UsageData> FetchUsageAmountAsync(string token, int month, int year, CancellationToken ct = default)
    {
        var response = await GetAsync<AmountResponse>($"/api/v0/usage/amount?month={month}&year={year}", token, ct);
        EnsureSuccess(response.Code, response.Msg);
        return response.Data?.BizData
            ?? throw PlatformException.Api(response.Code, "amount 为空");
    }

    /// <summary>本月费用（biz_data 是数组，取第一个）。</summary>
    public async Task<UsageData> FetchUsageCostAsync(string token, int month, int year, CancellationToken ct = default)
    {
        var response = await GetAsync<CostResponse>($"/api/v0/usage/cost?month={month}&year={year}", token, ct);
        EnsureSuccess(response.Code, response.Msg);
        var first = response.Data?.BizData?.FirstOrDefault()
            ?? throw PlatformException.Api(response.Code, "cost 为空");
        return first;
    }

    // MARK: - 请求

    private static async Task<T> GetAsync<T>(string path, string token, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(token))
            throw PlatformException.EmptyToken();

        using var request = new HttpRequestMessage(HttpMethod.Get, BaseUrl + path);
        request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
        request.Headers.TryAddWithoutValidation("Referer", "https://platform.deepseek.com/usage");
        request.Headers.TryAddWithoutValidation("Origin", "https://platform.deepseek.com");

        HttpResponseMessage response;
        try
        {
            response = await Http.SendAsync(request, ct);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw PlatformException.Network("请求超时");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw PlatformException.Network(ex.Message);
        }

        using (response)
        {
            if ((int)response.StatusCode != 200)
                throw PlatformException.Http((int)response.StatusCode);

            var json = await response.Content.ReadAsStringAsync(ct);
            try
            {
                return JsonSerializer.Deserialize<T>(json, Json.Options)
                    ?? throw PlatformException.Decoding("响应为空");
            }
            catch (JsonException ex)
            {
                throw PlatformException.Decoding(ex.Message);
            }
        }
    }

    private static void EnsureSuccess(int code, string msg)
    {
        if (code != 0)
            throw PlatformException.Api(code, msg);
    }

    // MARK: - 响应 DTO（与 macOS 版保持相同结构）

    private sealed class CurrentUserData
    {
        [System.Text.Json.Serialization.JsonPropertyName("id")] public string Id { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("email")] public string? Email { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("currency")] public string? Currency { get; set; }
    }

    private sealed class CurrentUserResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("code")] public int Code { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("msg")] public string Msg { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("data")] public BizWrapper<CurrentUserData>? Data { get; set; }
    }

    private sealed class SummaryResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("code")] public int Code { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("msg")] public string Msg { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("data")] public BizWrapper<UserSummary>? Data { get; set; }
    }

    private sealed class AmountResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("code")] public int Code { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("msg")] public string Msg { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("data")] public BizWrapper<UsageData>? Data { get; set; }
    }

    private sealed class CostResponse
    {
        [System.Text.Json.Serialization.JsonPropertyName("code")] public int Code { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("msg")] public string Msg { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("data")] public BizWrapper<List<UsageData>>? Data { get; set; }
    }
}

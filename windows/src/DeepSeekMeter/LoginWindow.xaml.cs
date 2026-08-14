using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using DeepSeekMeter.Core;
using Microsoft.Web.WebView2.Core;

namespace DeepSeekMeter;

/// <summary>
/// 登录窗口：内嵌官方登录页（WebView2 / Edge Chromium）；登录后只读 localStorage 提取 Token，
/// Token 校验在原生侧完成（对齐 macOS 版 LoginWindowController.swift）。
/// </summary>
public partial class LoginWindow : Window
{
    private readonly Action<string, string> _onToken;
    private readonly Action _onCancel;
    private readonly PlatformService _platformService = new();

    private DispatcherTimer? _pollTimer;
    private bool _isChecking;
    private bool _tokenReceived;
    private string _lastSignature = "";

    public LoginWindow(Action<string, string> onToken, Action onCancel)
    {
        InitializeComponent();
        _onToken = onToken;
        _onCancel = onCancel;
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            // 独立用户数据目录：登录态与浏览器互不影响，重启后仍可用
            var userDataFolder = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DeepSeekMeter", "WebView2");
            var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
            await WebView.EnsureCoreWebView2Async(env);
            WebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            WebView.CoreWebView2.Settings.IsStatusBarEnabled = false;

            // OAuth / 扫码弹窗：在同一 WebView 内导航，保持同一登录态（对齐 macOS 共享 dataStore）
            WebView.CoreWebView2.NewWindowRequested += (_, args) =>
            {
                args.Handled = true;
                WebView.CoreWebView2.Navigate(args.Uri);
            };
            WebView.CoreWebView2.NavigationCompleted += (_, _) => _ = CheckTokenAsync();

            StartPolling();
            WebView.CoreWebView2.Navigate("https://platform.deepseek.com/");
        }
        catch (Exception ex)
        {
            SetStatus($"WebView2 初始化失败：{ex.Message}（可点右上角「手动粘贴 Token」）");
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        StopPolling();
        if (!_tokenReceived)
            _onCancel();
    }

    // MARK: - 提取 Token

    private void StartPolling()
    {
        _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        _pollTimer.Tick += async (_, _) => await CheckTokenAsync();
        _pollTimer.Start();
    }

    private void StopPolling()
    {
        _pollTimer?.Stop();
        _pollTimer = null;
    }

    private void SetStatus(string text)
    {
        StatusText.Text = text;
        System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] login: {text}");
    }

    private async Task CheckTokenAsync()
    {
        if (_isChecking || _tokenReceived || WebView.CoreWebView2 is null) return;
        _isChecking = true;
        try
        {
            var js = """
(() => {
  try {
    const pairs = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      pairs[k] = localStorage.getItem(k);
    }
    return JSON.stringify({ ok: true, data: pairs });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
""";
            var result = await WebView.CoreWebView2.ExecuteScriptAsync(js);
            if (string.IsNullOrEmpty(result)) { SetStatus("等待登录完成…"); return; }

            // 关键：WebView2 的 ExecuteScriptAsync 返回的是「JSON 编码后的结果」，
            // 脚本返回字符串时外层是带引号转义的 JSON 字符串字面量（如 "\"{\"ok\":true...}\""），
            // 需先反序列化出字符串，再解析其中的 JSON 对象（与 macOS WKWebView 直接返回字符串不同）。
            string innerJson;
            try
            {
                innerJson = JsonSerializer.Deserialize<string>(result) ?? "";
            }
            catch (JsonException)
            {
                SetStatus("等待登录完成…");
                return;
            }

            using var doc = JsonDocument.Parse(innerJson);
            var root = doc.RootElement;
            if (!root.TryGetProperty("ok", out var ok) || !ok.GetBoolean()) { SetStatus("等待登录完成…"); return; }
            if (!root.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object)
            {
                SetStatus("尚未就绪，等待登录完成…");
                return;
            }

            var pairs = new Dictionary<string, string>();
            foreach (var prop in data.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.String)
                    pairs[prop.Name] = prop.Value.GetString() ?? "";
            }

            var signature = StorageSignature(pairs);
            if (signature == _lastSignature) { SetStatus("等待登录完成…"); return; }
            _lastSignature = signature;

            var candidates = TokenCandidates(pairs);
            if (candidates.Count == 0) { SetStatus("等待登录完成…"); return; }

            SetStatus("检测到登录信息，校验中…");
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] login: candidates = {candidates.Count}");
            await ValidateAsync(candidates);
        }
        catch (Exception ex)
        {
            SetStatus($"页面未就绪（{ex.Message}），等待登录…");
        }
        finally
        {
            _isChecking = false;
        }
    }

    private static string StorageSignature(Dictionary<string, string> pairs)
    {
        return string.Join("|", pairs.OrderBy(kv => kv.Key, StringComparer.Ordinal).Select(kv =>
        {
            var v = kv.Value;
            return $"{kv.Key}={v.Length}:{v[..Math.Min(16, v.Length)]}";
        }));
    }

    /// <summary>候选 Token 提取（对齐 macOS 版 tokenCandidates）：userToken 优先 → 键名含 token → 长值兜底。</summary>
    private static List<string> TokenCandidates(Dictionary<string, string> pairs)
    {
        static string Unwrap(string raw)
        {
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.ValueKind == JsonValueKind.Object &&
                    doc.RootElement.TryGetProperty("value", out var v) &&
                    v.ValueKind == JsonValueKind.String)
                {
                    var value = v.GetString();
                    if (!string.IsNullOrEmpty(value)) return value;
                }
            }
            catch (JsonException) { /* 非 JSON 原样返回 */ }
            return raw;
        }

        var result = new List<string>();
        void Add(string t)
        {
            var trimmed = t.Trim();
            if (trimmed.Length > 0 && !result.Contains(trimmed)) result.Add(trimmed);
        }

        // 1. userToken 优先
        if (pairs.TryGetValue("userToken", out var userToken) && !string.IsNullOrEmpty(userToken))
            Add(Unwrap(userToken));

        // 2. 键名含 token
        foreach (var (key, value) in pairs)
        {
            if (string.IsNullOrEmpty(value)) continue;
            if (key.Contains("token", StringComparison.OrdinalIgnoreCase) && value.Length >= 20)
                Add(Unwrap(value));
        }

        // 3. 兜底：40~512 字符的长值
        foreach (var (_, value) in pairs)
        {
            if (value.Length >= 40 && value.Length <= 512)
                Add(Unwrap(value));
        }
        return result;
    }

    /// <summary>逐个校验候选 Token（对齐 macOS 版 validate）。</summary>
    private async Task ValidateAsync(List<string> candidates)
    {
        if (_tokenReceived) return;
        foreach (var token in candidates)
        {
            if (_tokenReceived) return;
            try
            {
                var user = await _platformService.FetchCurrentUserAsync(token);
                _tokenReceived = true;
                SetStatus("已获取 Token ✓");
                StopPolling();
                Close();
                _onToken(token, user.Email);
                return;
            }
            catch (PlatformException ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] login: 候选校验失败 - {ex.Message}");
            }
        }
        SetStatus("校验未通过，稍后自动重试…");
    }

    /// <summary>手动粘贴 Token 兜底（WebView2 不可用时仍可登录）。</summary>
    private void OnManualTokenClick(object sender, RoutedEventArgs e)
    {
        var dialog = new TokenInputDialog(token =>
        {
            if (string.IsNullOrWhiteSpace(token)) return;
            SetStatus("校验中…");
            _ = ValidateAsync([token.Trim()]);
        });
        dialog.Owner = this;
        dialog.ShowDialog();
    }

    private void OnOpenInBrowserClick(object sender, RoutedEventArgs e)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "https://platform.deepseek.com/",
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            SetStatus($"打开浏览器失败：{ex.Message}");
        }
    }
}

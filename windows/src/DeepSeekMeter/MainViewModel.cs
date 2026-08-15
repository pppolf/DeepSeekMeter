using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using DeepSeekMeter.Core;

namespace DeepSeekMeter;

/// <summary>
/// 应用状态中枢：轮询余额 + 用量，暴露给 UI（对齐 macOS 版 AppModel.swift）。
/// 所有网络请求只经 PlatformService，错误统一为 PlatformException。
/// </summary>
public sealed class MainViewModel : INotifyPropertyChanged
{
    public SettingsStore Settings { get; }

    private readonly PlatformService _service = new();
    private DispatcherTimer? _timer;
    private LoginWindow? _loginWindow;
    private int _consecutiveFailures;
    private double _baseIntervalSeconds = 60;

    private BalanceInfo? _lastBalance;
    private DateTime? _lastUpdate;
    private string? _lastError;

    private MonthUsage? _monthUsage;
    private string? _usageError;
    private bool _platformTokenExpired;
    private bool _isFetching;
    private string _currency = "CNY";

    public MainViewModel(SettingsStore settings)
    {
        Settings = settings;
    }

    // MARK: - 绑定属性

    /// <summary>数据可信度状态（托盘/悬浮窗/错误提示共用）。</summary>
    public DataStatus Status =>
        DataState.Evaluate(Settings.PlatformToken, PlatformTokenExpired, HasData, HasError);

    private bool HasData => LastBalance is not null || MonthUsage is not null;

    private bool HasError => LastError is not null || UsageError is not null;

    /// <summary>当前账户币种（余额/登录接口返回，用于费用展示，不再写死 CNY）。</summary>
    public string Currency
    {
        get => _currency;
        private set { if (_currency != value) { _currency = value; OnPropertyChanged(); } }
    }

    public BalanceInfo? LastBalance
    {
        get => _lastBalance;
        private set { if (!Equals(_lastBalance, value)) { _lastBalance = value; OnPropertyChanged(); OnPropertyChanged(nameof(Status)); } }
    }

    public DateTime? LastUpdate
    {
        get => _lastUpdate;
        private set { if (_lastUpdate != value) { _lastUpdate = value; OnPropertyChanged(); } }
    }

    public string? LastError
    {
        get => _lastError;
        private set { if (_lastError != value) { _lastError = value; OnPropertyChanged(); OnPropertyChanged(nameof(Status)); } }
    }

    public MonthUsage? MonthUsage
    {
        get => _monthUsage;
        private set { if (!ReferenceEquals(_monthUsage, value)) { _monthUsage = value; OnPropertyChanged(); OnPropertyChanged(nameof(Status)); } }
    }

    public string? UsageError
    {
        get => _usageError;
        private set { if (_usageError != value) { _usageError = value; OnPropertyChanged(); OnPropertyChanged(nameof(Status)); } }
    }

    public bool PlatformTokenExpired
    {
        get => _platformTokenExpired;
        private set { if (_platformTokenExpired != value) { _platformTokenExpired = value; OnPropertyChanged(); OnPropertyChanged(nameof(Status)); } }
    }

    public bool IsFetching
    {
        get => _isFetching;
        private set { if (_isFetching != value) { _isFetching = value; OnPropertyChanged(); } }
    }

    /// <summary>登录成功回调（由 App 设置，用于弹回悬浮窗）。</summary>
    public Action? OnLoginSucceeded { get; set; }

    // MARK: - 轮询

    public void StartPolling()
    {
        StopPolling();
        _baseIntervalSeconds = Settings.RefreshInterval;
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(_baseIntervalSeconds),
        };
        _timer.Tick += async (_, _) => await AutoRefreshAsync();
        _timer.Start();
        _ = RefreshAsync(); // 启动时立即拉一次
    }

    public void StopPolling()
    {
        if (_timer is null) return;
        _timer.Stop();
        _timer = null;
    }

    public void SetRefreshInterval(double interval)
    {
        Settings.RefreshInterval = interval;
        _consecutiveFailures = 0; // 手动改间隔重置退避
        StartPolling();
    }

    public async Task RefreshAsync()
    {
        await PerformRefreshAsync();
    }

    /// <summary>定时自动刷新；连续失败时按指数退避拉长间隔。</summary>
    private async Task AutoRefreshAsync()
    {
        await PerformRefreshAsync();
        ApplyBackoff();
    }

    /// <summary>连续失败时指数退避（最多 10 分钟），成功恢复基础间隔。</summary>
    private void ApplyBackoff()
    {
        if (_timer is null) return;
        if (_consecutiveFailures > 0)
        {
            var factor = Math.Pow(2, Math.Min(_consecutiveFailures, 4)); // 2/4/8/16 倍
            _timer.Interval = TimeSpan.FromSeconds(Math.Min(_baseIntervalSeconds * factor, 600));
        }
        else
        {
            _timer.Interval = TimeSpan.FromSeconds(_baseIntervalSeconds);
        }
    }

    // MARK: - 拉取

    public async Task PerformRefreshAsync()
    {
        if (IsFetching) return;
        IsFetching = true;
        try
        {
            // 余额与用量并发执行，减少一次刷新总耗时
            await Task.WhenAll(FetchBalanceAsync(), FetchUsageAsync());
            _consecutiveFailures = 0;
        }
        catch (Exception ex)
        {
            // 兜底：任何未捕获异常都转为应用错误，不导致程序退出
            LastError = ex.Message;
            _consecutiveFailures++;
        }
        finally
        {
            IsFetching = false;
        }
    }

    /// <summary>余额（平台侧 get_user_summary）。</summary>
    private async Task FetchBalanceAsync()
    {
        if (string.IsNullOrEmpty(Settings.PlatformToken))
        {
            LastBalance = null;
            return;
        }
        try
        {
            var summary = await _service.FetchSummaryAsync(Settings.PlatformToken);
            var wallet = summary.NormalWallets.FirstOrDefault();
            if (wallet is null)
            {
                // 接口成功但钱包列表为空：识别为明确空状态，不保留旧余额
                LastBalance = null;
                LastError = "余额数据为空";
                return;
            }
            var bonus = summary.BonusWallets.FirstOrDefault()?.Value ?? 0;
            LastBalance = new BalanceInfo
            {
                Currency = wallet.Currency,
                TotalBalance = wallet.Balance,
                GrantedBalance = bonus.ToString(CultureInfo.InvariantCulture),
                ToppedUpBalance = Math.Max(0, wallet.Value - bonus).ToString(CultureInfo.InvariantCulture),
            };
            Currency = wallet.Currency; // 同步账户币种
            LastUpdate = DateTime.Now;
            LastError = null;
        }
        catch (PlatformException ex)
        {
            // 保留旧余额，仅标记错误（旧数据由 Status=Stale 标注「可能过期」）
            LastError = ex.Message;
            _consecutiveFailures++;
            if (ex.IsTokenExpired)
            {
                PlatformTokenExpired = true;
                StopPolling(); // Token 过期暂停高频自动刷新，等待重新登录
            }
        }
    }

    /// <summary>用量：拉取本月 by_api_key 实时接口并聚合（对齐 macOS 版，北京时间窗口）。</summary>
    private async Task FetchUsageAsync()
    {
        if (string.IsNullOrEmpty(Settings.PlatformToken))
        {
            MonthUsage = null;
            UsageError = null;
            return;
        }
        try
        {
            // 用平台时区（北京时间）而不是本地时区：跨时区旅行时本地时区变化，
            // 会导致「今日/本月」与平台统计口径错位（今日费用/请求显示 0 或错位）
            var beijingNow = TimeZoneInfo.ConvertTime(DateTime.Now, MonthUsage.PlatformTimeZone);
            var start = new DateTime(beijingNow.Year, beijingNow.Month, 1, 0, 0, 0, DateTimeKind.Unspecified);
            var end = start.AddMonths(1);
            var tz = (int)MonthUsage.PlatformTimeZone.BaseUtcOffset.TotalSeconds; // 28800（UTC+8）
            var startTs = new DateTimeOffset(start, MonthUsage.PlatformTimeZone.GetUtcOffset(start)).ToUnixTimeSeconds();
            var endTs = new DateTimeOffset(end, MonthUsage.PlatformTimeZone.GetUtcOffset(end)).ToUnixTimeSeconds();

            var amountTask = _service.FetchApiKeyAmountAsync(Settings.PlatformToken, startTs, endTs, tz);
            var costTask = _service.FetchApiKeyCostAsync(Settings.PlatformToken, startTs, endTs, tz);
            await Task.WhenAll(amountTask, costTask);

            MonthUsage = MonthUsage.Aggregated(startTs, endTs, tz, amountTask.Result, costTask.Result);
            UsageError = null;
            PlatformTokenExpired = false;
            LastUpdate = DateTime.Now; // 最后成功时间
        }
        catch (PlatformException ex)
        {
            // 保留旧用量，仅标记错误
            UsageError = ex.Message;
            _consecutiveFailures++;
            if (ex.IsTokenExpired)
            {
                PlatformTokenExpired = true;
                StopPolling(); // Token 过期暂停高频自动刷新，等待重新登录
            }
        }
    }

    // MARK: - 平台登录

    /// <summary>打开内嵌登录窗口：登录成功后自动获取并校验 Token。</summary>
    public void BeginPlatformLogin()
    {
        _loginWindow?.Close();
        var window = new LoginWindow(
            onToken: (token, __) =>
            {
                _ = SavePlatformTokenAsync(token).ContinueWith(t =>
                {
                    if (t.IsCompletedSuccessfully && t.Result)
                        OnLoginSucceeded?.Invoke();
                }, TaskScheduler.FromCurrentSynchronizationContext());
            },
            onCancel: () => { });
        _loginWindow = window;
        window.Show();
    }

    /// <summary>保存新的平台 Token 并立即校验；返回是否成功。</summary>
    public async Task<bool> SavePlatformTokenAsync(string token)
    {
        var trimmed = token.Trim();
        if (trimmed.Length == 0)
        {
            UsageError = PlatformException.EmptyToken().Message;
            return false;
        }
        try
        {
            var user = await _service.FetchCurrentUserAsync(trimmed);
            // 先校验 Token，再原子落盘（DPAPI 加密 + 写文件）；失败不触发登录成功
            if (!Settings.TrySetPlatformCredentials(trimmed, user.Email, out var setError))
            {
                UsageError = setError;
                return false;
            }
            Currency = user.Currency;
            UsageError = null;
            PlatformTokenExpired = false;
            await FetchUsageAsync();
            await FetchBalanceAsync();
            _consecutiveFailures = 0;
            StartPolling(); // 重新登录成功后恢复自动刷新
            return UsageError is null && LastError is null;
        }
        catch (PlatformException ex)
        {
            UsageError = ex.Message;
            if (ex.IsTokenExpired) PlatformTokenExpired = true;
            return false;
        }
    }

    public void ClearPlatformToken()
    {
        // 先清除设置文件中的加密字段（成功才清内存，失败保留一致登录状态）
        if (!Settings.TryClearPlatformCredentials(out var clearError))
        {
            LastError = "本地登录信息清除失败";
            return;
        }
        // 设置文件清除成功后，再清理 WebView2 网页登录数据
        var webDataCleared = LoginWindow.ClearWebViewData();
        MonthUsage = null;
        UsageError = null;
        LastBalance = null;
        PlatformTokenExpired = false;
        Currency = "CNY";
        LastError = webDataCleared
            ? null
            : "应用 Token 已清除，但网页登录数据清理失败";
    }

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

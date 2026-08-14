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

    private BalanceInfo? _lastBalance;
    private DateTime? _lastUpdate;
    private string? _lastError;

    private MonthUsage? _monthUsage;
    private string? _usageError;
    private bool _platformTokenExpired;
    private bool _isFetching;

    public MainViewModel(SettingsStore settings)
    {
        Settings = settings;
    }

    // MARK: - 绑定属性

    public BalanceInfo? LastBalance
    {
        get => _lastBalance;
        private set { if (!Equals(_lastBalance, value)) { _lastBalance = value; OnPropertyChanged(); } }
    }

    public DateTime? LastUpdate
    {
        get => _lastUpdate;
        private set { if (_lastUpdate != value) { _lastUpdate = value; OnPropertyChanged(); } }
    }

    public string? LastError
    {
        get => _lastError;
        private set { if (_lastError != value) { _lastError = value; OnPropertyChanged(); } }
    }

    public MonthUsage? MonthUsage
    {
        get => _monthUsage;
        private set { if (!ReferenceEquals(_monthUsage, value)) { _monthUsage = value; OnPropertyChanged(); } }
    }

    public string? UsageError
    {
        get => _usageError;
        private set { if (_usageError != value) { _usageError = value; OnPropertyChanged(); } }
    }

    public bool PlatformTokenExpired
    {
        get => _platformTokenExpired;
        private set { if (_platformTokenExpired != value) { _platformTokenExpired = value; OnPropertyChanged(); } }
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
        var interval = TimeSpan.FromSeconds(Settings.RefreshInterval);
        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = interval,
        };
        _timer.Tick += async (_, _) => await RefreshAsync();
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
        StartPolling();
    }

    public async Task RefreshAsync()
    {
        await PerformRefreshAsync();
    }

    // MARK: - 拉取

    public async Task PerformRefreshAsync()
    {
        if (IsFetching) return;
        IsFetching = true;
        try
        {
            await FetchBalanceAsync();
            await FetchUsageAsync();
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
            if (wallet is not null)
            {
                var bonus = summary.BonusWallets.FirstOrDefault()?.Value ?? 0;
                LastBalance = new BalanceInfo
                {
                    Currency = wallet.Currency,
                    TotalBalance = wallet.Balance,
                    GrantedBalance = bonus.ToString(CultureInfo.InvariantCulture),
                    ToppedUpBalance = Math.Max(0, wallet.Value - bonus).ToString(CultureInfo.InvariantCulture),
                };
                LastUpdate = DateTime.Now;
                LastError = null;
            }
        }
        catch (PlatformException ex)
        {
            LastError = ex.Message;
            if (ex.IsTokenExpired) PlatformTokenExpired = true;
        }
    }

    /// <summary>用量：拉取本月 usage/amount + usage/cost（对齐 macOS 版 async let 并发）。</summary>
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
            var now = DateTime.Now;
            var amountTask = _service.FetchUsageAmountAsync(Settings.PlatformToken, now.Month, now.Year);
            var costTask = _service.FetchUsageCostAsync(Settings.PlatformToken, now.Month, now.Year);
            await Task.WhenAll(amountTask, costTask);

            MonthUsage = new MonthUsage
            {
                Year = now.Year,
                Month = now.Month,
                AmountModels = amountTask.Result.Total,
                CostModels = costTask.Result.Total,
                CostDays = costTask.Result.Days ?? [],
                AmountDays = amountTask.Result.Days ?? [],
            };
            UsageError = null;
            PlatformTokenExpired = false;
        }
        catch (PlatformException ex)
        {
            UsageError = ex.Message;
            if (ex.IsTokenExpired) PlatformTokenExpired = true;
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
            Settings.PlatformToken = trimmed;
            Settings.PlatformUserName = user.Email;
            UsageError = null;
            PlatformTokenExpired = false;
            await FetchUsageAsync();
            await FetchBalanceAsync();
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
        Settings.ClearPlatformToken();
        MonthUsage = null;
        UsageError = null;
        LastBalance = null;
        LastError = null;
        PlatformTokenExpired = false;
    }

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

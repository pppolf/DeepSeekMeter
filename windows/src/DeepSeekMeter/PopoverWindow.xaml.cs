using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using DeepSeekMeter.Core;

namespace DeepSeekMeter;

/// <summary>
/// 悬浮窗主界面（对齐 macOS 版 Views/PopoverView.swift）。
/// 数据来自 MainViewModel（@Published 等价物：INotifyPropertyChanged）。
/// </summary>
public partial class PopoverWindow : Window
{
    private readonly MainViewModel _model;
    private bool _suppressEvents;

    /// <summary>模型用量行（UI 展示用）。</summary>
    private sealed record ModelRow(string Name, string Detail);

    /// <summary>Token 趋势指标（对齐 TrendMetric）。</summary>
    private enum TrendMetric { Output, CacheHit, Total }

    private TrendMetric _trend = TrendMetric.Output;

    public PopoverWindow(MainViewModel model)
    {
        InitializeComponent();
        _model = model;
        _model.PropertyChanged += (_, _) => Refresh();
        Refresh();
    }

    // MARK: - 刷新全部 UI

    private void Refresh()
    {
        if (!IsLoaded) return;

        UpdateHeader();
        UpdateBalance();
        UpdateUsage();
        UpdateTrend();
        UpdateErrorBanner();
        UpdateSettings();
        UpdateFooter();

        _suppressEvents = true;
        try
        {
            // 刷新间隔单选
            Interval15.IsChecked = _model.Settings.RefreshInterval == 15;
            Interval30.IsChecked = _model.Settings.RefreshInterval == 30;
            Interval60.IsChecked = _model.Settings.RefreshInterval == 60;
            Interval300.IsChecked = _model.Settings.RefreshInterval == 300;
            Interval600.IsChecked = _model.Settings.RefreshInterval == 600;

            // 趋势单选
            TrendOutput.IsChecked = _trend == TrendMetric.Output;
            TrendCacheHit.IsChecked = _trend == TrendMetric.CacheHit;
            TrendTotal.IsChecked = _trend == TrendMetric.Total;

            // 开机自启
            LaunchAtLoginBox.IsChecked = _model.Settings.LaunchAtLogin;
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    // MARK: - 头部

    private void UpdateHeader()
    {
        var hasBalance = _model.LastBalance is not null;
        var hasError = _model.LastError is not null;

        if (hasBalance)
        {
            StatusText.Text = "可用";
            StatusText.Foreground = new SolidColorBrush(Color.FromRgb(46, 160, 67));
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(46, 160, 67));
        }
        else if (hasError)
        {
            StatusText.Text = "异常";
            StatusText.Foreground = new SolidColorBrush(Color.FromRgb(229, 72, 77));
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(229, 72, 77));
        }
        else
        {
            StatusText.Text = "未获取";
            StatusText.Foreground = new SolidColorBrush(Color.FromRgb(136, 136, 136));
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(136, 136, 136));
        }

        TimeText.Text = _model.LastUpdate is { } t ? t.ToString("HH:mm:ss") : "";
    }

    // MARK: - 余额

    private void UpdateBalance()
    {
        if (_model.LastBalance is { } balance)
        {
            BalanceCurrencyText.Text = Formatting.CurrencySymbol(balance.Currency);
            BalanceValueText.Text = Formatting.Format(balance.Total);
            CurrencyCodeText.Text = $"币种：{balance.Currency}";
            GrantedText.Text = $"赠送 {Formatting.CurrencySymbol(balance.Currency)}{Formatting.Format(balance.Granted)}";
            ToppedUpText.Text = $"充值 {Formatting.CurrencySymbol(balance.Currency)}{Formatting.Format(balance.ToppedUp)}";
        }
        else
        {
            BalanceCurrencyText.Text = "¥";
            BalanceValueText.Text = "—";
            CurrencyCodeText.Text = "";
            GrantedText.Text = "赠送 —";
            ToppedUpText.Text = "充值 —";
        }
    }

    // MARK: - 本月用量

    private void UpdateUsage()
    {
        var usage = _model.MonthUsage;
        var expiredOrError = _model.PlatformTokenExpired || _model.UsageError is not null;

        if (usage is not null)
        {
            UsageContent.Visibility = Visibility.Visible;
            LoadingPanel.Visibility = Visibility.Collapsed;
            LoginPromptPanel.Visibility = Visibility.Collapsed;
            ExpiredPanel.Visibility = Visibility.Collapsed;

            var symbol = Formatting.CurrencySymbol("CNY");
            MonthTitleText.Text = $"{usage.Year}年{usage.Month}月用量";
            TotalCostText.Text = $"累计 {symbol}{Formatting.Format(usage.TotalCost)}";

            var today = DateTime.Now;
            var todayTokens = usage.TokensOn(today);
            TodayCostText.Text = $"{symbol}{Formatting.Format(usage.CostOn(today))}";
            TodayRequestsText.Text = Formatting.CountString(todayTokens.Requests);
            TodayOutputText.Text = Formatting.TokenString(todayTokens.Response);

            MonthRequestsText.Text = Formatting.CountString(usage.TotalRequests);
            MonthOutputText.Text = Formatting.TokenString(usage.ResponseTokens);
            CacheHitText.Text = Formatting.TokenString(usage.CacheHitTokens);

            // 按模型拆分（仅显示有请求的模型，对齐 macOS filter { $0.requests > 0 }）
            var rows = usage.AmountModels
                .Where(m => m.Requests > 0)
                .Select(m =>
                {
                    var cost = usage.CostModels.FirstOrDefault(c => c.Model == m.Model)?
                        .Usage.Sum(i => i.Value) ?? 0;
                    return new ModelRow(
                        Formatting.ModelDisplayName(m.Model),
                        $"{Formatting.CountString(m.Requests)} 次 · {symbol}{Formatting.Format(cost)}");
                })
                .ToList();
            ModelList.ItemsSource = rows;
        }
        else if (expiredOrError)
        {
            UsageContent.Visibility = Visibility.Collapsed;
            LoadingPanel.Visibility = Visibility.Collapsed;
            LoginPromptPanel.Visibility = Visibility.Collapsed;
            ExpiredPanel.Visibility = Visibility.Visible;

            ExpiredText.Text = _model.PlatformTokenExpired
                ? "平台登录已过期，请重新登录"
                : (_model.UsageError ?? "用量获取失败");
        }
        else if (_model.IsFetching)
        {
            UsageContent.Visibility = Visibility.Collapsed;
            LoadingPanel.Visibility = Visibility.Visible;
            LoginPromptPanel.Visibility = Visibility.Collapsed;
            ExpiredPanel.Visibility = Visibility.Collapsed;
        }
        else
        {
            UsageContent.Visibility = Visibility.Collapsed;
            LoadingPanel.Visibility = Visibility.Collapsed;
            LoginPromptPanel.Visibility = Visibility.Visible;
            ExpiredPanel.Visibility = Visibility.Collapsed;
        }
    }

    // MARK: - Token 趋势

    private void UpdateTrend()
    {
        var usage = _model.MonthUsage;
        TrendEmptyText.Visibility = Visibility.Collapsed;

        if (usage is null)
        {
            TrendChart.Entries = [];
            TrendTodayText.Text = "今日 —";
            TrendPeakText.Text = "";
            if (_model.UsageError is null && !_model.IsFetching)
                TrendEmptyText.Visibility = Visibility.Visible;
            return;
        }

        var todayKey = usage.AmountDays.Max(d => d.Date);
        var entries = new List<SparklineControl.Entry>();
        foreach (var day in usage.AmountDays)
        {
            if (string.CompareOrdinal(day.Date, todayKey) > 0) continue;
            if (!DateTime.TryParseExact(day.Date, "yyyy-MM-dd",
                    System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None, out var date)) continue;
            entries.Add(new SparklineControl.Entry(date, DailyValue(day)));
        }
        TrendChart.Entries = entries;

        var today = DateTime.Now;
        var todayDay = usage.AmountDays.FirstOrDefault(d => d.Date == today.ToString("yyyy-MM-dd"));
        TrendTodayText.Text = $"今日 {Formatting.TokenString(todayDay is null ? 0 : DailyValue(todayDay))}";

        if (entries.Count > 0)
        {
            var peak = entries.MaxBy(e => e.Value)!;
            TrendPeakText.Text = $"峰值 {Formatting.TokenString(peak.Value)}（{peak.Date.Month}月{peak.Date.Day}日）";
        }
        else
        {
            TrendPeakText.Text = "";
        }
    }

    private double DailyValue(UsageDay day)
    {
        var resp = day.Data.Sum(m => m.ValueFor("RESPONSE_TOKEN"));
        var hit = day.Data.Sum(m => m.ValueFor("PROMPT_CACHE_HIT_TOKEN"));
        var miss = day.Data.Sum(m => m.ValueFor("PROMPT_CACHE_MISS_TOKEN"));
        return _trend switch
        {
            TrendMetric.Output => resp,
            TrendMetric.CacheHit => hit,
            _ => resp + hit + miss,
        };
    }

    // MARK: - 错误横幅 / 设置 / 底部

    private void UpdateErrorBanner()
    {
        if (_model.LastError is { } error)
        {
            ErrorBanner.Visibility = Visibility.Visible;
            ErrorText.Text = error;
        }
        else
        {
            ErrorBanner.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateSettings()
    {
        var loggedIn = !string.IsNullOrEmpty(_model.Settings.PlatformToken);
        if (loggedIn)
        {
            AccountStatusText.Text = "已登录 ✓";
            AccountStatusText.Foreground = new SolidColorBrush(Color.FromRgb(46, 160, 67));
            AccountNameText.Text = _model.Settings.PlatformUserName;
            LoginButton.Content = "重新登录";
            LoginButton.Background = Brushes.Transparent;
            LoginButton.BorderBrush = new SolidColorBrush(Color.FromRgb(204, 204, 204));
            LoginButton.Foreground = new SolidColorBrush(Color.FromRgb(51, 51, 51));
        }
        else
        {
            AccountStatusText.Text = "未登录";
            AccountStatusText.Foreground = new SolidColorBrush(Color.FromRgb(136, 136, 136));
            AccountNameText.Text = "";
            LoginButton.Content = "登录";
            LoginButton.Background = new SolidColorBrush(Color.FromRgb(77, 107, 254));
            LoginButton.BorderBrush = Brushes.Transparent;
            LoginButton.Foreground = Brushes.White;
        }
    }

    private void UpdateFooter()
    {
        RefreshButton.Content = _model.IsFetching ? "刷新中…" : "刷新";
        RefreshButton.IsEnabled = !_model.IsFetching;
        LogoutButton.Visibility = string.IsNullOrEmpty(_model.Settings.PlatformToken)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    // MARK: - 事件

    private void OnLoginPromptClick(object sender, RoutedEventArgs e) => _model.BeginPlatformLogin();

    private async void OnRefreshClick(object sender, RoutedEventArgs e) => await _model.RefreshAsync();

    private void OnLogoutClick(object sender, RoutedEventArgs e) => _model.ClearPlatformToken();

    private void OnQuitClick(object sender, RoutedEventArgs e) => Application.Current.Shutdown();

    private void OnIntervalChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        double interval = 60;
        if (ReferenceEquals(sender, Interval15)) interval = 15;
        else if (ReferenceEquals(sender, Interval30)) interval = 30;
        else if (ReferenceEquals(sender, Interval60)) interval = 60;
        else if (ReferenceEquals(sender, Interval300)) interval = 300;
        else if (ReferenceEquals(sender, Interval600)) interval = 600;
        _model.SetRefreshInterval(interval);
    }

    private void OnLaunchAtLoginChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        _model.Settings.LaunchAtLogin = LaunchAtLoginBox.IsChecked == true;
    }

    private void OnTrendChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        if (ReferenceEquals(sender, TrendOutput)) _trend = TrendMetric.Output;
        else if (ReferenceEquals(sender, TrendCacheHit)) _trend = TrendMetric.CacheHit;
        else if (ReferenceEquals(sender, TrendTotal)) _trend = TrendMetric.Total;
        UpdateTrend();
    }

    /// <summary>点击外部自动关闭（对齐 NSPopover transient 行为）。</summary>
    private void OnDeactivated(object? sender, EventArgs e) => Hide();
}

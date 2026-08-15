using System.ComponentModel;
using System.Threading;
using System.Windows;
using DeepSeekMeter.Core;

namespace DeepSeekMeter;

/// <summary>
/// 应用入口（对齐 macOS 版 AppMain + AppDelegate）：
/// 无主窗口，仅托盘图标；首次使用自动弹出悬浮窗引导登录。
/// </summary>
public partial class App : System.Windows.Application
{
    private SettingsStore? _settings;
    private MainViewModel? _model;
    private TrayIconController? _tray;
    private Mutex? _singleInstanceMutex;
    private bool _syncingLaunchAtLogin;

    /// <summary>二次启动信号：已有实例收到后打开悬浮窗，而非静默退出。</summary>
    private static readonly EventWaitHandle ShowSignal =
        new(false, EventResetMode.AutoReset, @"Local\DeepSeekMeter.Show");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 单实例：已有实例时通知它打开悬浮窗，本实例退出（不重复托盘图标）
        _singleInstanceMutex = new Mutex(true, @"Local\DeepSeekMeter", out var createdNew);
        if (!createdNew)
        {
            try { ShowSignal.Set(); } catch { /* 忽略 */ }
            Shutdown();
            return;
        }

        _settings = new SettingsStore();
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        _model = new MainViewModel(_settings);
        _model.OnLoginSucceeded = () => _tray?.ShowPopover();
        _tray = new TrayIconController(_model);

        ShutdownMode = ShutdownMode.OnExplicitShutdown; // 无主窗口，托盘「退出」时手动关闭

        ReconcileLaunchAtLogin(); // 启动时核对设置与注册表真实状态
        StartShowSignalListener(); // 监听二次启动信号

        _model.StartPolling();

        // 启动即弹出悬浮窗（默认置顶），避免藏在托盘后台找不到
        Dispatcher.BeginInvoke(async () =>
        {
            await Task.Delay(500);
            _tray?.ShowPopover();
        });

        // 展示一次迁移/解密警告（构造期间产生，此时 UI 已可订阅）
        ShowStartupWarning();
    }

    /// <summary>展示一次迁移/解密警告（不含 Token）。</summary>
    private void ShowStartupWarning()
    {
        if (_settings is null || string.IsNullOrEmpty(_settings.StartupWarning)) return;
        var warning = _settings.StartupWarning;
        try
        {
            MessageBox.Show(warning, "DeepSeek Meter", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch
        {
            // 无桌面会话时忽略提示
        }
    }

    /// <summary>启动时核对设置与注册表真实状态，保证界面显示的是真实自启状态。</summary>
    private void ReconcileLaunchAtLogin()
    {
        if (_settings is null) return;
        var registryEnabled = StartupService.IsEnabled();
        _syncingLaunchAtLogin = true;
        try
        {
            if (_settings.LaunchAtLogin && !registryEnabled)
            {
                // 设置开启但注册表被外部删除：重新注册
                StartupService.Enable();
            }
            else if (!_settings.LaunchAtLogin && registryEnabled)
            {
                // 注册表存在但设置关闭：以注册表为准，同步设置（界面不能错误显示关闭）
                _settings.LaunchAtLogin = true;
            }
        }
        finally
        {
            _syncingLaunchAtLogin = false;
        }
    }

    /// <summary>监听二次启动信号：收到后打开悬浮窗。</summary>
    private void StartShowSignalListener()
    {
        Task.Run(() =>
        {
            while (true)
            {
                try
                {
                    ShowSignal.WaitOne();
                    Dispatcher.BeginInvoke(() => _tray?.ShowPopover());
                }
                catch (ObjectDisposedException)
                {
                    break;
                }
                catch (AbandonedMutexException)
                {
                    // 信号被异常放弃，继续等待
                }
                catch
                {
                    break;
                }
            }
        });
    }

    /// <summary>开机自启开关变更时同步注册表（对齐 macOS SMAppService）；失败则回滚并提示，保证设置/UI/注册表一致。</summary>
    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(SettingsStore.LaunchAtLogin) || _settings is null) return;
        if (_syncingLaunchAtLogin) return; // 回滚触发的二次变更，避免递归

        var ok = _settings.LaunchAtLogin ? StartupService.Enable() : StartupService.Disable();
        if (ok) return;

        // 注册表操作失败：回滚设置值，UI 通过 PropertyChanged 同步回原状态，并给出简洁提示
        _syncingLaunchAtLogin = true;
        try
        {
            _settings.LaunchAtLogin = !_settings.LaunchAtLogin;
        }
        finally
        {
            _syncingLaunchAtLogin = false;
        }
        try
        {
            MessageBox.Show(
                "开机自启设置失败，已还原。可能没有写入注册表的权限。",
                "DeepSeek Meter",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        catch
        {
            // 无桌面会话时忽略提示
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _model?.StopPolling();
        _tray?.Dispose();
        _tray = null;
        _singleInstanceMutex?.ReleaseMutex();
        _singleInstanceMutex?.Dispose();
        _singleInstanceMutex = null;
        base.OnExit(e);
    }
}

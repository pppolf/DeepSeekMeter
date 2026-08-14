using System.ComponentModel;
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

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 单实例：已有实例时直接退出（避免重复托盘图标）；Mutex 保持到进程退出
        _singleInstanceMutex = new Mutex(true, @"Local\DeepSeekMeter", out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        _settings = new SettingsStore();
        _settings.PropertyChanged += OnSettingsPropertyChanged;
        _model = new MainViewModel(_settings);
        _model.OnLoginSucceeded = () => _tray?.ShowPopover();
        _tray = new TrayIconController(_model);

        ShutdownMode = ShutdownMode.OnExplicitShutdown; // 无主窗口，托盘「退出」时手动关闭

        _model.StartPolling();

        // 首次使用：自动弹出悬浮窗引导登录
        if (string.IsNullOrEmpty(_settings.PlatformToken))
        {
            Dispatcher.BeginInvoke(async () =>
            {
                await Task.Delay(500);
                _tray?.ShowPopover();
            });
        }
    }

    /// <summary>开机自启开关变更时同步注册表（对齐 macOS SMAppService）。</summary>
    private void OnSettingsPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(SettingsStore.LaunchAtLogin) || _settings is null) return;
        if (_settings.LaunchAtLogin)
            StartupService.Enable();
        else
            StartupService.Disable();
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

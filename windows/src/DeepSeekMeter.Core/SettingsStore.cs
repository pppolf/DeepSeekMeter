using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace DeepSeekMeter.Core;

/// <summary>
/// 用户设置：平台 Token + 刷新间隔 + 开机自启。
/// 持久化到本机 JSON 文件（默认 %APPDATA%\DeepSeekMeter\settings.json），
/// 对齐 macOS 版 SettingsStore.swift 的 UserDefaults/plist 语义（Token 只存本机、不存钥匙串）。
/// </summary>
public sealed class SettingsStore : INotifyPropertyChanged
{
    /// <summary>可选的刷新间隔（秒）。</summary>
    public static readonly double[] IntervalOptions = [15, 30, 60, 300, 600];

    /// <summary>设置文件路径（测试可注入临时路径）。</summary>
    public string SettingsFilePath { get; }

    private string _platformToken = "";
    private string _platformUserName = "";
    private double _refreshInterval = 60;
    private bool _launchAtLogin;

    public SettingsStore(string? settingsFilePath = null)
    {
        SettingsFilePath = settingsFilePath ?? DefaultPath();
        Load();
    }

    public static string DefaultPath()
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DeepSeekMeter");
        return Path.Combine(dir, "settings.json");
    }

    // MARK: - 属性（变更即保存，对齐 didSet 行为）

    public string PlatformToken
    {
        get => _platformToken;
        set
        {
            if (_platformToken == value) return;
            _platformToken = value;
            OnPropertyChanged();
            Save();
        }
    }

    public string PlatformUserName
    {
        get => _platformUserName;
        set
        {
            if (_platformUserName == value) return;
            _platformUserName = value;
            OnPropertyChanged();
            Save();
        }
    }

    public double RefreshInterval
    {
        get => _refreshInterval;
        set
        {
            if (Math.Abs(_refreshInterval - value) < 0.001) return;
            _refreshInterval = value;
            OnPropertyChanged();
            Save();
        }
    }

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            if (_launchAtLogin == value) return;
            _launchAtLogin = value;
            OnPropertyChanged();
            Save();
        }
    }

    public void ClearPlatformToken()
    {
        PlatformToken = "";
        PlatformUserName = "";
    }

    // MARK: - 持久化

    private sealed class Snapshot
    {
        public string? PlatformToken { get; set; }
        public string? PlatformUserName { get; set; }
        public double? RefreshInterval { get; set; }
        public bool? LaunchAtLogin { get; set; }
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(SettingsFilePath)) return;
            var json = File.ReadAllText(SettingsFilePath);
            var snap = JsonSerializer.Deserialize<Snapshot>(json, SnapshotOptions);
            if (snap is null) return;
            _platformToken = snap.PlatformToken ?? "";
            _platformUserName = snap.PlatformUserName ?? "";
            _refreshInterval = (snap.RefreshInterval is > 0) ? snap.RefreshInterval!.Value : 60;
            _launchAtLogin = snap.LaunchAtLogin ?? false;
        }
        catch (Exception ex)
        {
            // 设置损坏时回退默认值，不影响启动
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 读取设置失败：{ex.Message}");
        }
    }

    private void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(SettingsFilePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var snap = new Snapshot
            {
                PlatformToken = _platformToken,
                PlatformUserName = _platformUserName,
                RefreshInterval = _refreshInterval,
                LaunchAtLogin = _launchAtLogin,
            };
            var json = JsonSerializer.Serialize(snap, SnapshotOptions);
            // 原子写入：先写临时文件再替换
            var tmp = SettingsFilePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, SettingsFilePath, overwrite: true);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 保存设置失败：{ex.Message}");
        }
    }

    private static readonly JsonSerializerOptions SnapshotOptions = new() { WriteIndented = true };

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

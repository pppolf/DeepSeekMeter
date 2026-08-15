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
        _platformToken = "";
        _platformUserName = "";
        OnPropertyChanged(nameof(PlatformToken));
        OnPropertyChanged(nameof(PlatformUserName));
        Save(); // 写空：PlatformTokenProtected 为 null，明文字段不写入
        // 清理可能残留的临时设置文件（其中也可能含密文）
        try
        {
            var tmp = SettingsFilePath + ".tmp";
            if (File.Exists(tmp)) File.Delete(tmp);
        }
        catch
        {
            // 忽略临时文件清理失败
        }
    }

    /// <summary>设置保存失败时触发（参数为失败原因），供 UI 提示。</summary>
    public event Action<string>? SaveFailed;

    /// <summary>最近一次保存是否成功。</summary>
    public bool LastSaveSucceeded { get; private set; } = true;

    // MARK: - 持久化

    private sealed class Snapshot
    {
        /// <summary>旧版明文 Token（仅用于迁移读取，保存时不再写入）。</summary>
        public string? PlatformToken { get; set; }
        /// <summary>新版 DPAPI 加密 Token（Base64）。</summary>
        public string? PlatformTokenProtected { get; set; }
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
            _platformUserName = snap.PlatformUserName ?? "";
            // 刷新间隔只接受项目已有合法选项，损坏/非法值回退 1 分钟
            var loaded = (snap.RefreshInterval is > 0) ? snap.RefreshInterval!.Value : 60;
            _refreshInterval = IntervalOptions.Contains(loaded) ? loaded : 60;
            _launchAtLogin = snap.LaunchAtLogin ?? false;

            // Token：优先解密新版密文；否则迁移旧明文
            if (!string.IsNullOrEmpty(snap.PlatformTokenProtected))
            {
                _platformToken = UnprotectToken(snap.PlatformTokenProtected) ?? "";
            }
            else if (!string.IsNullOrEmpty(snap.PlatformToken))
            {
                _platformToken = snap.PlatformToken;
                MigrateLegacyToken(); // 加密成功后写回密文并删除明文
            }
        }
        catch (Exception ex)
        {
            // 设置损坏时回退默认值，不影响启动
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 读取设置失败：{ex.Message}");
        }
    }

    /// <summary>旧明文 Token 迁移：加密成功后重新保存（密文替换明文，旧文件在加密失败时不受影响）。</summary>
    private void MigrateLegacyToken()
    {
        try
        {
            Save(); // Save 只写 PlatformTokenProtected，加密失败会抛异常并保留旧文件
        }
        catch
        {
            // 加密失败：保留旧明文配置，不破坏；下次仍可重试
        }
    }

    private static string? ProtectToken(string token)
    {
        if (string.IsNullOrEmpty(token)) return null;
        return Convert.ToBase64String(TokenProtector.Protect(token));
    }

    private static string? UnprotectToken(string base64)
    {
        try
        {
            var cipher = Convert.FromBase64String(base64);
            return TokenProtector.Unprotect(cipher);
        }
        catch
        {
            return null; // 损坏密文/解密失败 → 需要重新登录
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
                // 不写明文 PlatformToken，只写密文 PlatformTokenProtected
                PlatformTokenProtected = ProtectToken(_platformToken),
                PlatformUserName = _platformUserName,
                RefreshInterval = _refreshInterval,
                LaunchAtLogin = _launchAtLogin,
            };
            var json = JsonSerializer.Serialize(snap, SnapshotOptions);
            // 原子写入：先写临时文件再替换（.tmp 中只含密文）
            var tmp = SettingsFilePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, SettingsFilePath, overwrite: true);
            LastSaveSucceeded = true;
        }
        catch (Exception ex)
        {
            LastSaveSucceeded = false;
            // 只记录不含 Token 的可读错误
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 保存设置失败：{ex.Message}");
            SaveFailed?.Invoke("设置保存失败，请检查磁盘空间或文件权限"); // 让界面知道，不含敏感信息
        }
    }

    private static readonly JsonSerializerOptions SnapshotOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

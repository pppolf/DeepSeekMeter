using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeepSeekMeter.Core;

/// <summary>
/// 用户设置：平台 Token（DPAPI 加密）+ 刷新间隔 + 开机自启。
/// 持久化到本机 JSON 文件（默认 %APPDATA%\DeepSeekMeter\settings.json）。
/// 凭据通过原子操作写入：先加密并落盘成功，再更新内存状态，失败不假装成功。
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

    /// <summary>构造完成后可读取的启动警告（迁移/解密失败），由应用启动后展示一次，不含 Token。</summary>
    public string? StartupWarning { get; private set; }

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

    // MARK: - 属性

    /// <summary>平台 Token（内存中的明文，仅用于网络请求；落盘时加密）。</summary>
    public string PlatformToken => _platformToken;

    /// <summary>平台用户名（邮箱）。</summary>
    public string PlatformUserName => _platformUserName;

    public double RefreshInterval
    {
        get => _refreshInterval;
        set
        {
            if (Math.Abs(_refreshInterval - value) < 0.001) return;
            var previous = _refreshInterval;
            _refreshInterval = value;
            if (WriteSettings(_platformToken, _platformUserName, out var error))
            {
                OnPropertyChanged();
            }
            else
            {
                _refreshInterval = previous; // 保存失败回滚，不假装成功
                SaveFailed?.Invoke(error ?? "设置保存失败");
            }
        }
    }

    public bool LaunchAtLogin
    {
        get => _launchAtLogin;
        set
        {
            if (_launchAtLogin == value) return;
            var previous = _launchAtLogin;
            _launchAtLogin = value;
            if (WriteSettings(_platformToken, _platformUserName, out var error))
            {
                OnPropertyChanged();
            }
            else
            {
                _launchAtLogin = previous;
                SaveFailed?.Invoke(error ?? "设置保存失败");
            }
        }
    }

    // MARK: - 原子凭据操作

    /// <summary>原子保存平台凭据：先加密并落盘成功，再更新内存；失败不改内存并返回脱敏错误。</summary>
    public bool TrySetPlatformCredentials(string token, string userName, out string? error)
    {
        error = null;
        if (!WriteSettings(token, userName, out error)) return false;

        _platformToken = token;
        _platformUserName = userName;
        OnPropertyChanged(nameof(PlatformToken));
        OnPropertyChanged(nameof(PlatformUserName));
        return true;
    }

    /// <summary>原子清除平台凭据：先在设置文件移除加密字段成功，再清内存；失败保留一致登录状态。</summary>
    public bool TryClearPlatformCredentials(out string? error)
    {
        error = null;
        if (!WriteSettings(null, null, out error)) return false;

        _platformToken = "";
        _platformUserName = "";
        OnPropertyChanged(nameof(PlatformToken));
        OnPropertyChanged(nameof(PlatformUserName));
        return true;
    }

    /// <summary>设置保存失败时触发（参数为脱敏中文提示）。</summary>
    public event Action<string>? SaveFailed;

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
                var token = UnprotectToken(snap.PlatformTokenProtected);
                if (token is null)
                {
                    _platformToken = "";
                    StartupWarning = "本地登录信息无法解密，请重新登录";
                }
                else
                {
                    _platformToken = token;
                }
            }
            else if (!string.IsNullOrEmpty(snap.PlatformToken))
            {
                // 旧明文迁移：加密成功落盘后才视为迁移成功；失败保留旧文件
                if (WriteSettings(snap.PlatformToken, snap.PlatformUserName, out _))
                {
                    _platformToken = snap.PlatformToken;
                }
                else
                {
                    _platformToken = "";
                    StartupWarning = "本地登录信息迁移失败，请重新登录";
                }
            }
        }
        catch (Exception ex)
        {
            // 设置损坏时回退默认值，不影响启动
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 读取设置失败：{ex.Message}");
        }
    }

    /// <summary>
    /// 底层持久化：加密 token（若非空）后原子写入设置文件。返回是否成功及脱敏错误。
    /// 不修改任何内存字段；.tmp 中只含密文。
    /// </summary>
    private bool WriteSettings(string? token, string? userName, out string? error)
    {
        error = null;
        string? protectedToken = null;
        if (!string.IsNullOrEmpty(token))
        {
            try
            {
                protectedToken = Convert.ToBase64String(TokenProtector.Protect(token));
            }
            catch
            {
                error = "本地登录信息加密失败，请重试";
                return false;
            }
        }

        try
        {
            var dir = Path.GetDirectoryName(SettingsFilePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var snap = new Snapshot
            {
                PlatformTokenProtected = protectedToken,
                PlatformUserName = userName,
                RefreshInterval = _refreshInterval,
                LaunchAtLogin = _launchAtLogin,
            };
            var json = JsonSerializer.Serialize(snap, SnapshotOptions);
            var tmp = SettingsFilePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, SettingsFilePath, overwrite: true);
            return true;
        }
        catch (Exception ex)
        {
            error = "设置保存失败，请检查磁盘空间或文件权限";
            // 只记录不含 Token、不含路径敏感信息的可读错误
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 设置保存失败：{ex.Message}");
            return false;
        }
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

    private static readonly JsonSerializerOptions SnapshotOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

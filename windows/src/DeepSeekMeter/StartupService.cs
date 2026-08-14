using Microsoft.Win32;

namespace DeepSeekMeter;

/// <summary>
/// 开机自启：注册表 HKCU\...\Run 键（对齐 macOS 版 SMAppService 语义）。
/// 只写当前用户（HKCU），无需管理员权限。
/// </summary>
public static class StartupService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "DeepSeekMeter";

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(ValueName) is string v && !string.IsNullOrEmpty(v);
    }

    /// <summary>启用：写入当前 exe 路径（带引号，路径含空格也能正常启动）。返回是否成功。</summary>
    public static bool Enable()
    {
        try
        {
            var path = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(path)) return false;

            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
            // 用引号包起来，避免「C:\Program Files\...\DeepSeekMeter.exe」这类含空格路径启动失败
            key.SetValue(ValueName, $"\"{path}\"");
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 开启自启失败：{ex.Message}");
            return false;
        }
    }

    /// <summary>禁用：删除注册表项。返回是否成功。</summary>
    public static bool Disable()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(ValueName, throwOnMissingValue: false);
            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[DeepSeekMeter] 关闭自启失败：{ex.Message}");
            return false;
        }
    }
}

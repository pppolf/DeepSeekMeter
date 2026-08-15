using System.Runtime.InteropServices;
using System.Text;

namespace DeepSeekMeter.Core;

/// <summary>
/// 平台 Token 保护：使用 Windows DPAPI（CryptProtectData/CryptUnprotectData），
/// 绑定当前 Windows 用户（CurrentUser 语义，无额外熵），零第三方依赖。
/// 密文仅在当前用户会话内可解密；解密失败调用方按「需要重新登录」处理。
/// </summary>
public static class TokenProtector
{
    private const int CryptprotectUiForbidden = 0x1;

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob
    {
        public int cbData;
        public IntPtr pbData;
    }

    /// <summary>加密为字节数组（失败抛异常，异常信息不含 Token 内容）。</summary>
    public static byte[] Protect(string plain)
    {
        if (string.IsNullOrEmpty(plain)) return [];

        var plainBytes = Encoding.UTF8.GetBytes(plain);
        var inBlob = new DataBlob { cbData = plainBytes.Length, pbData = Marshal.AllocHGlobal(plainBytes.Length) };
        try
        {
            Marshal.Copy(plainBytes, 0, inBlob.pbData, plainBytes.Length);
            var entropy = default(DataBlob); // 无额外熵，仅绑定当前用户
            var outBlob = default(DataBlob);
            if (!CryptProtectData(ref inBlob, null, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, ref outBlob))
                throw new InvalidOperationException("令牌加密失败");

            var result = new byte[outBlob.cbData];
            Marshal.Copy(outBlob.pbData, result, 0, outBlob.cbData);
            LocalFree(outBlob.pbData);
            return result;
        }
        finally
        {
            Marshal.FreeHGlobal(inBlob.pbData);
        }
    }

    /// <summary>解密；失败返回 null（调用方按「需要重新登录」处理，不抛异常）。</summary>
    public static string? Unprotect(byte[] cipher)
    {
        if (cipher is null || cipher.Length == 0) return null;

        var inBlob = new DataBlob { cbData = cipher.Length, pbData = Marshal.AllocHGlobal(cipher.Length) };
        try
        {
            Marshal.Copy(cipher, 0, inBlob.pbData, cipher.Length);
            var entropy = default(DataBlob);
            var outBlob = default(DataBlob);
            if (!CryptUnprotectData(ref inBlob, null, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, ref outBlob))
                return null;

            var result = new byte[outBlob.cbData];
            Marshal.Copy(outBlob.pbData, result, 0, outBlob.cbData);
            LocalFree(outBlob.pbData);
            return Encoding.UTF8.GetString(result);
        }
        catch
        {
            return null;
        }
        finally
        {
            Marshal.FreeHGlobal(inBlob.pbData);
        }
    }

    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptProtectData(
        ref DataBlob pDataIn, string? szDataDescr, ref DataBlob pOptionalEntropy,
        IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DataBlob pDataOut);

    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CryptUnprotectData(
        ref DataBlob pDataIn, string? szDataDescr, ref DataBlob pOptionalEntropy,
        IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DataBlob pDataOut);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr hMem);
}

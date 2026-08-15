using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace DeepSeekMeter.Core;

/// <summary>
/// 平台 Token 保护：使用 Windows DPAPI（CryptProtectData/CryptUnprotectData），
/// 绑定当前 Windows 用户（CurrentUser 语义，无额外熵），零第三方依赖。
/// 密文仅在当前用户会话内可解密；解密失败调用方按「需要重新登录」处理。
/// 明文临时缓冲（托管与非托管）在用后清零，非托管 LocalAlloc 在所有路径统一 LocalFree。
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
        try
        {
            return ProtectCore(plainBytes);
        }
        finally
        {
            // 清理托管明文副本
            CryptographicOperations.ZeroMemory(plainBytes);
        }
    }

    private static byte[] ProtectCore(byte[] plainBytes)
    {
        var inBlob = default(DataBlob);
        var outBlob = default(DataBlob);
        inBlob.pbData = Marshal.AllocHGlobal(plainBytes.Length);
        inBlob.cbData = plainBytes.Length;
        try
        {
            Marshal.Copy(plainBytes, 0, inBlob.pbData, plainBytes.Length);
            var entropy = default(DataBlob); // 无额外熵，仅绑定当前用户
            if (!CryptProtectData(ref inBlob, null, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, ref outBlob))
            {
                var winErr = Marshal.GetLastWin32Error();
                throw new InvalidOperationException($"令牌加密失败（错误码 0x{winErr:X8}）");
            }
            var result = new byte[outBlob.cbData];
            Marshal.Copy(outBlob.pbData, result, 0, outBlob.cbData);
            return result;
        }
        finally
        {
            // 释放 DPAPI 输出（LocalAlloc）
            if (outBlob.pbData != IntPtr.Zero)
            {
                LocalFree(outBlob.pbData);
                outBlob.pbData = IntPtr.Zero;
            }
            // 释放前清零非托管输入缓冲（含明文）
            if (inBlob.pbData != IntPtr.Zero)
            {
                ZeroNative(inBlob.pbData, plainBytes.Length);
                Marshal.FreeHGlobal(inBlob.pbData);
                inBlob.pbData = IntPtr.Zero;
            }
        }
    }

    /// <summary>解密；失败返回 null（调用方按「需要重新登录」处理，不抛异常）。</summary>
    public static string? Unprotect(byte[] cipher)
    {
        if (cipher is null || cipher.Length == 0) return null;

        var inBlob = default(DataBlob);
        var outBlob = default(DataBlob);
        inBlob.pbData = Marshal.AllocHGlobal(cipher.Length);
        inBlob.cbData = cipher.Length;
        try
        {
            Marshal.Copy(cipher, 0, inBlob.pbData, cipher.Length);
            var entropy = default(DataBlob);
            if (!CryptUnprotectData(ref inBlob, null, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptprotectUiForbidden, ref outBlob))
                return null;

            var plainBytes = new byte[outBlob.cbData];
            Marshal.Copy(outBlob.pbData, plainBytes, 0, outBlob.cbData);
            try
            {
                return Encoding.UTF8.GetString(plainBytes);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(plainBytes);
            }
        }
        catch
        {
            return null;
        }
        finally
        {
            if (outBlob.pbData != IntPtr.Zero)
            {
                LocalFree(outBlob.pbData);
                outBlob.pbData = IntPtr.Zero;
            }
            if (inBlob.pbData != IntPtr.Zero)
            {
                // 密文不敏感，但保持一致清理
                Marshal.FreeHGlobal(inBlob.pbData);
                inBlob.pbData = IntPtr.Zero;
            }
        }
    }

    private static readonly byte[] ZeroBuffer = new byte[1024];

    /// <summary>清零非托管内存（用于含明文的输入缓冲）。</summary>
    private static void ZeroNative(IntPtr ptr, int length)
    {
        int remaining = length;
        int offset = 0;
        while (remaining > 0)
        {
            int chunk = Math.Min(remaining, ZeroBuffer.Length);
            Marshal.Copy(ZeroBuffer, 0, ptr + offset, chunk);
            offset += chunk;
            remaining -= chunk;
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

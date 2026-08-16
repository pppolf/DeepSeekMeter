package com.deepseek.meter.core

/**
 * Token 存取抽象（对齐 ios/DeepSeekMeterCore TokenStoring / 决策见 MOBILE-PLAN.md 4.4）：
 * - Android 实现：Keystore AES/GCM 加密后密文存 SharedPreferences（App 层提供）
 * - 自测：内存实现
 * 读取失败统一按「需要重新登录」处理（对齐 Windows TokenProtector 语义）。
 */
interface TokenStore {
    fun loadToken(): String?
    fun saveToken(token: String)
    fun clearToken()
}

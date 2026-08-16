package com.deepseek.meter.core

/**
 * 低余额通知策略（纯函数，可 JVM 单测；对齐 iOS 低余额通知语义）。
 * 只做决策：是否应该通知 + 新的 alerted（已提醒）状态；持久化由 App 层负责
 * （SharedPreferences 非敏感标志），本类不依赖 NotificationManager / Context / androidx.work。
 */
data class LowBalanceDecision(
    val shouldNotify: Boolean,
    val alerted: Boolean
)

object LowBalancePolicy {
    /** 默认阈值：1.0 = 当前钱包币种的一个单位（CNY → ¥1.00、USD → $1.00） */
    const val DEFAULT_THRESHOLD = 1.0

    /**
     * 低余额决策状态机：
     *  - balance <= 0：无有效低余额区间，不通知，alerted 保持；
     *  - 0 < balance < threshold 且 alerted == false：首次低余额 → 通知，alerted = true；
     *  - 0 < balance < threshold 且 alerted == true：同一低余额周期 → 不重复通知；
     *  - balance >= threshold：余额恢复 → 不通知，alerted 重置（下次跌破可再次提醒）。
     *
     * @param balance   当前钱包余额数值（币种由调用方保证与 threshold 一致）
     * @param threshold 低余额阈值（默认 1.0，表示当前钱包币种的一个单位）
     * @param alerted   上次提醒状态（App 层从 SharedPreferences 读入）
     */
    fun evaluate(
        balance: Double,
        threshold: Double = DEFAULT_THRESHOLD,
        alerted: Boolean
    ): LowBalanceDecision {
        if (balance <= 0.0) {
            return LowBalanceDecision(shouldNotify = false, alerted = alerted)
        }
        if (balance >= threshold) {
            return LowBalanceDecision(shouldNotify = false, alerted = false)
        }
        if (alerted) {
            return LowBalanceDecision(shouldNotify = false, alerted = true)
        }
        return LowBalanceDecision(shouldNotify = true, alerted = true)
    }
}

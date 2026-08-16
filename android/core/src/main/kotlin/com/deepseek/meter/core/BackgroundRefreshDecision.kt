package com.deepseek.meter.core

/**
 * 后台刷新结果决策（领域枚举，平台无关；不引用 androidx.work）。
 * App 层 Worker 负责映射：RETRY -> Result.retry()，COMPLETE -> Result.success()。
 */
enum class RefreshDecision { RETRY, COMPLETE }

/**
 * 后台刷新错误 → 决策映射（纯函数，可 JVM 单测）：
 *  - NETWORK：临时网络异常 → RETRY（WorkManager 自带退避重试）；
 *  - 其他（EMPTY_TOKEN / Token 失效 40002·40003 / HTTP / API / DECODING）→ COMPLETE，
 *    避免失效 Token 或不可恢复错误导致 WorkManager 无限重试。
 */
object BackgroundRefreshDecision {
    fun decide(error: PlatformException?): RefreshDecision {
        if (error == null) return RefreshDecision.COMPLETE
        return if (error.kind == PlatformErrorKind.NETWORK) RefreshDecision.RETRY else RefreshDecision.COMPLETE
    }
}

package com.deepseek.meter.app.background

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.deepseek.meter.app.KeystoreTokenStore
import com.deepseek.meter.app.notification.LowBalanceNotifier
import com.deepseek.meter.core.BackgroundRefreshDecision
import com.deepseek.meter.core.LowBalancePolicy
import com.deepseek.meter.core.PlatformException
import com.deepseek.meter.core.PlatformService
import com.deepseek.meter.core.RefreshDecision

/**
 * 后台余额刷新 Worker（Issue #15）：只调 get_user_summary 做低余额检查，
 * 不拉完整用量（省电、省流量、省后台执行时间）。Best Effort，由系统调度。
 *
 * 安全边界：Token 严禁进入 WorkManager InputData（会落 WorkManager 数据库），
 * 由 Worker 自行从 Keystore 读取；错误映射复用 :core 的 BackgroundRefreshDecision。
 */
class BackgroundRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : Worker(appContext, params) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // 1. 防御性 early-return：开关关闭时直接成功、不联网（关闭后即使任务被系统调度也不打扰）
        if (!prefs.getBoolean(KEY_ALERTS_ENABLED, false)) return Result.success()

        // 2. 从 Keystore 读 Token（解密失败按未登录处理，不 Crash）
        val token = try {
            KeystoreTokenStore(applicationContext).loadToken()
        } catch (_: Exception) {
            null
        }
        if (token.isNullOrEmpty()) return Result.success()

        // 3. 拉取账户汇总 → 低余额策略 → 必要时本地通知
        return try {
            val summary = PlatformService().fetchSummary(token)
            val wallet = summary.normalWallets.firstOrNull()
            if (wallet == null) {
                Result.success()
            } else {
                // 与 AppModel 相同的钱包选择规则（firstOrNull），保证通知币种与 UI 一致
                val decision = LowBalancePolicy.evaluate(
                    balance = wallet.value,
                    threshold = LowBalancePolicy.DEFAULT_THRESHOLD,
                    alerted = prefs.getBoolean(KEY_ALERTED, false)
                )
                // 持久化新的 alerted 状态（无论是否通知都写回；恢复时由策略重置）
                prefs.edit().putBoolean(KEY_ALERTED, decision.alerted).apply()
                if (decision.shouldNotify) {
                    LowBalanceNotifier(applicationContext).notifyLowBalance(wallet.value, wallet.currency)
                }
                Result.success()
            }
        } catch (e: PlatformException) {
            // 4. 错误映射：NETWORK → retry（系统退避）；其余（含 Token 失效 40002/40003）→ success，避免无限重试
            when (BackgroundRefreshDecision.decide(e)) {
                RefreshDecision.RETRY -> Result.retry()
                RefreshDecision.COMPLETE -> Result.success()
            }
        } catch (_: Exception) {
            // 未预期异常按不可恢复处理，避免无休止重试
            Result.success()
        }
    }

    companion object {
        private const val PREFS = "deepseek_meter_background"
        /** 低余额通知开关（设置页写入；Worker 每次执行前检查） */
        const val KEY_ALERTS_ENABLED = "lowBalanceAlertsEnabled"
        /** 同一低余额周期是否已提醒（策略返回的状态持久化于此） */
        const val KEY_ALERTED = "lowBalanceAlerted"
    }
}

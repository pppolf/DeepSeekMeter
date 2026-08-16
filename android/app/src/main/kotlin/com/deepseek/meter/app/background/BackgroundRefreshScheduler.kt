package com.deepseek.meter.app.background

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * 后台余额刷新调度器（Issue #15）：
 * 唯一周期任务 + ExistingPeriodicWorkPolicy.UPDATE——任何情况下不会因多次进入设置页
 * 注册多个后台 Worker（UPDATE 不取消运行中的 worker、保持原排队时间）；
 * 网络约束 CONNECTED；周期 15 分钟（WorkManager 下限），Best Effort、不保证精确时间。
 */
object BackgroundRefreshScheduler {

    const val UNIQUE_WORK_NAME = "deepseek-meter-background-refresh"

    private const val PERIOD_MINUTES = 15L

    /** 开启低余额通知后注册唯一周期任务（已存在则按 UPDATE 无干扰更新） */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<BackgroundRefreshWorker>(
            PERIOD_MINUTES, TimeUnit.MINUTES
        ).setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
        ).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    /** 关闭低余额通知后取消唯一周期任务 */
    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }
}

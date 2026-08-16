package com.deepseek.meter.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.PlatformService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * App 层状态控制器：负责 AppModel 的线程调度（单线程执行器 + 定时刷新）与 Compose 状态桥接。
 * 核心（:core）保持同步纯逻辑（对齐 iOS AppModel 注入化设计），轮询节奏在 App 层。
 */
class AppController(context: Context) {
    private val executor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("deepseek_meter_settings", Context.MODE_PRIVATE)

    private val _state = mutableStateOf<AppModel.State?>(null)

    private val appModel: AppModel = AppModel(
        platformService = PlatformService(),
        tokenStore = KeystoreTokenStore(context),
        onStateChanged = { s -> mainHandler.post { _state.value = s } }
    )

    /** 供 Compose 观察的状态（初始回退到 appModel.state，首个回调到达后持续更新） */
    val state: AppModel.State get() = _state.value ?: appModel.state

    /** 前台定时刷新间隔（秒）；持久化到 SharedPreferences */
    var refreshIntervalSeconds: Long
        get() = prefs.getLong(KEY_INTERVAL, 60)
        set(value) {
            prefs.edit().putLong(KEY_INTERVAL, value).apply()
            restartPolling()
        }

    private var scheduledFuture: ScheduledFuture<*>? = null

    fun start() {
        restartPolling()
    }

    fun stop() {
        scheduledFuture?.cancel(false)
        executor.shutdown()
    }

    private fun restartPolling() {
        scheduledFuture?.cancel(false)
        scheduledFuture = executor.scheduleWithFixedDelay(
            { appModel.refresh() },
            0,
            refreshIntervalSeconds,
            TimeUnit.SECONDS
        )
    }

    /** 手动刷新（下拉/按钮） */
    fun refresh() {
        executor.execute { appModel.refresh() }
    }

    /** 保存并校验 Token（登录页调用）；结果回调在主线程 */
    fun saveToken(token: String, onResult: (Boolean) -> Unit) {
        executor.execute {
            val ok = appModel.savePlatformToken(token)
            mainHandler.post { onResult(ok) }
        }
    }

    /** 退出登录 */
    fun clearToken() {
        executor.execute { appModel.clearPlatformToken() }
    }

    companion object {
        private const val KEY_INTERVAL = "refreshInterval"
    }
}

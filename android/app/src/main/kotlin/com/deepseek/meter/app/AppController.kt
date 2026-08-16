package com.deepseek.meter.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.PlatformService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * App 层状态控制器：负责 AppModel 的线程调度（单线程执行器 + 定时刷新）与 Compose 状态桥接。
 * 核心（:core）保持同步纯逻辑（对齐 iOS AppModel 注入化设计），轮询节奏在 App 层。
 *
 * 生命周期三态（由 MainActivity 的 LifecycleEventObserver 桥接，见 Issue #12）：
 *  - startForegroundPolling()：进入前台（ON_START），立即刷新并启动 15/30/60/300/600 秒轮询；
 *  - pauseForegroundPolling()：进入后台（ON_STOP），仅取消 ScheduledFuture，保留 Executor；
 *  - close()：Composition 真正释放，取消任务并 shutdown Executor（幂等，之后拒绝一切任务）。
 *
 * pause 与 close 必须分开：Compose composition 不随 Activity 进入后台而销毁，
 * 后台必须停掉高频轮询（省电），但回前台要能立即恢复而不是重建线程池；
 * 若沿用 DisposableEffect 单点启停，按 Home 后 15~600 秒轮询仍会继续。
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

    /** 前台定时刷新间隔（秒）；持久化到 SharedPreferences（仅前台轮询中重建定时任务） */
    var refreshIntervalSeconds: Long
        get() = prefs.getLong(KEY_INTERVAL, 60)
        set(value) {
            prefs.edit().putLong(KEY_INTERVAL, value).apply()
            if (polling && !closed) restartPolling()
        }

    private var scheduledFuture: ScheduledFuture<*>? = null

    /** 是否处于前台轮询中（决定间隔修改是否重建定时任务）；主线程写、间隔 setter 可能跨线程读，@Volatile 保证可见性 */
    @Volatile
    private var polling = false

    /** 关闭标记：close() 后拒绝一切新任务，防止 dispose 后残留回调提交任务 */
    @Volatile
    private var closed = false

    /** 进入前台：立即刷新 + 启动定时轮询（重复调用安全：先取消旧任务再重建，不会产生双 scheduler） */
    fun startForegroundPolling() {
        if (closed) return
        polling = true
        restartPolling()
    }

    /** 进入后台：停止前台高频轮询，保留 Executor 以便回前台快速恢复 */
    fun pauseForegroundPolling() {
        polling = false
        scheduledFuture?.cancel(false)
        scheduledFuture = null
    }

    /** 彻底释放：取消任务 + 关闭线程池；幂等，close 后不再接受任何任务 */
    fun close() {
        if (closed) return
        closed = true
        polling = false
        scheduledFuture?.cancel(false)
        scheduledFuture = null
        executor.shutdown()
    }

    private fun restartPolling() {
        if (closed || !polling) return
        scheduledFuture?.cancel(false)
        scheduledFuture = executor.scheduleWithFixedDelay(
            {
                // 兜底捕获：AppModel 内部已捕获 PlatformException，
                // 这里防意外运行时异常终止定时线程（ScheduledExecutorService 特性）
                try {
                    appModel.refresh()
                } catch (_: Throwable) {
                    // 忽略单次失败，下个周期继续
                }
            },
            0,
            refreshIntervalSeconds,
            TimeUnit.SECONDS
        )
    }

    /** 手动刷新（下拉/按钮） */
    fun refresh() {
        submit {
            try {
                appModel.refresh()
            } catch (_: Throwable) {
                // 兜底：状态机内部已捕获平台异常
            }
        }
    }

    /** 保存并校验 Token（登录页调用）；结果回调在主线程 */
    fun saveToken(token: String, onResult: (Boolean) -> Unit) {
        submit {
            val ok = try {
                appModel.savePlatformToken(token)
            } catch (_: Throwable) {
                false
            }
            mainHandler.post { onResult(ok) }
        }
    }

    /** 退出登录 */
    fun clearToken() {
        submit {
            try {
                appModel.clearPlatformToken()
            } catch (_: Throwable) {
                // 兜底
            }
        }
    }

    /** 统一任务提交入口：close 后拒绝；与 shutdown 竞态时忽略被拒绝的任务 */
    private fun submit(task: () -> Unit) {
        if (closed) return
        try {
            executor.execute(task)
        } catch (_: RejectedExecutionException) {
            // close() 与提交竞态：任务被拒绝直接忽略，避免 Crash；
            // 仅捕获拒绝异常（任务体自身的异常由各任务内 try/catch 兜底），不吞其他运行时异常
        }
    }

    companion object {
        private const val KEY_INTERVAL = "refreshInterval"
    }
}

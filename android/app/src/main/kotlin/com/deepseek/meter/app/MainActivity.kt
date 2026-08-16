package com.deepseek.meter.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/// 入口 Activity：组装 Theme -> AppController -> 根 Compose
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            DeepSeekMeterTheme {
                DeepSeekMeterApp(rememberAppController())
            }
        }
    }
}

/**
 * Controller 装配 + 生命周期桥接（[Issue #12](https://github.com/pppolf/DeepSeekMeter/issues/12)）：
 *  - ON_START：startForegroundPolling()（立即刷新 + 启动定时轮询）
 *  - ON_STOP：pauseForegroundPolling()（后台停掉高频轮询，保留线程池）
 *  - composition dispose：close()（幂等，彻底释放）
 *
 * 不能只用 DisposableEffect 启停 Controller：Compose composition 不随 Activity 进入后台而销毁，
 * 只用 onDispose 会让 ScheduledExecutorService 在后台继续 15~600 秒高频轮询。
 * 配置变更：manifest 已声明 configChanges（orientation|screenSize|keyboardHidden），
 * 普通旋转不重建 Activity；即使其他配置重建，旧 composition 走 dispose→close()，
 * 新实例重建 Controller，不会产生双轮询器。
 */
@Composable
fun rememberAppController(): AppController {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val controller = remember { AppController(context.applicationContext) }
    // 以 lifecycleOwner 为 key：观察者仅在生命周期宿主变化时重建；
    // Activity 生命周期内该值不变，effect 只执行一次（注册观察者 + 初始状态补偿）
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> controller.startForegroundPolling()
                Lifecycle.Event.ON_STOP -> controller.pauseForegroundPolling()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        // 补偿初始状态：effect 执行时 Activity 通常已 STARTED，不会再收到 ON_START，需手动启动一次
        if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            controller.startForegroundPolling()
        }
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            controller.close()
        }
    }
    return controller
}

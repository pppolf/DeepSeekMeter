package com.deepseek.meter.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

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

@Composable
fun rememberAppController(): AppController {
    val context = LocalContext.current
    val controller = remember { AppController(context.applicationContext) }
    DisposableEffect(Unit) {
        controller.start()
        onDispose { controller.stop() }
    }
    return controller
}

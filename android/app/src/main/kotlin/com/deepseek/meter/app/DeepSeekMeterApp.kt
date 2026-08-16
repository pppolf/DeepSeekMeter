package com.deepseek.meter.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

/// 根界面：主页 + 设置 两个 Tab（对齐 iOS 两 Tab 结构）+ 登录全屏页
@Composable
fun DeepSeekMeterApp(controller: AppController) {
    val state = controller.state
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    var showLogin by remember { mutableStateOf(false) }

    if (showLogin) {
        LoginScreen(
            onDismiss = { showLogin = false },
            onSaveToken = { token, done ->
                controller.saveToken(token) { ok ->
                    done(ok)
                    if (ok) showLogin = false
                }
            }
        )
        return
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Text("🏠") },
                    label = { Text("主页") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    icon = { Text("⚙️") },
                    label = { Text("设置") }
                )
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (selectedTab == 0) {
                HomeScreen(state = state, controller = controller, onLogin = { showLogin = true })
            } else {
                SettingsScreen(state = state, controller = controller, onLogin = { showLogin = true })
            }
        }
    }
}

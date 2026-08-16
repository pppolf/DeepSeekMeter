package com.deepseek.meter.app

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.DataStatus

/**
 * 设置：账号（登录/退出）、刷新间隔、隐私说明（对齐 iOS SettingsView）。
 */
@Composable
fun SettingsScreen(state: AppModel.State, controller: AppController, onLogin: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Text("设置", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))

        Card(shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text("账号", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                state.userName?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.height(8.dp))
                }
                Row {
                    if (state.status == DataStatus.NOT_LOGGED_IN) {
                        Button(onClick = onLogin) { Text("登录") }
                    } else {
                        OutlinedButton(onClick = onLogin) { Text("重新登录") }
                        Spacer(Modifier.width(12.dp))
                        Button(onClick = { controller.clearToken() }) { Text("退出登录") }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        Card(shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text("自动刷新", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                val options = listOf(
                    15L to "15秒",
                    30L to "30秒",
                    60L to "1分钟",
                    300L to "5分钟",
                    600L to "10分钟"
                )
                Column {
                    options.forEach { (seconds, label) ->
                        val selected = controller.refreshIntervalSeconds == seconds
                        TextButton(
                            onClick = { controller.refreshIntervalSeconds = seconds },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                Text(
                                    if (selected) "● " + label else "○ " + label,
                                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(Modifier.weight(1f))
                                if (selected) {
                                    Text("✓", color = MaterialTheme.colorScheme.primary)
                                }
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))
        Card(shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                Text("隐私", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Text(
                    "所有数据来自 DeepSeek 官方平台接口，使用你自己的登录态，不会发送到任何第三方。Token 使用 Android Keystore 加密后保存在本机，「退出登录」可随时清除。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }
        }
    }
}

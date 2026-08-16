package com.deepseek.meter.app

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.deepseek.meter.app.background.BackgroundRefreshScheduler
import com.deepseek.meter.app.background.BackgroundRefreshWorker
import com.deepseek.meter.app.notification.LowBalanceNotifier
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.DataStatus
import com.deepseek.meter.core.LowBalancePolicy
import com.deepseek.meter.core.format

/**
 * 设置：账号（登录/退出）、刷新间隔、低余额通知、隐私说明（对齐 iOS SettingsView）。
 * 通知开关与后台 Worker 生命周期闭环（Issue #15）：
 *  OFF→ON：权限通过后保存 enabled=true 并注册唯一周期任务（UPDATE）；
 *  ON→OFF：保存 enabled=false、取消唯一任务、重置 alerted 状态；
 *  Worker 每次执行前还会二次检查开关（双重保障）。
 */
@Composable
fun SettingsScreen(state: AppModel.State, controller: AppController, onLogin: () -> Unit) {
    val context = LocalContext.current

    // ---- 低余额通知状态（Issue #15） ----
    val notifier = remember { LowBalanceNotifier(context) }
    val bgPrefs = remember {
        context.getSharedPreferences(BackgroundRefreshWorker.PREFS_NAME, Context.MODE_PRIVATE)
    }
    var alertsEnabled by remember { mutableStateOf(bgPrefs.getBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, false)) }
    var showPermissionNote by remember { mutableStateOf(false) }
    // 拒绝计数（权限三态）：0=未请求；1=曾拒绝，可再次点击重试；≥2=引导系统设置，不再弹框
    var permissionDenialCount by remember { mutableStateOf(bgPrefs.getInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, 0)) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted && notifier.areNotificationsEnabled()) {
            bgPrefs.edit().putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, true).apply()
            alertsEnabled = true
            showPermissionNote = false
            permissionDenialCount = 0
            bgPrefs.edit().putInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, 0).apply()
            BackgroundRefreshScheduler.schedule(context)
        } else {
            // 拒绝（或渠道在系统设置中被关闭）：保持关闭，记录拒绝次数（持久化，重启后不重置），展示系统设置入口
            permissionDenialCount += 1
            bgPrefs.edit().putInt(BackgroundRefreshWorker.KEY_DENIAL_COUNT, permissionDenialCount).apply()
            showPermissionNote = true
        }
    }

    fun enableAlerts() {
        notifier.createChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notifier.areNotificationsEnabled()) {
            // Android 13+ 未授予：首次点击请求；拒绝一次允许再次点击重试；
            // 拒绝两次以上直接引导系统设置，不再骚扰式弹框（系统对多次拒绝通常也不再展示对话框）
            if (permissionDenialCount >= 2) {
                showPermissionNote = true
            } else {
                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        } else {
            // 已授权（或 <13 无运行时权限）：启用并注册唯一周期任务
            bgPrefs.edit().putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, true).apply()
            alertsEnabled = true
            showPermissionNote = false
            BackgroundRefreshScheduler.schedule(context)
        }
    }

    fun disableAlerts() {
        bgPrefs.edit()
            .putBoolean(BackgroundRefreshWorker.KEY_ALERTS_ENABLED, false)
            .remove(BackgroundRefreshWorker.KEY_ALERTED) // 重置提醒状态
            .apply()
        alertsEnabled = false
        showPermissionNote = false
        BackgroundRefreshScheduler.cancel(context)
    }

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
                Text("通知", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "低余额提醒：余额低于 " + format(LowBalancePolicy.DEFAULT_THRESHOLD) + "（当前币种单位）时本地通知，纯本地无推送",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline,
                        modifier = Modifier.weight(1f)
                    )
                    Switch(
                        checked = alertsEnabled,
                        onCheckedChange = { on -> if (on) enableAlerts() else disableAlerts() }
                    )
                }
                if (showPermissionNote) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        if (permissionDenialCount >= 2)
                            "通知权限已关闭：请在系统设置中允许 DeepSeekMeter 通知后重试"
                        else
                            "通知权限被拒绝：可再次点击开关重试，或打开系统设置开启",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                    TextButton(onClick = { notifier.openNotificationSettings() }) {
                        Text("打开系统通知设置")
                    }
                }
                // QA 入口（仅 debug 构建）：低余额通知管线真机验证用——
                // 渠道/权限/图标/文案/点击跳转与真实余额无关，无需真实低余额账户（#16 QA 矩阵）
                if (BuildConfig.DEBUG) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "QA：发送一条测试低余额通知（仅 debug 构建显示）",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline
                    )
                    TextButton(onClick = { notifier.notifyLowBalance(0.5, "CNY") }) {
                        Text("发送测试通知")
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

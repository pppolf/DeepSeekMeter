package com.deepseek.meter.app.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.Settings
import com.deepseek.meter.app.MainActivity
import com.deepseek.meter.app.R
import com.deepseek.meter.core.LowBalancePolicy
import com.deepseek.meter.core.currencySymbol
import com.deepseek.meter.core.format

/**
 * 低余额本地通知（纯本地，无任何第三方推送；Issue #15）。
 * Channel 创建 / 权限有效性 / 发送 / 系统设置入口。
 * 平台 API 直接实现（minSdk 26 起 Notification.Builder(context, channel) 可用），零新增依赖。
 */
class LowBalanceNotifier(private val context: Context) {

    private val manager: NotificationManager?
        get() = context.getSystemService(NotificationManager::class.java)

    /** 创建通知渠道（幂等；API 26+，与 minSdk 一致） */
    fun createChannel() {
        val m = manager ?: return
        m.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "账户余额低于 " + format(LowBalancePolicy.DEFAULT_THRESHOLD) + "（当前币种单位）时提醒"
            }
        )
    }

    /**
     * 通知当前是否可用：Android 13+ 由 POST_NOTIFICATIONS 权限决定，
     * 旧版本由用户在系统设置中关闭渠道决定；areNotificationsEnabled 覆盖两者。
     */
    fun areNotificationsEnabled(): Boolean = manager?.areNotificationsEnabled() ?: false

    /** 发送低余额通知；权限不可用时静默跳过并返回 false（不 Crash） */
    fun notifyLowBalance(balance: Double, currency: String): Boolean {
        if (!areNotificationsEnabled()) return false
        createChannel()
        val m = manager ?: return false
        val intent = Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val symbol = currencySymbol(currency)
        val balanceText = symbol + format(balance)
        val thresholdText = symbol + format(LowBalancePolicy.DEFAULT_THRESHOLD)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("余额不足提醒")
            .setContentText("当前余额 $balanceText，低于 $thresholdText")
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        m.notify(NOTIFICATION_ID, notification)
        return true
    }

    /** 打开系统通知设置（永久拒绝后的恢复入口） */
    fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    companion object {
        const val CHANNEL_ID = "deepseek-meter-low-balance"
        private const val CHANNEL_NAME = "低余额提醒"
        private const val NOTIFICATION_ID = 1001
    }
}

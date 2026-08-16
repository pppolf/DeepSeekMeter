package com.deepseek.meter.core

import java.util.Calendar

/**
 * 状态中枢（对齐 iOS AppModel.swift 的逻辑；零第三方依赖）。
 * 设计差异：同步执行（刷新/登录均为阻塞调用），线程调度交给 App 层
 * （Compose LaunchedEffect / 前台定时器 / WorkManager），核心保持纯逻辑、可单测。
 * 状态发布通过 onStateChanged 回调（App 层桥接为 Compose State）。
 */
class AppModel(
    private val platformService: PlatformService = PlatformService(),
    val tokenStore: TokenStore,
    val onStateChanged: ((State) -> Unit)? = null
) {
    companion object {
        val INTERVAL_OPTIONS = listOf(15L, 30L, 60L, 300L, 600L)
    }

    data class State(
        val token: String?,
        val lastBalance: BalanceInfo?,
        val lastUpdate: Long?,
        val lastError: String?,
        val monthUsage: MonthUsage?,
        val usageError: String?,
        val tokenExpired: Boolean,
        val fetching: Boolean,
        val currency: String,
        val userName: String?
    ) {
        val status: DataStatus
            get() = dataStatus(token, tokenExpired, lastBalance != null || monthUsage != null, lastError != null || usageError != null)
    }

    var state: State
        private set

    init {
        state = State(
            token = tokenStore.loadToken(),
            lastBalance = null,
            lastUpdate = null,
            lastError = null,
            monthUsage = null,
            usageError = null,
            tokenExpired = false,
            fetching = false,
            currency = "CNY",
            userName = null
        )
        onStateChanged?.invoke(state)
    }

    private fun publish(newState: State) {
        state = newState
        onStateChanged?.invoke(newState)
    }

    /** 拉取最新数据（下拉刷新/定时器调用）；执行中重复调用会被忽略 */
    fun refresh() {
        if (state.fetching) return
        publish(state.copy(fetching = true))
        try {
            fetchBalance()
            fetchUsage()
        } finally {
            publish(state.copy(fetching = false))
        }
    }

    /** 保存新的平台 Token 并立即校验；返回是否成功（对齐 iOS savePlatformToken） */
    fun savePlatformToken(newToken: String): Boolean {
        val trimmed = newToken.trim()
        if (trimmed.isEmpty()) {
            publish(state.copy(usageError = "请先在设置中填写平台 Token"))
            return false
        }
        return try {
            val user = platformService.fetchCurrentUser(trimmed)
            tokenStore.saveToken(trimmed)
            publish(state.copy(token = trimmed, userName = user.email, currency = user.currency, usageError = null, tokenExpired = false))
            fetchUsage()
            fetchBalance()
            state.usageError == null && state.lastError == null
        } catch (e: PlatformException) {
            publish(state.copy(usageError = e.message, tokenExpired = state.tokenExpired || e.isTokenExpired))
            false
        }
    }

    /** 退出登录：清内存 + 落盘 */
    fun clearPlatformToken() {
        tokenStore.clearToken()
        publish(
            State(
                token = null, lastBalance = null, lastUpdate = null, lastError = null,
                monthUsage = null, usageError = null, tokenExpired = false,
                fetching = false, currency = "CNY", userName = null
            )
        )
    }

    private fun fetchBalance() {
        val token = state.token
        if (token.isNullOrEmpty()) {
            publish(state.copy(lastBalance = null))
            return
        }
        try {
            val summary = platformService.fetchSummary(token)
            val wallet = summary.normalWallets.firstOrNull()
            if (wallet == null) {
                publish(state.copy(lastBalance = null, lastError = "余额数据为空"))
                return
            }
            val bonus = summary.bonusWallets.firstOrNull()?.value ?: 0.0
            publish(
                state.copy(
                    lastBalance = BalanceInfo(
                        wallet.currency, wallet.balance, bonus.toString(),
                        maxOf(0.0, wallet.value - bonus).toString()
                    ),
                    currency = wallet.currency,
                    lastUpdate = System.currentTimeMillis(),
                    lastError = null
                )
            )
        } catch (e: PlatformException) {
            publish(state.copy(lastError = e.message, tokenExpired = state.tokenExpired || e.isTokenExpired))
        }
    }

    private fun fetchUsage() {
        val token = state.token
        if (token.isNullOrEmpty()) {
            publish(state.copy(monthUsage = null, usageError = null))
            return
        }
        try {
            val cal = Calendar.getInstance(MonthUsage.PLATFORM_TIME_ZONE)
            cal.set(Calendar.DAY_OF_MONTH, 1)
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val startTs = cal.timeInMillis / 1000
            cal.add(Calendar.MONTH, 1)
            val endTs = cal.timeInMillis / 1000
            val tz = MonthUsage.PLATFORM_TIME_ZONE.getOffset(System.currentTimeMillis()) / 1000

            val amountData = platformService.fetchApiKeyAmount(token, startTs, endTs, tz)
            val costData = platformService.fetchApiKeyCost(token, startTs, endTs, tz)
            publish(
                state.copy(
                    monthUsage = MonthUsage.aggregated(startTs, endTs, tz, amountData, costData),
                    usageError = null,
                    tokenExpired = false,
                    lastUpdate = System.currentTimeMillis()
                )
            )
        } catch (e: PlatformException) {
            publish(state.copy(usageError = e.message, tokenExpired = state.tokenExpired || e.isTokenExpired))
        }
    }
}

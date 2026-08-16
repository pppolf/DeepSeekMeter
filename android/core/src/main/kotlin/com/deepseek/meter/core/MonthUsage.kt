package com.deepseek.meter.core

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 聚合后的本月用量（UI 直接使用）。
 * 对齐 iOS MonthUsage：平台统计口径为北京时间（UTC+8），按天/按月均以该时区计。
 */
data class MonthUsage(
    val year: Int,
    val month: Int,
    val amountModels: List<ModelUsage>,
    val costModels: List<ModelUsage>,
    val costDays: List<UsageDay>,
    val amountDays: List<UsageDay>
) {
    val totalCost: Double
        get() = costModels.sumOf { m -> m.usage.sumOf { it.amount } }

    val promptTokens: Double get() = sumAmount("PROMPT_TOKEN")
    val cacheHitTokens: Double get() = sumAmount("PROMPT_CACHE_HIT_TOKEN")
    val cacheMissTokens: Double get() = sumAmount("PROMPT_CACHE_MISS_TOKEN")
    val responseTokens: Double get() = sumAmount("RESPONSE_TOKEN")
    val totalRequests: Int get() = amountModels.sumOf { it.requests }

    private fun sumAmount(type: String): Double = amountModels.sumOf { it.value(type) }

    /** 某一天费用（无数据返回 0） */
    fun cost(on: Date): Double {
        val key = dayKey(on)
        val day = costDays.firstOrNull { it.date == key } ?: return 0.0
        return day.data.sumOf { m -> m.usage.sumOf { it.amount } }
    }

    /** 某一天 Token/请求（无数据返回全 0） */
    fun tokens(on: Date): TokenDay {
        val key = dayKey(on)
        val day = amountDays.firstOrNull { it.date == key } ?: return TokenDay(0, 0.0, 0.0, 0.0)
        return TokenDay(
            day.data.sumOf { it.requests },
            day.data.sumOf { it.value("RESPONSE_TOKEN") },
            day.data.sumOf { it.value("PROMPT_CACHE_HIT_TOKEN") },
            day.data.sumOf { it.value("PROMPT_CACHE_MISS_TOKEN") }
        )
    }

    data class TokenDay(val requests: Int, val response: Double, val cacheHit: Double, val cacheMiss: Double)

    companion object {
        /** 平台统计口径时区：北京时间（UTC+8） */
        val PLATFORM_TIME_ZONE: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

        fun dayFormatter(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            .apply { timeZone = PLATFORM_TIME_ZONE }

        private fun dayKey(date: Date): String = dayFormatter().format(date)

        /**
         * 把 by_api_key 的天桶序列聚合成 MonthUsage（对齐 iOS MonthUsage.aggregated）。
         * - startTs/endTs：查询窗口（Unix 秒），窗口外的桶忽略；year/month 取自 startTs（调用方保证为本月 1 日）
         * - tzSeconds：桶所属时区秒偏移（UTC+8 = 28800）
         * - 费用只聚合第一个币种分组
         */
        fun aggregated(
            startTs: Long,
            endTs: Long,
            tzSeconds: Int,
            amountData: ApiKeyAmountData?,
            costData: ApiKeyCostData?
        ): MonthUsage {
            val timeZone = TimeZone.getTimeZone("GMT").apply { rawOffset = tzSeconds * 1000 }
            val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { this.timeZone = timeZone }
            fun dayString(ts: Long): String = formatter.format(Date(ts * 1000))
            fun inWindow(ts: Long): Boolean = ts >= startTs && ts < endTs

            val startDate = Date(startTs * 1000)
            val cal = Calendar.getInstance(timeZone).apply { time = startDate }
            val year = cal.get(Calendar.YEAR)
            val month = cal.get(Calendar.MONTH) + 1

            // 1. token/请求：day -> model -> type -> value
            val amountByDay = mutableMapOf<String, MutableMap<String, MutableMap<String, Double>>>()
            val amountByModel = mutableMapOf<String, MutableMap<String, Double>>()
            for (series in amountData?.series ?: emptyList()) {
                for (bucket in series.buckets) {
                    if (!inWindow(bucket.time)) continue
                    val day = dayString(bucket.time)
                    for ((type, value) in bucket.usage) {
                        amountByDay.getOrPut(day) { mutableMapOf() }
                            .getOrPut(series.model) { mutableMapOf() }
                            .merge(type, value, Double::plus)
                        amountByModel.getOrPut(series.model) { mutableMapOf() }
                            .merge(type, value, Double::plus)
                    }
                }
            }

            // 2. 费用：只取第一个币种分组，day -> model -> 金额（统一记为 COST）
            val costByDay = mutableMapOf<String, MutableMap<String, Double>>()
            val costByModel = mutableMapOf<String, Double>()
            val firstGroup = costData?.groups?.firstOrNull()
            if (firstGroup != null) {
                for (series in firstGroup.series) {
                    for (bucket in series.buckets) {
                        if (!inWindow(bucket.time)) continue
                        val day = dayString(bucket.time)
                        val value = bucket.cost.toDoubleOrNull() ?: 0.0
                        costByDay.getOrPut(day) { mutableMapOf() }
                            .merge(series.model, value, Double::plus)
                        costByModel.merge(series.model, value, Double::plus)
                    }
                }
            }

            // 3. 组装（key 与 model 排序，保证输出稳定）
            val amountDays = amountByDay.keys.sorted().map { day ->
                val models = amountByDay[day]!!.keys.sorted().map { model ->
                    val items = amountByDay[day]!![model]!!.toSortedMap().map { (type, v) ->
                        UsageItem(type, v)
                    }
                    ModelUsage(model, items)
                }
                UsageDay(day, models)
            }
            val amountModels = amountByModel.keys.sorted().map { model ->
                val items = amountByModel[model]!!.toSortedMap().map { (type, v) -> UsageItem(type, v) }
                ModelUsage(model, items)
            }
            val costDays = costByDay.keys.sorted().map { day ->
                val models = costByDay[day]!!.keys.sorted().map { model ->
                    ModelUsage(model, listOf(UsageItem("COST", costByDay[day]!![model]!!)))
                }
                UsageDay(day, models)
            }
            val costModels = costByModel.keys.sorted().map { model ->
                ModelUsage(model, listOf(UsageItem("COST", costByModel[model]!!)))
            }

            return MonthUsage(year, month, amountModels, costModels, costDays, amountDays)
        }
    }
}

// MARK: - 数据可信度状态

enum class DataStatus { NOT_LOGGED_IN, LOADING, FRESH, STALE, ERROR, TOKEN_EXPIRED }

/** 数据状态判定（纯函数，可测；对齐 iOS dataStatus） */
fun dataStatus(token: String?, tokenExpired: Boolean, hasData: Boolean, hasError: Boolean): DataStatus {
    if (token.isNullOrEmpty()) return DataStatus.NOT_LOGGED_IN
    if (tokenExpired) return DataStatus.TOKEN_EXPIRED
    if (hasError) return if (hasData) DataStatus.STALE else DataStatus.ERROR
    if (hasData) return DataStatus.FRESH
    return DataStatus.LOADING
}

package com.deepseek.meter.core

import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// MARK: - 余额信息（由平台 get_user_summary 构造，供 UI 展示）

data class BalanceInfo(
    val currency: String,
    val totalBalance: String,
    val grantedBalance: String,
    val toppedUpBalance: String
) {
    val total: Double get() = totalBalance.toDoubleOrNull() ?: 0.0
    val granted: Double get() = grantedBalance.toDoubleOrNull() ?: 0.0
    val toppedUp: Double get() = toppedUpBalance.toDoubleOrNull() ?: 0.0
}

// MARK: - 平台用量模型（platform.deepseek.com 私有接口，需登录 userToken）

/** 单个模型的用量条目 */
data class UsageItem(val type: String, val amount: Double)

/** 单个模型的用量 */
data class ModelUsage(val model: String, val usage: List<UsageItem>) {
    fun value(type: String): Double = usage.firstOrNull { it.type == type }?.amount ?: 0.0
    val requests: Int get() = value("REQUEST").toLong().toInt()

    companion object {
        fun fromJson(o: JSONObject): ModelUsage {
            val items = mutableListOf<UsageItem>()
            val arr = o.optJSONArray("usage") ?: JSONArray()
            for (i in 0 until arr.length()) {
                val u = arr.optJSONObject(i) ?: continue
                items.add(UsageItem(u.optString("type"), u.optString("amount").toDoubleOrNull() ?: 0.0))
            }
            return ModelUsage(o.optString("model"), items)
        }
    }
}

/** usage/amount 的 biz_data：{total, days} */
data class UsageData(val total: List<ModelUsage>, val days: List<UsageDay>?) {
    companion object {
        fun fromJson(o: JSONObject): UsageData {
            val total = mutableListOf<ModelUsage>()
            val t = o.optJSONArray("total") ?: JSONArray()
            for (i in 0 until t.length()) {
                t.optJSONObject(i)?.let { total.add(ModelUsage.fromJson(it)) }
            }
            val days = mutableListOf<UsageDay>()
            val d = o.optJSONArray("days") ?: JSONArray()
            for (i in 0 until d.length()) {
                d.optJSONObject(i)?.let { days.add(UsageDay.fromJson(it)) }
            }
            return UsageData(total, days)
        }
    }
}

/** 某一天的用量 */
data class UsageDay(val date: String, val data: List<ModelUsage>) {
    companion object {
        fun fromJson(o: JSONObject): UsageDay {
            val models = mutableListOf<ModelUsage>()
            val arr = o.optJSONArray("data") ?: JSONArray()
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { models.add(ModelUsage.fromJson(it)) }
            }
            return UsageDay(o.optString("date"), models)
        }
    }
}

// MARK: - by_api_key 实时接口模型

data class ApiKeyInfo(val trackingId: String, val name: String, val sensitiveId: String, val valid: Boolean) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyInfo = ApiKeyInfo(
            o.optString("tracking_id"), o.optString("name"),
            o.optString("sensitive_id"), o.optBoolean("valid")
        )
    }
}

/** 按天桶的 token 用量（真实响应值为 JSON 数字） */
data class ApiKeyUsageBucket(val time: Long, val usage: Map<String, Double>) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyUsageBucket {
            val map = mutableMapOf<String, Double>()
            val u = o.optJSONObject("usage") ?: JSONObject()
            val keys = u.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                map[k] = u.optDouble(k, 0.0)
            }
            return ApiKeyUsageBucket(o.optLong("time"), map)
        }
    }
}

data class ApiKeyAmountSeries(val apiKey: ApiKeyInfo, val model: String, val buckets: List<ApiKeyUsageBucket>) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyAmountSeries {
            val buckets = mutableListOf<ApiKeyUsageBucket>()
            val arr = o.optJSONArray("buckets") ?: JSONArray()
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { buckets.add(ApiKeyUsageBucket.fromJson(it)) }
            }
            val ak = o.optJSONObject("api_key") ?: JSONObject()
            return ApiKeyAmountSeries(ApiKeyInfo.fromJson(ak), o.optString("model"), buckets)
        }
    }
}

data class ApiKeyAmountData(
    val start: Long, val end: Long, val bucket: Long,
    val models: List<String>, val series: List<ApiKeyAmountSeries>
) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyAmountData {
            val models = mutableListOf<String>()
            val m = o.optJSONArray("models") ?: JSONArray()
            for (i in 0 until m.length()) models.add(m.optString(i))
            val series = mutableListOf<ApiKeyAmountSeries>()
            val s = o.optJSONArray("series") ?: JSONArray()
            for (i in 0 until s.length()) {
                s.optJSONObject(i)?.let { series.add(ApiKeyAmountSeries.fromJson(it)) }
            }
            return ApiKeyAmountData(o.optLong("start"), o.optLong("end"), o.optLong("bucket"), models, series)
        }
    }
}

data class ApiKeyCostBucket(val time: Long, val cost: String) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyCostBucket = ApiKeyCostBucket(o.optLong("time"), o.optString("cost"))
    }
}

data class ApiKeyCostSeries(val apiKey: ApiKeyInfo, val model: String, val buckets: List<ApiKeyCostBucket>) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyCostSeries {
            val buckets = mutableListOf<ApiKeyCostBucket>()
            val arr = o.optJSONArray("buckets") ?: JSONArray()
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { buckets.add(ApiKeyCostBucket.fromJson(it)) }
            }
            val ak = o.optJSONObject("api_key") ?: JSONObject()
            return ApiKeyCostSeries(ApiKeyInfo.fromJson(ak), o.optString("model"), buckets)
        }
    }
}

data class ApiKeyCostGroup(val currency: String, val series: List<ApiKeyCostSeries>) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyCostGroup {
            val series = mutableListOf<ApiKeyCostSeries>()
            val arr = o.optJSONArray("series") ?: JSONArray()
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { series.add(ApiKeyCostSeries.fromJson(it)) }
            }
            return ApiKeyCostGroup(o.optString("currency"), series)
        }
    }
}

data class ApiKeyCostData(
    val start: Long, val end: Long, val bucket: Long,
    val models: List<String>, val groups: List<ApiKeyCostGroup>
) {
    companion object {
        fun fromJson(o: JSONObject): ApiKeyCostData {
            val models = mutableListOf<String>()
            val m = o.optJSONArray("models") ?: JSONArray()
            for (i in 0 until m.length()) models.add(m.optString(i))
            val groups = mutableListOf<ApiKeyCostGroup>()
            val g = o.optJSONArray("data") ?: JSONArray()
            for (i in 0 until g.length()) {
                g.optJSONObject(i)?.let { groups.add(ApiKeyCostGroup.fromJson(it)) }
            }
            return ApiKeyCostData(o.optLong("start"), o.optLong("end"), o.optLong("bucket"), models, groups)
        }
    }
}

// MARK: - get_user_summary

data class WalletBalance(val currency: String, val balance: String, val tokenEstimation: String?) {
    val value: Double get() = balance.toDoubleOrNull() ?: 0.0
    companion object {
        fun fromJson(o: JSONObject): WalletBalance = WalletBalance(
            o.optString("currency"), o.optString("balance"),
            if (o.has("token_estimation")) o.optString("token_estimation") else null
        )
    }
}

data class WalletCost(val currency: String, val amount: String) {
    val value: Double get() = amount.toDoubleOrNull() ?: 0.0
    companion object {
        fun fromJson(o: JSONObject): WalletCost = WalletCost(o.optString("currency"), o.optString("amount"))
    }
}

data class UserSummary(val normalWallets: List<WalletBalance>, val bonusWallets: List<WalletBalance>, val totalCosts: List<WalletCost>) {
    companion object {
        fun fromJson(o: JSONObject): UserSummary {
            fun wallets(key: String): List<WalletBalance> {
                val list = mutableListOf<WalletBalance>()
                val arr = o.optJSONArray(key) ?: JSONArray()
                for (i in 0 until arr.length()) {
                    arr.optJSONObject(i)?.let { list.add(WalletBalance.fromJson(it)) }
                }
                return list
            }
            val costs = mutableListOf<WalletCost>()
            val arr = o.optJSONArray("total_costs") ?: JSONArray()
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { costs.add(WalletCost.fromJson(it)) }
            }
            return UserSummary(wallets("normal_wallets"), wallets("bonus_wallets"), costs)
        }
    }
}

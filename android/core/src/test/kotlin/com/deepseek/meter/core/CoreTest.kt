package com.deepseek.meter.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.Date
import java.util.TimeZone

/**
 * 核心纯逻辑自测（移植 ios/DeepSeekMeterCore 自测的第 1~10 节；样例 JSON 为真实响应结构）。
 */
class CoreTest {

    private fun assertClose(expected: Double, actual: Double, delta: Double) {
        assertTrue("expect $expected, got $actual", Math.abs(expected - actual) < delta)
    }

    // 1. 格式化与币种符号
    @Test
    fun formatting() {
        assertEquals("110.00", format(110.0))
        assertEquals("0.35", format(0.35))
        assertEquals("1234.5", format(1234.5))
        assertEquals("¥", currencySymbol("CNY"))
        assertEquals("$", currencySymbol("USD"))
        assertEquals("€", currencySymbol("EUR"))
        assertEquals("HK$", currencySymbol("HKD"))
        assertEquals("£", currencySymbol("GBP"))
        assertEquals("XXX", currencySymbol("XXX"))
        assertEquals("311932800.0", format(311932800.0))
        assertEquals("1.20亿", tokenString(120_000_000.0))
        assertEquals("3.4万", tokenString(34_000.0))
    }

    // 1.5 平台时区（北京时间计日）
    @Test
    fun platformDayFormatting() {
        val f = MonthUsage.dayFormatter()
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        utc.set(2026, Calendar.AUGUST, 14, 16, 30, 0)
        utc.set(Calendar.MILLISECOND, 0)
        assertEquals("2026-08-15", f.format(utc.time))

        val sh = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
        sh.set(2026, Calendar.AUGUST, 15, 23, 30, 0)
        sh.set(Calendar.MILLISECOND, 0)
        assertEquals("2026-08-15", f.format(sh.time))
    }

    // 2. usage/amount 解码（真实返回结构）
    @Test
    fun amountDecoding() {
        val root = JSONObject(AMOUNT_JSON)
        assertEquals(0, root.getInt("code"))
        val usage = UsageData.fromJson(root.getJSONObject("data").getJSONObject("biz_data"))
        assertEquals(1, usage.total.size)
        val model = usage.total[0]
        assertEquals("deepseek-v4-pro", model.model)
        assertClose(311932800.0, model.value("PROMPT_CACHE_HIT_TOKEN"), 1.0)
        assertClose(950284.0, model.value("RESPONSE_TOKEN"), 1.0)
        assertEquals(1130, model.requests)
        assertEquals(1, usage.days?.size)
        val day = usage.days!![0]
        assertEquals("2026-08-01", day.date)
        assertEquals(2, day.data[0].requests)
    }

    // 3. usage/cost 解码（biz_data 是数组）
    @Test
    fun costDecoding() {
        val root = JSONObject(COST_JSON)
        val arr = root.getJSONObject("data").getJSONArray("biz_data")
        val data = UsageData.fromJson(arr.getJSONObject(0))
        val total = data.total[0].usage.sumOf { it.amount }
        assertClose(18.252291, total, 0.001)
    }

    // 4. get_user_summary 解码
    @Test
    fun summaryDecoding() {
        val root = JSONObject(SUMMARY_JSON)
        val summary = UserSummary.fromJson(root.getJSONObject("data").getJSONObject("biz_data"))
        assertClose(40.24923164, summary.normalWallets[0].value, 0.0001)
        assertClose(19.75076836, summary.totalCosts[0].value, 0.0001)
    }

    // 6. biz_code != 0 正确解码
    @Test
    fun bizCodeDecoding() {
        val root = JSONObject(BIZ_ERR_JSON)
        assertEquals(10001, root.getJSONObject("data").getInt("biz_code"))
    }

    // 7. 空 data / 空 biz_data
    @Test
    fun emptyDataDecoding() {
        assertNull(JSONObject(EMPTY_DATA_JSON).optJSONObject("data"))
        val biz = JSONObject(EMPTY_BIZ_JSON).getJSONObject("data")
        assertNotNull(biz)
        assertNull(biz.optJSONObject("biz_data"))
    }

    // 8. 数据可信度状态判定
    @Test
    fun dataStatusLogic() {
        assertEquals(DataStatus.NOT_LOGGED_IN, dataStatus("", false, false, false))
        assertEquals(DataStatus.TOKEN_EXPIRED, dataStatus("tok", true, true, false))
        assertEquals(DataStatus.STALE, dataStatus("tok", false, true, true))
        assertEquals(DataStatus.FRESH, dataStatus("tok", false, true, false))
        assertEquals(DataStatus.ERROR, dataStatus("tok", false, false, true))
        assertEquals(DataStatus.LOADING, dataStatus("tok", false, false, false))
    }

    // 9. 空钱包
    @Test
    fun emptyWallet() {
        val summary = UserSummary.fromJson(JSONObject(EMPTY_WALLET_JSON).getJSONObject("data").getJSONObject("biz_data"))
        assertTrue(summary.normalWallets.isEmpty())
    }

    // 10. by_api_key 解码 + 聚合（时间戳：1785513600 = 北京 8/1 00:00）
    @Test
    fun apiKeyAggregation() {
        val amountData = ApiKeyAmountData.fromJson(
            JSONObject(BY_KEY_AMOUNT_JSON).getJSONObject("data").getJSONObject("biz_data")
        )
        assertEquals(1, amountData.series.size)
        assertEquals(2, amountData.series[0].buckets.size)
        assertEquals("test-key", amountData.series[0].apiKey.name)
        assertEquals("test-tracking", amountData.series[0].apiKey.trackingId)

        val costData = ApiKeyCostData.fromJson(
            JSONObject(BY_KEY_COST_JSON).getJSONObject("data").getJSONObject("biz_data")
        )
        assertEquals("CNY", costData.groups[0].currency)

        val usage = MonthUsage.aggregated(1785513600L, 1788192000L, 28800, amountData, costData)
        assertEquals(2026, usage.year)
        assertEquals(8, usage.month)
        assertEquals(2, usage.amountDays.size)
        assertEquals("2026-08-01", usage.amountDays[0].date)
        assertEquals("2026-08-02", usage.amountDays[1].date)
        assertEquals(7, usage.amountModels[0].requests)
        assertClose(300.0, usage.amountModels[0].value("RESPONSE_TOKEN"), 0.001)
        assertEquals(2, usage.costDays.size)
        assertClose(1.5, usage.cost(Date(1785513600L * 1000)), 0.001)
        assertClose(4.0, usage.totalCost, 0.001)

        // 空数据聚合为 0
        val empty = MonthUsage.aggregated(1785513600L, 1788192000L, 28800, null, null)
        assertTrue(empty.amountDays.isEmpty())
        assertEquals(0.0, empty.totalCost, 0.0)

        // 边界 1：窗口外（9/1）的桶被忽略；窗口内 8/31 计入
        val edge = ApiKeyAmountData.fromJson(
            JSONObject(MONTH_EDGE_JSON).getJSONObject("data").getJSONObject("biz_data")
        )
        val edgeUsage = MonthUsage.aggregated(1785513600L, 1788192000L, 28800, edge, null)
        assertEquals(1, edgeUsage.amountDays.size)
        assertEquals("2026-08-31", edgeUsage.amountDays[0].date)
        assertEquals(3, edgeUsage.amountModels[0].requests)

        // 边界 2：多币种只聚合第一个分组（CNY 1.0，USD 5.0 不混加）
        val mc = ApiKeyCostData.fromJson(
            JSONObject(MULTI_CURRENCY_JSON).getJSONObject("data").getJSONObject("biz_data")
        )
        val mcUsage = MonthUsage.aggregated(1785513600L, 1788192000L, 28800, null, mc)
        assertClose(1.0, mcUsage.totalCost, 0.001)
    }

    companion object {
        const val AMOUNT_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_TOKEN","amount":"0"},{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"311932800"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"1584089"},{"type":"RESPONSE_TOKEN","amount":"950284"},{"type":"REQUEST","amount":"1130"}]}],"days":[{"date":"2026-08-01","data":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"100"},{"type":"RESPONSE_TOKEN","amount":"50"},{"type":"REQUEST","amount":"2"}]}]}]}}}"""

        const val COST_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":[{"total":[{"model":"deepseek-v4-pro","usage":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"7.7983200000000000"},{"type":"PROMPT_CACHE_MISS_TOKEN","amount":"4.7522670000000000"},{"type":"RESPONSE_TOKEN","amount":"5.7017040000000000"}]}],"days":[]}]}}"""

        const val SUMMARY_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[{"currency":"CNY","balance":"40.2492316400000000","token_estimation":"0"}],"bonus_wallets":[{"currency":"CNY","balance":"0","token_estimation":"0"}],"total_costs":[{"currency":"CNY","amount":"19.7507683600000000"}]}}}"""

        const val BIZ_ERR_JSON = """{"code":0,"msg":"","data":{"biz_code":10001,"biz_msg":"业务错误","biz_data":null}}"""

        const val EMPTY_DATA_JSON = """{"code":0,"msg":"","data":null}"""

        const val EMPTY_BIZ_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":null}}"""

        const val EMPTY_WALLET_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"normal_wallets":[],"bonus_wallets":[],"total_costs":[]}}}"""

        const val BY_KEY_AMOUNT_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"usage":{"REQUEST":2,"RESPONSE_TOKEN":100}},{"time":1785600000,"usage":{"REQUEST":5,"RESPONSE_TOKEN":200}}]}]}}}"""

        const val BY_KEY_COST_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.5"},{"time":1785600000,"cost":"2.5"}]}]}]}}}"""

        const val MONTH_EDGE_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1788105600,"usage":{"REQUEST":3}},{"time":1788192000,"usage":{"REQUEST":99}}]}]}}}"""

        const val MULTI_CURRENCY_JSON = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"start":1785513600,"end":1788192000,"bucket":86400,"models":["deepseek-v4-pro"],"data":[{"currency":"CNY","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"1.0"}]}]},{"currency":"USD","series":[{"api_key":{"tracking_id":"test-tracking","name":"test-key","sensitive_id":"sk-xxx","valid":true},"model":"deepseek-v4-pro","buckets":[{"time":1785513600,"cost":"5.0"}]}]}]}}}"""
    }
}

package com.deepseek.meter.core

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

// MARK: - 错误类型（对齐 Swift PlatformError / Windows PlatformException）

enum class PlatformErrorKind { EMPTY_TOKEN, NETWORK, HTTP, API, DECODING }

/** 平台接口错误（带用户可读的中文 message） */
class PlatformException(
    val kind: PlatformErrorKind,
    override val message: String,
    val httpCode: Int? = null,
    val apiCode: Int? = null
) : Exception(message) {
    /** Token 无效或已过期（40002 / 40003） */
    val isTokenExpired: Boolean get() = apiCode == 40002 || apiCode == 40003
}

// MARK: - 网络抽象（设备用 HttpURLConnection；测试注入 stub，对齐 iOS URLSession 可注入）

data class PlatformHttpResponse(val status: Int, val body: String)

interface PlatformHttp {
    fun get(url: String, headers: Map<String, String>): PlatformHttpResponse
}

/** HttpURLConnection 实现（平台内置，零第三方依赖） */
object UrlConnectionHttp : PlatformHttp {
    override fun get(url: String, headers: Map<String, String>): PlatformHttpResponse {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "GET"
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            for ((k, v) in headers) conn.setRequestProperty(k, v)
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
            return PlatformHttpResponse(code, body)
        } finally {
            conn.disconnect()
        }
    }
}

// MARK: - 平台私有接口客户端（platform.deepseek.com，用浏览器登录态 userToken 鉴权）
// 接口契约与 macOS/iOS/Windows 版完全一致（4 个已验证接口）

data class UserInfo(val email: String, val currency: String)

class PlatformService(private val http: PlatformHttp = UrlConnectionHttp) {

    companion object {
        const val BASE_URL = "https://platform.deepseek.com"
        const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
    }

    // MARK: - 接口

    /** 校验 Token 并返回用户信息（email、currency） */
    fun fetchCurrentUser(token: String): UserInfo {
        val root = get("/auth-api/v0/users/current", token)
        val data = bizData(root, "用户信息为空")
        return UserInfo(
            data.optString("email", ""),
            data.optString("currency", "CNY")
        )
    }

    /** 平台侧账户汇总（余额 / 累计消费） */
    fun fetchSummary(token: String): UserSummary {
        val root = get("/api/v0/users/get_user_summary", token)
        return UserSummary.fromJson(bizData(root, "summary 为空"))
    }

    /** 按 API Key 的 token 用量（实时；bucket=86400 按天分桶） */
    fun fetchApiKeyAmount(token: String, start: Long, end: Long, tz: Int): ApiKeyAmountData {
        val root = get("/api/v0/usage/by_api_key/amount?start=$start&end=$end&tz=$tz&bucket=86400", token)
        return ApiKeyAmountData.fromJson(bizData(root, "by_api_key amount 为空"))
    }

    /** 按 API Key 的费用（实时；bucket=86400 按天分桶） */
    fun fetchApiKeyCost(token: String, start: Long, end: Long, tz: Int): ApiKeyCostData {
        val root = get("/api/v0/usage/by_api_key/cost?start=$start&end=$end&tz=$tz&bucket=86400", token)
        return ApiKeyCostData.fromJson(bizData(root, "by_api_key cost 为空"))
    }

    // MARK: - 请求与解包

    private fun get(path: String, token: String): JSONObject {
        if (token.isBlank()) throw PlatformException(PlatformErrorKind.EMPTY_TOKEN, "请先在设置中填写平台 Token")
        val url = BASE_URL + path
        val headers = mapOf(
            "User-Agent" to USER_AGENT,
            "Authorization" to "Bearer $token",
            "Accept" to "application/json, text/plain, */*",
            "Referer" to "https://platform.deepseek.com/usage",
            "Origin" to "https://platform.deepseek.com"
        )
        val response = try {
            http.get(url, headers)
        } catch (e: IOException) {
            throw PlatformException(PlatformErrorKind.NETWORK, "用量获取失败：${e.message ?: "网络错误"}")
        }
        if (response.status != 200) {
            throw PlatformException(PlatformErrorKind.HTTP, "用量获取失败（HTTP ${response.status}）", httpCode = response.status)
        }
        val root = try {
            JSONObject(response.body)
        } catch (e: Exception) {
            throw PlatformException(PlatformErrorKind.DECODING, "用量解析失败：${e.message ?: "JSON 解析错误"}")
        }
        ensureSuccess(root)
        return root
    }

    /** 业务层 biz_data：校验外层 code 与 data.biz_code，返回 data.biz_data */
    private fun bizData(root: JSONObject, emptyMessage: String): JSONObject {
        val data = root.optJSONObject("data")
            ?: throw PlatformException(PlatformErrorKind.API, emptyMessage, apiCode = root.optInt("code"))
        val bizCode = data.optInt("biz_code")
        val bizMsg = data.optString("biz_msg")
        if (bizCode != 0) throw PlatformException(PlatformErrorKind.API, buildApiMessage(bizCode, bizMsg), apiCode = bizCode)
        return data.optJSONObject("biz_data")
            ?: throw PlatformException(PlatformErrorKind.API, emptyMessage, apiCode = bizCode)
    }

    private fun ensureSuccess(root: JSONObject) {
        val code = root.optInt("code")
        if (code != 0) {
            val msg = root.optString("msg")
            throw PlatformException(PlatformErrorKind.API, buildApiMessage(code, msg), apiCode = code)
        }
    }

    private fun buildApiMessage(code: Int, msg: String): String {
        if (code == 40002 || code == 40003) return "平台 Token 无效或已过期，请重新获取"
        return "平台接口错误（$code）：$msg"
    }
}

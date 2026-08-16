package com.deepseek.meter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * PlatformService 测试（移植 iOS 自测第 11 节）：请求头/URL 契约 + 错误归一化（stub 注入）。
 */
class PlatformServiceTest {

    private class StubHttp(
        var onRequest: ((String, Map<String, String>) -> PlatformHttpResponse)? = null
    ) : PlatformHttp {
        var lastUrl: String = ""
        var lastHeaders: Map<String, String> = emptyMap()
        override fun get(url: String, headers: Map<String, String>): PlatformHttpResponse {
            lastUrl = url
            lastHeaders = headers
            return onRequest?.invoke(url, headers)
                ?: PlatformHttpResponse(200, "{\"code\":0,\"msg\":\"\",\"data\":null}")
        }
    }

    private val currentUserOK = """{"code":0,"msg":"","data":{"biz_code":0,"biz_msg":"","biz_data":{"id":"u_1","email":"dev@example.com","currency":"USD"}}}"""

    private fun assertPlatformError(expectedKind: PlatformErrorKind, expectedMessage: String, block: () -> Unit) {
        try {
            block()
            fail("应抛出 PlatformException")
        } catch (e: PlatformException) {
            assertEquals(expectedKind, e.kind)
            assertEquals(expectedMessage, e.message)
        }
    }

    @Test
    fun currentUserWithHeaders() {
        val stub = StubHttp { _, _ -> PlatformHttpResponse(200, currentUserOK) }
        val service = PlatformService(stub)
        val user = service.fetchCurrentUser("test-token-abc")
        assertEquals("dev@example.com", user.email)
        assertEquals("USD", user.currency)
        assertTrue(stub.lastUrl.startsWith("https://platform.deepseek.com/auth-api/v0/users/current"))
        assertEquals("Bearer test-token-abc", stub.lastHeaders["Authorization"])
        assertEquals("https://platform.deepseek.com/usage", stub.lastHeaders["Referer"])
        assertEquals("https://platform.deepseek.com", stub.lastHeaders["Origin"])
        assertTrue(stub.lastHeaders["User-Agent"]!!.isNotBlank())
    }

    @Test
    fun emptyToken() {
        val service = PlatformService(StubHttp())
        assertPlatformError(PlatformErrorKind.EMPTY_TOKEN, "请先在设置中填写平台 Token") {
            service.fetchCurrentUser("  ")
        }
    }

    @Test
    fun expiredBizCode() {
        val expired = """{"code":0,"msg":"","data":{"biz_code":40002,"biz_msg":"token 失效","biz_data":null}}"""
        val service = PlatformService(StubHttp { _, _ -> PlatformHttpResponse(200, expired) })
        assertPlatformError(PlatformErrorKind.API, "平台 Token 无效或已过期，请重新获取") {
            service.fetchCurrentUser("bad")
        }
    }

    @Test
    fun httpError() {
        val service = PlatformService(StubHttp { _, _ -> PlatformHttpResponse(500, "") })
        assertPlatformError(PlatformErrorKind.HTTP, "用量获取失败（HTTP 500）") {
            service.fetchCurrentUser("bad")
        }
    }

    @Test
    fun decodingError() {
        val service = PlatformService(StubHttp { _, _ -> PlatformHttpResponse(200, "not-json") })
        try {
            service.fetchCurrentUser("bad")
            fail("应抛出 PlatformException")
        } catch (e: PlatformException) {
            assertEquals(PlatformErrorKind.DECODING, e.kind)
            assertTrue(e.message.startsWith("用量解析失败："))
        }
    }
}

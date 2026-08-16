package com.deepseek.meter.core

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 后台刷新错误决策测试（对齐 Issue #13 验收清单）：
 * NETWORK→RETRY；EMPTY_TOKEN / TokenExpired(40002,40003) / HTTP / API / DECODING→COMPLETE。
 */
class BackgroundRefreshDecisionTest {

    @Test
    fun noErrorCompletes() {
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(null))
    }

    @Test
    fun networkErrorRetries() {
        val e = PlatformException(PlatformErrorKind.NETWORK, "用量获取失败：连接超时")
        assertEquals(RefreshDecision.RETRY, BackgroundRefreshDecision.decide(e))
    }

    @Test
    fun emptyTokenCompletes() {
        val e = PlatformException(PlatformErrorKind.EMPTY_TOKEN, "请先在设置中填写平台 Token")
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e))
    }

    @Test
    fun tokenExpiredCompletes() {
        val e40002 = PlatformException(PlatformErrorKind.API, "平台 Token 无效或已过期，请重新获取", apiCode = 40002)
        val e40003 = PlatformException(PlatformErrorKind.API, "平台 Token 无效或已过期，请重新获取", apiCode = 40003)
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e40002))
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e40003))
    }

    @Test
    fun httpErrorCompletes() {
        val e = PlatformException(PlatformErrorKind.HTTP, "用量获取失败（HTTP 500）", httpCode = 500)
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e))
    }

    @Test
    fun apiErrorCompletes() {
        val e = PlatformException(PlatformErrorKind.API, "平台接口错误（10001）：示例", apiCode = 10001)
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e))
    }

    @Test
    fun decodingErrorCompletes() {
        val e = PlatformException(PlatformErrorKind.DECODING, "用量解析失败：JSON 解析错误")
        assertEquals(RefreshDecision.COMPLETE, BackgroundRefreshDecision.decide(e))
    }
}

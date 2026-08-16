package com.deepseek.meter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 低余额通知策略测试（对齐 Issue #13 验收清单）：
 * balance=0 / <threshold / =threshold / >threshold；首次通知；去重；恢复重置；再次跌破再通知；自定义阈值。
 */
class LowBalancePolicyTest {

    private fun evaluate(balance: Double, alerted: Boolean, threshold: Double = 1.0): LowBalanceDecision =
        LowBalancePolicy.evaluate(balance, threshold, alerted)

    // 余额 <= 0：不通知，alerted 保持
    @Test
    fun zeroBalanceDoesNotNotify() {
        val d = evaluate(0.0, alerted = false)
        assertFalse(d.shouldNotify)
        assertFalse(d.alerted)
    }

    @Test
    fun negativeBalanceKeepsAlertedState() {
        val d = evaluate(-0.5, alerted = true)
        assertFalse(d.shouldNotify)
        assertTrue(d.alerted)
    }

    // 首次低余额：通知并置位
    @Test
    fun firstLowBalanceNotifiesAndSetsAlerted() {
        val d = evaluate(0.72, alerted = false)
        assertTrue(d.shouldNotify)
        assertTrue(d.alerted)
    }

    // 同一低余额周期：不重复通知
    @Test
    fun repeatedLowBalanceDoesNotNotify() {
        val d = evaluate(0.72, alerted = true)
        assertFalse(d.shouldNotify)
        assertTrue(d.alerted)
    }

    // balance == threshold：不算低余额，且重置 alerted
    @Test
    fun thresholdEqualResetsAlerted() {
        val d = evaluate(1.0, alerted = true)
        assertFalse(d.shouldNotify)
        assertFalse(d.alerted)
    }

    // 余额恢复：重置 alerted
    @Test
    fun aboveThresholdResetsAlerted() {
        val d = evaluate(5.0, alerted = true)
        assertFalse(d.shouldNotify)
        assertFalse(d.alerted)
    }

    // 恢复后再次跌破：可再次通知
    @Test
    fun recoveryThenDropAgainNotifies() {
        val recovered = evaluate(5.0, alerted = true)
        assertFalse(recovered.alerted)
        val dropped = evaluate(0.5, alerted = recovered.alerted)
        assertTrue(dropped.shouldNotify)
        assertTrue(dropped.alerted)
    }

    // 自定义阈值（非 1.0 币种单位场景）
    @Test
    fun customThreshold() {
        assertTrue(evaluate(0.9, alerted = false, threshold = 2.0).shouldNotify)
        assertFalse(evaluate(2.0, alerted = false, threshold = 2.0).shouldNotify)
        assertFalse(evaluate(2.5, alerted = false, threshold = 2.0).shouldNotify)
    }

    // 决策结果可作为下次输入往返（调用方持久化契约）
    @Test
    fun decisionRoundTrips() {
        val first = evaluate(0.3, alerted = false)
        val second = evaluate(0.3, alerted = first.alerted)
        assertTrue(first.shouldNotify)
        assertFalse(second.shouldNotify)
        assertEquals(true, second.alerted)
    }
}

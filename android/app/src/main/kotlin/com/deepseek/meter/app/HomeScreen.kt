package com.deepseek.meter.app

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.deepseek.meter.core.AppModel
import com.deepseek.meter.core.DataStatus
import com.deepseek.meter.core.ModelUsage
import com.deepseek.meter.core.MonthUsage
import com.deepseek.meter.core.UsageDay
import com.deepseek.meter.core.currencySymbol
import com.deepseek.meter.core.format
import com.deepseek.meter.core.tokenString
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.max

/**
 * 主页：余额 + 本月用量 + Token 趋势集成（视觉对齐 iOS HomeView / macOS 悬浮窗）。
 */
@Composable
fun HomeScreen(state: AppModel.State, controller: AppController, onLogin: () -> Unit) {
    var trendMetric by remember { mutableStateOf(TrendMetric.OUTPUT) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        when (state.status) {
            DataStatus.NOT_LOGGED_IN -> LoginCard(onLogin)
            DataStatus.TOKEN_EXPIRED -> ExpiredCard(onLogin)
            else -> {
                StatusRow(state, controller)
                Spacer(Modifier.height(12.dp))
                BalanceHero(state)
                Spacer(Modifier.height(16.dp))
                UsageSection(state)
                Spacer(Modifier.height(16.dp))
                TrendSection(state, trendMetric, onMetricChange = { trendMetric = it })
                if (state.status == DataStatus.STALE) {
                    Spacer(Modifier.height(12.dp))
                    Text("数据可能过期（刷新失败，正在显示旧数据）", color = Color(0xFFB26A00), fontSize = 12.sp)
                }
                (state.lastError ?: state.usageError)?.let { error ->
                    Spacer(Modifier.height(12.dp))
                    Text("⚠ " + error, color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Text(
            "数据来自 DeepSeek 官方平台接口，仅使用你自己的登录态，不向任何第三方上报",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.outline,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )
    }
}

// MARK: - 状态行

@Composable
private fun StatusRow(state: AppModel.State, controller: AppController) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        StatusPill(state)
        Spacer(Modifier.weight(1f))
        val updateText = state.lastUpdate?.let { "更新于 " + timeText(it) } ?: ""
        Text(updateText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
        Spacer(Modifier.width(8.dp))
        TextButton(onClick = { controller.refresh() }) {
            if (state.fetching) {
                CircularProgressIndicator(Modifier.height(14.dp).width(14.dp), strokeWidth = 2.dp)
            } else {
                Text("↻")
            }
        }
    }
}

@Composable
private fun StatusPill(state: AppModel.State) {
    val (color, text) = when (state.status) {
        DataStatus.FRESH -> Color(0xFF2E7D32) to "可用"
        DataStatus.STALE -> Color(0xFFB26A00) to "数据可能过期"
        DataStatus.ERROR -> Color(0xFFC62828) to "异常"
        DataStatus.TOKEN_EXPIRED -> Color(0xFFC62828) to "已过期"
        DataStatus.LOADING -> Color(0xFF757575) to "加载中"
        DataStatus.NOT_LOGGED_IN -> Color(0xFF757575) to "未登录"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.background(color.copy(alpha = 0.14f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Box(Modifier.height(8.dp).width(8.dp).background(color, RoundedCornerShape(50)))
        Spacer(Modifier.width(5.dp))
        Text(text, style = MaterialTheme.typography.labelSmall)
    }
}

// MARK: - 余额渐变卡

@Composable
private fun BalanceHero(state: AppModel.State) {
    val total = state.lastBalance?.total ?: 0.0
    val gradient = when {
        total < 1 -> listOf(Color(0xFFD94D38), Color(0xFF8C1410))
        total < 10 -> listOf(Color(0xFFFA9E33), Color(0xFFD15205))
        else -> listOf(BrandBlueLight, BrandBlueDark)
    }
    Card(
        shape = RoundedCornerShape(24.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            Modifier.background(Brush.linearGradient(gradient)).padding(20.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("账户余额", color = Color.White, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                Text(
                    state.currency,
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.background(Color.White.copy(alpha = 0.22f), RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                currencySymbol(state.currency) + " " + format(total),
                color = Color.White,
                fontSize = 42.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(Modifier.height(10.dp))
            Row {
                HeroMiniStat("赠送", state.lastBalance?.granted, state.currency)
                Spacer(Modifier.width(24.dp))
                HeroMiniStat("充值", state.lastBalance?.toppedUp, state.currency)
            }
        }
    }
}

@Composable
private fun HeroMiniStat(title: String, value: Double?, currency: String) {
    Column {
        Text(title, color = Color.White.copy(alpha = 0.8f), style = MaterialTheme.typography.labelSmall)
        Text(
            value?.let { currencySymbol(currency) + format(it) } ?: "—",
            color = Color.White,
            fontWeight = FontWeight.SemiBold
        )
    }
}

// MARK: - 本月用量

@Composable
private fun UsageSection(state: AppModel.State) {
    val usage = state.monthUsage
    Card(shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            if (usage != null) {
                val symbol = currencySymbol(state.currency)
                Row {
                    Text(
                        usage.year.toString() + "年" + usage.month.toString() + "月用量",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.weight(1f))
                    Text("累计 " + symbol + format(usage.totalCost), fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(12.dp))
                val today = usage.tokens(Date())
                Row {
                    StatCell("今日费用", symbol + format(usage.cost(Date())), Modifier.weight(1f))
                    StatCell("今日请求", countString(today.requests), Modifier.weight(1f))
                    StatCell("今日输出", tokenString(today.response), Modifier.weight(1f))
                }
                Spacer(Modifier.height(8.dp))
                Row {
                    StatCell("本月请求", countString(usage.totalRequests), Modifier.weight(1f))
                    StatCell("本月输出", tokenString(usage.responseTokens), Modifier.weight(1f))
                    StatCell("缓存命中", tokenString(usage.cacheHitTokens), Modifier.weight(1f))
                }
                val activeModels = usage.amountModels.filter { it.requests > 0 }
                if (activeModels.isNotEmpty()) {
                    Spacer(Modifier.height(12.dp))
                    HorizontalDivider()
                    activeModels.forEach { item ->
                        ModelRow(item, usage, symbol)
                    }
                }
            } else if (state.usageError != null) {
                Text(
                    if (state.tokenExpired) "平台登录已过期，请重新登录" else (state.usageError ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            } else if (state.fetching) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.height(16.dp).width(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                    Text("加载用量…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                }
            } else {
                Text("登录后显示余额与用量明细", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }
}

@Composable
private fun StatCell(title: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
        Text(value, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

@Composable
private fun ModelRow(item: ModelUsage, usage: MonthUsage, symbol: String) {
    val cost = usage.costModels.firstOrNull { it.model == item.model }?.usage?.sumOf { it.amount } ?: 0.0
    Row(Modifier.padding(vertical = 4.dp)) {
        Text(
            modelDisplayName(item.model),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            modifier = Modifier.weight(1f)
        )
        Text(
            countString(item.requests) + " 次 · " + symbol + format(cost),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.outline
        )
    }
}

// MARK: - Token 趋势

enum class TrendMetric(val label: String) { OUTPUT("输出"), CACHE_HIT("缓存命中"), TOTAL("总量") }

@Composable
private fun TrendSection(state: AppModel.State, metric: TrendMetric, onMetricChange: (TrendMetric) -> Unit) {
    val usage = state.monthUsage
    Card(shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Token 用量趋势", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                TrendMetric.values().forEach { m ->
                    FilterChip(
                        selected = metric == m,
                        onClick = { onMetricChange(m) },
                        label = { Text(m.label, fontSize = 12.sp) },
                        modifier = Modifier.padding(start = 4.dp)
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            if (usage != null) {
                val entries = dailyEntries(usage, metric)
                if (entries.isEmpty()) {
                    Text("本月暂无用量数据", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                } else {
                    TokenDailyChart(entries, Modifier.fillMaxWidth().height(150.dp))
                    Spacer(Modifier.height(6.dp))
                    Row {
                        val todayKey = dayFormatter.format(Date())
                        val todayVal = usage.amountDays.firstOrNull { it.date == todayKey }
                            ?.let { dailyValue(it, metric) } ?: 0.0
                        Text("今日 " + tokenString(todayVal), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                        Spacer(Modifier.weight(1f))
                        val peak = entries.maxByOrNull { it.second }
                        if (peak != null) {
                            Text(
                                "峰值 " + tokenString(peak.second) + "（" + dayLabel(peak.first) + "）",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }
                }
            } else if (state.usageError == null && !state.fetching) {
                Text("登录后查看 Token 用量趋势", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
        }
    }
}

/** 按天柱状图（Canvas 自绘，对齐 iOS TokenDailyChart） */
@Composable
private fun TokenDailyChart(entries: List<Pair<String, Double>>, modifier: Modifier = Modifier) {
    val maxV = max(entries.maxOfOrNull { it.second } ?: 0.0, 1.0)
    val barColor = MaterialTheme.colorScheme.primary
    val zeroColor = Color.Gray.copy(alpha = 0.15f)
    val labelColor = MaterialTheme.colorScheme.outline.toArgb()

    Canvas(modifier = modifier) {
        val labelH = 18.dp.toPx()
        val barArea = size.height - labelH
        val slot = size.width / entries.size.coerceAtLeast(1)
        val barW = (slot * 0.6f).coerceAtLeast(1f)
        val paint = Paint().apply {
            textSize = 9.sp.toPx()
            color = labelColor
            textAlign = Paint.Align.CENTER
        }
        entries.forEachIndexed { index, entry ->
            val value = entry.second
            val h = ((value / maxV) * barArea * 0.95f).toFloat()
                .coerceAtLeast(if (value > 0) 3.dp.toPx() else 1.dp.toPx())
            val x = index * slot + (slot - barW) / 2
            drawRoundRect(
                color = if (value > 0) barColor else zeroColor,
                topLeft = Offset(x, barArea - h),
                size = Size(barW, h),
                cornerRadius = CornerRadius(3.dp.toPx(), 3.dp.toPx())
            )
            drawContext.canvas.nativeCanvas.drawText(entry.first, x + barW / 2, size.height - 4.dp.toPx(), paint)
        }
    }
}

// MARK: - 登录/过期卡片

@Composable
private fun LoginCard(onLogin: () -> Unit) {
    Card(shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("🐳", fontSize = 40.sp)
            Spacer(Modifier.height(8.dp))
            Text("登录后查看余额与用量", fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text("内嵌官方登录页，登录一次自动获取登录态", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            Spacer(Modifier.height(12.dp))
            Button(onClick = onLogin) { Text("一键登录") }
        }
    }
}

@Composable
private fun ExpiredCard(onLogin: () -> Unit) {
    Card(shape = RoundedCornerShape(20.dp), modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("⚠️", fontSize = 40.sp)
            Spacer(Modifier.height(8.dp))
            Text("登录已过期，请重新登录", fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text("平台 Token 无效或已过期", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            Spacer(Modifier.height(12.dp))
            Button(onClick = onLogin) { Text("重新登录") }
        }
    }
}

// MARK: - 工具（对齐 iOS HomeView 助手）

private fun countString(n: Int): String = java.text.NumberFormat.getNumberInstance(Locale.US).format(n)

private fun modelDisplayName(model: String): String = model.replace("deepseek-", "")

// 平台计日格式（主线程单实例复用；SimpleDateFormat 非线程安全，调用方均为主线程/单线程执行器）
private val dayFormatter: SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    .apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }

private fun timeText(ms: Long): String =
    SimpleDateFormat("HH:mm", Locale.US).format(Date(ms))

private fun dayLabel(dateKey: String): String {
    val f = dayFormatter
    val date = f.parse(dateKey) ?: return dateKey
    val cal = Calendar.getInstance().apply { time = date }
    return (cal.get(Calendar.MONTH) + 1).toString() + "月" + cal.get(Calendar.DAY_OF_MONTH).toString() + "日"
}

private fun dailyValue(day: UsageDay, metric: TrendMetric): Double {
    val resp = day.data.sumOf { it.value("RESPONSE_TOKEN") }
    val hit = day.data.sumOf { it.value("PROMPT_CACHE_HIT_TOKEN") }
    val miss = day.data.sumOf { it.value("PROMPT_CACHE_MISS_TOKEN") }
    return when (metric) {
        TrendMetric.OUTPUT -> resp
        TrendMetric.CACHE_HIT -> hit
        TrendMetric.TOTAL -> resp + hit + miss
    }
}

private fun dailyEntries(usage: MonthUsage, metric: TrendMetric): List<Pair<String, Double>> {
    val todayKey = dayFormatter.format(Date())
    val f = dayFormatter
    return usage.amountDays
        .filter { it.date <= todayKey }
        .mapNotNull { day ->
            val date = f.parse(day.date) ?: return@mapNotNull null
            val cal = Calendar.getInstance().apply { time = date }
            cal.get(Calendar.DAY_OF_MONTH).toString() to dailyValue(day, metric)
        }
}

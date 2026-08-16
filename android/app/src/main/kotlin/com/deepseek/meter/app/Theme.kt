package com.deepseek.meter.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// 品牌深蓝（与 iOS 渐变余额卡 / App 图标一致）。
// 注意：Color 构造不是编译期常量，无法用 const val；internal 限制模块内访问。
internal val BrandBlue = Color(0xFF1D4ADA)
internal val BrandBlueLight = Color(0xFF2B6BF0)
internal val BrandBlueDark = Color(0xFF0D2E8A)

private val LightColors = lightColorScheme(
    primary = BrandBlue
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF7FA5FF)
)

/// Material3 主题（浅色/深色自适应）
@Composable
fun DeepSeekMeterTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content
    )
}

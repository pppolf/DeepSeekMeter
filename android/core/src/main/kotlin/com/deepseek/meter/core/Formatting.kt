package com.deepseek.meter.core

import java.util.Locale

/** 余额格式化：千元以上保留 1 位小数，其余保留 2 位（对齐 iOS Formatting.swift） */
fun format(value: Double): String {
    return if (value >= 1000) String.format(Locale.US, "%.1f", value)
    else String.format(Locale.US, "%.2f", value)
}

/** 币种代码 -> 常用符号（对齐 iOS Formatting.swift） */
fun currencySymbol(code: String): String {
    return when (code.uppercase(Locale.US)) {
        "CNY" -> "¥"
        "USD" -> "$"
        "EUR" -> "€"
        "JPY", "KRW" -> "¥"
        "HKD" -> "HK$"
        "GBP" -> "£"
        else -> code
    }
}

/** Token/数量展示：亿/万单位（对齐 iOS HomeView.tokenString） */
fun tokenString(n: Double): String {
    return when {
        n >= 1e8 -> String.format(Locale.US, "%.2f亿", n / 1e8)
        n >= 1e4 -> String.format(Locale.US, "%.1f万", n / 1e4)
        else -> format(n)
    }
}

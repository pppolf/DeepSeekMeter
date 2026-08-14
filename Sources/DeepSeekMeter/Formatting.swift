import Foundation

/// 余额格式化：千元以上保留 1 位小数，其余保留 2 位
func format(_ value: Double) -> String {
    if value >= 1000 {
        return String(format: "%.1f", value)
    }
    return String(format: "%.2f", value)
}

/// 币种代码 -> 常用符号
func currencySymbol(_ code: String) -> String {
    switch code.uppercased() {
    case "CNY": return "¥"
    case "USD": return "$"
    case "EUR": return "€"
    case "JPY", "KRW": return "¥"
    default: return code
    }
}

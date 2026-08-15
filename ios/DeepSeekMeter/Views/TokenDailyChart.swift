import SwiftUI
import DeepSeekMeterCore

/// Token 趋势指标（对齐 macOS PopoverView.TrendMetric）
enum TrendMetric: String, CaseIterable, Identifiable {
    case output = "输出"
    case cacheHit = "缓存命中"
    case total = "总量"
    var id: String { rawValue }
}

/// Token 每日用量条目（对齐 macOS SparklineView）
struct TokenDailyEntry: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 本月按天 Token 用量柱状图（对齐 macOS SparklineView；移动端加高、加大日期标注）
struct TokenDailyChart: View {
    let entries: [TokenDailyEntry]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(entries.map(\.value).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(entries) { entry in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.value > 0 ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.08))
                            .frame(height: max(3, CGFloat(entry.value / maxV) * (geo.size.height - 26)))
                        Text(String(Calendar.current.component(.day, from: entry.date)))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

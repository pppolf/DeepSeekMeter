import SwiftUI

/// Token 每日用量条目
struct TokenDailyEntry: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// 本月按天 Token 用量柱状图
struct TokenDailyChart: View {
    let entries: [TokenDailyEntry]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(entries.map(\.value).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(entries) { entry in
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(entry.value > 0 ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.08))
                            .frame(height: max(2, CGFloat(entry.value / maxV) * (geo.size.height - 12)))
                        Text(String(Calendar.current.component(.day, from: entry.date)))
                            .font(.system(size: 6))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: 42)
    }
}

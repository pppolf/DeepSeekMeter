import WidgetKit
import SwiftUI
import DeepSeekMeterCore

// MARK: - 数据（快照驱动）

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: Double
    let currency: String
    let updated: Date?
}

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), balance: 0, currency: "CNY", updated: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(makeEntry())
    }

    /// 快照驱动：时间轴只放一个条目 + 30 分钟轮询；
    /// 内容实际由 App 每次刷新后写入 BalanceSnapshot 并主动 reload（见 App 侧 onChange）
    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func makeEntry() -> BalanceEntry {
        let snap = BalanceSnapshot.load()
        return BalanceEntry(date: Date(), balance: snap.balance, currency: snap.currency, updated: snap.updated)
    }
}

// MARK: - 视图

struct BalanceWidgetView: View {
    let entry: BalanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("DeepSeekMeter", systemImage: "creditcard.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(currencySymbol(entry.currency))\(format(entry.balance))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(balanceColor)
            if let updated = entry.updated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// 余额配色：低于 1 红、低于 10 橙（对齐桌面菜单栏语义）
    private var balanceColor: Color {
        if entry.balance < 1 { return .red }
        if entry.balance < 10 { return .orange }
        return .primary
    }
}

// MARK: - Widget 配置

struct BalanceWidget: Widget {
    let kind = "DeepSeekMeterBalance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("DeepSeekMeter 余额")
        .description("显示最近一次刷新到的账户余额（数据只来自 DeepSeek 官方接口）")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

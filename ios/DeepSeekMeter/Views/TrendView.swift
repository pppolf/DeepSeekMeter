import SwiftUI
import Charts
import DeepSeekMeterCore

/// 趋势：本月按天 Token 柱状图（输出 / 缓存命中 / 总量可切换）
struct TrendView: View {
    @ObservedObject var appModel: AppModel
    @State private var metric: Metric = .output

    enum Metric: String, CaseIterable, Identifiable {
        case output = "输出"
        case cacheHit = "缓存命中"
        case total = "总量"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let usage = appModel.monthUsage, !usage.amountDays.isEmpty {
                    VStack(spacing: 12) {
                        Picker("指标", selection: $metric) {
                            ForEach(Metric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        Chart {
                            ForEach(dailyData(usage), id: \.id) { item in
                                BarMark(
                                    x: .value("日期", item.date),
                                    y: .value("Token", item.value)
                                )
                                .foregroundStyle(metricColor)
                            }
                        }
                        .chartYAxisLabel("Token")
                        .frame(height: 260)
                        .padding()

                        Text("本月按天 \(metric.rawValue) Token（北京时间）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "暂无趋势数据",
                        systemImage: "chart.bar",
                        description: Text(appModel.usageError ?? "本月暂无用量")
                    )
                }
            }
            .navigationTitle("趋势")
            .refreshable { await appModel.performRefresh() }
        }
    }

    private var metricColor: Color {
        switch metric {
        case .output: return .blue
        case .cacheHit: return .green
        case .total: return .purple
        }
    }

    private struct DayValue: Identifiable {
        let date: String
        let value: Double
        var id: String { date }
    }

    private func dailyData(_ usage: MonthUsage) -> [DayValue] {
        usage.amountDays.map { day in
            let value: Double
            switch metric {
            case .output:
                value = day.data.reduce(0) { $0 + $1.value(for: "RESPONSE_TOKEN") }
            case .cacheHit:
                value = day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_HIT_TOKEN") }
            case .total:
                value = day.data.reduce(0) { $0 + $1.usage.reduce(0) { $0 + $1.value } }
            }
            return DayValue(date: day.date, value: value)
        }
    }
}

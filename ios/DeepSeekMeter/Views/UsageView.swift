import SwiftUI
import DeepSeekMeterCore

/// 用量：本月汇总 + 按模型拆分（费用/请求/Token）
struct UsageView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let usage = appModel.monthUsage {
                    List {
                        Section("本月汇总") {
                            summaryRow("费用", "\(currencySymbol(appModel.currency))\(format(usage.totalCost))")
                            summaryRow("请求数", "\(usage.totalRequests)")
                            summaryRow("输出 Token", "\(Int(usage.responseTokens))")
                            summaryRow("缓存命中", "\(Int(usage.cacheHitTokens))")
                            summaryRow("缓存未命中", "\(Int(usage.cacheMissTokens))")
                        }
                        Section("按模型") {
                            if usage.costModels.isEmpty {
                                Text("本月暂无模型用量")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(usage.costModels) { model in
                                modelRow(model)
                            }
                        }
                    }
                } else if appModel.status == .notLoggedIn {
                    ContentUnavailableView(
                        "未登录",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("请在「概览」页登录")
                    )
                } else {
                    ContentUnavailableView(
                        "暂无数据",
                        systemImage: "chart.bar",
                        description: Text(appModel.usageError ?? "加载中…")
                    )
                }
            }
            .navigationTitle("用量")
            .refreshable { await appModel.performRefresh() }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// 费用 + 请求/输出（费用来自 costModels，请求/Token 来自 amountModels 交叉引用）
    private func modelRow(_ costModel: ModelUsage) -> some View {
        let amountModel = appModel.monthUsage?.amountModels.first { $0.model == costModel.model }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(costModel.model)
                    .font(.subheadline)
                Text("请求 \(amountModel?.requests ?? 0) · 输出 \(Int(amountModel?.value(for: "RESPONSE_TOKEN") ?? 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(currencySymbol(appModel.currency))\(format(costModel.usage.reduce(0) { $0 + $1.value }))")
                .font(.subheadline.monospacedDigit())
        }
    }
}

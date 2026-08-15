import SwiftUI
import DeepSeekMeterCore

/// 概览：余额卡片 + 今日概览 + 最后更新时间。
/// 状态驱动：未登录引导 / 登录过期提示 / 错误重试 / 旧数据 stale 标注。
struct OverviewView: View {
    @ObservedObject var appModel: AppModel
    @Binding var showLogin: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch appModel.status {
                    case .notLoggedIn:
                        loginGuideCard
                    case .tokenExpired:
                        expiredCard
                    default:
                        balanceCard
                        todayCard
                        if appModel.status == .stale {
                            staleBadge
                        }
                        if let error = visibleError {
                            errorCard(error)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("DeepSeekMeter")
            .refreshable { await appModel.performRefresh() }
            .onAppear { appModel.refresh() }
        }
    }

    // MARK: - 状态卡片

    private var loginGuideCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.open.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text("登录后查看余额与用量")
                .font(.headline)
            Button("登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var expiredCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("登录已过期，请重新登录")
                .font(.headline)
            Text("平台 Token 无效或已过期")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重新登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("账户余额")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(currencySymbol(appModel.currency)) \(format(appModel.lastBalance?.total ?? 0))")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(balanceColor)
            HStack {
                Text("赠送 \(format(appModel.lastBalance?.granted ?? 0)) · 充值 \(format(appModel.lastBalance?.toppedUp ?? 0))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastUpdate = appModel.lastUpdate {
                    Text("更新于 \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 余额配色：低于 1 红、低于 10 橙（对齐桌面菜单栏语义）
    private var balanceColor: Color {
        let value = appModel.lastBalance?.total ?? 0
        if value < 1 { return .red }
        if value < 10 { return .orange }
        return .primary
    }

    private var todayCard: some View {
        let usage = appModel.monthUsage
        // 注意：兜底元组必须带标签，否则与可选元组合并后标签丢失（编译器报 value has no member）
        let today = usage?.tokens(on: Date()) ?? (requests: 0, response: 0, cacheHit: 0, cacheMiss: 0)
        let todayCost = usage?.cost(on: Date()) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("今日概览")
                .font(.headline)
            HStack(spacing: 16) {
                statItem(title: "费用", value: "\(currencySymbol(appModel.currency))\(format(todayCost))")
                statItem(title: "请求", value: "\(today.requests)")
                statItem(title: "输出 Token", value: "\(Int(today.response))")
            }
            if usage == nil {
                Text("今日数据为空（本月暂无用量）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staleBadge: some View {
        Label("数据可能过期（刷新失败，正在显示旧数据）", systemImage: "clock.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.orange)
    }

    private var visibleError: String? {
        appModel.lastError ?? appModel.usageError
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
            Button("重试") { appModel.refresh() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

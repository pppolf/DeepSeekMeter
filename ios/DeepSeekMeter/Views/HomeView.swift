import SwiftUI
import DeepSeekMeterCore

/// 主页：余额 + 本月用量 + Token 趋势集成在一个可滚动页面。
/// 视觉对齐 macOS 悬浮窗（状态胶囊、余额大数字、今日/本月统计、按模型拆分、趋势图），
/// 并用品牌深蓝渐变余额卡提升移动端质感；数据状态六态完整呈现。
struct HomeView: View {
    @ObservedObject var appModel: AppModel
    @Binding var showLogin: Bool
    @State private var trendMetric: TrendMetric = .output

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch appModel.status {
                    case .notLoggedIn:
                        loginCard
                    case .tokenExpired:
                        expiredCard
                    default:
                        statusRow
                        balanceHero
                        usageSection
                        trendSection
                        if appModel.status == .stale {
                            staleBadge
                        }
                        if let error = visibleError {
                            errorBanner(error)
                        }
                    }
                    privacyFootnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DeepSeekMeter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appModel.refresh()
                    } label: {
                        if appModel.isFetching {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(appModel.isFetching)
                }
            }
            .refreshable { await appModel.performRefresh() }
            .onAppear { appModel.refresh() }
        }
    }

    // MARK: - 状态行

    private var statusRow: some View {
        HStack(spacing: 8) {
            statusPill
            Spacer()
            if let lastUpdate = appModel.lastUpdate {
                Text("更新于 \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var statusColor: Color {
        switch appModel.status {
        case .fresh: return .green
        case .stale: return .orange
        case .error, .tokenExpired: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        switch appModel.status {
        case .fresh: return "可用"
        case .stale: return "数据可能过期"
        case .error: return "异常"
        case .tokenExpired: return "已过期"
        case .loading: return "加载中"
        case .notLoggedIn: return "未登录"
        }
    }

    // MARK: - 余额渐变卡

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("账户余额", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(appModel.currency)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            Text("\(currencySymbol(appModel.currency)) \(format(appModel.lastBalance?.total ?? 0))")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: appModel.lastBalance?.total)
            HStack(spacing: 24) {
                heroMiniStat("赠送", appModel.lastBalance?.granted)
                heroMiniStat("充值", appModel.lastBalance?.toppedUp)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: heroGradientShadow, radius: 14, x: 0, y: 8)
    }

    /// 余额阈值配色：低于 1 红、低于 10 橙（对齐桌面菜单栏语义）
    private var heroGradient: LinearGradient {
        let value = appModel.lastBalance?.total ?? 0
        if value < 1 {
            return LinearGradient(colors: [Color(red: 0.85, green: 0.30, blue: 0.22), Color(red: 0.55, green: 0.08, blue: 0.12)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if value < 10 {
            return LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.20), Color(red: 0.82, green: 0.32, blue: 0.05)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 0.98), Color(red: 0.05, green: 0.18, blue: 0.55)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroGradientShadow: Color {
        let value = appModel.lastBalance?.total ?? 0
        if value < 1 { return Color.red.opacity(0.4) }
        if value < 10 { return Color.orange.opacity(0.4) }
        return Color(red: 0.16, green: 0.42, blue: 0.98).opacity(0.4)
    }

    private func heroMiniStat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Text(value.map { "\(currencySymbol(appModel.currency))\(format($0))" } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - 本月用量

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let usage = appModel.monthUsage {
                let symbol = currencySymbol(appModel.currency)
                HStack {
                    Text("\(usage.year)年\(usage.month)月用量")
                        .font(.headline)
                    Spacer()
                    Text("累计 \(symbol)\(format(usage.totalCost))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                let today = usage.tokens(on: Date())
                HStack(spacing: 10) {
                    statCell(title: "今日费用", value: "\(symbol)\(format(usage.cost(on: Date())))")
                    statCell(title: "今日请求", value: Self.countString(today.requests))
                    statCell(title: "今日输出", value: Self.tokenString(today.response))
                }
                HStack(spacing: 10) {
                    statCell(title: "本月请求", value: Self.countString(usage.totalRequests))
                    statCell(title: "本月输出", value: Self.tokenString(usage.responseTokens))
                    statCell(title: "缓存命中", value: Self.tokenString(usage.cacheHitTokens))
                }
                let activeModels = usage.amountModels.filter { $0.requests > 0 }
                if !activeModels.isEmpty {
                    Divider()
                    ForEach(activeModels) { item in
                        modelRow(item, usage: usage, symbol: symbol)
                    }
                }
            } else if appModel.usageError != nil {
                expiredOrErrorPrompt
            } else if appModel.isFetching {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载用量…")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            } else {
                loginPrompt
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelRow(_ item: ModelUsage, usage: MonthUsage, symbol: String) -> some View {
        HStack {
            Text(Self.modelDisplayName(item.model))
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            let cost = usage.costModels.first(where: { $0.model == item.model })?
                .usage.reduce(0) { $0 + $1.value } ?? 0
            Text("\(Self.countString(item.requests)) 次 · \(symbol)\(format(cost))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Token 用量趋势

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Token 用量趋势")
                    .font(.headline)
                Spacer()
                Picker("", selection: $trendMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if let usage = appModel.monthUsage {
                let entries = tokenDailyEntries(usage: usage, metric: trendMetric)
                if entries.isEmpty {
                    Text("本月暂无用量数据")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    TokenDailyChart(entries: entries)
                        .frame(height: 130)
                    HStack(spacing: 4) {
                        Text("今日 \(Self.tokenString(dailyValue(usage: usage, on: Date(), metric: trendMetric)))")
                        Spacer()
                        if let peak = entries.max(by: { $0.value < $1.value }) {
                            Text("峰值 \(Self.tokenString(peak.value))（\(Self.dayLabel(peak.date))）")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if appModel.usageError == nil && !appModel.isFetching {
                Text("登录后查看 Token 用量趋势")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - 登录/过期/错误状态

    private var loginCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("登录后查看余额与用量")
                .font(.headline)
            Text("内嵌官方登录页，登录一次自动获取登录态")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showLogin = true
            } label: {
                Label("一键登录", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var expiredCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("登录已过期，请重新登录")
                .font(.headline)
            Text("平台 Token 无效或已过期")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showLogin = true
            } label: {
                Label("重新登录", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var expiredOrErrorPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(appModel.platformTokenExpired ? "平台登录已过期，请重新登录" : (appModel.usageError ?? "用量获取失败"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button {
                showLogin = true
            } label: {
                Label("重新登录", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(.secondary)
                Text("登录后显示余额与用量明细")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Button {
                showLogin = true
            } label: {
                Label("一键登录", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var staleBadge: some View {
        Label("数据可能过期（刷新失败，正在显示旧数据）", systemImage: "clock.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var visibleError: String? {
        appModel.lastError ?? appModel.usageError
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var privacyFootnote: some View {
        Text("数据来自 DeepSeek 官方平台接口，仅使用你自己的登录态，不向任何第三方上报")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    // MARK: - 格式化与趋势工具（对齐 macOS PopoverView）

    private static func countString(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func tokenString(_ n: Double) -> String {
        if n >= 1e8 { return String(format: "%.2f亿", n / 1e8) }
        if n >= 1e4 { return String(format: "%.1f万", n / 1e4) }
        return format(n)
    }

    private static func modelDisplayName(_ model: String) -> String {
        model.replacingOccurrences(of: "deepseek-", with: "")
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
    }

    private func tokenDailyEntries(usage: MonthUsage, metric: TrendMetric) -> [TokenDailyEntry] {
        let todayKey = MonthUsage.dayFormatter.string(from: Date())
        return usage.amountDays.compactMap { day -> TokenDailyEntry? in
            guard day.date <= todayKey, let date = MonthUsage.dayFormatter.date(from: day.date) else { return nil }
            return TokenDailyEntry(date: date, value: dailyValue(day: day, metric: metric))
        }
    }

    private func dailyValue(usage: MonthUsage, on date: Date, metric: TrendMetric) -> Double {
        let key = MonthUsage.dayFormatter.string(from: date)
        guard let day = usage.amountDays.first(where: { $0.date == key }) else { return 0 }
        return dailyValue(day: day, metric: metric)
    }

    private func dailyValue(day: UsageDay, metric: TrendMetric) -> Double {
        let resp = day.data.reduce(0) { $0 + $1.value(for: "RESPONSE_TOKEN") }
        let hit = day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_HIT_TOKEN") }
        let miss = day.data.reduce(0) { $0 + $1.value(for: "PROMPT_CACHE_MISS_TOKEN") }
        switch metric {
        case .output: return resp
        case .cacheHit: return hit
        case .total: return resp + hit + miss
        }
    }
}

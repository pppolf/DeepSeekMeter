import SwiftUI
import AppKit

/// 悬浮窗主界面
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var trendMetric: TrendMetric = .output

    private var balance: BalanceInfo? { model.lastBalance }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                balanceSection
                usageSection
                tokenTrendSection
                if let error = model.lastError {
                    errorBanner(error)
                }
                Divider()
                settingsSection
                footer
            }
            .padding(16)
            .frame(width: 340)
        }
        .frame(width: 340)
        .scrollIndicators(.hidden)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
            Text("DeepSeek Meter")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 4)
            statusPill
            if let lastUpdate = model.lastUpdate {
                Text(lastUpdate.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.14), in: Capsule())
    }

    private var statusColor: Color {
        if model.lastBalance != nil { return .green }
        if model.lastError != nil { return .red }
        return .gray
    }

    private var statusText: String {
        if model.lastBalance != nil { return "可用" }
        if model.lastError != nil { return "异常" }
        return "未获取"
    }

    // MARK: - 余额

    private var balanceSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("总余额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currencySymbol(balance?.currency ?? "CNY"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(format(balance?.total ?? 0))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: balance?.total)
                }
                if let currency = balance?.currency {
                    Text("币种：\(currency)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                miniStat(title: "赠送余额", value: balance?.granted, currency: balance?.currency)
                miniStat(title: "充值余额", value: balance?.toppedUp, currency: balance?.currency)
            }
        }
    }

    private func miniStat(title: String, value: Double?, currency: String?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\(currencySymbol(currency ?? "CNY"))\(format($0))" } ?? "—")
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }

    // MARK: - 本月用量

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let usage = model.monthUsage {
                HStack(spacing: 6) {
                    Text("\(usage.year)年\(usage.month)月用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("累计 ¥\(format(usage.totalCost))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                HStack(spacing: 10) {
                    statCell(title: "今日费用", value: "¥\(format(usage.cost(on: Date())))")
                    let today = usage.tokens(on: Date())
                    statCell(title: "今日请求", value: Self.countString(today.requests))
                    statCell(title: "今日输出", value: Self.tokenString(today.response))
                }
                HStack(spacing: 10) {
                    statCell(title: "本月请求", value: Self.countString(usage.totalRequests))
                    statCell(title: "本月输出", value: Self.tokenString(usage.responseTokens))
                    statCell(title: "缓存命中", value: Self.tokenString(usage.cacheHitTokens))
                }
                ForEach(usage.amountModels.filter { $0.requests > 0 }) { item in
                    HStack {
                        Text(Self.modelDisplayName(item.model))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let cost = usage.costModels.first(where: { $0.model == item.model })?
                            .usage.reduce(0) { $0 + $1.value } ?? 0
                        Text("\(Self.countString(item.requests)) 次 · ¥\(format(cost))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if model.platformTokenExpired || model.usageError != nil {
                expiredOrErrorPrompt
            } else if model.isFetching {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载用量…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                loginPrompt
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var loginPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(.secondary)
                Text("登录后显示余额与用量明细")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Button {
                model.beginPlatformLogin()
            } label: {
                Label("一键登录", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var expiredOrErrorPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(model.platformTokenExpired ? "平台登录已过期，请重新登录" : (model.usageError ?? "用量获取失败"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button {
                model.beginPlatformLogin()
            } label: {
                Label("重新登录", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Token 用量趋势（本月按天）

    private var tokenTrendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Token 用量趋势")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $trendMetric) {
                    ForEach(TrendMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 138)
            }

            if let usage = model.monthUsage {
                let entries = tokenDailyEntries(usage: usage, metric: trendMetric)
                if entries.isEmpty {
                    Text("本月暂无用量数据")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    TokenDailyChart(entries: entries)
                        .frame(height: 42)
                    HStack(spacing: 4) {
                        Text("今日 \(Self.tokenString(dailyValue(usage: usage, on: Date(), metric: trendMetric)))")
                        Spacer()
                        if let peak = entries.max(by: { $0.value < $1.value }) {
                            Text("峰值 \(Self.tokenString(peak.value))（\(Self.dayLabel(peak.date))）")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else if model.usageError == nil && !model.isFetching {
                Text("登录后查看 Token 用量趋势")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 错误提示

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 设置

    private var settingsSection: some View {
        VStack(spacing: 12) {
            // 平台 Token（一键登录）
            HStack(spacing: 8) {
                Text("平台账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                if model.settings.platformToken.isEmpty {
                    Text("未登录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("登录") { model.beginPlatformLogin() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Text("已登录 ✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                    if !model.settings.platformUserName.isEmpty {
                        Text(model.settings.platformUserName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("重新登录") { model.beginPlatformLogin() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }

            // 刷新间隔
            HStack(spacing: 8) {
                Text("刷新间隔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Picker("", selection: intervalBinding) {
                    ForEach(SettingsStore.intervalOptions, id: \.self) { interval in
                        Text(Self.intervalLabel(interval)).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                Spacer(minLength: 0)
            }

            // 开机自启
            HStack(spacing: 8) {
                Text("开机自启")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                if model.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var intervalBinding: Binding<TimeInterval> {
        Binding(
            get: { model.settings.refreshInterval },
            set: { model.setRefreshInterval($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { model.settings.launchAtLogin = $0 }
        )
    }

    private static func intervalLabel(_ interval: TimeInterval) -> String {
        switch interval {
        case 15: return "15秒"
        case 30: return "30秒"
        case 60: return "1分"
        case 300: return "5分"
        case 600: return "10分"
        default: return "\(Int(interval))s"
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            Button {
                model.refresh()
            } label: {
                Label(model.isFetching ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isFetching)

            Spacer()

            if !model.settings.platformToken.isEmpty {
                Button("退出登录") { model.clearPlatformToken() }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - 格式化工具

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

    // MARK: - Token 趋势工具

    private func tokenDailyEntries(usage: MonthUsage, metric: TrendMetric) -> [TokenDailyEntry] {
        let todayKey = Self.dayParser.string(from: Date())
        return usage.amountDays.compactMap { day -> TokenDailyEntry? in
            guard day.date <= todayKey, let date = Self.dayParser.date(from: day.date) else { return nil }
            return TokenDailyEntry(date: date, value: dailyValue(day: day, metric: metric))
        }
    }

    private func dailyValue(usage: MonthUsage, on date: Date, metric: TrendMetric) -> Double {
        let key = Self.dayParser.string(from: date)
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

    private static var dayParser: DateFormatter {
        MonthUsage.dayFormatter
    }

    private static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
    }
}

/// Token 趋势指标
enum TrendMetric: String, CaseIterable, Identifiable {
    case output = "输出"
    case cacheHit = "缓存命中"
    case total = "总量"
    var id: String { rawValue }
}

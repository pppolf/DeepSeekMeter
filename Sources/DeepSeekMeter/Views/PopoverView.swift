import SwiftUI
import AppKit

/// 悬浮窗主界面
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var draftKey = ""
    @State private var showingKeyField = false

    private var balance: BalanceInfo? { model.lastBalance }

    var body: some View {
        VStack(spacing: 14) {
            header
            balanceSection
            trendSection
            if let error = model.lastError {
                errorBanner(error)
            }
            Divider()
            settingsSection
            footer
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            draftKey = model.settings.apiKey
            showingKeyField = model.settings.apiKey.isEmpty
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
            Text("DeepSeek Meter")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
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
        if model.isAvailable == nil { return .gray }
        return model.isAvailable == true ? .green : .red
    }

    private var statusText: String {
        if model.isAvailable == nil { return "未获取" }
        return model.isAvailable == true ? "可用" : "不可用"
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

    // MARK: - 趋势

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("近24小时趋势")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                deltaChip(label: "1小时", delta: model.trend.delta(since: 3600))
                deltaChip(label: "今日", delta: model.trend.deltaToday())
                deltaChip(label: "24小时", delta: model.trend.delta(since: 86400))
            }
            SparklineView(points: model.trend.series(hours: 24), height: 44)
                .opacity(model.trend.snapshots.isEmpty ? 0.35 : 1)
            if model.trend.snapshots.isEmpty {
                Text("暂无历史数据，持续运行后将在这里显示余额变化趋势")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func deltaChip(label: String, delta: Double?) -> some View {
        HStack(spacing: 3) {
            if let delta {
                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(delta >= 0 ? .green : .orange)
                Text("\(label) \(format(abs(delta)))")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            } else {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: Capsule())
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
            // API Key
            HStack(spacing: 8) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                if showingKeyField {
                    SecureField("sk-…", text: $draftKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { saveKey() }
                    Button("保存") { saveKey() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Text(maskedKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("修改") {
                        draftKey = model.settings.apiKey
                        showingKeyField = true
                    }
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

    private var maskedKey: String {
        let key = model.settings.apiKey
        guard !key.isEmpty else { return "未设置" }
        if key.count <= 10 { return "••••••" }
        return "sk-••••••\(key.suffix(4))"
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

    private func saveKey() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task { @MainActor in
            let ok = await model.saveAPIKey(key)
            if ok { showingKeyField = false }
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

            if !model.settings.apiKey.isEmpty {
                Button("清除 Key") { model.clearAPIKey() }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

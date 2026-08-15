import Foundation
import Combine

/// 应用状态中枢：轮询余额 + 用量、暴露给 SwiftUI 视图
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore

    @Published var lastBalance: BalanceInfo?
    @Published var lastUpdate: Date?
    @Published var lastError: String?

    @Published var monthUsage: MonthUsage?
    @Published var usageError: String?
    @Published var platformTokenExpired = false

    @Published var isFetching = false

    /// 当前账户币种（余额/登录接口返回，用于费用展示，不再写死 CNY）
    @Published var currency: String = "CNY"

    /// 数据可信度状态（托盘/悬浮窗/错误提示共用，保证一致）
    var status: DataStatus {
        dataStatus(
            token: settings.platformToken,
            tokenExpired: platformTokenExpired,
            hasData: lastBalance != nil || monthUsage != nil,
            hasError: lastError != nil || usageError != nil
        )
    }

    private let platformService = PlatformService()
    private var timer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - 轮询

    func startPolling() {
        timer?.invalidate()
        let interval = settings.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh() // 启动时立即拉一次
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        settings.refreshInterval = interval
        startPolling()
    }

    func refresh() {
        Task { await performRefresh() }
    }

    // MARK: - 拉取

    func performRefresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        await fetchBalance()
        await fetchUsage()
    }

    /// 余额（平台侧 get_user_summary）
    private func fetchBalance() async {
        guard !settings.platformToken.isEmpty else {
            lastBalance = nil
            return
        }
        do {
            let summary = try await platformService.fetchSummary(token: settings.platformToken)
            guard let wallet = summary.normalWallets.first else {
                // 接口成功但钱包列表为空：识别为明确空状态，不保留旧余额
                lastBalance = nil
                lastError = "余额数据为空"
                return
            }
            let bonus = summary.bonusWallets.first?.value ?? 0
            lastBalance = BalanceInfo(
                currency: wallet.currency,
                totalBalance: String(wallet.value),
                grantedBalance: String(bonus),
                toppedUpBalance: String(max(0, wallet.value - bonus))
            )
            currency = wallet.currency
            lastUpdate = Date()
            lastError = nil
        } catch {
            // 保留旧余额，仅标记错误（旧数据由 status=stale 标注「可能过期」）
            lastError = (error as? PlatformError)?.message ?? error.localizedDescription
            if case PlatformError.api(let code, _) = error, code == 40002 || code == 40003 {
                platformTokenExpired = true
            }
        }
    }

    /// 用量：拉取本月 usage/amount + usage/cost
    private func fetchUsage() async {
        guard !settings.platformToken.isEmpty else {
            monthUsage = nil
            usageError = nil
            return
        }
        do {
            // 用平台时区（北京时间）而不是 Calendar.current：用户跨时区旅行时本地时区变化，
            // 会导致「今日/本月」与平台统计口径错位（今日费用/请求显示 0 或错位）
            let calendar = MonthUsage.platformCalendar
            let now = Date()
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return }
            let tz = 8 * 3600 // UTC+8（北京时间），与平台计日口径一致
            // by_api_key 接口实时返回当日数据（usage/amount、usage/cost 有数小时～次日延迟）
            async let amountFuture = platformService.fetchAPIKeyAmount(
                token: settings.platformToken,
                start: Int(start.timeIntervalSince1970),
                end: Int(end.timeIntervalSince1970),
                tz: tz
            )
            async let costFuture = platformService.fetchAPIKeyCost(
                token: settings.platformToken,
                start: Int(start.timeIntervalSince1970),
                end: Int(end.timeIntervalSince1970),
                tz: tz
            )
            let (amountData, costData) = try await (amountFuture, costFuture)
            monthUsage = MonthUsage.aggregated(
                startTs: Int(start.timeIntervalSince1970),
                amountData: amountData,
                costData: costData
            )
            usageError = nil
            platformTokenExpired = false
            lastUpdate = Date() // 最后成功时间
        } catch {
            // 保留旧用量，仅标记错误
            usageError = (error as? PlatformError)?.message ?? error.localizedDescription
            if case PlatformError.api(let code, _) = error, code == 40002 || code == 40003 {
                platformTokenExpired = true
            }
        }
    }

    // MARK: - 平台登录（内嵌官方页面）

    private var loginController: LoginWindowController?

    /// 打开内嵌登录窗口：登录成功后自动获取并校验 Token
    func beginPlatformLogin() {
        loginController = LoginWindowController(
            onToken: { [weak self] token, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let ok = await self.savePlatformToken(token)
                    if ok {
                        self.onLoginSucceeded?()
                    }
                }
            },
            onCancel: {}
        )
        loginController?.show()
    }

    /// 登录成功回调（由 AppDelegate 设置，用于弹回悬浮窗）
    var onLoginSucceeded: (() -> Void)?

    /// 保存新的平台 Token 并立即校验；返回是否成功
    @discardableResult
    func savePlatformToken(_ token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            usageError = PlatformError.emptyToken.message
            return false
        }
        do {
            let user = try await platformService.fetchCurrentUser(token: trimmed)
            settings.platformToken = trimmed
            settings.platformUserName = user.email
            currency = user.currency
            usageError = nil
            platformTokenExpired = false
            await fetchUsage()
            await fetchBalance()
            return usageError == nil && lastError == nil
        } catch {
            usageError = (error as? PlatformError)?.message ?? error.localizedDescription
            if case PlatformError.api(let code, _) = error, code == 40002 || code == 40003 {
                platformTokenExpired = true
            }
            return false
        }
    }

    func clearPlatformToken() {
        settings.clearPlatformToken()
        monthUsage = nil
        usageError = nil
        lastBalance = nil
        lastError = nil
        platformTokenExpired = false
        currency = "CNY"
    }
}

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
            if let wallet = summary.normalWallets.first {
                let bonus = summary.bonusWallets.first?.value ?? 0
                lastBalance = BalanceInfo(
                    currency: wallet.currency,
                    totalBalance: String(wallet.value),
                    grantedBalance: String(bonus),
                    toppedUpBalance: String(max(0, wallet.value - bonus))
                )
                lastUpdate = Date()
                lastError = nil
            }
        } catch {
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
            let now = Date()
            let calendar = Calendar.current
            let year = calendar.component(.year, from: now)
            let month = calendar.component(.month, from: now)
            async let amountFuture = platformService.fetchUsageAmount(token: settings.platformToken, month: month, year: year)
            async let costFuture = platformService.fetchUsageCost(token: settings.platformToken, month: month, year: year)
            let (amountData, costData) = try await (amountFuture, costFuture)
            monthUsage = MonthUsage(
                year: year,
                month: month,
                amountModels: amountData.total,
                costModels: costData.total,
                costDays: costData.days ?? [],
                amountDays: amountData.days ?? []
            )
            usageError = nil
            platformTokenExpired = false
        } catch {
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
    }
}

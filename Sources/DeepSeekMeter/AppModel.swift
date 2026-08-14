import Foundation
import Combine

/// 应用状态中枢：轮询余额 + 用量、暴露给 SwiftUI 视图
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let trend: TrendStore

    @Published var lastBalance: BalanceInfo?
    @Published var isAvailable: Bool?
    @Published var lastUpdate: Date?
    @Published var lastError: String?

    @Published var monthUsage: MonthUsage?
    @Published var usageError: String?

    @Published var isFetching = false

    private let service = BalanceService()
    private let platformService = PlatformService()
    private var timer: Timer?

    init(settings: SettingsStore, trend: TrendStore) {
        self.settings = settings
        self.trend = trend
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

    /// 余额：优先 API Key（/user/balance），否则用平台 Token（get_user_summary）
    private func fetchBalance() async {
        do {
            if !settings.apiKey.isEmpty {
                let response = try await service.fetch(apiKey: settings.apiKey)
                lastBalance = response.balanceInfos.first
                isAvailable = response.isAvailable
                lastUpdate = Date()
                lastError = nil
                if let info = response.balanceInfos.first {
                    trend.add(info)
                }
            } else if !settings.platformToken.isEmpty {
                let summary = try await platformService.fetchSummary(token: settings.platformToken)
                if let wallet = summary.normalWallets.first {
                    let bonus = summary.bonusWallets.first?.value ?? 0
                    lastBalance = BalanceInfo(
                        currency: wallet.currency,
                        totalBalance: String(wallet.value),
                        grantedBalance: String(bonus),
                        toppedUpBalance: String(max(0, wallet.value - bonus))
                    )
                    isAvailable = true
                    lastUpdate = Date()
                    lastError = nil
                    if let info = lastBalance {
                        trend.add(info)
                    }
                }
            } else {
                lastError = BalanceError.emptyAPIKey.message
            }
        } catch {
            lastError = (error as? BalanceError)?.message ?? error.localizedDescription
        }
    }

    /// 用量：平台 Token 拉取本月 usage/amount + usage/cost
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
        } catch {
            usageError = (error as? PlatformError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - 凭证管理

    /// 保存新的 API Key 并立即校验一次；返回是否成功
    @discardableResult
    func saveAPIKey(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = BalanceError.emptyAPIKey.message
            return false
        }
        settings.apiKey = trimmed
        await performRefresh()
        return lastError == nil
    }

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
            await fetchUsage()
            await fetchBalance()
            return usageError == nil
        } catch {
            usageError = (error as? PlatformError)?.message ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 平台登录（内嵌官方页面）

    private var loginController: LoginWindowController?

    /// 打开内嵌登录窗口：登录成功后自动获取并校验 Token
    func beginPlatformLogin() {
        loginController = LoginWindowController(
            onToken: { [weak self] token, _ in
                Task { @MainActor [weak self] in
                    _ = await self?.savePlatformToken(token)
                }
            },
            onCancel: {}
        )
        loginController?.show()
    }

    func clearAPIKey() {
        settings.clearAPIKey()
        lastBalance = nil
        isAvailable = nil
        lastUpdate = nil
        lastError = nil
    }

    func clearPlatformToken() {
        settings.clearPlatformToken()
        monthUsage = nil
        usageError = nil
    }
}

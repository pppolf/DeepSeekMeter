import Foundation
import Combine

/// iOS 状态中枢（对齐 macOS AppModel.swift 的轮询/拉取/错误态逻辑）。
/// 与 macOS 版的关键差异：依赖注入 TokenStoring 与 PlatformService（URLSession 可注入），
/// 因此整个状态机可在 macOS 上以「内存 TokenStore + URLProtocol Mock」跑自测（见 Selftest 第 12 节）。
/// UI 只读 @Published 状态，不直接发起网络请求。
@MainActor
public final class AppModel: ObservableObject {
    // MARK: - 状态

    @Published public var lastBalance: BalanceInfo?
    @Published public var lastUpdate: Date?
    @Published public var lastError: String?

    @Published public var monthUsage: MonthUsage?
    @Published public var usageError: String?
    @Published public var platformTokenExpired = false

    @Published public var isFetching = false

    /// 当前账户币种（余额/登录接口返回，用于费用展示，不再写死 CNY）
    @Published public var currency: String = "CNY"

    /// 登录邮箱（保存 Token 成功时从 /users/current 获取，设置页展示）
    @Published public var platformUserName: String?

    /// 内存中的 Token：初始化时从 TokenStore 读取，保存/清除同步落盘
    @Published public private(set) var token: String?

    // MARK: - 依赖注入

    public let tokenStore: TokenStoring
    public let platformService: PlatformService

    /// 可选刷新间隔（秒），对齐 macOS SettingsStore.intervalOptions
    public static let intervalOptions: [TimeInterval] = [15, 30, 60, 300, 600]

    /// 当前刷新间隔（默认 60s，与 macOS 默认一致）
    public var refreshInterval: TimeInterval = 60

    private var timer: Timer?

    public init(platformService: PlatformService = PlatformService(), tokenStore: TokenStoring) {
        self.platformService = platformService
        self.tokenStore = tokenStore
        self.token = tokenStore.loadToken()
    }

    /// 数据可信度状态（未登录/加载中/最新/过期/错误/登录已过期 六态，与桌面版一致）
    public var status: DataStatus {
        dataStatus(
            token: token,
            tokenExpired: platformTokenExpired,
            hasData: lastBalance != nil || monthUsage != nil,
            hasError: lastError != nil || usageError != nil
        )
    }

    // MARK: - 轮询

    /// 前台定时刷新：进入 App 时调用（iOS 无常驻后台轮询，后台刷新见 BGAppRefreshTask 里程碑）
    public func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh() // 启动时立即拉一次
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    public func setRefreshInterval(_ interval: TimeInterval) {
        guard Self.intervalOptions.contains(interval) else { return }
        refreshInterval = interval
        startPolling()
    }

    /// 拉取最新数据（下拉刷新 / 重试按钮调用）
    public func refresh() {
        Task { await performRefresh() }
    }

    public func performRefresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        await fetchBalance()
        await fetchUsage()
    }

    // MARK: - 拉取

    /// 余额（平台侧 get_user_summary）
    private func fetchBalance() async {
        guard let token, !token.isEmpty else {
            lastBalance = nil
            return
        }
        do {
            let summary = try await platformService.fetchSummary(token: token)
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

    /// 用量：拉取本月 by_api_key amount + cost（实时接口）
    private func fetchUsage() async {
        guard let token, !token.isEmpty else {
            monthUsage = nil
            usageError = nil
            return
        }
        do {
            // 用平台时区（北京时间）而不是 Calendar.current：用户跨时区旅行时本地时区变化，
            // 会导致「今日/本月」与平台统计口径错位
            let calendar = MonthUsage.platformCalendar
            let now = Date()
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                throw PlatformError.api(code: -1, msg: "无法计算本月时间范围")
            }
            let tz = MonthUsage.platformTimeZone.secondsFromGMT()
            let startTs = Int(start.timeIntervalSince1970)
            let endTs = Int(end.timeIntervalSince1970)
            async let amountFuture = platformService.fetchAPIKeyAmount(
                token: token, start: startTs, end: endTs, tz: tz
            )
            async let costFuture = platformService.fetchAPIKeyCost(
                token: token, start: startTs, end: endTs, tz: tz
            )
            let (amountData, costData) = try await (amountFuture, costFuture)
            monthUsage = MonthUsage.aggregated(
                startTs: startTs,
                endTs: endTs,
                tzSeconds: tz,
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

    // MARK: - 登录

    /// 保存新的平台 Token 并立即校验；返回是否成功（登录页 WebView 提取到候选后调用）
    @discardableResult
    public func savePlatformToken(_ newToken: String) async -> Bool {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            usageError = PlatformError.emptyToken.message
            return false
        }
        do {
            let user = try await platformService.fetchCurrentUser(token: trimmed)
            token = trimmed
            tokenStore.saveToken(trimmed)
            platformUserName = user.email
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

    /// 退出登录：清内存 + 落盘
    public func clearPlatformToken() {
        tokenStore.clearToken()
        token = nil
        monthUsage = nil
        usageError = nil
        lastBalance = nil
        lastError = nil
        platformTokenExpired = false
        platformUserName = nil
        currency = "CNY"
    }
}

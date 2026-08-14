import Foundation
import Combine

/// 应用状态中枢：轮询余额、暴露给 SwiftUI 视图
@MainActor
final class AppModel: ObservableObject {
    let settings: SettingsStore
    let trend: TrendStore

    @Published var lastBalance: BalanceInfo?
    @Published var isAvailable: Bool?
    @Published var lastUpdate: Date?
    @Published var lastError: String?
    @Published var isFetching = false

    private let service = BalanceService()
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

    // MARK: - 拉取余额

    func performRefresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let response = try await service.fetch(apiKey: settings.apiKey)
            lastBalance = response.balanceInfos.first
            isAvailable = response.isAvailable
            lastUpdate = Date()
            lastError = nil
            if let info = response.balanceInfos.first {
                trend.add(info)
            }
        } catch {
            lastError = (error as? BalanceError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - API Key 管理

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

    func clearAPIKey() {
        settings.clearAPIKey()
        lastBalance = nil
        isAvailable = nil
        lastUpdate = nil
        lastError = nil
    }
}

import Foundation
import Combine

/// 余额快照历史：用于趋势折线图与「1小时 / 今日 / 24小时」消耗统计
@MainActor
final class TrendStore: ObservableObject {
    @Published private(set) var snapshots: [BalanceSnapshot] = []

    private static let maxCount = 6000
    private static let storageKey = "trend.snapshots"

    init() {
        load()
    }

    func add(_ info: BalanceInfo) {
        let snapshot = BalanceSnapshot(
            time: Date(),
            total: info.total,
            granted: info.granted,
            toppedUp: info.toppedUp
        )
        // 与上一条完全相同且间隔小于 1 分钟：只更新时间，避免重复点
        if let last = snapshots.last,
           abs(last.total - snapshot.total) < 0.0001,
           snapshot.time.timeIntervalSince(last.time) < 60 {
            snapshots[snapshots.count - 1] = snapshot
        } else {
            snapshots.append(snapshot)
            if snapshots.count > Self.maxCount {
                snapshots.removeFirst(snapshots.count - Self.maxCount)
            }
        }
        save()
    }

    /// 最近 seconds 秒内的余额变化（正 = 增加，负 = 消耗）
    func delta(since seconds: TimeInterval) -> Double? {
        guard let latest = snapshots.last else { return nil }
        let cutoff = latest.time.addingTimeInterval(-seconds)
        guard let base = snapshots.last(where: { $0.time <= cutoff }) else { return nil }
        return latest.total - base.total
    }

    /// 今日（本地零点起）余额变化
    func deltaToday() -> Double? {
        guard let latest = snapshots.last else { return nil }
        let start = Calendar.current.startOfDay(for: latest.time)
        guard let base = snapshots.last(where: { $0.time <= start }) else { return nil }
        return latest.total - base.total
    }

    /// 最近 hours 小时的余额序列（用于折线图）
    func series(hours: Double = 24) -> [Double] {
        guard let latest = snapshots.last else { return [] }
        let cutoff = latest.time.addingTimeInterval(-hours * 3600)
        return snapshots.filter { $0.time >= cutoff }.map { $0.total }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([BalanceSnapshot].self, from: data)
        else { return }
        snapshots = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

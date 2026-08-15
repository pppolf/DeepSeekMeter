import Foundation
import BackgroundTasks
import DeepSeekMeterCore

/// 后台刷新服务（BGAppRefreshTask）：由系统调度、**不保证触发**，仅作「下次打开前的预刷新」。
/// 主刷新路径仍是前台：进入即刷 + 下拉刷新 + 前台定时器（AppModel.startPolling）。
/// 对应 Info.plist：UIBackgroundModes=[fetch]、BGTaskSchedulerPermittedIdentifiers=[com.deepseek.meter.refresh]。
enum BackgroundRefreshService {
    /// 后台任务标识（与 Info.plist BGTaskSchedulerPermittedIdentifiers 对应）
    static let taskIdentifier = "com.deepseek.meter.refresh"

    /// 调度下一次后台刷新（App 启动 / 每次后台任务完成时调用）。
    /// 系统可能拒绝（低电量、频控等），尽力而为即可。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 系统允许的最短间隔
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 后台任务执行体：先重排下一次窗口，再拉取数据（AppModel 内部 @MainActor）
    static func refresh(appModel: AppModel) async {
        schedule()
        await appModel.performRefresh()
    }
}

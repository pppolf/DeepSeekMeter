import UIKit
import BackgroundTasks
import DeepSeekMeterCore

/// 应用生命周期（UIApplicationDelegate 适配）：
/// 在 didFinishLaunching 手动注册 BGAppRefreshTask 处理器。
/// 说明：SwiftUI 的 .backgroundTask(.appRefresh) 在 Xcode 26 中为泛型 BackgroundTask API，
/// 闭包签名有变化（不再直接传 BGAppRefreshTask），改用手动 BGTaskScheduler.register 更稳定，
/// 任务标识与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 保持一致。
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// 后台任务通过该弱引用拿到 AppModel（App 启动时注入，见 DeepSeekMeterApp.task）
    static weak var appModel: AppModel?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshService.taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            BackgroundRefreshService.schedule() // 先重排下一个窗口，防止错过
            Task { @MainActor in
                if let appModel = Self.appModel {
                    await appModel.performRefresh()
                }
                task.setTaskCompleted(success: true)
            }
        }
        return true
    }
}

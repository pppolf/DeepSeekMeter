import SwiftUI
import DeepSeekMeterCore

/// DeepSeekMeter iOS 版入口（SwiftUI App 生命周期 + UIApplicationDelegate 适配）。
/// 组装：KeychainTokenStore -> AppModel -> ContentView（依赖注入，便于预览与测试）；
/// 后台任务在 AppDelegate 中手动注册（BGTaskScheduler），前台轮询在此启动并注入 AppModel 引用。
@main
struct DeepSeekMeterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel(tokenStore: KeychainTokenStore())

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .task {
                    AppDelegate.appModel = appModel
                    appModel.startPolling()
                    BackgroundRefreshService.schedule()
                }
        }
    }
}

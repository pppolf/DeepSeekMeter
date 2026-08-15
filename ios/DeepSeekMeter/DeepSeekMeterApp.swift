import SwiftUI
import DeepSeekMeterCore

/// DeepSeekMeter iOS 版入口（SwiftUI App 生命周期）。
/// 组装：KeychainTokenStore -> AppModel -> ContentView（依赖注入，便于预览与测试）
@main
struct DeepSeekMeterApp: App {
    @StateObject private var appModel = AppModel(tokenStore: KeychainTokenStore())

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .task { appModel.startPolling() }
        }
    }
}

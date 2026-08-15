import SwiftUI
import WidgetKit
import DeepSeekMeterCore

/// 主界面：主页（余额/用量/趋势集成）+ 设置 两个 Tab + 登录 sheet
struct ContentView: View {
    @ObservedObject var appModel: AppModel
    @State private var showLogin = false

    var body: some View {
        TabView {
            HomeView(appModel: appModel, showLogin: $showLogin)
                .tabItem { Label("主页", systemImage: "house.fill") }
            SettingsView(appModel: appModel, showLogin: $showLogin)
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .sheet(isPresented: $showLogin) {
            LoginView(appModel: appModel)
        }
        // 余额变化：写小组件快照 + 弹本地通知（均为纯本地，无第三方上报）
        .onChange(of: appModel.lastBalance?.total) { _, newValue in
            if let total = newValue {
                BalanceSnapshot.save(balance: total, currency: appModel.currency)
                WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekMeterBalance")
                NotificationService.notifyLowBalanceIfNeeded(balance: total, currency: appModel.currency)
            }
        }
    }
}

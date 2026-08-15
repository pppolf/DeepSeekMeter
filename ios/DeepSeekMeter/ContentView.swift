import SwiftUI
import DeepSeekMeterCore

/// 主界面：四 Tab（概览 / 用量 / 趋势 / 设置）+ 登录 sheet
struct ContentView: View {
    @ObservedObject var appModel: AppModel
    @State private var showLogin = false

    var body: some View {
        TabView {
            OverviewView(appModel: appModel, showLogin: $showLogin)
                .tabItem { Label("概览", systemImage: "creditcard") }
            UsageView(appModel: appModel)
                .tabItem { Label("用量", systemImage: "list.bullet.rectangle") }
            TrendView(appModel: appModel)
                .tabItem { Label("趋势", systemImage: "chart.bar") }
            SettingsView(appModel: appModel, showLogin: $showLogin)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showLogin) {
            LoginView(appModel: appModel)
        }
        // 余额低于阈值时弹本地通知（纯本地，无第三方推送）
        .onChange(of: appModel.lastBalance?.total) { _, newValue in
            if let total = newValue {
                NotificationService.notifyLowBalanceIfNeeded(balance: total, currency: appModel.currency)
            }
        }
    }
}

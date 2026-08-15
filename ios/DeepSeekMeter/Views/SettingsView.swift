import SwiftUI
import DeepSeekMeterCore

/// 设置：账号（登录/退出）、刷新间隔、隐私说明
struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    @Binding var showLogin: Bool
    @State private var confirmLogout = false
    @AppStorage(NotificationService.enabledKey) private var lowBalanceAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    if let email = appModel.platformUserName, !email.isEmpty {
                        LabeledContent("邮箱", value: email)
                    }
                    if appModel.status == .notLoggedIn {
                        Button("登录") { showLogin = true }
                    } else {
                        Button("重新登录") { showLogin = true }
                        Button("退出登录", role: .destructive) { confirmLogout = true }
                    }
                }

                Section("自动刷新") {
                    Picker("刷新间隔", selection: refreshSelection) {
                        ForEach(AppModel.intervalOptions, id: \.self) { interval in
                            Text(Self.label(interval)).tag(interval)
                        }
                    }
                }

                Section("提醒") {
                    Toggle("余额低于 1 时提醒", isOn: $lowBalanceAlert)
                }

                Section("隐私") {
                    Text("所有数据来自 DeepSeek 官方平台接口，使用你自己的登录态，不会发送到任何第三方。Token 保存在本机钥匙串（Keychain），「退出登录」可随时清除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { appModel.clearPlatformToken() }
            }
            .onChange(of: lowBalanceAlert) { _, enabled in
                if enabled {
                    NotificationService.requestAuthorization()
                } else {
                    NotificationService.resetLowBalanceFlag()
                }
            }
        }
    }

    private var refreshSelection: Binding<TimeInterval> {
        Binding(
            get: { appModel.refreshInterval },
            set: { appModel.setRefreshInterval($0) }
        )
    }

    private static func label(_ interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) 秒" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟" }
        return "\(Int(interval / 3600)) 小时"
    }
}

import SwiftUI
import DeepSeekMeterCore

/// 占位首页：验证「App 工程 -> 本地核心包」链路（M3 替换为概览/用量/趋势/设置四 Tab）
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("\(format(1234.5)) \(currencySymbol("CNY"))")
                .font(.title2.monospacedDigit())
            Text("DeepSeekMeter 核心包链路正常")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

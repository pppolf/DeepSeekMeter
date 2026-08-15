import WidgetKit
import SwiftUI

/// 小组件入口：DeepSeekMeter 余额小组件（快照驱动，不联网、不持有 Token）
@main
struct DeepSeekMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}

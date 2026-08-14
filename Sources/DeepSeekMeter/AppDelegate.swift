import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let trend = TrendStore()
    private lazy var model = AppModel(settings: settings, trend: trend)
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(model: model)
        statusController = controller
        model.startPolling()

        // 首次使用：自动弹出悬浮窗引导填写 API Key
        if settings.apiKey.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusController?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }
}

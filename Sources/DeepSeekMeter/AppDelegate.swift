import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var model = AppModel(settings: settings)
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(model: model)
        statusController = controller
        model.onLoginSucceeded = { [weak self] in
            self?.statusController?.showPopover()
        }
        model.startPolling()

        // 首次使用：自动弹出悬浮窗引导登录
        if settings.platformToken.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusController?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }
}

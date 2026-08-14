import AppKit

@main
struct DeepSeekMeterApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 仅菜单栏，无 Dock 图标
        app.run()
    }
}

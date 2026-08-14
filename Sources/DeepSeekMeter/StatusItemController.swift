import AppKit
import SwiftUI
import Combine

/// 菜单栏状态项 + 点击弹出的悬浮窗（NSPopover）
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "DeepSeek Meter"
        }

        let hosting = NSHostingView(rootView: PopoverView(model: model))
        let fitting = hosting.fittingSize
        let width: CGFloat = 340
        let height: CGFloat = fitting.height > 0 ? fitting.height : 600
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let contentVC = NSViewController()
        contentVC.view = hosting
        popover.contentViewController = contentVC
        popover.contentSize = NSSize(width: width, height: height)
        popover.behavior = .transient // 点击外部自动关闭
        popover.animates = true

        // 状态变化时刷新菜单栏文字/图标
        model.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.render() }
            }
            .store(in: &cancellables)

        render()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate() // 让输入框可编辑
    }

    // MARK: - 菜单栏渲染

    func render() {
        guard let button = statusItem.button else { return }
        let model = self.model
        button.attributedTitle = Self.attributedTitle(for: model)
        button.image = Self.icon(for: model)
        button.toolTip = Self.tooltip(for: model)
    }

    private static func attributedTitle(for model: AppModel?) -> NSAttributedString {
        let text: String
        if let balance = model?.lastBalance {
            text = "\(currencySymbol(balance.currency))\(format(balance.total))"
        } else {
            text = "—"
        }
        return NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: titleColor(for: model),
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
        )
    }

    private static func titleColor(for model: AppModel?) -> NSColor {
        if let available = model?.isAvailable, !available {
            return .systemGray
        }
        if let balance = model?.lastBalance {
            if balance.total < 1 { return .systemRed }
            if balance.total < 10 { return .systemOrange }
            return .labelColor
        }
        return model?.lastError != nil ? .systemRed : .labelColor
    }

    private static func icon(for model: AppModel?) -> NSImage? {
        let name = model?.isFetching == true ? "arrow.triangle.2.circlepath" : "sparkles"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "DeepSeek Meter")
        image?.isTemplate = true
        return image
    }

    private static func tooltip(for model: AppModel?) -> String {
        guard let lastUpdate = model?.lastUpdate else {
            return model?.lastError ?? "DeepSeek Meter"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "DeepSeek Meter · 最后更新 \(formatter.string(from: lastUpdate))"
    }
}

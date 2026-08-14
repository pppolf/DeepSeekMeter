import AppKit
import SwiftUI
import Combine

/// 弹窗宿主：每次出现时重新计算内容尺寸，避免顶部/底部裁剪
private final class PopoverHostViewController: NSViewController {
    var onViewDidAppear: (() -> Void)?
    override func viewDidAppear() {
        super.viewDidAppear()
        onViewDidAppear?()
    }
}

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
        let width: CGFloat = 340
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 620)
        let contentVC = PopoverHostViewController()
        contentVC.view = hosting
        contentVC.onViewDidAppear = { [weak self] in
            Task { @MainActor [weak self] in self?.resizePopoverToFitContent() }
        }
        popover.contentViewController = contentVC
        popover.contentSize = NSSize(width: width, height: 620)
        popover.behavior = .transient // 点击外部自动关闭
        popover.animates = true

        // 状态变化时刷新菜单栏文字/图标，并自适应弹窗尺寸
        model.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.render()
                    self?.resizePopoverToFitContent()
                }
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

    /// 根据内容重新计算弹窗尺寸（不超屏幕，超出部分由 ScrollView 滚动）
    private func resizePopoverToFitContent() {
        guard let hosting = popover.contentViewController?.view as? NSHostingView<PopoverView> else { return }
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let maxHeight = max(screenHeight - 80, 300)
        let target = min(max(fitting.height, 320), maxHeight)
        hosting.setFrameSize(NSSize(width: 340, height: target))
        popover.contentSize = NSSize(width: 340, height: target)
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
        guard let model else { return .labelColor }
        switch model.status {
        case .fresh:
            if let balance = model.lastBalance {
                if balance.total < 1 { return .systemRed }
                if balance.total < 10 { return .systemOrange }
            }
            return .labelColor
        case .stale:
            return .systemOrange
        case .error, .tokenExpired:
            return .systemRed
        default:
            return .labelColor
        }
    }

    private static func icon(for model: AppModel?) -> NSImage? {
        let name = model?.isFetching == true ? "arrow.triangle.2.circlepath" : "sparkles"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "DeepSeek Meter")
        image?.isTemplate = true
        return image
    }

    private static func tooltip(for model: AppModel?) -> String {
        guard let model else { return "DeepSeek Meter" }
        switch model.status {
        case .tokenExpired:
            return "登录已过期，点击重新登录"
        case .error:
            return model.lastError ?? "获取失败"
        case .stale:
            var stale = model.lastError ?? "数据可能已过期"
            if let lastUpdate = model.lastUpdate {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                stale += " · 最后成功 \(formatter.string(from: lastUpdate))"
            }
            return stale
        default:
            break
        }
        guard let lastUpdate = model.lastUpdate else {
            return model.lastError ?? "DeepSeek Meter"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "DeepSeek Meter · 最后更新 \(formatter.string(from: lastUpdate))"
    }
}

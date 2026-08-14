import AppKit
import WebKit

/// 登录窗口：内嵌官方登录页；登录后只读 localStorage，Token 校验在原生侧完成
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindows: [NSWindow] = []
    private var pollTimer: Timer?
    private var isChecking = false
    private var tokenReceived = false
    private var lastSignature = ""

    private let dataStore = WKWebsiteDataStore.nonPersistent()
    private let statusLabel = NSTextField(labelWithString: "正在打开官方登录页…")
    private let platformService = PlatformService()

    private let onToken: (String, String) -> Void
    private let onCancel: () -> Void

    init(onToken: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.onToken = onToken
        self.onCancel = onCancel
        super.init()
    }

    func show() {
        guard window == nil else { return }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 644),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "登录 DeepSeek 平台"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let topBar = NSView(frame: NSRect(x: 0, y: 608, width: 480, height: 36))
        statusLabel.frame = NSRect(x: 12, y: 8, width: 300, height: 20)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let browserButton = NSButton(title: "用系统浏览器打开", target: self, action: #selector(openInBrowser))
        browserButton.bezelStyle = .inline
        browserButton.controlSize = .small
        browserButton.frame = NSRect(x: 480 - 152, y: 6, width: 140, height: 24)
        topBar.addSubview(statusLabel)
        topBar.addSubview(browserButton)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 644))
        content.addSubview(topBar)
        content.addSubview(webView)
        window.contentView = content
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startPolling()
        webView.load(URLRequest(url: URL(string: "https://platform.deepseek.com/")!))
    }

    // MARK: - 提取 Token

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkToken() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        NSLog("[DeepSeekMeter] login: \(text)")
    }

    private func checkToken() {
        guard !isChecking, !tokenReceived, let webView else { return }
        isChecking = true
        let js = """
(() => {
  try {
    const pairs = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      pairs[k] = localStorage.getItem(k);
    }
    return JSON.stringify({ ok: true, data: pairs });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
"""
        webView.evaluateJavaScript(js) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isChecking = false }
                guard !self.tokenReceived else { return }
                if let error {
                    self.setStatus("页面未就绪（\(error.localizedDescription)），等待登录…")
                    return
                }
                guard let str = result as? String,
                      let data = str.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["ok"] as? Bool == true,
                      let pairs = json["data"] as? [String: Any] else {
                    self.setStatus("尚未就绪，等待登录完成…")
                    return
                }
                let signature = Self.storageSignature(pairs)
                if signature == self.lastSignature {
                    self.setStatus("等待登录完成…")
                    return
                }
                self.lastSignature = signature
                let candidates = Self.tokenCandidates(from: pairs)
                if candidates.isEmpty {
                    self.setStatus("等待登录完成…")
                    return
                }
                self.setStatus("检测到登录信息，校验中…")
                NSLog("[DeepSeekMeter] login: candidates = \(candidates.count)")
                await self.validate(candidates: candidates)
            }
        }
    }

    private static func storageSignature(_ pairs: [String: Any]) -> String {
        pairs.keys.sorted().map { key in
            let v = (pairs[key] as? String) ?? ""
            return "\(key)=\(v.count):\(String(v.prefix(16)))"
        }.joined(separator: "|")
    }

    private static func tokenCandidates(from pairs: [String: Any]) -> [String] {
        func unwrap(_ raw: String) -> String {
            if let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let v = obj["value"] as? String, !v.isEmpty {
                return v
            }
            return raw
        }
        var result: [String] = []
        func add(_ t: String) {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !result.contains(trimmed) { result.append(trimmed) }
        }
        // 1. userToken 优先
        if let raw = pairs["userToken"] as? String, !raw.isEmpty {
            add(unwrap(raw))
        }
        // 2. 键名含 token
        for (key, value) in pairs {
            guard let value = value as? String, !value.isEmpty else { continue }
            if key.lowercased().contains("token") && value.count >= 20 {
                add(unwrap(value))
            }
        }
        // 3. 兜底：40~512 字符的长值
        for (_, value) in pairs {
            guard let value = value as? String, value.count >= 40, value.count <= 512 else { continue }
            add(unwrap(value))
        }
        return result
    }

    private func validate(candidates: [String]) async {
        guard !tokenReceived else { return }
        for token in candidates {
            if tokenReceived { return }
            do {
                let user = try await platformService.fetchCurrentUser(token: token)
                tokenReceived = true
                setStatus("已获取 Token ✓")
                stopPolling()
                close()
                onToken(token, user.email)
                return
            } catch {
                NSLog("[DeepSeekMeter] login: 候选校验失败 - \(error.localizedDescription)")
            }
        }
        setStatus("校验未通过，稍后自动重试…")
    }

    // MARK: - 窗口

    private func close() {
        window?.performClose(nil)
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if !tokenReceived {
            stopPolling()
            onCancel()
        }
    }

    @objc private func openInBrowser() {
        if let url = URL(string: "https://platform.deepseek.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - OAuth 弹窗（共享数据存储，token 仍可在主窗口读到）

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let config = configuration
        config.websiteDataStore = dataStore
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 600), configuration: config)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek 登录"
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        popupWindows.append(window)
        return popup
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkToken()
    }
}

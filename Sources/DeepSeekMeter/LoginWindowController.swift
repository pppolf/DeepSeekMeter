import AppKit
import WebKit

/// 登录窗口：内嵌官方登录页，登录后自动从页面 localStorage 提取并校验 userToken
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindows: [NSWindow] = []
    private var pollTimer: Timer?
    private var isChecking = false
    private var tokenReceived = false

    private let dataStore = WKWebsiteDataStore.nonPersistent()
    private let statusLabel = NSTextField(labelWithString: "正在打开官方登录页…")

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

        // 顶栏：状态 + 用系统浏览器打开
        let topBar = NSView(frame: NSRect(x: 0, y: 608, width: 480, height: 36))
        statusLabel.frame = NSRect(x: 12, y: 8, width: 280, height: 20)
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

    private func checkToken() {
        guard !isChecking, !tokenReceived, let webView else { return }
        isChecking = true
        let js = """
(async () => {
  const tryFetch = async (t) => {
    try {
      const r = await fetch('/auth-api/v0/users/current', {headers: {Authorization: 'Bearer ' + t, Accept: 'application/json'}});
      const j = await r.json();
      return (j && j.code === 0) ? (j.data && j.data.biz_data && j.data.biz_data.email) || 'ok' : null;
    } catch (e) { return null; }
  };
  const direct = localStorage.getItem('userToken');
  if (direct) {
    let t = direct;
    try { t = JSON.parse(direct).value || direct; } catch (e) {}
    const email = await tryFetch(t);
    if (email) return JSON.stringify({ token: t, email: email });
  }
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i) || '';
    const v = localStorage.getItem(k) || '';
    if (k.toLowerCase().indexOf('token') >= 0 && v.length > 40) {
      let t = v;
      try { t = JSON.parse(v).value || v; } catch (e) {}
      const email = await tryFetch(t);
      if (email) return JSON.stringify({ token: t, email: email });
    }
  }
  return JSON.stringify({ token: null });
})()
"""
        Task { @MainActor [weak self] in
            await self?.runCheck(webView: webView, js: js)
        }
    }

    private func runCheck(webView: WKWebView, js: String) async {
        defer { isChecking = false }
        guard !tokenReceived else { return }
        guard let value = try? await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page) else { return }
        guard let str = value as? String,
              let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else { return }
        let email = json["email"] as? String ?? ""
        tokenReceived = true
        statusLabel.stringValue = "已获取 Token ✓"
        stopPolling()
        close()
        onToken(token, email)
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
        checkToken() // 页面加载完成立即尝试一次
    }
}

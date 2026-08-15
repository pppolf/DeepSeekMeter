import SwiftUI
import WebKit
import DeepSeekMeterCore

/// 登录页：内嵌官方登录页（WKWebView）+ localStorage 轮询提取 Token，原生侧校验。
/// 机制对齐 macOS LoginWindowController：域名白名单、候选提取、OAuth 跳转留在 WebView 内。
struct LoginView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var status = "正在打开官方登录页…"
    @State private var showManualInput = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LoginWebView(
                    status: $status,
                    onToken: { token, completion in
                        Task { @MainActor in
                            let ok = await appModel.savePlatformToken(token)
                            if ok {
                                dismiss()
                            }
                            completion(ok)
                        }
                    }
                )
                Divider()
                HStack {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("登录 DeepSeek 平台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("手动粘贴 Token") { showManualInput = true }
                        .font(.footnote)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showManualInput) {
                ManualTokenInputView(appModel: appModel)
            }
        }
    }
}

/// 手动粘贴 Token 兜底（对齐 Windows 版 TokenInputDialog）
struct ManualTokenInputView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("平台 Token") {
                    SecureField("粘贴 userToken…", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("手动粘贴 Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { @MainActor in
                            if await appModel.savePlatformToken(token) {
                                dismiss()
                            } else {
                                message = appModel.usageError ?? "校验失败"
                            }
                        }
                    }
                }
            }
        }
    }
}

/// WKWebView 封装：官方登录页 + localStorage 轮询提取 Token
struct LoginWebView: UIViewRepresentable {
    @Binding var status: String
    let onToken: (String, @escaping (Bool) -> Void) -> Void

    /// 返回容器 UIView：内部承载主 WKWebView + 可能的 OAuth 弹窗覆盖层
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = context.coordinator.dataStore
        let webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.webView = webView
        context.coordinator.container = container
        container.addSubview(webView)
        context.coordinator.startPolling()
        webView.load(URLRequest(url: URL(string: "https://platform.deepseek.com/")!))
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status, onToken: onToken)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var status: String
        let onToken: (String, @escaping (Bool) -> Void) -> Void

        weak var webView: WKWebView?
        weak var container: UIView?
        /// 主 WebView 与弹窗共享的 nonPersistent 数据存储（登录态互通，且不落盘浏览器缓存）
        let dataStore = WKWebsiteDataStore.nonPersistent()
        private var pollTimer: Timer?
        private var isChecking = false
        private var isValidating = false
        private var tokenReceived = false
        private var lastSignature = ""

        init(status: Binding<String>, onToken: @escaping (String, @escaping (Bool) -> Void) -> Void) {
            self._status = status
            self.onToken = onToken
        }

        func startPolling() {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.checkToken()
            }
        }

        deinit {
            stopPolling()
        }

        private func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
        }

        // MARK: - WKNavigationDelegate

        /// 页面加载完成立即检测一次（无需等 1.5s 轮询）
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkToken()
        }

        // MARK: - WKUIDelegate：OAuth/扫码弹窗在 App 内承接
        // 历史教训：把 window.open 交给系统浏览器会把登录态落在 Safari，App 永远收不到 Token。
        // 这里在容器内叠加一个共享 dataStore 的 popup WKWebView 覆盖层，并提供关闭按钮。

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let config = configuration
            config.websiteDataStore = dataStore
            let popup = WKWebView(frame: .zero, configuration: config)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.customUserAgent = webView.customUserAgent
            present(popup: popup)
            return popup
        }

        private func present(popup: WKWebView) {
            guard let container else { return }
            let overlay = UIView(frame: container.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = .systemBackground
            container.addSubview(overlay)

            popup.frame = overlay.bounds
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(popup)

            let closeButton = UIButton(type: .system)
            closeButton.setTitle("✕ 关闭弹窗", for: .normal)
            closeButton.addTarget(self, action: #selector(closePopup(_:)), for: .touchUpInside)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(closeButton)
            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 8),
                closeButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12)
            ])
        }

        @objc private func closePopup(_ sender: UIButton) {
            sender.superview?.removeFromSuperview()
        }

        private func checkToken() {
            guard !isChecking, !isValidating, !tokenReceived, let webView else { return }
            // 只在 DeepSeek 官方域名执行 localStorage Token 扫描，避免在第三方页面读取登录数据
            guard Self.isDeepSeekDomain(webView.url) else {
                status = "请在官方登录页登录…"
                return
            }
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
                guard let self else { return }
                defer { self.isChecking = false }
                guard !self.tokenReceived, !self.isValidating else { return }
                if let error {
                    self.status = "页面未就绪（\(error.localizedDescription)），等待登录…"
                    return
                }
                guard let str = result as? String,
                      let data = str.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["ok"] as? Bool == true,
                      let pairs = json["data"] as? [String: Any] else {
                    self.status = "尚未就绪，等待登录完成…"
                    return
                }
                let signature = Self.storageSignature(pairs)
                if signature == self.lastSignature {
                    self.status = "等待登录完成…"
                    return
                }
                self.lastSignature = signature
                let candidates = Self.tokenCandidates(from: pairs)
                if candidates.isEmpty {
                    self.status = "等待登录完成…"
                    return
                }
                self.status = "检测到登录信息，校验中…"
                self.validate(candidates: candidates)
            }
        }

        /// 逐候选交给 AppModel 原生侧校验（内部 fetchCurrentUser）
        private func validate(candidates: [String]) {
            tryNext(candidates, index: 0)
        }

        private func tryNext(_ candidates: [String], index: Int) {
            guard !tokenReceived, index < candidates.count else { return }
            onToken(candidates[index]) { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.tokenReceived = true
                    self.stopPolling()
                    self.status = "已获取 Token ✓"
                } else {
                    self.status = "Token 校验未通过，尝试下一个候选…"
                    self.tryNext(candidates, index: index + 1)
                }
            }
        }

        // MARK: - 工具（对齐 macOS LoginWindowController）

        private static func storageSignature(_ pairs: [String: Any]) -> String {
            pairs.keys.sorted().map { key in
                let v = (pairs[key] as? String) ?? ""
                return "\(key)=\(v.count):\(String(v.prefix(16)))"
            }.joined(separator: "|")
        }

        /// 仅允许 DeepSeek 官方域名（*.deepseek.com）
        private static func isDeepSeekDomain(_ url: URL?) -> Bool {
            guard let host = url?.host else { return false }
            return host == "deepseek.com" || host.hasSuffix(".deepseek.com")
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
    }
}

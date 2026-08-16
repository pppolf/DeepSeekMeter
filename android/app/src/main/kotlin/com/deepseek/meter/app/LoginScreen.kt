package com.deepseek.meter.app

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Message
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button as AndroidButton
import android.widget.FrameLayout
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import org.json.JSONObject
import java.util.Timer
import java.util.TimerTask

/**
 * 登录页：内嵌官方登录页（WebView）+ localStorage 轮询提取 Token，原生侧校验。
 * 机制对齐 iOS LoginWebView / macOS LoginWindowController：域名白名单、候选提取、留在 WebView 内。
 * Issue #14：window.open / OAuth popup 在 App 内承接（onCreateWindow + 临时子 WebView），
 * 不跳系统浏览器；第三方 IdP 拒绝 embedded WebView 时清晰失败 + 手动 Token fallback。
 */
@Composable
fun LoginScreen(
    onDismiss: () -> Unit,
    onSaveToken: (String, (Boolean) -> Unit) -> Unit
) {
    var status by remember { mutableStateOf("正在打开官方登录页…") }
    var showManual by remember { mutableStateOf(false) }
    var manualToken by remember { mutableStateOf("") }
    var webViewRef by remember { mutableStateOf<TokenLoginWebView?>(null) }

    // 生命周期桥接：页面不可见时暂停 WebView 轮询，回到前台恢复
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> webViewRef?.resumePolling()
                Lifecycle.Event.ON_PAUSE -> webViewRef?.pausePolling()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text("登录 DeepSeek 平台", modifier = Modifier.weight(1f))
            TextButton(onClick = { showManual = true }) { Text("手动粘贴 Token") }
            TextButton(onClick = onDismiss) { Text("取消") }
        }
        AndroidView(
            factory = { ctx ->
                // 外层容器：onCreateWindow 承接的 popup 子 WebView 与关闭按钮挂载到这里（Issue #14）
                val container = FrameLayout(ctx)
                TokenLoginWebView(
                    ctx,
                    container,
                    onToken = onSaveToken,
                    onStatus = { s -> status = s }
                ).also { webViewRef = it }.also {
                    container.addView(
                        it,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    )
                }
                container
            },
            modifier = Modifier.weight(1f),
            onRelease = { webViewRef?.stopPolling() }
        )
        Text(
            status,
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            style = androidx.compose.material3.MaterialTheme.typography.bodySmall
        )
    }

    if (showManual) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showManual = false },
            title = { Text("手动粘贴 Token") },
            text = {
                OutlinedTextField(
                    value = manualToken,
                    onValueChange = { manualToken = it },
                    label = { Text("平台 Token") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password)
                )
            },
            confirmButton = {
                Button(onClick = {
                    onSaveToken(manualToken) { ok -> if (ok) onDismiss() }
                }) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { showManual = false }) { Text("取消") }
            }
        )
    }
}

/// WebView 封装：官方登录页 + localStorage 轮询提取 Token（对齐 iOS LoginWebView.Coordinator）。
/// Issue #14：支持 window.open / OAuth popup 的 App 内承接（onCreateWindow + 临时子 WebView），
/// 并遵守能力边界：不伪装 UA、不绕过第三方 IdP 对 embedded WebView 的限制，
/// 提供关闭出口与手动 Token fallback。
@SuppressLint("SetJavaScriptEnabled")
class TokenLoginWebView(
    context: Context,
    private val container: FrameLayout,
    private val onToken: (String, (Boolean) -> Unit) -> Unit,
    private val onStatus: (String) -> Unit
) : WebView(context) {

    /** 当前 popup 子 WebView（同一时间只保留一个，新窗口替换旧的） */
    private var popupWebView: WebView? = null

    /** popup 的关闭按钮（第三方 IdP 拒绝 embedded WebView 时给用户的明确出口） */
    private var popupCloseButton: AndroidButton? = null

    // 注意：以下状态字段必须先于 init 初始化——init 会调用 startPolling()，
    // 若声明在 init 之后，轮询 Timer 在登录页首次打开时仍为 null（真机发现：A3 遗留的 NPE 崩溃）
    private val pollTimer = Timer()
    private var isChecking = false
    private var isValidating = false
    private var tokenReceived = false
    private var lastSignature = ""
    private var polling = true

    init {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        // 必须开启：window.open / OAuth popup 才会回调 onCreateWindow，否则新窗口会被主 WebView 吞掉
        settings.setSupportMultipleWindows(true)
        settings.userAgentString = USER_AGENT
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                checkToken()
            }
        }
        webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message
            ): Boolean {
                return handleCreateWindow(resultMsg)
            }
        }
        loadUrl(LOGIN_URL)
        startPolling()
    }

    private fun startPolling() {
        pollTimer.schedule(object : TimerTask() {
            override fun run() {
                // 页面不可见时暂停轮询（onPause/onResume 由 LoginScreen 桥接）
                if (polling) post { checkToken() }
            }
        }, 1500, 1500)
    }

    /** 页面进入后台：暂停轮询，节省资源 */
    fun pausePolling() {
        polling = false
    }

    /** 页面回到前台：恢复轮询 */
    fun resumePolling() {
        polling = true
    }

    fun stopPolling() {
        pollTimer.cancel()
        closePopup()
        // 登录流程结束（成功/释放）：按 WebView.destroy() 的调用契约，先从容器移除再销毁，
        // 避免页面 JS 与回调残留；容器与 WebView 的相互引用随视图树整体回收
        (parent as? ViewGroup)?.removeView(this)
        destroy()
    }

    private fun checkToken() {
        if (isChecking || isValidating || tokenReceived) return
        val host = url?.let { Uri.parse(it).host } ?: return
        // 只在 DeepSeek 官方域名执行 localStorage Token 扫描，避免在第三方页面读取登录数据
        if (!(host == "deepseek.com" || host.endsWith(".deepseek.com"))) {
            onStatus("请在官方登录页登录…")
            return
        }
        isChecking = true
        val js = "(function() { try { var pairs = {}; for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); pairs[k] = localStorage.getItem(k); } return JSON.stringify({ ok: true, data: pairs }); } catch (e) { return JSON.stringify({ ok: false, error: String(e) }); } })()"
        evaluateJavascript(js) { result ->
            isChecking = false
            if (tokenReceived || isValidating) return@evaluateJavascript
            if (result == null || result == "null") {
                onStatus("尚未就绪，等待登录完成…")
                return@evaluateJavascript
            }
            try {
                val json = JSONObject(result)
                if (!json.optBoolean("ok")) {
                    onStatus("尚未就绪，等待登录完成…")
                    return@evaluateJavascript
                }
                val pairs = json.optJSONObject("data") ?: JSONObject()
                val signature = storageSignature(pairs)
                if (signature == lastSignature) {
                    onStatus("等待登录完成…")
                    return@evaluateJavascript
                }
                lastSignature = signature
                val candidates = tokenCandidates(pairs)
                if (candidates.isEmpty()) {
                    onStatus("等待登录完成…")
                    return@evaluateJavascript
                }
                onStatus("检测到登录信息，校验中…")
                validate(candidates, 0)
            } catch (_: Exception) {
                onStatus("尚未就绪，等待登录完成…")
            }
        }
    }

    /// 逐候选交给 AppModel 原生侧校验（内部 fetchCurrentUser）
    private fun validate(candidates: List<String>, index: Int) {
        if (tokenReceived || index >= candidates.size) return
        isValidating = true
        onToken(candidates[index]) { ok ->
            isValidating = false
            if (ok) {
                tokenReceived = true
                stopPolling()
                onStatus("已获取 Token ✓")
            } else {
                onStatus("Token 校验未通过，尝试下一个候选…")
                validate(candidates, index + 1)
            }
        }
    }

    // MARK: - Popup / OAuth 承接（Issue #14）

    /**
     * window.open / OAuth popup 承接：在 App 内创建临时子 WebView，不跳系统浏览器。
     * 只解决 popup 承载本身；第三方 IdP 若主动拒绝 embedded WebView（如 Google Sign-In），
     * 不做任何 UA 伪装或脚本绕过，用户可点右上角 ✕ 关闭弹窗，改用手动粘贴 Token。
     */
    private fun handleCreateWindow(resultMsg: Message): Boolean {
        return try {
            val popup = createPopupWebView()
            popupWebView = popup
            // WebViewTransport 是 WebView 的 inner class：Kotlin 必须以 WebView 实例为 receiver 构造
        val transport = popup.WebViewTransport()
            transport.webView = popup
            resultMsg.obj = transport
            resultMsg.sendToTarget()
            onStatus("检测到登录弹窗，请在弹窗内完成登录；无法完成时可点 ✕ 关闭")
            true
        } catch (_: Exception) {
            // 承接失败（极端情况）：交回 WebView 默认处理（主窗口内导航），绝不让弹窗流程卡死
            false
        }
    }

    /** 创建 popup 子 WebView（替换已存在的旧弹窗）；与主 WebView 共享 localStorage / cookie */
    private fun createPopupWebView(): WebView {
        closePopup()
        var sawThirdPartyHost = false
        val child = WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.setSupportMultipleWindows(true)
            settings.userAgentString = USER_AGENT
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    val host = Uri.parse(url).host ?: return
                    val isDeepSeek = host == "deepseek.com" || host.endsWith(".deepseek.com")
                    if (!isDeepSeek) {
                        // 记录离开过 DeepSeek 域名：区分「OAuth 回跳」与「纯 DeepSeek 弹窗（如扫码）」
                        sawThirdPartyHost = true
                        return
                    }
                    // 第三方 IdP 完成授权后重定向回 DeepSeek：关闭弹窗，主窗口轮询将读取新登录态
                    if (sawThirdPartyHost) {
                        closePopup()
                        onStatus("登录弹窗已返回 DeepSeek，正在读取登录态…")
                        checkToken()
                    }
                }

                override fun onReceivedError(
                    view: WebView,
                    request: WebResourceRequest,
                    error: WebResourceError
                ) {
                    // 主资源加载失败：给用户明确出口，不 Crash、不无限循环
                    if (request.isForMainFrame) {
                        onStatus("登录弹窗加载失败，可点右上角 ✕ 关闭，改用其他登录方式或手动粘贴 Token")
                    }
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(
                    view: WebView,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: Message
                ): Boolean {
                    // 弹窗内的二次 window.open 不再嵌套承接：嵌套会 closePopup() 销毁正处于
                    // onCreateWindow 回调中的当前弹窗，存在崩溃风险；交回默认处理（弹窗内导航）
                    onStatus("弹窗内弹出新窗口已忽略，可关闭弹窗后重试或手动粘贴 Token")
                    return false
                }
            }
        }
        container.addView(
            child,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        child.bringToFront()

        // 关闭按钮：第三方 IdP 拒绝 embedded WebView 时避免用户困死在弹窗内
        val density = resources.displayMetrics.density
        val button = AndroidButton(context).apply {
            text = "✕"
            textSize = 16f
            contentDescription = "关闭登录弹窗"
            setBackgroundColor(0x99000000.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setOnClickListener { closePopup() }
        }
        container.addView(
            button,
            FrameLayout.LayoutParams(
                (36 * density).toInt(),
                (36 * density).toInt(),
                Gravity.TOP or Gravity.END
            ).apply {
                topMargin = (8 * density).toInt()
                marginEnd = (8 * density).toInt()
            }
        )
        popupCloseButton = button
        return child
    }

    /** 关闭并销毁 popup（幂等）；主 WebView 继续轮询 */
    private fun closePopup() {
        popupCloseButton?.let { container.removeView(it) }
        popupCloseButton = null
        popupWebView?.let { w ->
            container.removeView(w)
            w.stopLoading()
            w.destroy()
        }
        popupWebView = null
    }

    // MARK: - 工具（对齐 iOS/macOS 实现）

    private fun storageSignature(pairs: JSONObject): String {
        val keys = ArrayList<String>()
        val it = pairs.keys()
        while (it.hasNext()) keys.add(it.next())
        keys.sort()
        val sb = StringBuilder()
        for (key in keys) {
            val v = pairs.optString(key, "")
            sb.append(key).append("=").append(v.length).append(":")
                .append(if (v.length > 16) v.take(16) else v).append("|")
        }
        return sb.toString()
    }

    // 候选提取策略与 iOS/macOS 完全一致（三端一致性优先，且该逻辑已在真实登录中验证）：
    // 候选值只用于向 platform.deepseek.com 官方接口校验（fetchCurrentUser），绝不写入日志、
    // 不发给任何第三方；只有校验通过的候选才会作为 Token 保存（Keystore 加密）。
    private fun tokenCandidates(pairs: JSONObject): List<String> {
        fun unwrap(raw: String): String {
            return try {
                val o = JSONObject(raw)
                val v = o.optString("value", "")
                if (v.isNotEmpty()) v else raw
            } catch (_: Exception) {
                raw
            }
        }
        val result = ArrayList<String>()
        fun add(t: String) {
            val tr = t.trim()
            if (tr.isNotEmpty() && tr !in result) result.add(tr)
        }
        // 1. userToken 优先
        pairs.optString("userToken", "").takeIf { it.isNotEmpty() }?.let { add(unwrap(it)) }
        // 2. 键名含 token
        run {
            val it = pairs.keys()
            while (it.hasNext()) {
                val key = it.next()
                val value = pairs.optString(key, "")
                if (value.isNotEmpty() && key.lowercase().contains("token") && value.length >= 20) {
                    add(unwrap(value))
                }
            }
        }
        // 3. 兜底：40~512 字符的长值
        run {
            val it = pairs.keys()
            while (it.hasNext()) {
                val value = pairs.optString(it.next(), "")
                if (value.length in 40..512) add(unwrap(value))
            }
        }
        return result
    }

    companion object {
        private const val LOGIN_URL = "https://platform.deepseek.com/"
        // 移动端 Chrome UA：保持页面正常渲染；刻意不伪装桌面 UA 绕过第三方 IdP 对 embedded WebView 的限制（Issue #14 能力边界）
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
    }
}

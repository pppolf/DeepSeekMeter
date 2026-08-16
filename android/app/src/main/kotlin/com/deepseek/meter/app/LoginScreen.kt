package com.deepseek.meter.app

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
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
                TokenLoginWebView(
                    ctx,
                    onToken = onSaveToken,
                    onStatus = { s -> status = s }
                ).also { webViewRef = it }
            },
            modifier = Modifier.weight(1f),
            onRelease = { it.stopPolling() }
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

/// WebView 封装：官方登录页 + localStorage 轮询提取 Token（对齐 iOS LoginWebView.Coordinator）
@SuppressLint("SetJavaScriptEnabled")
class TokenLoginWebView(
    context: Context,
    private val onToken: (String, (Boolean) -> Unit) -> Unit,
    private val onStatus: (String) -> Unit
) : WebView(context) {

    init {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.userAgentString =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                checkToken()
            }
        }
        webChromeClient = WebChromeClient()
        loadUrl("https://platform.deepseek.com/")
        startPolling()
    }

    private val pollTimer = Timer()
    private var isChecking = false
    private var isValidating = false
    private var tokenReceived = false
    private var lastSignature = ""
    private var polling = true

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
}

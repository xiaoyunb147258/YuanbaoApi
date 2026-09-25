package dev.yuanbao2api.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.webkit.JavascriptInterface
import android.webkit.WebView
import dev.yuanbao2api.GatewayService
import dev.yuanbao2api.http.GatewayServer
import dev.yuanbao2api.store.SettingsStore
import dev.yuanbao2api.util.Logger
import dev.yuanbao2api.util.NetUtil
import org.json.JSONArray
import org.json.JSONObject

class WebBridge(
    private val context: Context,
    private val webView: WebView
) {
    private val settings = SettingsStore(context)
    private val engine = dev.yuanbao2api.yuanbao.YuanbaoEngine.get(context)

    private val logListener: (Logger.Entry) -> Unit = { entry ->
        val js = "window.onNativeLog(${JSONObject.quote(entry.time)},${JSONObject.quote(entry.text)})"
        webView.post { try { webView.evaluateJavascript(js, null) } catch (_: Exception) {} }
    }

    init {
        Logger.addListener(logListener)
    }

    fun destroy() {
        Logger.removeListener(logListener)
    }

    private fun ok(data: String = ""): String = """{"ok":true,"data":$data}"""
    private fun err(msg: String): String = """{"ok":false,"error":${JSONObject.quote(msg)}}"""

    @JavascriptInterface
    fun getStatus(): String {
        return try {
            val obj = JSONObject()
                .put("running", GatewayService.running)
                .put("port", GatewayService.currentPort)
                .put("configPort", settings.port)
                .put("requestCount", GatewayServer.requestCount())
                .put("ip", NetUtil.getLocalIp())
                .put("apiKey", settings.apiKey)
                .put("loggedIn", engine.isReady())
                .put("autoStart", settings.autoStart)
                .put("showFloat", settings.showFloat)
                .put("canOverlay", canOverlay())
                .put("batteryIgnored", isIgnoringBattery())
            ok(obj.toString())
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun startService(): String { act(GatewayService.ACTION_START); return ok() }

    @JavascriptInterface
    fun stopService(): String { act(GatewayService.ACTION_STOP); return ok() }

    @JavascriptInterface
    fun restartService(): String { act(GatewayService.ACTION_RESTART); return ok() }

    private fun act(action: String) {
        val intent = Intent(context, GatewayService::class.java).apply { this.action = action }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    @JavascriptInterface
    fun clearCookie(): String {
        return ok()
    }

    @JavascriptInterface
    fun saveSettings(port: Int, apiKey: String): String {
        return try {
            if (port in 1..65535) settings.port = port
            settings.apiKey = apiKey
            ok()
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun setSwitch(key: String, value: Boolean): String {
        return try {
            when (key) {
                "autoStart" -> settings.autoStart = value
                "showFloat" -> settings.showFloat = value
            }
            ok()
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun getModels(): String {
        return try {
            val arr = JSONArray()
            dev.yuanbao2api.yuanbao.ModelCatalog.MODELS.forEach { m ->
                arr.put(JSONObject().put("id", m.id).put("name", m.name))
            }
            ok(arr.toString())
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun getLogs(): String {
        return try {
            val arr = JSONArray()
            Logger.all().forEach { e ->
                arr.put(JSONObject().put("time", e.time).put("text", e.text))
            }
            ok(arr.toString())
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun clearLogs(): String { Logger.clear(); return ok() }

    @JavascriptInterface
    fun copyToClipboard(text: String): String {
        return try {
            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("yb", text))
            ok()
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    private fun canOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    @JavascriptInterface
    fun requestOverlay(): String {
        return try {
            if (!canOverlay()) {
                context.startActivity(Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + context.packageName)
                ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
            }
            ok()
        } catch (e: Exception) { err(e.message ?: "error") }
    }

    @JavascriptInterface
    fun requestBattery(): String {
        return try {
            if (!isIgnoringBattery()) {
                context.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:" + context.packageName))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            ok()
        } catch (e: Exception) { err(e.message ?: "error") }
    }
}

package dev.yuanbao2api

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import dev.yuanbao2api.ui.WebBridge

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var bridge: WebBridge? = null

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this)
        setContentView(webView)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            loadWithOverviewMode = true
            useWideViewPort = true
        }
        webView.webViewClient = WebViewClient()
        val b = WebBridge(this, webView)
        bridge = b
        webView.addJavascriptInterface(b, "YuanbaoNative")
        webView.addJavascriptInterface(object {
            @android.webkit.JavascriptInterface
            fun openLogin() {
                startActivity(Intent(this@MainActivity, LoginActivity::class.java))
            }
        }, "YuanbaoLogin")
        webView.loadUrl("file:///android_asset/index.html")

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        })

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")))
            } catch (_: Exception) {}
        }
    }

    override fun onDestroy() {
        bridge?.destroy()
        bridge = null
        webView.destroy()
        super.onDestroy()
    }
}

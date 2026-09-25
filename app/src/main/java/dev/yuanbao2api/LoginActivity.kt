package dev.yuanbao2api

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

/**
 * 内置元宝登录页。登录后点右上角「保存」，抓取 cookie 持久化。
 */
class LoginActivity : AppCompatActivity() {

    private lateinit var webView: WebView

    companion object {
        const val URL = "https://yuanbao.tencent.com/chat/naQivTmsDa"
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this)
        root.setBackgroundColor(Color.WHITE)

        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        webView.webViewClient = WebViewClient()

        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        lp.topMargin = dp(56)
        root.addView(webView, lp)

        val bar = FrameLayout(this)
        bar.setBackgroundColor(Color.parseColor("#0052D9"))

        val title = TextView(this).apply {
            text = "登录元宝"
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER_VERTICAL
        }
        val tlp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        tlp.leftMargin = dp(16)
        bar.addView(title, tlp)

        val saveBtn = Button(this).apply {
            text = "保存"
            setTextColor(Color.parseColor("#0052D9"))
            setBackgroundColor(Color.parseColor("#FFFFFF"))
            setOnClickListener { saveCookie() }
        }
        val blp = FrameLayout.LayoutParams(dp(80), dp(40))
        blp.gravity = Gravity.END or Gravity.CENTER_VERTICAL
        blp.rightMargin = dp(12)
        bar.addView(saveBtn, blp)

        root.addView(bar, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(56)
        ))

        setContentView(root)
        webView.loadUrl(URL)
    }

    private fun saveCookie() {
        // 全局 CookieManager 是所有 WebView 共享的，这里确认登录完成，
        // 再让引擎重新加载页面，即可带上登录态。
        CookieManager.getInstance().flush()
        val c = CookieManager.getInstance().getCookie("https://yuanbao.tencent.com") ?: ""
        if (c.isBlank()) {
            Toast.makeText(this, "未获取到登录信息，请确认已登录", Toast.LENGTH_LONG).show()
            return
        }
        dev.yuanbao2api.yuanbao.YuanbaoEngine.get(this).reload()
        Toast.makeText(this, "登录完成", Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }
}

package dev.yuanbao2api.yuanbao

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong

/**
 * 元宝网页引擎：常驻 WebView 加载 yuanbao.tencent.com，
 * 发消息 = 模拟输入+回车（网页自行发送），
 * 收回复 = 轮询 DOM 读 .hyc-common-markdown 最后一条正文。
 */
class YuanbaoEngine private constructor(private val context: Context) {

    interface Listener {
        fun onDelta(requestId: String, delta: String)
        fun onDone(requestId: String, fullText: String, error: String?)
    }

    class PendingReq(
        val requestId: String,
        val listener: Listener,
        var lastText: String = "",
        var finished: Boolean = false
    )

    private val handler = Handler(Looper.getMainLooper())
    private var webView: WebView? = null
    private var attached = false
    private val seq = AtomicLong(0)
    private val pending = HashMap<String, PendingReq>()
    private var ready = false

    private val bridge = object {
        @JavascriptInterface
        fun onPoll(rid: String, text: String, done: Boolean) {
            val req: PendingReq
            synchronized(pending) {
                req = pending[rid] ?: return
                if (req.finished) return
                val prev = req.lastText
                if (text.length > prev.length && text.startsWith(prev)) {
                    val delta = text.substring(prev.length)
                    req.lastText = text
                    handler.post { req.listener.onDelta(rid, delta) }
                } else if (text != prev) {
                    req.lastText = text
                }
                if (done) {
                    req.finished = true
                    pending.remove(rid)
                    val full = req.lastText
                    handler.post { req.listener.onDone(rid, full, null) }
                }
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    fun ensureWebView(onReady: () -> Unit) {
        if (webView != null && ready) { onReady(); return }
        handler.post {
            val wv = WebView(context)
            wv.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
            }
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)
            wv.addJavascriptInterface(bridge, "Native")
            var notified = false
            wv.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    if (!notified && url != null && url.contains("yuanbao.tencent.com")) {
                        notified = true
                        ready = true
                        onReady()
                    }
                }
            }
            try {
                val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val lp = WindowManager.LayoutParams(
                    1, 1,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT
                )
                wm.addView(wv, lp)
                attached = true
            } catch (_: Exception) { attached = false }
            wv.loadUrl(PAGE_URL)
            webView = wv
        }
    }

    fun isReady(): Boolean = ready

    /** 重新加载页面（登录完成后调用，带上新登录态） */
    fun reload() {
        handler.post {
            webView?.loadUrl(PAGE_URL)
        }
    }

    fun send(prompt: String, listener: Listener): String {
        val rid = "r" + seq.incrementAndGet()
        synchronized(pending) { pending[rid] = PendingReq(rid, listener) }
        handler.post {
            val q = JSONObject.quote(prompt)
            // 已验证可用：逐字符派发完整键盘事件序列写入 Quill，再派发 Enter 发送
            val js = "(function(){var b=document.querySelector('.ql-editor');" +
                "if(!b){Native.onPoll('" + rid + "','',true);return;}" +
                "window.__YB_BASE__=document.querySelectorAll('.hyc-common-markdown').length;" +
                "b.focus();b.innerHTML='';" +
                "var s=" + q + ";" +
                "for(var i=0;i<s.length;i++){var ch=s[i];" +
                "b.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true}));" +
                "b.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true}));" +
                "b.textContent+=ch;" +
                "b.dispatchEvent(new InputEvent('input',{inputType:'insertText',data:ch,bubbles:true}));" +
                "b.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true}));}" +
                "setTimeout(function(){b.dispatchEvent(new KeyboardEvent('keydown'," +
                "{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));},350);" +
                "window.__YB_POLL__('" + rid + "');})()"
            webView?.evaluateJavascript(POLL_FN, null)
            webView?.evaluateJavascript(js, null)
        }
        return rid
    }

    private val POLL_FN = "(function(){if(window.__YB_POLL__)return;" +
        "window.__YB_POLL__=function(rid){" +
        "var tries=0;var stable=0;var last='';" +
        "var timer=setInterval(function(){" +
        "  tries++;" +
        "  var items=document.querySelectorAll('.hyc-common-markdown');" +
        "  var base=window.__YB_BASE__||0;" +
        "  if(items.length<=base){ if(tries>200){clearInterval(timer);Native.onPoll(rid,last,true);} return; }" +
        "  var el=items[items.length-1];" +
        "  var txt=(el.innerText||'').trim();" +
        "  if(txt===last){stable++;}else{stable=0;last=txt;Native.onPoll(rid,txt,false);}" +
        "  if(stable>=3&&txt.length>0){ clearInterval(timer);Native.onPoll(rid,txt,true);return; }" +
        "  if(tries>400){clearInterval(timer);Native.onPoll(rid,txt,true);}" +
        "},600);};})()"

    fun shutdown() {
        handler.post {
            if (attached) {
                try {
                    val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                    webView?.let { wm.removeView(it) }
                } catch (_: Exception) {}
                attached = false
            }
            webView?.destroy()
            webView = null
            ready = false
        }
    }

    companion object {
        const val PAGE_URL = "https://yuanbao.tencent.com/chat/naQivTmsDa"

        @Volatile
        private var instance: YuanbaoEngine? = null

        fun get(context: Context): YuanbaoEngine {
            return instance ?: synchronized(this) {
                instance ?: YuanbaoEngine(context.applicationContext).also { instance = it }
            }
        }
    }
}

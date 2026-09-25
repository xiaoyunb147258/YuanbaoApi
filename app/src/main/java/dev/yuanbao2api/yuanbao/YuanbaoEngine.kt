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

    fun send(prompt: String, listener: Listener, model: String? = null): String {
        val rid = "r" + seq.incrementAndGet()
        synchronized(pending) { pending[rid] = PendingReq(rid, listener) }
        handler.post {
            val q = JSONObject.quote(prompt)
            val m = JSONObject.quote(model ?: "")
            // 输入框选择器容错：Quill(.ql-editor) → contenteditable → textarea
            // 若传了 model，先在下拉/菜单里按名称模糊匹配点选（尽力而为，失败不阻塞）
            val js = "(function(){" +
                "try{" +
                "var b=document.querySelector('.ql-editor')||document.querySelector('[contenteditable=true]')||document.querySelector('textarea');" +
                "if(!b){Native.onPoll('" + rid + "','',true);return;}" +
                "var m=" + m + ";" +
                "if(m){try{var btns=document.querySelectorAll('[class*=model],[class*=Model],[role=menuitem],.t-dropdown-menu .t-menu__item');" +
                "for(var k=0;k<btns.length;k++){var t=(btns[k].innerText||'').trim();" +
                "if(t&&m&&(t===m||t.indexOf(m)>=0)){btns[k].click();break;}}}catch(e2){}}" +
                "var cnt=document.querySelectorAll('.hyc-common-markdown').length;" +
                "if(cnt===0){cnt=document.querySelectorAll('.markdown-body, .markdown, [class*=markdown]').length;}" +
                "window.__YB_BASE__=cnt;" +
                "var s=" + q + ";" +
                "if(b.tagName==='TEXTAREA'){" +
                "b.focus();b.value='';b.value=s;" +
                "b.dispatchEvent(new InputEvent('input',{inputType:'insertText',data:s,bubbles:true}));" +
                "}else{" +
                "b.focus();b.innerHTML='';" +
                "for(var i=0;i<s.length;i++){var ch=s[i];" +
                "b.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true}));" +
                "b.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true}));" +
                "b.textContent+=ch;" +
                "b.dispatchEvent(new InputEvent('input',{inputType:'insertText',data:ch,bubbles:true}));" +
                "b.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true}));}}" +
                "window.__YB_POLL__('" + rid + "');" +
                "setTimeout(function(){try{b.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));}catch(e3){}},350);" +
                "}catch(e){Native.onPoll('" + rid + "','',true);}" +
                "})()"
            webView?.evaluateJavascript(POLL_FN, null)
            webView?.evaluateJavascript(js, null)
        }
        return rid
    }

    private val POLL_FN = "(function(){if(window.__YB_POLL__)return;" +
        "window.__YB_SEL__=function(){var a=document.querySelectorAll('.hyc-common-markdown');" +
        "if(a.length)return a;return document.querySelectorAll('.markdown-body, .markdown, [class*=markdown]');};" +
        "window.__YB_POLL__=function(rid){" +
        "var tries=0;var stable=0;var last='';" +
        "var timer=setInterval(function(){" +
        "  tries++;" +
        "  var items=window.__YB_SEL__();" +
        "  var base=window.__YB_BASE__||0;" +
        "  if(items.length<=base){ if(tries>200){clearInterval(timer);Native.onPoll(rid,last,true);} return; }" +
        "  var el=items[items.length-1];" +
        "  var txt=(el.innerText||el.textContent||'').trim();" +
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

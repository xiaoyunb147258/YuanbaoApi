package dev.yuanbao2api.store

import android.content.Context
import android.content.SharedPreferences
import android.webkit.CookieManager

/**
 * 登录态存储：WebView 登录元宝后，把 cookie 抓下来持久化，供网关直连使用。
 */
class CookieStore private constructor(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("yb_cookie", Context.MODE_PRIVATE)

    @Volatile
    var cookie: String = prefs.getString("cookie", "") ?: ""
        private set

    val hasCookie: Boolean get() = cookie.isNotBlank()

    /** 从系统 CookieManager 抓取元宝域名的 cookie */
    fun refreshFromWebView() {
        val cm = CookieManager.getInstance()
        val c = cm.getCookie("https://yuanbao.tencent.com") ?: ""
        if (c.isNotBlank()) {
            cookie = c
            prefs.edit().putString("cookie", c).apply()
        }
    }

    /** 手动设置（用于调试） */
    fun setCookie(c: String) {
        cookie = c
        prefs.edit().putString("cookie", c).apply()
    }

    fun clear() {
        cookie = ""
        prefs.edit().remove("cookie").apply()
    }

    companion object {
        @Volatile
        private var instance: CookieStore? = null

        fun get(context: Context): CookieStore {
            return instance ?: synchronized(this) {
                instance ?: CookieStore(context).also { instance = it }
            }
        }
    }
}

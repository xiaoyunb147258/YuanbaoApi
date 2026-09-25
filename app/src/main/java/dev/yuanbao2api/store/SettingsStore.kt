package dev.yuanbao2api.store

import android.content.Context
import android.content.SharedPreferences

class SettingsStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("yb_settings", Context.MODE_PRIVATE)

    var port: Int
        get() = prefs.getInt("port", 9990)
        set(v) = prefs.edit().putInt("port", v).apply()

    var apiKey: String
        get() = prefs.getString("api_key", "sk-yuanbao-local") ?: "sk-yuanbao-local"
        set(v) = prefs.edit().putString("api_key", v).apply()

    var autoStart: Boolean
        get() = prefs.getBoolean("auto_start", true)
        set(v) = prefs.edit().putBoolean("auto_start", v).apply()

    var showFloat: Boolean
        get() = prefs.getBoolean("show_float", true)
        set(v) = prefs.edit().putBoolean("show_float", v).apply()
}

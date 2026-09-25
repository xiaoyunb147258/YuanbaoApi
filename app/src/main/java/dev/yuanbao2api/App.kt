package dev.yuanbao2api

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                "yb_gateway",
                getString(R.string.channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = getString(R.string.channel_desc); setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
}

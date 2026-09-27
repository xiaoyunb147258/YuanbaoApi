package com.yuanbao.yuanbao_api

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/// 前台保活服务：常驻通知，配合忽略电池优化，保证应用不被系统回收
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundInternal()
        return START_STICKY
    }

    private fun startForegroundInternal() {
        val channelId = "yuanbao_keepalive"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(channelId, "后台保活", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, channelId)
        else
            Notification.Builder(this)
        startForeground(
            1002,
            notif.setContentTitle("豆包助手正在后台运行")
                .setContentText("保持引擎常驻，随时可用")
                .setSmallIcon(android.R.drawable.ic_menu_info_details)
                .build()
        )
    }
}

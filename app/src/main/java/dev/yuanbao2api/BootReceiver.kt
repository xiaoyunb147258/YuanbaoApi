package dev.yuanbao2api

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import dev.yuanbao2api.store.SettingsStore

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON") return
        if (!SettingsStore(context).autoStart) return
        val si = Intent(context, GatewayService::class.java).apply {
            this.action = GatewayService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(si)
        } else {
            context.startService(si)
        }
    }
}

package com.yuanbao.yuanbao_api

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "yuanbao/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestOverlay" -> {
                        result.success(requestOverlayPermission())
                    }
                    "toggleFloatingBall" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        toggleFloatingBall(on)
                        result.success(true)
                    }
                    "requestIgnoreBattery" -> {
                        result.success(requestIgnoreBattery())
                    }
                    "toggleForegroundService" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        toggleForegroundService(on)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestOverlayPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return false
            }
        }
        return true
    }

    private fun requestIgnoreBattery(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
                return false
            }
        }
        return true
    }

    private fun toggleFloatingBall(on: Boolean) {
        val intent = Intent(this, FloatingBallService::class.java)
        if (on) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } else {
            stopService(intent)
        }
    }

    private fun toggleForegroundService(on: Boolean) {
        val intent = Intent(this, KeepAliveService::class.java)
        if (on) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } else {
            stopService(intent)
        }
    }
}

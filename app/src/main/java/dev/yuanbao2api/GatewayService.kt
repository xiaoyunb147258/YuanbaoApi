package dev.yuanbao2api

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import dev.yuanbao2api.http.GatewayServer
import dev.yuanbao2api.http.RequestHandler
import dev.yuanbao2api.store.CookieStore
import dev.yuanbao2api.store.SettingsStore
import dev.yuanbao2api.util.Logger
import dev.yuanbao2api.util.NetUtil
import dev.yuanbao2api.yuanbao.YuanbaoClient
import dev.yuanbao2api.yuanbao.YuanbaoEngine

class GatewayService : Service() {

    private lateinit var settings: SettingsStore
    private lateinit var cookies: CookieStore
    private lateinit var client: YuanbaoClient
    private var server: GatewayServer? = null
    private var floating: FloatingWindow? = null
    private lateinit var engine: YuanbaoEngine
    private val handler = Handler(Looper.getMainLooper())

    private val notifyRunnable = Runnable {
        if (running) {
            try {
                getSystemService(android.app.NotificationManager::class.java)
                    .notify(NOTIFY_ID, buildNotification(currentPort))
            } catch (_: Exception) {}
        }
    }

    companion object {
        const val ACTION_START = "dev.yuanbao2api.START"
        const val ACTION_STOP = "dev.yuanbao2api.STOP"
        const val ACTION_RESTART = "dev.yuanbao2api.RESTART"
        private const val CHANNEL_ID = "yb_gateway"
        private const val NOTIFY_ID = 2001

        @Volatile var running = false
            private set
        @Volatile var currentPort = 9990
            private set
    }

    override fun onCreate() {
        super.onCreate()
        settings = SettingsStore(this)
        cookies = CookieStore.get(this)
        engine = YuanbaoEngine.get(this)
        client = YuanbaoClient(engine)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { stopGateway(); stopSelf(); return START_NOT_STICKY }
            ACTION_RESTART -> { stopGateway(); startGateway() }
            else -> startGateway()
        }
        return START_STICKY
    }

    private fun startGateway() {
        if (running) return
        cookies.refreshFromWebView()
        currentPort = settings.port
        startForeground(NOTIFY_ID, buildNotification(currentPort))
        try {
            val handlerH = RequestHandler(settings, client)
            server = GatewayServer(settings.port, handlerH).also { it.start() }
            running = true
            currentPort = GatewayServer.runningPort
            Logger.log("服务启动，端口 ${GatewayServer.runningPort}")
            engine.ensureWebView { Logger.log("元宝网页引擎就绪") }
            syncFloating()
            handler.removeCallbacks(notifyRunnable)
            handler.postDelayed(notifyRunnable, 30_000)
        } catch (e: Exception) {
            Logger.log("服务启动失败：" + e.message)
            running = false
        }
    }

    private fun stopGateway() {
        handler.removeCallbacks(notifyRunnable)
        server?.stop()
        server = null
        running = false
        floating?.hide()
        floating = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        Logger.log("服务已停止")
    }

    private fun syncFloating() {
        if (settings.showFloat) {
            if (floating == null) floating = FloatingWindow(this)
            floating?.show(NetUtil.getLocalIp() + ":" + currentPort)
        } else {
            floating?.hide()
            floating = null
        }
    }

    private fun buildNotification(port: Int): Notification {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else 0
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), flags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("元宝 API 运行中")
            .setContentText("地址 " + NetUtil.getLocalIp() + ":" + port +
                "  已处理 " + GatewayServer.requestCount() + " 次请求")
            .setSmallIcon(R.drawable.ic_stat_gateway)
            .setContentIntent(pi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    fun refresh() {
        cookies.refreshFromWebView()
        syncFloating()
        handler.removeCallbacks(notifyRunnable)
        handler.post(notifyRunnable)
    }

    override fun onDestroy() {
        handler.removeCallbacks(notifyRunnable)
        stopGateway()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

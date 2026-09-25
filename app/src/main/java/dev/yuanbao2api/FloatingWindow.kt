package dev.yuanbao2api

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

class FloatingWindow(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var container: LinearLayout? = null
    private var addrView: TextView? = null

    @SuppressLint("ClickableViewAccessibility")
    fun show(text: String) {
        if (container != null) {
            addrView?.text = text
            return
        }
        val c = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#E6000000"))
                cornerRadius = dp(12).toFloat()
                setStroke(dp(1), Color.parseColor("#550052D9"))
            }
        }
        val title = TextView(context).apply {
            this.text = "元宝 API"
            setTextColor(Color.parseColor("#4D9EFF"))
            textSize = 12f
        }
        val addr = TextView(context).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 12f
        }
        c.addView(title)
        c.addView(addr)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16); y = dp(140)
        }

        var downX = 0f; var downY = 0f
        var startX = 0; var startY = 0
        var moved = false
        c.setOnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = ev.rawX; downY = ev.rawY
                    startX = lp.x; startY = lp.y; moved = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - downX; val dy = ev.rawY - downY
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) moved = true
                    if (moved) {
                        lp.x = startX + dx.toInt(); lp.y = startY + dy.toInt()
                        try { wm.updateViewLayout(c, lp) } catch (_: Exception) {}
                    }
                }
            }
            true
        }
        try {
            wm.addView(c, lp)
            container = c
            addrView = addr
        } catch (_: Exception) {
            container = null
        }
    }

    fun hide() {
        container?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        container = null
        addrView = null
    }

    private fun dp(v: Int): Int = (v * context.resources.displayMetrics.density).toInt()
}

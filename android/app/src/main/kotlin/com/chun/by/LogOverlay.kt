package com.chun.by

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * 实时输出窗：AI 执行插件/命令/抓包时自动弹出，可拖动、缩小、关闭。
 */
class LogOverlay(private val ctx: Context) {
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())

    private var root: View? = null
    private var lp: WindowManager.LayoutParams? = null
    private var body: LinearLayout? = null
    private var scroll: ScrollView? = null
    private val lines = ArrayDeque<String>()
    private var collapsed = false
    private var lastLine = ""

    private fun dp(v: Int): Int = (v * ctx.resources.displayMetrics.density).toInt()

    private fun round(color: Int, r: Int): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(r).toFloat()
    }

    fun isShowing(): Boolean = root != null

    @SuppressLint("ClickableViewAccessibility")
    fun show(title: String = "实时输出") {
        main.post {
            if (root != null) return@post
            val w = dp(300)
            val h = dp(220)
            val params = WindowManager.LayoutParams(
                w, h,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = dp(16)
                y = dp(160)
            }
            lp = params

            val container = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                background = round(0xF2141B2B.toInt(), 16)
                setPadding(dp(10), dp(8), dp(10), dp(8))
            }

            // 标题栏
            var startX = 0f
            var startY = 0f
            var sx = 0
            var sy = 0

            val bar = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setOnTouchListener { _, e ->
                    when (e.action) {
                        MotionEvent.ACTION_DOWN -> {
                            startX = e.rawX; startY = e.rawY
                            sx = params.x; sy = params.y
                            false
                        }
                        MotionEvent.ACTION_MOVE -> {
                            params.x = (sx + (e.rawX - startX)).toInt()
                            params.y = (sy + (e.rawY - startY)).toInt()
                            wm.updateViewLayout(container, params)
                            true
                        }
                        else -> false
                    }
                }
            }

            val dot = TextView(ctx).apply {
                text = "●"
                setTextColor(0xFF22C55E.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
                setPadding(0, 0, dp(6), 0)
            }
            val titleView = TextView(ctx).apply {
                text = title
                setTextColor(0xFFE2E8F0.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            }
            val collapseBtn = TextView(ctx).apply {
                text = "－"
                setTextColor(0xFF94A3B8.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(10), 0, dp(10), 0)
                setOnClickListener { toggleCollapse() }
            }
            val closeBtn = TextView(ctx).apply {
                text = "×"
                setTextColor(0xFF94A3B8.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setPadding(dp(8), 0, dp(2), 0)
                setOnClickListener { hide() }
            }

            bar.addView(dot, LinearLayout.LayoutParams(-2, -2))
            bar.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
            bar.addView(collapseBtn, LinearLayout.LayoutParams(-2, -2))
            bar.addView(closeBtn, LinearLayout.LayoutParams(-2, -2))

            val sc = ScrollView(ctx)
            val bodyLayout = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
            sc.addView(bodyLayout)

            container.addView(bar, LinearLayout.LayoutParams(-1, dp(30)))
            val bodyParams = LinearLayout.LayoutParams(-1, 0, 1f)
            container.addView(sc, bodyParams)

            scroll = sc
            body = bodyLayout
            root = container
            collapsed = false

            runCatching { wm.addView(container, params) }.onFailure {
                root = null
                body = null
                scroll = null
            }
        }
    }

    private fun toggleCollapse() {
        val container = root ?: return
        val params = lp ?: return
        collapsed = !collapsed
        scroll?.visibility = if (collapsed) View.GONE else View.VISIBLE
        params.height = if (collapsed) dp(36) else dp(220)
        runCatching { wm.updateViewLayout(container, params) }
    }

    fun hide() {
        main.post {
            val v = root ?: return@post
            runCatching { wm.removeView(v) }
            root = null
            body = null
            scroll = null
        }
    }

    fun append(line: String) {
        main.post {
            val b = body ?: return@post
            val text = line.trimEnd()
            if (text.isEmpty()) return@post
            if (text == lastLine) return@post
            lastLine = text
            lines.addLast(text)
            while (lines.size > 300) lines.removeFirst()

            val tv = TextView(ctx).apply {
                setTextColor(
                    when {
                        text.startsWith("ERROR") || text.contains("error:", true) -> 0xFFF87171.toInt()
                        text.startsWith("==") -> 0xFF60A5FA.toInt()
                        else -> 0xFFCBD5E1.toInt()
                    }
                )
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
                setTextIsSelectable(false)
                typeface = android.graphics.Typeface.MONOSPACE
                this.text = line.take(300)
            }
            b.addView(tv)
            while (b.childCount > 200) b.removeViewAt(0)
            scroll?.post { scroll?.fullScroll(View.FOCUS_DOWN) }
        }
    }

    fun clear() {
        main.post {
            body?.removeAllViews()
            lines.clear()
        }
    }
}

package com.chun.by

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 悬浮窗：开第二个 Flutter 引擎渲染「灵动岛胶囊 + 对话小窗」。
 * 窗口尺寸/位置由这里控制；Flutter 侧负责画内容、发拖动/缩放/展开收起事件。
 */
class FloatingChatService(private val ctx: Context) {

    companion object {
        @Volatile
        var instance: FloatingChatService? = null
            private set

        const val CHANNEL = "com.chun.by/floating"
        private const val KEY_W = "win_w"
        private const val KEY_H = "win_h"
        private const val KEY_X = "pos_x"
        private const val KEY_Y = "pos_y"
        private const val PILL_W = 260
        private const val PILL_H = 64
        private const val WIN_W = 330
        private const val WIN_H = 600
    }

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()

    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var lp: WindowManager.LayoutParams? = null
    private var channel: MethodChannel? = null
    private var expanded = false
    private var moved = false
    private var pillX = 0
    private var pillY = 0
    private var fromY = 0
    private val prefs by lazy {
        ctx.getSharedPreferences("floating_chat", Context.MODE_PRIVATE)
    }

    /** 悬浮窗发来 send（用户消息）/ action（卡片点按），转发给主引擎的 AI。 */
    var onEvent: ((String, Map<String, Any?>?) -> Unit)? = null

    private fun overlayType() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    fun ensure() {
        if (view != null) return
        try {
            val engine = FlutterEngine(ctx.applicationContext)
            val entry = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "floatingChatMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entry)
            FlutterEngineCache.getInstance().put("floating_chat", engine)

            val v = FlutterView(ctx.applicationContext, RenderMode.texture)
            v.attachToFlutterEngine(engine)
            v.setBackgroundColor(Color.TRANSPARENT)

            val p = WindowManager.LayoutParams(
                dp(PILL_W), dp(PILL_H),
                overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT,
            )
            // 上次拖过就从上次的位置出现；没有就顶部居中
            val savedX = prefs.getInt(KEY_X, Int.MIN_VALUE)
            val savedY = prefs.getInt(KEY_Y, Int.MIN_VALUE)
            if (savedX != Int.MIN_VALUE && savedY != Int.MIN_VALUE) {
                p.gravity = Gravity.TOP or Gravity.START
                p.x = savedX; p.y = savedY
                moved = true
            } else {
                p.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                p.x = 0
                p.y = dp(16)
            }
            p.alpha = 1f
            fromY = p.y

            wm.addView(v, p)

            this.engine = engine; view = v; lp = p
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "expand" -> { expand(); result.success(true) }
                    "collapse" -> { collapse(); result.success(true) }
                    "move" -> {
                        // Flutter 传的是逻辑像素，乘 density 转物理像素
                        val dx = call.argument<Double>("dx") ?: 0.0
                        val dy = call.argument<Double>("dy") ?: 0.0
                        move((dx * density).toInt(), (dy * density).toInt()); result.success(true)
                    }
                    "resize" -> {
                        val dw = call.argument<Double>("dw") ?: 0.0
                        val dh = call.argument<Double>("dh") ?: 0.0
                        resize((dw * density).toInt(), (dh * density).toInt()); result.success(true)
                    }
                    "close" -> { hide(); result.success(true) }
                    "send" -> {
                        onEvent?.invoke("send", call.arguments as? Map<String, Any?>)
                        result.success(true)
                    }
                    "action" -> {
                        onEvent?.invoke("action", call.arguments as? Map<String, Any?>)
                        result.success(true)
                    }
                    "attach" -> {
                        onEvent?.invoke("attach", call.arguments as? Map<String, Any?>)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
            FloatingChatService.instance = this
        } catch (e: Throwable) {
            android.util.Log.e("FloatingChatService", "ensure failed", e)
            Toast.makeText(ctx, "悬浮窗启动失败：${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    fun show() {
        if (!Settings.canDrawOverlays(ctx)) {
            Toast.makeText(ctx, "请先开启悬浮窗权限（设置 → 权限 → 悬浮窗）", Toast.LENGTH_LONG).show()
            return
        }
        ensure()
        view?.post {
            lp?.let {
                it.alpha = 1f
                wm.updateViewLayout(view!!, it)
            }
        }
    }

    fun hide() {
        try {
            view?.let { wm.removeView(it) }
        } catch (_: Throwable) {}
        view = null
        lp = null
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        FlutterEngineCache.getInstance().remove("floating_chat")
        engine = null
        instance = null
        expanded = false
        moved = false
    }

    private fun expand() {
        if (expanded) return
        expanded = true
        val v = view ?: return
        val p = lp ?: return
        // 展开后要能打字：去掉 NOT_FOCUSABLE
        p.flags = p.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        // 记住展开前的位置，收起时回去
        if (!moved) { pillX = p.x; pillY = p.y }
        // 用上次用户缩放后的尺寸；没缩过就用默认
        val w = prefs.getInt(KEY_W, dp(WIN_W))
        val h = prefs.getInt(KEY_H, dp(WIN_H))
        animateSize(p.width, p.height, w, h, dp(70))
    }

    private fun collapse() {
        if (!expanded) return
        expanded = false
        val v = view ?: return
        val p = lp ?: return
        // 收起回胶囊：恢复不抢焦点
        p.flags = p.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        // 收起回胶囊：回到展开前记下的位置（pillY）
        animateSize(p.width, p.height, dp(PILL_W), dp(PILL_H), pillY)
    }

    /** 尺寸/位置用 180ms 动画过渡，避免窗口尺寸突变导致 FlutterView 卡屏。 */
    private fun animateSize(fromW: Int, fromH: Int, toW: Int, toH: Int, toY: Int) {
        val v = view ?: return
        val p = lp ?: return
        android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 180
            addUpdateListener { a ->
                val t = a.animatedValue as Float
                p.width = (fromW + (toW - fromW) * t).toInt()
                p.height = (fromH + (toH - fromH) * t).toInt()
                if (!moved) p.y = (fromY + (toY - fromY) * t).toInt()
                runCatching { wm.updateViewLayout(v, p) }
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    p.width = toW; p.height = toH
                    if (!moved) p.y = toY
                    fromY = toY
                    runCatching { wm.updateViewLayout(v, p) }
                }
            })
            start()
        }
    }

    private fun move(dx: Int, dy: Int) {
        val v = view ?: return
        val p = lp ?: return
        p.gravity = Gravity.TOP or Gravity.START
        // 限制在屏幕内：至少露出 40dp，避免拖没了找不回来
        val dm = ctx.resources.displayMetrics
        val maxX = dm.widthPixels - dp(40)
        val maxY = dm.heightPixels - dp(40)
        p.x = (p.x + dx).coerceIn(-dp(190), maxX)
        p.y = (p.y + dy).coerceIn(0, maxY)
        moved = true
        fromY = p.y
        wm.updateViewLayout(v, p)
        // 记住拖动后的位置
        prefs.edit().putInt(KEY_X, p.x).putInt(KEY_Y, p.y).apply()
    }

    private fun resize(dw: Int, dh: Int) {
        val v = view ?: return
        val p = lp ?: return
        p.width = (p.width + dw).coerceIn(dp(220), dp(400))
        p.height = (p.height + dh).coerceIn(dp(280), dp(900))
        wm.updateViewLayout(v, p)
        // 记住缩放后的尺寸，下次展开沿用
        prefs.edit().putInt(KEY_W, p.width).putInt(KEY_H, p.height).apply()
    }

    fun pushState(text: String) {
        channel?.invokeMethod("state", mapOf("text" to text))
    }

    fun push(role: String, text: String) {
        channel?.invokeMethod("push", mapOf("role" to role, "text" to text))
    }
}

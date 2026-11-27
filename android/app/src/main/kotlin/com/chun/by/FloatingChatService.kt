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
        private const val PILL_W = 230
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
            p.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            p.x = 0
            p.y = dp(16)
            p.alpha = 1f

            wm.addView(v, p)

            this.engine = engine; view = v; lp = p
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "expand" -> { expand(); result.success(true) }
                    "collapse" -> { collapse(); result.success(true) }
                    "move" -> {
                        val dx = call.argument<Double>("dx") ?: 0.0
                        val dy = call.argument<Double>("dy") ?: 0.0
                        move(dx.toInt(), dy.toInt()); result.success(true)
                    }
                    "resize" -> {
                        val dw = call.argument<Double>("dw") ?: 0.0
                        val dh = call.argument<Double>("dh") ?: 0.0
                        resize(dw.toInt(), dh.toInt()); result.success(true)
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
    }

    private fun expand() {
        if (expanded) return
        expanded = true
        val v = view ?: return
        val p = lp ?: return
        p.width = dp(WIN_W)
        p.height = dp(WIN_H)
        p.y = dp(70)
        wm.updateViewLayout(v, p)
    }

    private fun collapse() {
        if (!expanded) return
        expanded = false
        val v = view ?: return
        val p = lp ?: return
        p.width = dp(PILL_W)
        p.height = dp(PILL_H)
        p.y = dp(16)
        wm.updateViewLayout(v, p)
    }

    private fun move(dx: Int, dy: Int) {
        val v = view ?: return
        val p = lp ?: return
        p.gravity = Gravity.TOP or Gravity.START
        p.x += dx
        p.y += dy
        wm.updateViewLayout(v, p)
    }

    private fun resize(dw: Int, dh: Int) {
        val v = view ?: return
        val p = lp ?: return
        p.width = (p.width + dw).coerceIn(dp(220), dp(400))
        p.height = (p.height + dh).coerceIn(dp(280), dp(900))
        wm.updateViewLayout(v, p)
    }

    fun pushState(text: String) {
        channel?.invokeMethod("state", mapOf("text" to text))
    }

    fun push(role: String, text: String) {
        channel?.invokeMethod("push", mapOf("role" to role, "text" to text))
    }
}

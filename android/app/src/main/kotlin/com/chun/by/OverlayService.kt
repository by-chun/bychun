package com.chun.by

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.EditText
import android.widget.Button
import android.text.InputType

/** 系统级悬浮窗：G 悬浮球，点击展开快捷操作面板。 */
class OverlayService : Service() {
    companion object {
        var pendingHtml: String? = null
        @Volatile var instance: OverlayService? = null
    }

    var overlayResults: List<String> = emptyList()
    private lateinit var wm: WindowManager
    private var bubble: View? = null
    private var panel: View? = null
    private lateinit var lp: WindowManager.LayoutParams

    private var panelLp: WindowManager.LayoutParams? = null
    private var startX = 0f
    private var startY = 0f
    private var startLpX = 0
    private var startLpY = 0
    private var moved = false
    private val prefs by lazy { getSharedPreferences("overlay", android.content.Context.MODE_PRIVATE) }
    private fun panelWidth(): Int = prefs.getInt("panelWidth", dp(320))
    private fun setPanelWidth(w: Int) {
        prefs.edit().putInt("panelWidth", w).apply()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private var bridgeChannel: io.flutter.plugin.common.MethodChannel? = null
    private var logOverlay: com.chun.by.LogOverlay? = null

    fun showLog(title: String) {
        val lo = logOverlay ?: com.chun.by.LogOverlay(this).also { logOverlay = it }
        lo.show(title)
    }

    fun pushLog(line: String) {
        logOverlay?.append(line)
    }

    fun hideLog() {
        logOverlay?.hide()
    }

    /** AI 对话浮窗出现时临时收起悬浮球，避免两个浮窗同时挡屏。 */
    fun hideBubble() {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            bubble?.let { runCatching { wm.removeView(it) } }
            bubble = null
        }
    }

    /** AI 对话浮窗关闭后把悬浮球放回来（球已不再默认显示，这里保留空实现避免调用方报错）。 */
    fun restoreBubble() {
        // 球已移除，入口改用 AI 对话浮窗胶囊
    }

    /** MainActivity 把和 Flutter 的通道接进来，供悬浮窗 JS 桥回调工具。 */
    fun attachBridge(messenger: io.flutter.plugin.common.BinaryMessenger) {
        bridgeChannel = io.flutter.plugin.common.MethodChannel(messenger, "rowan/overlayHost")
        bridgeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "eval" -> {
                    evalJs(call.argument<String>("js") ?: "")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        if (webView != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                runCatching { bridgeChannel?.invokeMethod("overlayShown", null) }
            }
        }
    }

    /** 向悬浮窗页面注入 JS（用于把主会话的流式输出推过去）。 */
    fun evalJs(js: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { webView?.evaluateJavascript(js, null) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            startForeground(1001, buildNotification())
        } catch (e: Exception) {
            android.util.Log.e("OverlayService", "startForeground failed", e)
        }
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        instance = this
        try {
            // 不再默认显示悬浮球：入口统一走 AI 对话浮窗的胶囊
            applyPrefs()
            pendingHtml?.let {
                overlayHtml = it
                showPanel()
            }
        } catch (e: Exception) {
            android.util.Log.e("OverlayService", "init failed", e)
        }
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    private fun addBubble() {
        val bubblePx = (48 * resources.displayMetrics.density).toInt()
        lp = WindowManager.LayoutParams(
            bubblePx,
            bubblePx,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = 900
        lp.y = 800

        val tv = AnvilBubbleView(this).apply {
            setOnClickListener { togglePanel() }
            setOnTouchListener { v, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = e.rawX; startY = e.rawY; startLpX = lp.x; startLpY = lp.y
                        moved = false
                        false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (Math.abs(e.rawX - startX) > 8 || Math.abs(e.rawY - startY) > 8) moved = true
                        lp.x = (startLpX + (e.rawX - startX)).toInt()
                        lp.y = (startLpY + (e.rawY - startY)).toInt()
                        wm.updateViewLayout(v, lp)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!moved) return@setOnTouchListener false
                        val screenW = resources.displayMetrics.widthPixels
                        lp.x = if (lp.x + v.width / 2 < screenW / 2) 0 else screenW - v.width
                        wm.updateViewLayout(v, lp)
                        true
                    }
                    else -> false
                }
            }
        }
        bubble = tv
        wm.addView(tv, lp)
    }

    private fun togglePanel() {
        if (webView != null) hidePanel() else showPanel()
    }

    private var currentTab = 0
    private var lastPid = ""

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun roundBg(color: Int, radius: Int, stroke: Int? = null): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }

    private var webView: android.webkit.WebView? = null
    var overlayHtml: String? = null
        private set

    /** AI 注入界面；已显示则热更新。 */
    fun setHtml(html: String) {
        overlayHtml = html
        pendingHtml = html
        val wv = webView ?: return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            wv.loadDataWithBaseURL("https://rowan.local/", html, "text/html", "utf-8", null)
        }
    }

    private fun showPanel() {
        if (webView != null) return
        val w = dp(prefs.getInt("panelWidth", 320))
        val h = dp(prefs.getInt("panelHeight", 520))
        val wv = android.webkit.WebView(this).apply {
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.mediaPlaybackRequiresUserGesture = false
            addJavascriptInterface(Bridge(this), "Rowan")
            webViewClient = object : android.webkit.WebViewClient() {
                override fun onPageFinished(view: android.webkit.WebView?, url: String?) {
                    injectCloseButton(view)
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        runCatching { bridgeChannel?.invokeMethod("overlayShown", null) }
                    }
                }
            }
        }
        val html = overlayHtml ?: defaultHtml()
        wv.loadDataWithBaseURL("https://rowan.local/", html, "text/html", "utf-8", null)

        val params = WindowManager.LayoutParams(
            w, h, overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = dp(12)
        params.y = dp(120)

        // 顶部空白区域可拖动整个面板（不动 HTML 里的按钮）
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        wv.setOnTouchListener { _, e ->
            val topZone = dp(34)
            when (e.action) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    dragging = e.y < topZone
                    downX = e.rawX; downY = e.rawY
                    startX = params.x; startY = params.y
                    false
                }
                android.view.MotionEvent.ACTION_MOVE -> {
                    if (!dragging) return@setOnTouchListener false
                    params.x = startX + (e.rawX - downX).toInt()
                    params.y = startY + (e.rawY - downY).toInt()
                    runCatching { wm.updateViewLayout(wv, params) }
                    true
                }
                else -> {
                    dragging = false
                    false
                }
            }
        }

        wm.addView(wv, params)
        webView = wv
        panelLp = params
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { bridgeChannel?.invokeMethod("overlayShown", null) }
        }
    }

    /** 给 AI 生成的任意页面注入一个固定关闭按钮，避免关不掉。 */
    private fun injectCloseButton(view: android.webkit.WebView?) {
        val js = """
      (function(){
        if (document.getElementById('__rowan_close')) return;
        var b = document.createElement('div');
        b.id = '__rowan_close';
        b.textContent = '✕';
        b.style.cssText = 'position:fixed;top:10px;right:10px;width:30px;height:30px;border-radius:15px;'
          + 'background:rgba(15,23,42,.55);color:#fff;font-size:15px;line-height:30px;text-align:center;'
          + 'z-index:2147483647;font-family:system-ui,sans-serif;';
        b.onclick = function(){ try { Rowan.close(); } catch(e) { document.body.innerHTML = ''; } };
        document.body.appendChild(b);

        // 页面没实现 __rowanChat 时的兜底输出区，保证主会话的 AI 输出能看到
        if (!window.__rowanChat) {
          window.__rowanChat = {
            update: function(text, running) {
              var old = document.getElementById('__rowan_out');
              if (!old) {
                old = document.createElement('div');
                old.id = '__rowan_out';
                old.style.cssText = 'position:fixed;left:8px;right:8px;bottom:8px;max-height:45%;overflow:auto;'
                  + 'background:rgba(15,23,42,.88);color:#fff;border-radius:12px;padding:10px;'
                  + 'font:12px/1.6 system-ui,sans-serif;z-index:2147483646;white-space:pre-wrap;display:none;';
                document.body.appendChild(old);
              }
              if (!text) { old.style.display = 'none'; return; }
              old.style.display = 'block';
              old.textContent = text + (running ? ' …' : '');
            }
          };
        }

        // 输入框聚焦时通知原生切到可接收键盘的窗口，否则键盘不会弹
        document.addEventListener('focusin', function(e){
          var t = e.target;
          if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) {
            try { Rowan.focusInput(true); } catch(_) {}
          }
        }, true);
        document.addEventListener('focusout', function(){
          try { Rowan.focusInput(false); } catch(_) {}
        }, true);
      })();
    """.trimIndent()
        view?.evaluateJavascript(js, null)
    }

    private fun hidePanel() {
        val had = webView != null
        webView?.let { runCatching { wm.removeView(it) } }
        webView = null
        panelLp = null
        if (had) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                runCatching { bridgeChannel?.invokeMethod("overlayHidden", null) }
            }
        }
    }

    /** JS 桥：Rowan.call(tool, argsJson, cbId) */
    inner class Bridge(private val wv: android.webkit.WebView) {
        /** 页面上的关闭按钮调用。 */
        @android.webkit.JavascriptInterface
        fun close() {
            android.os.Handler(android.os.Looper.getMainLooper()).post { hidePanel() }
        }

        /** 页面输入框聚焦/失焦：聚焦时把窗口改成可接收键盘。 */
        @android.webkit.JavascriptInterface
        fun focusInput(on: Boolean) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                val lp = panelLp ?: return@post
                val wvRef = webView ?: return@post
                if (on) {
                    lp.flags = lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                    lp.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                        WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
                } else {
                    lp.flags = lp.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                }
                runCatching { wm.updateViewLayout(wvRef, lp) }
                if (on) {
                    wvRef.requestFocus()
                    val imm = getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                    wvRef.postDelayed({ runCatching { imm?.showSoftInput(wvRef, 0) } }, 150)
                }
            }
        }

        @android.webkit.JavascriptInterface
        fun chatSend(text: String) {
            val ch = bridgeChannel ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                runCatching { ch.invokeMethod("chatSend", mapOf("text" to text), null) }
            }
        }

        @android.webkit.JavascriptInterface
        fun call(tool: String, argsJson: String, cbId: String) {
            val ch = bridgeChannel
            if (ch == null) {
                postResult(wv, cbId, """{"ok":false,"msg":"宿主未就绪"}""")
                return
            }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                runCatching {
                    ch.invokeMethod(
                        "callTool",
                        mapOf("tool" to tool, "args" to argsJson),
                        object : io.flutter.plugin.common.MethodChannel.Result {
                            override fun success(result: Any?) {
                                postResult(wv, cbId, result?.toString() ?: """{"ok":true}""")
                            }

                            override fun error(code: String, msg: String?, details: Any?) {
                                postResult(wv, cbId, """{"ok":false,"msg":${org.json.JSONObject.quote(msg ?: code)}}""")
                            }

                            override fun notImplemented() {
                                postResult(wv, cbId, """{"ok":false,"msg":"notImplemented"}""")
                            }
                        },
                    )
                }.onFailure { postResult(wv, cbId, """{"ok":false,"msg":${org.json.JSONObject.quote(it.message ?: "err")}}""") }
            }
        }
    }

    private fun postResult(wv: android.webkit.WebView, cbId: String, json: String) {
        val q = org.json.JSONObject.quote(json)
        wv.post {
            runCatching {
                wv.evaluateJavascript("window.__rowanResult && window.__rowanResult('$cbId', $q)", null)
            }
        }
    }

    private fun defaultHtml(): String = """
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
html,body{margin:0;height:100%;background:transparent;font:13px -apple-system,system-ui,sans-serif}
.card{margin:8px;padding:14px;border-radius:16px;background:rgba(255,255,255,.92);
box-shadow:0 8px 30px rgba(15,23,42,.18);backdrop-filter:blur(18px);color:#334155}
h3{margin:0 0 8px;font-size:14px;color:#0F172A}
p{margin:0;line-height:1.6;color:#64748B;font-size:12px}
kbd{background:#F1F5F9;border-radius:5px;padding:1px 5px;font-size:11px}
</style></head><body>
<div class="card">
<h3>悬浮窗已就绪</h3>
<p>这里还是空的。<br>让 AI 给你建一个界面，例如：<br>
<kbd>「帮我做一个悬浮窗，有 PID 输入框和搜索按钮，点了调用 memScan」</kbd></p>
</div></body></html>
"""

    fun applyPrefs() {
        try {
            val f = java.io.File(filesDir, "overlay.json")
            if (!f.exists()) return
            val o = org.json.JSONObject(f.readText())
            val size = o.optInt("size", 48).coerceIn(24, 96)
            val opacity = o.optDouble("opacity", 0.8).coerceIn(0.2, 1.0)
            val density = resources.displayMetrics.density
            val px = (size * density).toInt()
            bubble?.let { b ->
                val p = b.layoutParams
                if (p != null) {
                    p.width = px
                    p.height = px
                    wm.updateViewLayout(b, p)
                }
                b.alpha = opacity.toFloat()
            }
            // 自定义图标 / 面板背景（Dart 侧复制到固定文件名，存在即应用）
            val iconFile = java.io.File(filesDir, "overlay_icon.png")
            if (iconFile.exists()) {
                val bmp = android.graphics.BitmapFactory.decodeFile(iconFile.absolutePath)
                if (bmp != null) {
                    bubble?.setBackgroundDrawable(android.graphics.drawable.BitmapDrawable(resources, bmp))
                    (bubble as? android.widget.TextView)?.text = ""
                }
            }
            val bgFile = java.io.File(filesDir, "overlay_bg.png")
            if (bgFile.exists()) {
                val bmp = android.graphics.BitmapFactory.decodeFile(bgFile.absolutePath)
                if (bmp != null) {
                    panel?.setBackgroundDrawable(android.graphics.drawable.BitmapDrawable(resources, bmp))
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("OverlayService", "applyPrefs failed", e)
        }
    }

    // ---------- gmem（root helper）----------
    private fun ensureGmem(): String? {
        return try {
            val f = java.io.File(filesDir, "gmem")
            if (!f.exists() || f.length() < 1024) {
                assets.open("gmem").use { inp -> f.outputStream().use { inp.copyTo(it) } }
            }
            f.setExecutable(true)
            f.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("OverlayService", "ensureGmem failed", e)
            null
        }
    }

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    /** 用 gmem（root helper）搜索 32 位整数。 */
    private fun searchWithEngine(pid: Int, value: Int, cb: (String) -> Unit) {
        Thread {
            try {
                val r = gmem("scan $pid i32 $value 60")
                val arr = r?.optJSONArray("hits")
                val out = ArrayList<String>()
                if (arr != null) for (i in 0 until arr.length()) out.add(arr.optString(i))
                val txt = if (out.isEmpty()) "未找到" else out.joinToString("\n")
                mainHandler.post { cb(txt) }
            } catch (e: Throwable) {
                mainHandler.post { cb("root 未授权或 helper 未就绪（${e.message}）") }
            }
        }.start()
    }

    private fun gmem(args: String): org.json.JSONObject? {
        val bin = ensureGmem() ?: return null
        return try {
            val p = ProcessBuilder("su", "-c", "\"$bin\" $args").start()
            val out = p.inputStream.bufferedReader().readText()
            p.waitFor()
            val json = out.lineSequence().lastOrNull { it.trim().startsWith("{") } ?: return null
            org.json.JSONObject(json)
        } catch (e: Exception) {
            android.util.Log.e("OverlayService", "gmem $args failed", e)
            null
        }
    }

    fun showResults(list: List<String>) {
        overlayResults = list
        if (webView != null) {
            hidePanel()
            showPanel()
        }
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        hidePanel()
        bubble?.let { runCatching { wm.removeView(it) } }
        bubble = null
    }

    private fun buildNotification(): android.app.Notification {
        val chId = "rowan_overlay"
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val nm = getSystemService(android.app.NotificationManager::class.java)
            nm.createNotificationChannel(
                android.app.NotificationChannel(chId, "悬浮窗", android.app.NotificationManager.IMPORTANCE_LOW)
            )
        }
        return androidx.core.app.NotificationCompat.Builder(this, chId)
            .setContentTitle("Rowan")
            .setContentText("悬浮窗运行中")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
}

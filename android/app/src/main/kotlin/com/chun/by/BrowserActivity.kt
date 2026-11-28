package com.chun.by

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 内置浏览器：给 AI 做「浏览器自动化」用。
 * AI 打开它 → 用 screenDump/screenTap 操作，或直接调 channel 的 browserNavigate /
 * browserExecJs / browserSnapshot 读写页面。
 * 单例 WebView 常驻，关闭 Activity 只是不可见，页面和 Cookie 状态保留。
 */
object BrowserBridge {
    @JvmStatic
    var webView: WebView? = null
        private set

    @JvmStatic
    var activity: BrowserActivity? = null
        private set

    @JvmStatic
    fun open(url: String?) {
        activity?.let { it.loadUrl(url ?: it.currentUrl()) }
    }

    @JvmStatic
    fun close() {
        activity?.finish()
    }

    /** 同步执行一段 JS，返回结果（用 WebView evaluateJavascript 阻塞等回调）。 */
    @JvmStatic
    fun execJs(js: String): String {
        val wv = webView ?: return "（浏览器没打开）"
        val latch = CountDownLatch(1)
        val holder = StringBuilder()
        wv.post {
            wv.evaluateJavascript(js) { v -> holder.append(v ?: ""); latch.countDown() }
        }
        try { latch.await(10, TimeUnit.SECONDS) } catch (_: Throwable) {}
        return holder.toString()
    }

    /** 拿页面纯文本快照（innerText，截断避免过长）。 */
    @JvmStatic
    fun snapshot(maxLen: Int): String {
        val js = "(function(){var t=document.body?document.body.innerText:'';return t.length>0?t:'（空页面）';})()"
        val r = execJs(js)
        val cleaned = r.trim().removePrefix("\"").removeSuffix("\"")
            .replace("\\n", "\n").replace("\\u0026", "&")
        return if (cleaned.length > maxLen) cleaned.substring(0, maxLen) + "\n…（截断）" else cleaned
    }

    @JvmStatic
    fun title(): String {
        val r = execJs("document.title")
        return r.trim().removePrefix("\"").removeSuffix("\"")
    }
}

class BrowserActivity : Activity() {
    private lateinit var urlBar: EditText
    private lateinit var wv: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        BrowserBridge.activity = this

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF0B1220.toInt())
        }

        // 顶栏：后退 / 前进 / 地址栏 / 执行
        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            gravity = Gravity.CENTER_VERTICAL
        }
        fun btn(label: String, onClick: () -> Unit): TextView {
            return TextView(this).apply {
                text = label
                textSize = 13f
                setTextColor(0xFF4D7CFE.toInt())
                setPadding(dp(10), dp(6), dp(10), dp(6))
                setOnClickListener { onClick() }
            }
        }
        top.addView(btn("←") { if (wv.canGoBack()) wv.goBack() })
        top.addView(btn("→") { if (wv.canGoForward()) wv.goForward() })
        urlBar = EditText(this).apply {
            setSingleLine(true)
            textSize = 13f
            setTextColor(0xFFEAF0FB.toInt())
            hint = "输入网址，回车打开"
            setHintTextColor(0xFF7886A0.toInt())
            setBackgroundColor(0xFF141B2E.toInt())
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        top.addView(urlBar)
        top.addView(btn("↻") { wv.reload() })
        top.addView(btn("✕") { finish() })
        root.addView(top)

        wv = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(0xFFFFFFFF.toInt())
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
                cacheMode = WebSettings.LOAD_DEFAULT
                userAgentString = "Mozilla/5.0 (Linux; Android) Rowan/5.2 Mobile"
            }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    urlBar.setText(url ?: "")
                    urlBar.setSelection(urlBar.text.length)
                }
            }
            webChromeClient = WebChromeClient()
        }
        root.addView(wv, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        BrowserBridge.webView = wv
        setContentView(root)
        val start = intent?.getStringExtra("url")
        if (!start.isNullOrEmpty()) loadUrl(start)
    }

    fun loadUrl(url: String) {
        val u = if (url.startsWith("http://") || url.startsWith("https://")) url
        else "https://$url"
        wv.loadUrl(u)
    }

    fun currentUrl(): String = wv.url ?: ""

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        super.onDestroy()
        BrowserBridge.activity = null
        // WebView 常驻，不销毁，页面状态保留
    }
}

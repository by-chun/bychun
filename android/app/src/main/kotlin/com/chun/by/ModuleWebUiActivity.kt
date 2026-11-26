package com.chun.by

import android.app.Activity
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream

/**
 * 内置打开 Zygisk 模块 WebUI，并注入 ksu.exec / ap.exec 桥（走 su 执行命令）。
 *
 * 页面优先从 APK 内置模块 zip 的 webroot 解出来，保证页面和这里的桥协议是同一版本；
 * /data/adb/modules 里的页面可能还是旧模块装的，协议对不上会一直「读不到状态」。
 */
class ModuleWebUiActivity : Activity() {
    private lateinit var web: WebView
    private var ready = false

    private inner class Bridge {
        /** 老页面用它判断回调协议；新页面另外注入 __ROWAN_BRIDGE__ 标记。 */
        @JavascriptInterface
        fun api(): String = "callback-id"

        @JavascriptInterface
        fun exec(cmd: String, cb: String) {
            val callback = if (Regex("^[A-Za-z0-9_]+$").matches(cb)) cb else ""
            Thread {
                var out = ""
                var err = ""
                var proc: Process? = null
                try {
                    for (bin in listOf("su", "/system/bin/su", "/system/xbin/su")) {
                        try {
                            proc = ProcessBuilder(bin, "-c", cmd).redirectErrorStream(true).start()
                            break
                        } catch (_: Exception) {
                            proc = null
                        }
                    }
                    if (proc == null) {
                        err = "ROWAN_NO_SU"
                    } else {
                        val sb = StringBuilder()
                        val reader = Thread {
                            try {
                                proc.inputStream.bufferedReader().forEachLine { sb.append(it).append('\n') }
                            } catch (_: Exception) {
                            }
                        }
                        reader.start()
                        // 没有 Root 授权时 su 会一直等，必须自己超时，否则页面永远停在「读取中」
                        val done = proc.waitFor(10, TimeUnit.SECONDS)
                        if (!done) {
                            proc.destroy()
                            err = "ROWAN_TIMEOUT"
                        }
                        reader.join(500)
                        out = sb.toString()
                    }
                } catch (e: Exception) {
                    err = e.message ?: "error"
                }
                val o = JSONObject.quote(out)
                val e = JSONObject.quote(err)
                runOnUiThread {
                    if (ready && callback.isNotEmpty()) {
                        runCatching {
                            web.evaluateJavascript(
                                "try{window['$callback'] && window['$callback'](null,$o,$e)}catch(x){}",
                                null,
                            )
                        }
                    }
                }
            }.start()
        }
    }

    /** 把 zip 里的 webroot/ 解到 cache/webui，返回是否解出 index.html。 */
    private fun extractAssetWebroot(dst: File): Boolean {
        return try {
            var found = false
            assets.open("rowan-module.zip").use { inp ->
                ZipInputStream(inp).use { zip ->
                    var entry = zip.nextEntry
                    while (entry != null) {
                        val name = entry.name
                        if (!entry.isDirectory && name.startsWith("webroot/")) {
                            val rel = name.removePrefix("webroot/")
                            val f = File(dst, rel)
                            f.parentFile?.mkdirs()
                            f.outputStream().use { o -> zip.copyTo(o) }
                            if (rel == "index.html") found = true
                        }
                        zip.closeEntry()
                        entry = zip.nextEntry
                    }
                }
            }
            found
        } catch (_: Exception) {
            false
        }
    }

    private fun copyInstalledWebroot(dst: File): Boolean {
        return try {
            val p = ProcessBuilder(
                "su", "-c",
                "cp -r /data/adb/modules/rowan/webroot/. ${dst.absolutePath}/"
            ).redirectErrorStream(true).start()
            p.waitFor(30, TimeUnit.SECONDS)
            File(dst, "index.html").exists()
        } catch (_: Exception) {
            false
        }
    }

    private fun prepareWebroot(): File? {
        val dst = File(cacheDir, "webui")
        dst.deleteRecursively()
        dst.mkdirs()
        if (!extractAssetWebroot(dst) && !copyInstalledWebroot(dst)) return null
        return dst.takeIf { File(it, "index.html").exists() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dir = prepareWebroot()
        if (dir == null) {
            val tv = android.widget.TextView(this).apply {
                text = "读不到模块 WebUI\n请先安装 Rowan Frida 模块，或从管理器里打开"
                textSize = 14f
                setPadding(48, 120, 48, 0)
            }
            setContentView(tv)
            return
        }
        ready = true
        web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.allowFileAccess = true
        web.settings.allowContentAccess = true
        web.addJavascriptInterface(Bridge(), "ksu")
        web.webViewClient = WebViewClient()

        // 注入标记，页面据此确定用「回调函数名」协议，不再依赖 api() 是否可用
        val html = File(dir, "index.html").readText()
        val marked = if (html.contains("<head>")) {
            html.replaceFirst("<head>", "<head><script>window.__ROWAN_BRIDGE__=1;</script>")
        } else {
            "<script>window.__ROWAN_BRIDGE__=1;</script>$html"
        }
        web.loadDataWithBaseURL("https://rowan.local/", marked, "text/html", "utf-8", null)
        setContentView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    override fun onDestroy() {
        super.onDestroy()
        ready = false
        runCatching { web.destroy() }
    }
}

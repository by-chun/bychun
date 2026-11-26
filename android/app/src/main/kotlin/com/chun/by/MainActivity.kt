package com.chun.by

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.os.Build
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : com.ryanheise.audioservice.AudioServiceActivity() {

    private var pendingPick: io.flutter.plugin.common.MethodChannel.Result? = null
    private var vpnPending: io.flutter.plugin.common.MethodChannel.Result? = null
    private var nativeChannel: MethodChannel? = null
    private var chatOverlay: AiChatOverlay? = null

    /** AI 对话浮窗：按需创建，事件回传给 Flutter（send / stop）。 */
    private fun ensureChatOverlay(): AiChatOverlay {
        chatOverlay?.let { return it }
        val o = AiChatOverlay(this) { type, data ->
            runOnUiThread {
                nativeChannel?.invokeMethod(
                    "chatOverlayEvent",
                    mapOf("type" to type, "data" to data),
                )
            }
        }
        chatOverlay = o
        return o
    }
    private var streamSink: EventChannel.EventSink? = null
    private var readAssetResult: io.flutter.plugin.common.MethodChannel.Result? = null
    private var mediaProjection: android.media.projection.MediaProjection? = null
    private var projectionPending: io.flutter.plugin.common.MethodChannel.Result? = null
    private var projectionAction: String? = null
    private var virtualDisplay: android.hardware.display.VirtualDisplay? = null
    private var mediaRecorder: android.media.MediaRecorder? = null
    private var recordingFile: java.io.File? = null

    override fun onPostResume() {
        super.onPostResume()
        runCatching {
            com.chun.by.OverlayService.instance?.attachBridge(flutterEngine!!.dartExecutor.binaryMessenger)
        }
    }

    /** 根据 ELF e_machine 判定架构名。 */
    private fun archOf(f: java.io.File): String = when (ElfVaddr.machine(f)) {
        0x3E -> "x86_64"
        0x03 -> "x86"
        0x28 -> "arm"
        else -> "arm64"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        installCrashLogger()
        runCatching { com.chun.by.CaptureServer.start(8899) }
        // 部分 ROM（如 ColorOS）会忽略主题里的状态栏设置，这里强制透明 + 深色图标。
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.WHITE
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            )
    }


    private val executor = Executors.newCachedThreadPool()
    private var terminalSink: EventChannel.EventSink? = null

    /** 主线程回 MethodChannel 结果；重复回复/通道已关闭时不能把异常抛到主线程。 */
    private fun safeSuccess(r: io.flutter.plugin.common.MethodChannel.Result, v: Any?) {
        try {
            r.success(v)
        } catch (_: Throwable) {
        }
    }

    /** 向 EventChannel 推事件；订阅已取消时忽略。 */
    private fun addStreamEvent(v: Any) {
        try {
            streamSink?.success(v)
        } catch (_: Throwable) {
        }
    }

    private fun safeError(
        r: io.flutter.plugin.common.MethodChannel.Result,
        code: String,
        msg: String?,
        details: Any?,
    ) {
        try {
            r.error(code, msg, details)
        } catch (_: Throwable) {
        }
    }

    override fun getBackgroundMode(): io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode =
        io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.chun.by/terminal_view", TerminalPlatformViewFactory())
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.chun.by/terminal").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { terminalSink = events }
                override fun onCancel(arguments: Any?) { terminalSink = null }
            },
        )
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "rowan/stream").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    streamSink = events
                }

                override fun onCancel(arguments: Any?) {
                    streamSink = null
                }
            },
        )
        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        nativeChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "exec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        val timeout = call.argument<Int>("timeout") ?: 15
                        executor.execute {
                            val r = runShell(cmd, timeout)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "rootExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        executor.execute {
                            val r = runSu(cmd)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "prootExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        executor.execute {
                            val r = ProotLauncher.exec(this, cmd)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "exportJson" -> {
                        val name = call.argument<String>("name") ?: "rowan-export.json"
                        val content = call.argument<String>("content") ?: ""
                        val ok = try {
                            val dir = android.os.Environment.getExternalStoragePublicDirectory(
                                android.os.Environment.DIRECTORY_DOWNLOADS)
                            dir.mkdirs()
                            val f = java.io.File(dir, name)
                            f.writeText(content)
                            true
                        } catch (e: Throwable) {
                            android.util.Log.e("MainActivity", "exportJson failed", e)
                            false
                        }
                        safeSuccess(result, ok)
                    }
                    "pickTextFile" -> {
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "*/*"))
                            }
                            startActivityForResult(intent, 4712)
                            pendingPick = result
                        } catch (e: Throwable) {
                            safeSuccess(result, null)
                        }
                    }
                    "logShow" -> {
                        val title = call.argument<String>("title") ?: "实时输出"
                        runOnUiThread { com.chun.by.OverlayService.instance?.showLog(title) }
                        safeSuccess(result, true)
                    }
                    "logLine" -> {
                        val line = call.argument<String>("line") ?: ""
                        runOnUiThread { com.chun.by.OverlayService.instance?.pushLog(line) }
                        safeSuccess(result, true)
                    }
                    "logHide" -> {
                        runOnUiThread { com.chun.by.OverlayService.instance?.hideLog() }
                        safeSuccess(result, true)
                    }
                    "screenEnabled" -> {
                        safeSuccess(result, ScreenReaderService.instance != null)
                    }
                    "screenOpenSettings" -> {
                        ScreenReaderService.openSettings(this)
                        safeSuccess(result, true)
                    }
                    "screenDump" -> {
                        val nodes = ScreenReaderService.instance?.dumpNodes() ?: emptyList<Map<String, Any?>>()
                        safeSuccess(result, nodes)
                    }
                    "screenShot" -> {
                        executor.execute {
                            var bytes = ScreenReaderService.instance?.captureScreenshot()
                            if (bytes == null) {
                                val f = java.io.File(cacheDir, "shot_tmp.png")
                                val r = runSu("screencap -p '${f.absolutePath}' && chmod 644 '${f.absolutePath}' && echo OK")
                                if ((r["stdout"] as? String).orEmpty().contains("OK") && f.exists()) {
                                    bytes = f.readBytes()
                                }
                                f.delete()
                            }
                            runOnUiThread { safeSuccess(result, bytes) }
                        }
                    }
                    "screenTap" -> {
                        val x = call.argument<Int>("x") ?: 0
                        val y = call.argument<Int>("y") ?: 0
                        safeSuccess(result, ScreenReaderService.instance?.tapAt(x, y) ?: false)
                    }
                    "screenSwipe" -> {
                        val x1 = call.argument<Int>("x1") ?: 0
                        val y1 = call.argument<Int>("y1") ?: 0
                        val x2 = call.argument<Int>("x2") ?: 0
                        val y2 = call.argument<Int>("y2") ?: 0
                        val ms = call.argument<Long>("ms") ?: 300L
                        safeSuccess(result, ScreenReaderService.instance?.swipe(x1, y1, x2, y2, ms) ?: false)
                    }
                    "screenType" -> {
                        val text = call.argument<String>("text") ?: ""
                        safeSuccess(result, ScreenReaderService.instance?.typeText(text) ?: false)
                    }
                    "projectShot" -> {
                        // 截图：已有投影直接抓帧，否则先请求录屏授权
                        if (mediaProjection != null) {
                            safeSuccess(result, captureProjectionFrame())
                        } else {
                            projectionPending = result
                            projectionAction = "shot"
                            requestProjection()
                        }
                    }
                    "recordStart" -> {
                        if (mediaProjection != null) {
                            safeSuccess(result, startRecording())
                        } else {
                            projectionPending = result
                            projectionAction = "record"
                            requestProjection()
                        }
                    }
                    "recordStop" -> {
                        safeSuccess(result, stopRecording())
                    }
                    "terminalPaths" -> {
                        runOnUiThread {
                            val ok = ProotLauncher.prepare(this)
                            safeSuccess(result, 
                                mapOf(
                                    "ok" to ok,
                                    "proot" to ProotLauncher.prootBin(this),
                                    "rootfs" to ProotLauncher.rootfs(this),
                                    "libs" to applicationInfo.nativeLibraryDir,
                                    "tmp" to java.io.File(filesDir, "tmp").apply { mkdirs() }.absolutePath,
                                )
                            )
                        }
                    }
                    "killAllProcs" -> {
                        ProotLauncher.killAll()
                        safeSuccess(result, true)
                    }
                    "killStream" -> {
                        val tag = call.argument<String>("tag") ?: ""
                        if (tag.isNotEmpty()) ProotLauncher.killStream(tag)
                        safeSuccess(result, true)
                    }
                    "streamExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        val tag = call.argument<String>("tag") ?: "stream"
                        val outBuf = StringBuilder()
                        ProotLauncher.execStream(
                            this,
                            cmd,
                            tag = tag,
                            onLine = { line ->
                                outBuf.append(line).append('\n')
                                runOnUiThread {
                                    addStreamEvent(mapOf("tag" to tag, "line" to line))
                                }
                            },
                            onDone = { code ->
                                appendAiLog(cmd, outBuf.toString(), code)
                                runOnUiThread {
                                    addStreamEvent(mapOf("tag" to tag, "done" to true, "code" to code))
                                    safeSuccess(result, code)
                                }
                            },
                        )
                    }
                    "writeAppFile" -> {
                        val name = call.argument<String>("name") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        val rel = name.trimStart('/')
                        if (rel.isEmpty() || rel.contains("..")) {
                            safeSuccess(result, false)
                        } else {
                            try {
                                val f = java.io.File(filesDir, rel)
                                f.parentFile?.mkdirs()
                                f.writeText(content)
                                safeSuccess(result, true)
                            } catch (e: Throwable) {
                                safeSuccess(result, false)
                            }
                        }
                    }
                    "readAppFile" -> {
                        val name = call.argument<String>("name") ?: ""
                        val rel = name.trimStart('/')
                        if (rel.isEmpty() || rel.contains("..")) {
                            safeSuccess(result, null)
                        } else {
                            try {
                                val f = java.io.File(filesDir, rel)
                                safeSuccess(result, if (f.exists()) f.readText() else null)
                            } catch (e: Throwable) {
                                safeSuccess(result, null)
                            }
                        }
                    }
                    "listAppDir" -> {
                        val name = call.argument<String>("name") ?: ""
                        try {
                            val dir = if (name.isEmpty()) filesDir else java.io.File(filesDir, name.trimStart('/'))
                            safeSuccess(result, (dir.list() ?: emptyArray()).joinToString("\n"))
                        } catch (e: Throwable) {
                            safeSuccess(result, "")
                        }
                    }
                    "captureLog" -> {
                        val limit = call.argument<Int>("limit") ?: 50
                        safeSuccess(result, CaptureServer.listJson(0, limit))
                    }
                    "captureClear" -> {
                        CaptureServer.clear()
                        safeSuccess(result, true)
                    }
                    "runJavaOverlay" -> {
                        val dex = call.argument<String>("dex") ?: ""
                        val cls = call.argument<String>("className") ?: ""
                        executor.execute {
                            val r = JavaPlugin.run(this, dex, cls)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "chatOverlayShow" -> {
                        ensureChatOverlay().show()
                        safeSuccess(result, true)
                    }
                    "chatOverlayMinimize" -> {
                        val f = com.chun.by.FloatingChatService(this)
                        f.onEvent = { type, data ->
                            val text = when (type) {
                                "send" -> (data?.get("text") as? String) ?: ""
                                "action" -> {
                                    val a = (data?.get("action") as? String) ?: ""
                                    val args = (data?.get("args") as? Map<*, *>) ?: emptyMap<Any, Any>()
                                    if (args.isEmpty()) a else "$a: ${args.entries.joinToString(" ") { "${it.key}=${it.value}" }}"
                                }
                                else -> ""
                            }
                            if (text.isNotEmpty()) {
                                runOnUiThread {
                                    nativeChannel?.invokeMethod(
                                        "chatOverlayEvent",
                                        mapOf("type" to "send", "data" to text),
                                    )
                                }
                            }
                        }
                        f.show()
                        moveTaskToBack(true)
                        safeSuccess(result, true)
                    }
                    "chatOverlayHide" -> {
                        chatOverlay?.hide()
                        safeSuccess(result, true)
                    }
                    "chatOverlayState" -> {
                        val t = call.argument<String>("text") ?: ""
                        chatOverlay?.setState(t)
                        com.chun.by.FloatingChatService.instance?.pushState(t)
                        safeSuccess(result, true)
                    }
                    "chatOverlayPush" -> {
                        val role = call.argument<String>("role") ?: "assistant"
                        val text = call.argument<String>("text") ?: ""
                        ensureChatOverlay().push(role, text)
                        com.chun.by.FloatingChatService.instance?.push(role, text)
                        safeSuccess(result, true)
                    }
                    "overlayHtml" -> {
                        val html = call.argument<String>("html") ?: ""
                        runOnUiThread {
                            com.chun.by.OverlayService.instance?.setHtml(html)
                        }
                        safeSuccess(result, true)
                    }
                    "containerWrite" -> {
                        val path = call.argument<String>("path") ?: ""
                        val content = call.argument<String>("content") ?: ""
                        try {
                            val root = java.io.File(ProotLauncher.rootfs(this))
                            val f = java.io.File(root, path.trimStart('/'))
                            f.parentFile?.mkdirs()
                            f.writeText(content)
                            safeSuccess(result, true)
                        } catch (e: Throwable) {
                            safeSuccess(result, false)
                        }
                    }
                    "setOverlayPref" -> {
                        val size = call.argument<Int>("size") ?: 48
                        val opacity = call.argument<Double>("opacity") ?: 0.8
                        executor.execute {
                            try {
                                val f = java.io.File(filesDir, "overlay.json")
                                val o = org.json.JSONObject()
                                o.put("size", size)
                                o.put("opacity", opacity)
                                f.writeText(o.toString())
                                runOnUiThread { OverlayService.instance?.applyPrefs() }
                                runOnUiThread { safeSuccess(result, true) }
                            } catch (e: Exception) {
                                runOnUiThread { safeError(result, "FAIL", e.message, null) }
                            }
                        }
                    }
                    "disasmMem" -> {
                        // 对运行中进程的某个地址反汇编：gmem 读内存 -> Capstone
                        val pid = call.argument<Int>("pid") ?: 0
                        val addrStr = call.argument<String>("addr") ?: "0"
                        val count = call.argument<Int>("count") ?: 40
                        executor.execute {
                            try {
                                val gmem = java.io.File(filesDir, "gmem")
                                if (!gmem.exists()) {
                                    runOnUiThread { safeError(result, "NO_HELPER", "gmem 未释放", null) }
                                    return@execute
                                }
                                val addr = addrStr.removePrefix("0x").toLong(16)
                                val need = count * 4
                                val p = ProcessBuilder("su", "-c", "\"${gmem.absolutePath}\" read $pid ${java.lang.Long.toHexString(addr)} $need").start()
                                val out = p.inputStream.bufferedReader().readText()
                                p.waitFor()
                                val jo = org.json.JSONObject(out.lines().lastOrNull { it.trim().startsWith("{") } ?: "{}")
                                val hex = jo.optString("hex")
                                if (hex.length < 8) {
                                    runOnUiThread { safeError(result, "READ_FAIL", "读内存失败（root？）", null) }
                                    return@execute
                                }
                                val bytes = ByteArray(hex.length / 2) { i ->
                                    hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
                                }
                                if (!NativeDisasm.available) {
                                    runOnUiThread { safeError(result, "NO_ENGINE", "disasm 未加载", null) }
                                    return@execute
                                }
                                val json = NativeDisasm.disasm(bytes, addr, count, 0, "arm64")
                                runOnUiThread { safeSuccess(result, json) }
                            } catch (e: Throwable) {
                                runOnUiThread { safeError(result, "FAIL", e.message ?: "error", null) }
                            }
                        }
                    }
                    "assemble" -> {
                        val asmText = call.argument<String>("asm") ?: ""
                        val addr = call.argument<String>("addr") ?: "0"
                        val arch = call.argument<String>("arch") ?: "arm64"
                        executor.execute {
                            try {
                                if (!NativeAsm.available) {
                                    runOnUiThread { safeError(result, "NO_ENGINE", "asm 库未加载", null) }
                                    return@execute
                                }
                                val a = addr.removePrefix("0x").toLong(16)
                                val json = NativeAsm.assemble(asmText, a, arch)
                                runOnUiThread { safeSuccess(result, json) }
                            } catch (e: Throwable) {
                                runOnUiThread { safeError(result, "FAIL", e.message ?: "error", null) }
                            }
                        }
                    }
                    "disasm" -> {
                        // param: path(so 绝对路径), vaddr(十六进制字符串), count
                        val path = call.argument<String>("path") ?: ""
                        val vaddrStr = call.argument<String>("vaddr") ?: ""
                        val count = call.argument<Int>("count") ?: 200
                        executor.execute {
                            try {
                                if (!NativeDisasm.available) {
                                    runOnUiThread { safeError(result, "NO_ENGINE", "disasm 库未加载", null) }
                                    return@execute
                                }
                                val f = java.io.File(path)
                                if (!f.exists()) {
                                    runOnUiThread { safeError(result, "NO_FILE", "文件不存在: $path", null) }
                                    return@execute
                                }
                                val addr = vaddrStr.removePrefix("0x").toLong(16)
                                val segs = ElfVaddr.segments(f)
                                val off = ElfVaddr.toFileOffset(segs, addr)
                                if (off == null) {
                                    runOnUiThread { safeError(result, "NO_SEG", "地址不在任何可加载段: $vaddrStr", null) }
                                    return@execute
                                }
                                val bytes = ElfVaddr.readAt(f, off, count * 4)
                                if (bytes == null || bytes.isEmpty()) {
                                    runOnUiThread { safeError(result, "NO_DATA", "读不到代码", null) }
                                    return@execute
                                }
                                val json = NativeDisasm.disasm(bytes, addr, count, 0, archOf(f))
                                runOnUiThread { safeSuccess(result, json) }
                            } catch (e: Throwable) {
                                runOnUiThread { safeError(result, "FAIL", e.message ?: "error", null) }
                            }
                        }
                    }
                    "nativeLibDir" -> runOnUiThread { safeSuccess(result, applicationInfo.nativeLibraryDir) }
                    "openModuleWebUi" -> runOnUiThread {
                        startActivity(Intent(this, ModuleWebUiActivity::class.java))
                        safeSuccess(result, true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        executor.execute {
                            val r = runSu("pm install -r \"$path\"")
                            val out = (((r["stdout"] as? String) ?: "") + ((r["stderr"] as? String) ?: "")).trim()
                            runOnUiThread {
                                safeSuccess(result, mapOf("ok" to ((r["code"] as? Int ?: 1) == 0), "msg" to out))
                            }
                        }
                    }
                    "readAsset" -> {
                        val name = call.argument<String>("name") ?: ""
                        executor.execute {
                            try {
                                val bytes = assets.open(name).use { it.readBytes() }
                                runOnUiThread { safeSuccess(result, bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { safeSuccess(result, null) }
                            }
                        }
                    }
                    "decodeText" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        val charset = call.argument<String>("charset") ?: "UTF-8"
                        executor.execute {
                            val s = try {
                                String(bytes, java.nio.charset.Charset.forName(charset))
                            } catch (e: Exception) {
                                String(bytes)
                            }
                            runOnUiThread { safeSuccess(result, s) }
                        }
                    }
                    "openTerminal" -> runOnUiThread {
                        startActivity(android.content.Intent(this, TerminalActivity::class.java))
                        safeSuccess(result, true)
                    }
                    "pickFile" -> runOnUiThread {
                        pendingPick = result
                        val i = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        startActivityForResult(i, 1001)
                    }
                    "home" -> runOnUiThread { safeSuccess(result, System.getProperty("user.home") ?: "/") }
                    "openOverlaySettings" -> runOnUiThread {
                        val i = Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName"))
                        startActivity(i)
                        safeSuccess(result, true)
                    }
                    "openSettings" -> {
                        val kind = call.argument<String>("kind") ?: ""
                        try {
                            if (kind == "vpn") {
                                val prep = android.net.VpnService.prepare(this)
                                if (prep != null) startActivityForResult(prep, 1101)
                                safeSuccess(result, true)
                            } else {
                                val i = when (kind) {
                                    "unknownSources" -> Intent(
                                        android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        android.net.Uri.parse("package:$packageName"),
                                    )
                                    "battery" -> Intent(
                                        android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        android.net.Uri.parse("package:$packageName"),
                                    )
                                    "usage" -> Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                    "overlay" -> Intent(
                                        android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                        android.net.Uri.parse("package:$packageName"),
                                    )
                                    "appDetails" -> Intent(
                                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        android.net.Uri.parse("package:$packageName"),
                                    )
                                    else -> null
                                }
                                if (i != null) {
                                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(i)
                                }
                                safeSuccess(result, i != null)
                            }
                        } catch (e: Exception) {
                            safeSuccess(result, false)
                        }
                    }
                    "requestMedia" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 33) {
                                requestPermissions(
                                    arrayOf(
                                        "android.permission.READ_MEDIA_IMAGES",
                                        "android.permission.READ_MEDIA_VIDEO",
                                        "android.permission.READ_MEDIA_AUDIO",
                                    ), 1102,
                                )
                            } else {
                                requestPermissions(arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE), 1102)
                            }
                            safeSuccess(result, true)
                        } catch (e: Exception) {
                            safeSuccess(result, false)
                        }
                    }
                    "permStatus" -> executor.execute {
                        fun granted(p: String) =
                            checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        val overlay = android.provider.Settings.canDrawOverlays(this)
                        val storage = granted(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                        val allFiles = Build.VERSION.SDK_INT < 30 || android.os.Environment.isExternalStorageManager()
                        val notif = if (Build.VERSION.SDK_INT >= 33)
                            granted(android.Manifest.permission.POST_NOTIFICATIONS)
                        else true
                        val installPkgs = packageManager.canRequestPackageInstalls()
                        val battery = (getSystemService(android.os.PowerManager::class.java))?.isIgnoringBatteryOptimizations(packageName) ?: false
                        val usageStats = try {
                            val am = getSystemService(android.app.AppOpsManager::class.java)
                            am.unsafeCheckOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName) == android.app.AppOpsManager.MODE_ALLOWED
                        } catch (e: Exception) { false }
                        val mediaImages = if (Build.VERSION.SDK_INT >= 33)
                            granted("android.permission.READ_MEDIA_IMAGES") else storage
                        val mediaVideo = if (Build.VERSION.SDK_INT >= 33)
                            granted("android.permission.READ_MEDIA_VIDEO") else storage
                        val mediaAudio = if (Build.VERSION.SDK_INT >= 33)
                            granted("android.permission.READ_MEDIA_AUDIO") else storage
                        val root = ((runSu("id")["stdout"] as? String) ?: "").contains("uid=0")
                        val shizuku = try { ShizukuBridge.available() } catch (e: Exception) { false }
                        runOnUiThread {
                            safeSuccess(result, mapOf(
                                "overlay" to overlay,
                                "storage" to storage,
                                "allFiles" to allFiles,
                                "notification" to notif,
                                "root" to root,
                                "installPackages" to installPkgs,
                                "battery" to battery,
                                "usageStats" to usageStats,
                                "mediaImages" to mediaImages,
                                "mediaVideo" to mediaVideo,
                                "mediaAudio" to mediaAudio,
                                "shizuku" to shizuku,
                                "accessibility" to (ScreenReaderService.instance != null),
                                "vpn" to (android.net.VpnService.prepare(this) == null),
                            ))
                        }
                    }
                    "installFridaModule" -> {
                        val manager = call.argument<String>("manager") ?: "auto"
                        executor.execute {
                            val r = installFridaModule(manager)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "termKey" -> {
                        val data = call.argument<String>("data") ?: ""
                        executor.execute { TerminalSessionManager.current?.write(data) }
                        safeSuccess(result, true)
                    }
                    "overlayResults" -> {
                        val list = call.argument<List<String>>("list") ?: emptyList<String>()
                        runOnUiThread { OverlayService.instance?.showResults(list) }
                        safeSuccess(result, OverlayService.instance != null)
                    }
                    "requestPermissions" -> {
                        // 只在确实没权限时才弹，避免每次都跳。
                        val hasAllFiles = Build.VERSION.SDK_INT < 30 || android.os.Environment.isExternalStorageManager()
                        val perms = mutableListOf<String>()
                        if (Build.VERSION.SDK_INT >= 33) {
                            if (checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) != android.content.pm.PackageManager.PERMISSION_GRANTED)
                                perms += android.Manifest.permission.READ_MEDIA_IMAGES
                            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
                                perms += android.Manifest.permission.POST_NOTIFICATIONS
                        } else {
                            if (checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED)
                                perms += android.Manifest.permission.READ_EXTERNAL_STORAGE
                        }
                        if (!hasAllFiles && Build.VERSION.SDK_INT >= 30) {
                            try {
                                startActivity(Intent(
                                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    android.net.Uri.parse("package:$packageName")))
                            } catch (_: Exception) {}
                        }
                        if (perms.isNotEmpty()) requestPermissions(perms.toTypedArray(), 2001)
                        // targetSdk < 33 时系统不会弹通知权限框，只能跳系统通知设置
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            try {
                                startActivity(Intent(
                                    android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS,
                                    android.net.Uri.parse("package:$packageName"),
                                ).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName))
                            } catch (_: Exception) {}
                        }
                        runOnUiThread { safeSuccess(result, true) }
                    }
                    "ptyOpen" -> {
                        val shell = call.argument<String>("shell") ?: "/system/bin/sh"
                        if (!PtyBridge.available) runOnUiThread { safeError(result, "NO_PTY", "pty 未编译", null) }
                        else runOnUiThread { safeSuccess(result, PtyBridge.open(shell)) }
                    }
                    "ptyWrite" -> {
                        val fd = call.argument<Int>("fd") ?: -1
                        val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                        runOnUiThread { safeSuccess(result, PtyBridge.write(fd, data)) }
                    }
                    "ptyRead" -> {
                        val fd = call.argument<Int>("fd") ?: -1
                        val size = call.argument<Int>("size") ?: 4096
                        executor.execute {
                            val b = PtyBridge.read(fd, size)
                            runOnUiThread { safeSuccess(result, b) }
                        }
                    }
                    "ptyClose" -> {
                        val fd = call.argument<Int>("fd") ?: -1
                        runOnUiThread { PtyBridge.close(fd); safeSuccess(result, true) }
                    }
                    "listApps" -> executor.execute {
                        val r = listApps()
                        runOnUiThread { safeSuccess(result, r) }
                    }
                    "zipList" -> {
                        val p = call.argument<String>("path")
                        executor.execute {
                            val r = zipList(p)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "zipRead" -> {
                        val p = call.argument<String>("path")
                        val e = call.argument<String>("entry")
                        val m = call.argument<Int>("max") ?: 1048576
                        executor.execute {
                            val r = zipRead(p, e, m)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "shizukuAvailable" -> runOnUiThread { safeSuccess(result, ShizukuBridge.available()) }
                    "shizukuPermission" -> runOnUiThread { safeSuccess(result, ShizukuBridge.hasPermission()) }
                    "shizukuRequest" -> runOnUiThread { ShizukuBridge.request(); safeSuccess(result, true) }
                    "shizukuExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        executor.execute { val r = ShizukuBridge.exec(cmd); runOnUiThread { safeSuccess(result, r) } }
                    }
                    "rootCheck" -> executor.execute {
                        val r = runSu("id")
                        val ok = ((r["stdout"] as? String) ?: "").contains("uid=0")
                        runOnUiThread { safeSuccess(result, ok) }
                    }
                    "memoryAvailable" -> runOnUiThread { safeSuccess(result, NativeMemory.available) }
                    "memoryRead" -> {
                        val pid = call.argument<Int>("pid") ?: -1
                        val addr = call.argument<Long>("addr") ?: 0L
                        val size = call.argument<Int>("size") ?: 256
                        executor.execute { val b = NativeMemory.readMem(pid, addr, size); runOnUiThread { safeSuccess(result, b) } }
                    }
                    "memoryWrite" -> {
                        val pid = call.argument<Int>("pid") ?: -1
                        val addr = call.argument<Long>("addr") ?: 0L
                        val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                        executor.execute { val ok = NativeMemory.writeMem(pid, addr, data); runOnUiThread { safeSuccess(result, ok) } }
                    }
                    "memoryScan" -> {
                        val pid = call.argument<Int>("pid") ?: -1
                        val value = call.argument<Int>("value") ?: 0
                        executor.execute { val r = NativeMemory.scan(pid, value); runOnUiThread { safeSuccess(result, r) } }
                    }
                    "memoryPointerScan" -> {
                        val pid = call.argument<Int>("pid") ?: -1
                        val target = call.argument<Long>("target") ?: 0L
                        executor.execute { val r = NativeMemory.pointerScan(pid, target); runOnUiThread { safeSuccess(result, r) } }
                    }
                    "memoryPatch" -> {
                        val pid = call.argument<Int>("pid") ?: -1
                        val addr = call.argument<Long>("addr") ?: 0L
                        val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                        executor.execute { val ok = NativeMemory.patchBytes(pid, addr, data); runOnUiThread { safeSuccess(result, ok) } }
                    }
                    "prootExec" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        executor.execute {
                            val r = if (ProotLauncher.isReady(this)) ProotLauncher.exec(this, cmd) else runShell(cmd, 60)
                            runOnUiThread { safeSuccess(result, r) }
                        }
                    }
                    "prootReady" -> runOnUiThread { safeSuccess(result, ProotLauncher.isReady(this)) }
                    "vpnStart" -> runOnUiThread {
                        val prep = android.net.VpnService.prepare(this)
                        if (prep != null) {
                            vpnPending = result
                            startActivityForResult(prep, 4720)
                        } else {
                            startVpnService()
                            // 服务异步启动，稍等再读状态（否则 running 还是 false）
                            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                safeSuccess(result, mapOf(
                                    "ok" to true,
                                    "running" to DnsVpnService.runningNow,
                                    "dns" to DnsVpnService.upstreamDns,
                                    "auto" to DnsVpnService.autoDetected,
                                    "needDns" to DnsVpnService.noDns,
                                ))
                            }, 700)
                        }
                    }
                    "vpnStatus" -> safeSuccess(result, mapOf(
                        "running" to DnsVpnService.runningNow,
                        "dns" to DnsVpnService.upstreamDns,
                        "auto" to DnsVpnService.autoDetected,
                        "needDns" to DnsVpnService.noDns,
                    ))
                    "vpnSetDns" -> {
                        val d = call.argument<String>("dns")?.trim().orEmpty()
                        if (d.isEmpty()) {
                            safeSuccess(result, mapOf("ok" to false, "error" to "dns 为空"))
                        } else {
                            runCatching {
                                startService(Intent(this, DnsVpnService::class.java)
                                    .setAction(DnsVpnService.ACTION_SET_DNS)
                                    .putExtra("dns", d))
                            }
                            // 如果 VPN 还没跑起来（上次因缺 DNS 退出），用新 DNS 重新启动
                            runCatching { stopService(Intent(this, DnsVpnService::class.java).setAction(DnsVpnService.ACTION_STOP)) }
                            startVpnService()
                            safeSuccess(result, mapOf("ok" to true, "dns" to d))
                        }
                    }
                    "vpnStop" -> {
                        stopService(Intent(this, DnsVpnService::class.java).setAction(DnsVpnService.ACTION_STOP))
                        safeSuccess(result, true)
                    }
                    "vpnLog" -> executor.execute {
                        val f = DnsVpnService.logFile(filesDir)
                        val text = runCatching { if (f.exists()) f.readText() else "" }.getOrDefault("")
                        runOnUiThread { safeSuccess(result, text) }
                    }
                    "vpnClear" -> {
                        runCatching { DnsVpnService.logFile(filesDir).delete() }
                        safeSuccess(result, true)
                    }
                    "caInstall" -> executor.execute {
                        val log = StringBuilder()
                        val ok = CaInstaller.installToSystem(this) { line ->
                            synchronized(log) { log.appendLine(line) }
                        }
                        runOnUiThread { safeSuccess(result, mapOf("ok" to ok, "log" to log.toString())) }
                    }
                    "caStatus" -> executor.execute {
                        val cert = CaInstaller.ensureCa(this)
                        runOnUiThread {
                            safeSuccess(result, 
                                mapOf(
                                    "hash" to (cert?.let { CaInstaller.subjectHash(it) } ?: ""),
                                    "pem" to (cert?.let { CaInstaller.pem(it) } ?: ""),
                                )
                            )
                        }
                    }
                    "envList" -> runOnUiThread { safeSuccess(result, ProotLauncher.envInfo(this)) }
                    "envCurrent" -> runOnUiThread { safeSuccess(result, ProotLauncher.currentEnv(this)) }
                    "envSet" -> {
                        val env = call.argument<String>("env") ?: ""
                        ProotLauncher.setCurrentEnv(this, env)
                        runOnUiThread { safeSuccess(result, true) }
                    }
                    "envRemove" -> executor.execute {
                        val env = call.argument<String>("env") ?: ""
                        val ok = ProotLauncher.removeEnv(this, env)
                        runOnUiThread { safeSuccess(result, ok) }
                    }
                    "envInstallUrl" -> executor.execute {
                        val url = call.argument<String>("url") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val log = StringBuilder()
                        val ok = ProotLauncher.installFromUrl(this, url, name) { line ->
                            synchronized(log) { log.appendLine(line) }
                        }
                        runOnUiThread { safeSuccess(result, mapOf("ok" to ok, "log" to log.toString())) }
                    }
                    "envImport" -> executor.execute {
                        val path = call.argument<String>("path") ?: ""
                        val env = call.argument<String>("env") ?: ""
                        val log = StringBuilder()
                        val ok = ProotLauncher.importTar(this, java.io.File(path), env) { line ->
                            synchronized(log) { log.appendLine(line) }
                        }
                        runOnUiThread { safeSuccess(result, mapOf("ok" to ok, "log" to log.toString())) }
                    }
                    "appDataDir" -> runOnUiThread { safeSuccess(result, filesDir.absolutePath) }
                    "prootPrepare" -> executor.execute {
                        val ok = ProotLauncher.prepare(this)
                        runOnUiThread { safeSuccess(result, ok) }
                    }
                    "showOverlay" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !android.provider.Settings.canDrawOverlays(this)
                        ) {
                            runOnUiThread {
                                startActivity(android.content.Intent(
                                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    android.net.Uri.parse("package:$packageName"),
                                ))
                                safeError(result, "NO_PERMISSION", "需要悬浮窗权限（已打开设置）", null)
                            }
                        } else {
                            runOnUiThread {
                                try {
                                    val intent = Intent(this, OverlayService::class.java)
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                                    safeSuccess(result, true)
                                } catch (e: Exception) {
                                    safeError(result, "FAIL", "启动悬浮窗失败: ${e.message}", null)
                                }
                            }
                        }
                    }
                    "hideOverlay" -> {
                        stopService(Intent(this, OverlayService::class.java))
                        runOnUiThread { safeSuccess(result, true) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listApps(): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        try {
            val pm = packageManager
            for (ai in pm.getInstalledApplications(0)) {
                val isSystem = (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                val apk = ai.publicSourceDir ?: ""
                val size = try { java.io.File(apk).length() } catch (e: Exception) { 0L }
                out.add(
                    mapOf(
                        "label" to pm.getApplicationLabel(ai).toString(),
                        "package" to ai.packageName,
                        "apk" to apk,
                        "size" to size,
                        "system" to isSystem,
                        "icon" to appIconBase64(ai),
                    ),
                )
            }
        } catch (_: Exception) {}
        return out.sortedBy { (it["label"] as? String) ?: "" }
    }

    /// 直接读 APK 里的应用图标，缩到 96px 转 base64（取不到就返回空串）。
    private fun appIconBase64(ai: android.content.pm.ApplicationInfo): String {
        return try {
            val d = packageManager.getApplicationIcon(ai)
            val bmp: android.graphics.Bitmap = if (d is android.graphics.drawable.BitmapDrawable && d.bitmap != null) {
                d.bitmap
            } else {
                android.graphics.Bitmap.createBitmap(96, 96, android.graphics.Bitmap.Config.ARGB_8888).also {
                    val c = android.graphics.Canvas(it)
                    d.setBounds(0, 0, 96, 96)
                    d.draw(c)
                }
            }
            val scaled = android.graphics.Bitmap.createScaledBitmap(bmp, 96, 96, true)
            val bo = java.io.ByteArrayOutputStream()
            scaled.compress(android.graphics.Bitmap.CompressFormat.PNG, 85, bo)
            android.util.Base64.encodeToString(bo.toByteArray(), android.util.Base64.NO_WRAP)
        } catch (e: Exception) {
            ""
        }
    }

    private fun zipList(path: String?): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        if (path == null) return out
        try {
            java.util.zip.ZipFile(path).use { z ->
                for (e in z.entries()) {
                    out.add(mapOf("name" to e.name, "size" to e.size, "dir" to e.isDirectory))
                }
            }
        } catch (_: Exception) {}
        return out
    }

    private fun zipRead(path: String?, entry: String?, max: Int): ByteArray? {
        if (path == null || entry == null) return null
        return try {
            java.util.zip.ZipFile(path).use { z ->
                val e = z.getEntry(entry) ?: return null
                z.getInputStream(e).use { ins ->
                    val buf = ByteArray(max)
                    var read = 0
                    while (read < max) {
                        val n = ins.read(buf, read, max - read)
                        if (n <= 0) break
                        read += n
                    }
                    buf.copyOf(read)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == 4800) {
            val r = projectionPending
            projectionPending = null
            val action = projectionAction
            projectionAction = null
            if (resultCode != RESULT_OK || data == null) {
                r?.success(null)
                return
            }
            val mpm = getSystemService(android.content.Context.MEDIA_PROJECTION_SERVICE)
                as android.media.projection.MediaProjectionManager
            mediaProjection = mpm.getMediaProjection(resultCode, data)
            when (action) {
                "shot" -> r?.success(captureProjectionFrame())
                "record" -> r?.success(startRecording())
                else -> r?.success(null)
            }
            return
        }
        if (requestCode == 4720) {
            val r = vpnPending
            vpnPending = null
            if (resultCode == RESULT_OK) {
                startVpnService()
                r?.success(mapOf(
                    "ok" to true,
                    "running" to DnsVpnService.runningNow,
                    "dns" to DnsVpnService.upstreamDns,
                    "auto" to DnsVpnService.autoDetected,
                    "needDns" to DnsVpnService.noDns,
                ))
            } else {
                r?.success(false)
            }
            return
        }
        if (requestCode == 4712) {
            val r = pendingPick
            pendingPick = null
            if (resultCode != RESULT_OK || data?.data == null) {
                r?.success(null)
                return
            }
            try {
                val text = contentResolver.openInputStream(data.data!!)?.bufferedReader()?.use { it.readText() }
                r?.success(text)
            } catch (e: Throwable) {
                r?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1001) return
        val r = pendingPick
        pendingPick = null
        val uri = data?.data
        if (uri == null) {
            r?.success(null)
            return
        }
        try {
            val dir = java.io.File(filesDir, "attachments").apply { mkdirs() }
            val name = (uri.lastPathSegment ?: "file").substringAfterLast('/')
            val out = java.io.File(dir, "${System.currentTimeMillis()}_$name")
            contentResolver.openInputStream(uri)?.use { ins -> out.outputStream().use { ins.copyTo(it) } }
            r?.success(out.absolutePath)
        } catch (e: Exception) {
            r?.success(null)
        }
    }

    private fun installFridaModule(manager: String): Map<String, Any> {
        return try {
            val zip = java.io.File(cacheDir, "rowan-module.zip")
            assets.open("rowan-module.zip").use { inp -> zip.outputStream().use { out -> inp.copyTo(out) } }
            if (manager == "export") {
                val dl = java.io.File("/sdcard/Download")
                if (!dl.exists()) dl.mkdirs()
                val dst = java.io.File(dl, "rowan-module.zip")
                zip.copyTo(dst, overwrite = true)
                return mapOf("ok" to true, "msg" to "已导出到 ${dst.absolutePath}，去管理器里手动安装")
            }
            val magiskCmds = listOf(
                "magisk --install-module ${zip.absolutePath}",
                "/debug_ramdisk/magisk --install-module ${zip.absolutePath}",
                "/data/adb/magisk/magisk --install-module ${zip.absolutePath}",
            )
            val ksuCmds = listOf("ksud module install ${zip.absolutePath}")
            val apdCmds = listOf("apd module install ${zip.absolutePath}")
            val cmds = when (manager) {
                "magisk" -> magiskCmds
                "ksu" -> ksuCmds
                "apatch" -> apdCmds
                else -> ksuCmds + apdCmds + magiskCmds
            }
            val logs = StringBuilder()
            for (cmd in cmds) {
                val r = runSu(cmd)
                val code = r["code"] as? Int ?: -1
                val out = (((r["stdout"] as? String) ?: "") + ((r["stderr"] as? String) ?: "")).trim()
                if (code == 0) return mapOf("ok" to true, "msg" to "$cmd\n${out.take(300)}")
                logs.append("$cmd -> ${out.ifEmpty { "exit=$code" }}\n")
            }
            mapOf("ok" to false, "msg" to logs.toString().take(600))
        } catch (e: Exception) {
            mapOf("ok" to false, "msg" to (e.message ?: "error"))
        }
    }

    /// 崩溃日志写到 filesDir/crash.log，闪退后可以用终端 cat 出来。
    private fun installCrashLogger() {
        val def = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching {
                val f = java.io.File(filesDir, "crash.log")
                val ts = java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.US)
                    .format(java.util.Date())
                f.appendText("\n==== $ts  thread=${t.name} ====\n")
                f.appendText(e.stackTraceToString())
            }
            def?.uncaughtException(t, e)
        }
    }

    private fun startVpnService() {
        val i = Intent(this, DnsVpnService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i) else startService(i)
    }

    /** 把 AI 在对话里执行的命令与输出落一份日志，原生终端打开时回显。 */
    private fun appendAiLog(cmd: String, output: String, code: Int) {
        try {
            val dir = java.io.File("/sdcard/Rowan")
            if (!dir.exists()) dir.mkdirs()
            val f = java.io.File(dir, "ai_console.log")
            val sb = StringBuilder()
            if (f.exists() && f.length() < 512 * 1024) sb.append(f.readText())
            sb.append("> ").append(cmd).append('\n')
            if (output.isNotBlank()) sb.append(output.trimEnd()).append('\n')
            sb.append("[exit ").append(code).append("]\n\n")
            val text = sb.toString()
            f.writeText(if (text.length > 200000) text.takeLast(200000) else text)
        } catch (_: Throwable) {
        }
    }

    /** Android 14+ 录屏前先启动 mediaProjection 前台服务。 */
    private fun ensureProjectionService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            runCatching {
                startForegroundService(Intent(this, MediaProjectionService::class.java))
            }
        }
    }

    /** 请求录屏授权（MediaProjection）。 */
    private fun requestProjection() {
        runCatching {
            ensureProjectionService()
            val mpm = getSystemService(android.content.Context.MEDIA_PROJECTION_SERVICE)
                as android.media.projection.MediaProjectionManager
            startActivityForResult(mpm.createScreenCaptureIntent(), 4800)
        }.onFailure {
            projectionPending?.success(null)
            projectionPending = null
            projectionAction = null
        }
    }

    /** 抓一帧 → PNG 字节（不落盘）。 */
    private fun captureProjectionFrame(): ByteArray? {
        val proj = mediaProjection ?: return null
        return try {
            val metrics = resources.displayMetrics
            val w = metrics.widthPixels
            val h = metrics.heightPixels
            val dpi = metrics.densityDpi
            val imageReader = android.media.ImageReader.newInstance(
                w, h, android.graphics.PixelFormat.RGBA_8888, 2)
            val vd = proj.createVirtualDisplay(
                "rowan-shot", w, h, dpi,
                android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader.surface, null, null)
            virtualDisplay = vd
            var img: android.media.Image? = null
            var tries = 0
            while (tries < 20) {
                img = imageReader.acquireLatestImage()
                if (img != null) break
                Thread.sleep(50); tries++
            }
            if (img == null) { vd.release(); imageReader.close(); return null }
            val plane = img.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * w
            val bmp = android.graphics.Bitmap.createBitmap(
                w + rowPadding / pixelStride, h, android.graphics.Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(buffer)
            img.close()
            vd.release(); imageReader.close()
            virtualDisplay = null
            val cropped = android.graphics.Bitmap.createBitmap(bmp, 0, 0, w, h)
            val bos = java.io.ByteArrayOutputStream()
            cropped.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, bos)
            bos.toByteArray()
        } catch (e: Throwable) {
            null
        }
    }

    /** 开始录屏 → MP4。 */
    private fun startRecording(): String? {
        val proj = mediaProjection ?: return null
        return try {
            val metrics = resources.displayMetrics
            val w = metrics.widthPixels
            val h = metrics.heightPixels
            val dpi = metrics.densityDpi
            val dir = java.io.File(getExternalFilesDir(null), "recordings").apply { mkdirs() }
            val f = java.io.File(dir, "rec_${System.currentTimeMillis()}.mp4")
            recordingFile = f
            val mr = if (Build.VERSION.SDK_INT >= 31) android.media.MediaRecorder(this)
                     else android.media.MediaRecorder()
            mr.setVideoSource(android.media.MediaRecorder.VideoSource.SURFACE)
            mr.setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
            mr.setVideoEncoder(android.media.MediaRecorder.VideoEncoder.H264)
            mr.setVideoSize(w, h)
            mr.setVideoFrameRate(30)
            mr.setVideoEncodingBitRate(8_000_000)
            mr.setOutputFile(f.absolutePath)
            mr.prepare()
            val vd = proj.createVirtualDisplay(
                "rowan-rec", w, h, dpi,
                android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                mr.surface, null, null)
            virtualDisplay = vd
            mr.start()
            mediaRecorder = mr
            f.absolutePath
        } catch (e: Throwable) {
            null
        }
    }

    /** 停止录屏，返回 MP4 路径。 */
    private fun stopRecording(): String? {
        return try {
            mediaRecorder?.stop()
            mediaRecorder?.release()
            mediaRecorder = null
            virtualDisplay?.release()
            virtualDisplay = null
            recordingFile?.absolutePath
        } catch (e: Throwable) {
            recordingFile?.absolutePath
        }
    }

    private fun runShell(cmd: String, timeoutSec: Int): Map<String, Any> {
        return try {
            val p = ProcessBuilder("/system/bin/sh", "-c", cmd).start()
            val out = StringBuilder()
            val err = StringBuilder()
            val tOut = Thread {
                // 进程被 destroy 时 readLine 会抛 InterruptedIOException，不接住会把整个 App 带崩
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r -> r.forEachLine { out.appendLine(it) } }
                } catch (_: Throwable) {
                }
            }
            val tErr = Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r -> r.forEachLine { err.appendLine(it) } }
                } catch (_: Throwable) {
                }
            }
            tOut.start(); tErr.start()
            val done = p.waitFor(timeoutSec.toLong(), TimeUnit.SECONDS)
            if (!done) p.destroy()
            tOut.join(1000); tErr.join(1000)
            val code = if (done) p.exitValue() else -1
            appendAiLog(cmd, out.toString() + err.toString(), code)
            mapOf(
                "stdout" to out.toString(),
                "stderr" to err.toString(),
                "code" to code,
                "timeout" to !done,
            )
        } catch (e: Exception) {
            mapOf("stdout" to "", "stderr" to (e.message ?: "exec error"), "code" to -1, "timeout" to false)
        }
    }

    private fun runSu(cmd: String): Map<String, Any> {
        return try {
            var p: Process? = null
            var lastErr: Exception? = null
            for (bin in listOf("su", "/system/bin/su", "/system/xbin/su")) {
                try { p = ProcessBuilder(bin, "-c", cmd).start(); break } catch (e: Exception) { lastErr = e }
            }
            if (p == null) throw lastErr ?: Exception("su not found")
            val out = StringBuilder()
            val err = StringBuilder()
            val t1 = Thread {
                try {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r -> r.forEachLine { out.appendLine(it) } }
                } catch (_: Throwable) {
                }
            }
            val t2 = Thread {
                try {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r -> r.forEachLine { err.appendLine(it) } }
                } catch (_: Throwable) {
                }
            }
            t1.start(); t2.start()
            val done = p.waitFor(60, TimeUnit.SECONDS)
            if (!done) p.destroy()
            t1.join(1000); t2.join(1000)
            mapOf(
                "stdout" to out.toString(),
                "stderr" to err.toString(),
                "code" to (if (done) p.exitValue() else -1),
                "timeout" to !done,
            )
        } catch (e: Exception) {
            mapOf("stdout" to "", "stderr" to (e.message ?: "su error"), "code" to -1, "timeout" to false)
        }
    }

    companion object {
        const val CHANNEL = "com.chun.by/native"
    }
}

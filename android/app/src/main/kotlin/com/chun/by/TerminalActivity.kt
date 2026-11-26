package com.chun.by

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import com.termux.terminal.TerminalSession
import com.termux.terminal.TerminalSessionClient
import com.termux.view.TerminalView
import com.termux.view.TerminalViewClient

/**
 * 多标签终端：每个标签一个独立 TerminalSession（都在 Alpine 里），顶部横向标签栏。
 */
class TerminalActivity : Activity() {
    private lateinit var view: TerminalView
    private lateinit var tabBar: LinearLayout
    private lateinit var tabsScroll: HorizontalScrollView
    private lateinit var holder: android.widget.FrameLayout

    private data class Tab(val id: Int, var title: String, val env: String, val session: TerminalSession)

    private val tabs = mutableListOf<Tab>()
    private var activeId = -1
    private var seq = 0

    private val sessionClient = object : TerminalSessionClient {
        override fun onTextChanged(changedSession: TerminalSession) {
            // TerminalSession 在读写线程回调，View 更新必须回主线程，否则新输出不重绘
            runOnUiThread {
                if (current()?.session == changedSession) view.onScreenUpdated()
            }
        }
        override fun onTitleChanged(changedSession: TerminalSession) {}
        override fun onSessionFinished(finishedSession: TerminalSession) {
            runOnUiThread {
                val t = tabs.firstOrNull { it.session == finishedSession }
                if (t != null) {
                    t.title = "${t.title} (已结束)"
                    renderTabs()
                }
                if (current()?.session == finishedSession) view.onScreenUpdated()
            }
        }
        override fun onCopyTextToClipboard(session: TerminalSession, text: String) {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("terminal", text))
        }
        override fun onPasteTextFromClipboard(session: TerminalSession?) {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val text = cm.primaryClip?.getItemAt(0)?.coerceToText(this@TerminalActivity)?.toString() ?: return
            session?.write(text)
        }
        override fun onBell(session: TerminalSession) {}
        override fun getTerminalCursorStyle(): Int? = 1
        override fun onColorsChanged(session: TerminalSession) {}
        override fun onTerminalCursorStateChange(state: Boolean) {}
        override fun setTerminalShellPid(session: TerminalSession, pid: Int) {}
        override fun logError(tag: String, message: String) { Log.e(tag, message) }
        override fun logWarn(tag: String, message: String) { Log.w(tag, message) }
        override fun logInfo(tag: String, message: String) { Log.i(tag, message) }
        override fun logDebug(tag: String, message: String) { Log.d(tag, message) }
        override fun logVerbose(tag: String, message: String) { Log.v(tag, message) }
        override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) { Log.e(tag, message, e) }
        override fun logStackTrace(tag: String, e: Exception) { Log.e(tag, "", e) }
    }

    private val viewClient = object : TerminalViewClient {
        override fun onScale(scale: Float): Float = 1f
        override fun onSingleTapUp(e: MotionEvent) {
            // 点击终端区域时主动拉起软键盘
            showKeyboard()
        }
        override fun shouldBackButtonBeMappedToEscape(): Boolean = false
        override fun shouldEnforceCharBasedInput(): Boolean = true
        override fun shouldUseCtrlSpaceWorkaround(): Boolean = false
        override fun isTerminalViewSelected(): Boolean = true
        override fun copyModeChanged(copyMode: Boolean) {}
        override fun onKeyDown(keyCode: Int, e: KeyEvent, session: TerminalSession): Boolean {
            // 部分输入法的软键盘回车不会落到 PTY，这里显式写入 CR
            if (keyCode == KeyEvent.KEYCODE_ENTER || keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER) {
                if (e.action == KeyEvent.ACTION_DOWN) session.write("\r")
                return true
            }
            return false
        }
        override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean = false
        override fun onLongPress(event: MotionEvent): Boolean = false
        override fun readControlKey(): Boolean = false
        override fun readAltKey(): Boolean = false
        override fun readShiftKey(): Boolean = false
        override fun readFnKey(): Boolean = false
        override fun onCodePoint(codePoint: Int, ctrlDown: Boolean, session: TerminalSession): Boolean = false
        override fun onEmulatorSet() { view.updateSize() }
        override fun logError(tag: String, message: String) { Log.e(tag, message) }
        override fun logWarn(tag: String, message: String) { Log.w(tag, message) }
        override fun logInfo(tag: String, message: String) { Log.i(tag, message) }
        override fun logDebug(tag: String, message: String) { Log.d(tag, message) }
        override fun logVerbose(tag: String, message: String) { Log.v(tag, message) }
        override fun logStackTraceWithMessage(tag: String, message: String, e: Exception) { Log.e(tag, message, e) }
        override fun logStackTrace(tag: String, e: Exception) { Log.e(tag, "", e) }
    }

    private fun current(): Tab? = tabs.firstOrNull { it.id == activeId }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        GgetReceiver.ensureShellRc(this)

        view = TerminalView(this, null)
        view.setTerminalViewClient(viewClient)
        // TerminalView 自身不设 focusable，不手动设的话 requestFocus 无效、软键盘永远弹不出来
        view.isFocusable = true
        view.isFocusableInTouchMode = true
        view.setBackgroundColor(0xFF0B1220.toInt())
        view.keepScreenOn = true
        view.setOnClickListener { showKeyboard() }
        view.setOnLongClickListener {
            showTermMenu(view)
            true
        }
        view.setTextSize(getSharedPreferences("terminal", android.content.Context.MODE_PRIVATE)
            .getInt("fontSize", 26))

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF0B1220.toInt())
        }

        // 顶部标签栏
        tabBar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        tabsScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setBackgroundColor(0xFF0F172A.toInt())
        }
        tabsScroll.addView(tabBar, ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(tabsScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)))
        tabBar.setPadding(dp(6), dp(6), dp(6), dp(6))

        holder = android.widget.FrameLayout(this).apply { setBackgroundColor(0xFF0B1220.toInt()) }
        holder.addView(view, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        root.addView(holder, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        // 底部辅助键
        val keys = listOf(
            "ESC" to "\u001b", "TAB" to "\t", "↵" to "\r",
            "←" to "\u001b[D", "→" to "\u001b[C", "↑" to "\u001b[A", "↓" to "\u001b[B",
            "^C" to "\u0003", "^D" to "\u0004", "^Z" to "\u001a", "^L" to "\u000c",
            "|" to "|", "-" to "-", "/" to "/", "~" to "~",
        )
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xFF0A0F1A.toInt())
            setPadding(dp(8), dp(6), dp(8), dp(8))
        }
        // 键盘：显式拉起输入法（部分设备点击终端不自动弹）
        bar.addView(TextView(this).apply {
            text = "⌨"
            gravity = Gravity.CENTER
            setTextColor(0xFF93C5FD.toInt())
            textSize = 15f
            background = rounded(0x1A94A3B8, 10)
            setOnClickListener { showKeyboard() }
        }, LinearLayout.LayoutParams(dp(44), dp(38)).apply { marginEnd = dp(6) })
        for ((label, s) in keys) {
            val tv = TextView(this).apply {
                text = label
                gravity = Gravity.CENTER
                setTextColor(0xFFCBD5E1.toInt())
                textSize = 12.5f
                setTypeface(Typeface.MONOSPACE)
                background = rounded(0x1A94A3B8, 10)
                setOnClickListener {
                    if (s == "\t") view.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_TAB))
                    else current()?.session?.write(s)
                    view.requestFocus()
                }
            }
            bar.addView(tv, LinearLayout.LayoutParams(dp(44), dp(38)).apply { marginEnd = dp(6) })
        }
        // 粘贴
        val paste = TextView(this).apply {
            text = "粘贴"
            gravity = Gravity.CENTER
            setTextColor(0xFFDBEAFE.toInt())
            textSize = 12.5f
            setTypeface(Typeface.MONOSPACE)
            background = rounded(0x382563EB, 10, 0x733B82F6)
            setOnClickListener {
                val cm = getSystemService(android.content.Context.CLIPBOARD_SERVICE)
                        as android.content.ClipboardManager
                val txt = cm.primaryClip?.getItemAt(0)
                    ?.coerceToText(this@TerminalActivity)?.toString() ?: ""
                if (txt.isNotEmpty()) current()?.session?.write(txt)
                view.requestFocus()
            }
        }
        bar.addView(paste, LinearLayout.LayoutParams(dp(56), dp(38)))
        val barScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(bar)
        }
        root.addView(barScroll)

        setContentView(root)

        ensureEnv()
    }

    private fun ensureEnv() {
        // 不装任何容器也能用：默认开 Android 自带 shell（toybox 命令 + su/Shizuku 都可用）
        if (ProotLauncher.isReady(this)) newTab() else newSystemTab()
    }

    /** 系统 shell：不依赖 rootfs，跑的是 /system/bin/sh。 */
    private fun newSystemTab() {
        val id = ++seq
        val sh = "/system/bin/sh"
        try {
            val session = TerminalSession(
                sh, "/",
                arrayOf(sh),
                arrayOf(
                    "TERM=xterm-256color",
                    "HOME=/data/local/tmp",
                    "PATH=/sbin:/system/sbin:/system/bin:/system/xbin",
                    // 交互 shell 读 $ENV，gget 等函数由它载入
                    "ENV=${filesDir.absolutePath}/bin/shellrc",
                ),
                2000, sessionClient,
            )
            tabs.add(Tab(id, "system", "system", session))
            selectTab(id)
        } catch (e: Throwable) {
            AppToast.show(this, "启动失败：${e.message}", true)
        }
    }

    /** APK 不内置镜像：只给 URL 安装入口，或直接用系统 shell。 */
    private fun showEmptyState() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFF0B1220.toInt())
            setPadding(dp(24), 0, dp(24), 0)
        }
        val none = ProotLauncher.listEnvs(this).isEmpty()
        box.addView(TextView(this).apply {
            text = if (none) "还没有容器" else "容器不完整"
            setTextColor(0xFFE2E8F0.toInt())
            textSize = 15f
            gravity = Gravity.CENTER
        })
        box.addView(TextView(this).apply {
            text = "APK 不内置任何镜像。粘贴发行版 rootfs 直链（tar.gz / tar.xz）即可安装。"
            setTextColor(0xFF94A3B8.toInt())
            textSize = 11.5f
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(18))
        })
        box.addView(TextView(this).apply {
            text = "从 URL 安装容器…"
            setTextColor(0xFF93C5FD.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            setTypeface(Typeface.MONOSPACE)
            setPadding(dp(12), dp(14), dp(12), dp(14))
            setOnClickListener { installFromUrlDialog() }
        })
        box.addView(TextView(this).apply {
            text = "用系统 shell（不需要容器）"
            setTextColor(0xFF94A3B8.toInt())
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setOnClickListener {
                holder.removeAllViews()
                holder.addView(view, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                newSystemTab()
            }
        })
        holder.removeAllViews()
        holder.addView(box, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    /** root 类操作每次都现场确认，不提供「始终允许」。 */
    private fun confirmRoot(action: String, onAllow: () -> Unit) {
        android.app.AlertDialog.Builder(this)
            .setTitle("需要 root 权限")
            .setMessage("$action 将以 root 运行，可读写系统目录。\n\n此操作每次都需确认。")
            .setCancelable(false)
            .setPositiveButton("允许本次") { _, _ -> onAllow() }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun showKeyboard() {
        runCatching {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            view.requestFocus()
            imm.showSoftInput(view, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun newTab(requested: String = ProotLauncher.currentEnv(this)) {
        val env = requested
        if (!ProotLauncher.isReady(this, env)) {
            showEmptyState()
            return
        }
        val rootfs = ProotLauncher.rootfs(this, env)
        val proot = ProotLauncher.prootBin(this)
        val tmp = java.io.File(filesDir, "tmp").apply { mkdirs() }.absolutePath
        val id = ++seq
        try {
            val argv = ArrayList<String>()
            argv.addAll(listOf(proot, "-r", rootfs, "-0"))
            argv.addAll(listOf("-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", "/system"))
            for (b in ProotLauncher.bindings(this)) {
                argv.add("-b")
                argv.add(b)
            }
            argv.addAll(listOf("-w", "/root", "--link2symlink", "--kill-on-exit", "/bin/sh", "-l"))
            val session = TerminalSession(
                proot, rootfs,
                argv.toTypedArray(),
                arrayOf(
                    "TERM=xterm-256color",
                    "HOME=/root",
                    "LD_LIBRARY_PATH=${applicationInfo.nativeLibraryDir}:/system/lib64:/system/lib",
                    "PROOT_TMP_DIR=$tmp",
                    // 这个 proot 是 Termux 分体版（动态链 libtalloc/libandroid-shmem），loader 外置；
                    // 不指 PROOT_LOADER 时 proot 无法注入子进程，shell 直接起不来。
                    "PROOT_LOADER=${applicationInfo.nativeLibraryDir}/libproot-loader.so",
                    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                ),
                2000, sessionClient,
            )
            tabs.add(Tab(id, env, env, session))
            selectTab(id)
            echoAiLog(session)
        } catch (e: Throwable) {
            Log.e("TerminalActivity", "new tab failed", e)
            val tv = TextView(this).apply {
                text = "启动终端失败：\n${e.message}\n\nrootfs: $rootfs"
                textSize = 12f
                setTextColor(0xFFFF6B6B.toInt())
                setPadding(dp(16), dp(24), dp(16), 0)
            }
            tabBar.removeAllViews()
            tabBar.addView(tv)
        }
    }

    /** 把对话框里 AI 执行过的命令回显到新开的终端标签，两边能看到同一段历史。 */
    private fun echoAiLog(session: TerminalSession) {
        val f = java.io.File("/sdcard/Rowan/ai_console.log")
        if (!f.exists() || f.length() == 0L) return
        android.os.Handler(mainLooper).postDelayed({
            runCatching {
                session.write("echo '── AI 在对话里执行过的命令 ──'; cat '${f.absolutePath}'; echo\n")
            }
        }, 700)
    }

    private fun selectTab(id: Int) {
        activeId = id
        val t = current() ?: return
        runCatching {
            view.attachSession(t.session)
            TerminalSessionManager.current = t.session
            view.updateSize()
            view.requestFocus()
        }
        renderTabs()
    }

    private fun closeTab(id: Int) {
        val idx = tabs.indexOfFirst { it.id == id }
        if (idx < 0) return
        val t = tabs.removeAt(idx)
        runCatching { t.session.finishIfRunning() }
        if (tabs.isEmpty()) {
            newTab()
            return
        }
        if (activeId == id) selectTab(tabs[minOf(idx, tabs.size - 1)].id) else renderTabs()
    }

    private fun rounded(color: Int, radiusDp: Int, strokeColor: Int? = null): android.graphics.drawable.GradientDrawable {
        val d = android.graphics.drawable.GradientDrawable()
        d.cornerRadius = dp(radiusDp).toFloat()
        d.setColor(color)
        if (strokeColor != null) d.setStroke(dp(1), strokeColor)
        return d
    }

    private fun renderTabs() {
        tabBar.removeAllViews()
        for (t in tabs) {
            val active = t.id == activeId
            val chip = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(10), 0, dp(4), 0)
                background = if (active)
                    rounded(0x292563EB, 10, 0x733B82F6)
                else
                    rounded(0x1A94A3B8, 10)
                setOnClickListener { selectTab(t.id) }
            }
            if (active) {
                chip.addView(android.view.View(this).apply {
                    background = rounded(0xFF22C55E.toInt(), 3)
                }, LinearLayout.LayoutParams(dp(6), dp(6)).apply { marginEnd = dp(6) })
            }
            chip.addView(TextView(this).apply {
                text = t.title
                textSize = 11.5f
                setTextColor(if (active) 0xFFE2E8F0.toInt() else 0xFF94A3B8.toInt())
                setTypeface(Typeface.MONOSPACE)
            })
            chip.addView(TextView(this).apply {
                text = "×"
                textSize = 13f
                setPadding(dp(8), dp(4), dp(6), dp(4))
                setTextColor(0xFF64748B.toInt())
                setOnClickListener { closeTab(t.id) }
            })
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(32))
            lp.marginEnd = dp(6)
            tabBar.addView(chip, lp)
        }
        tabsScroll.post { tabsScroll.fullScroll(View.FOCUS_RIGHT) }
    }

    private fun newRootTab() {
        confirmRoot("宿主 root shell（su）") { startRootTab() }
    }

    private fun startRootTab() {
        val su = listOf("/system/bin/su", "/system/xbin/su", "/debug_ramdisk/su", "su")
            .firstOrNull { java.io.File(it).exists() } ?: "su"
        val id = ++seq
        try {
            val session = TerminalSession(
                su, "/",
                arrayOf(su, "-c", "/system/bin/sh"),
                arrayOf(
                    "TERM=xterm-256color",
                    "HOME=/data/local/tmp",
                    "PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/debug_ramdisk",
                ),
                2000, sessionClient,
            )
            tabs.add(Tab(id, "root", "root", session))
            selectTab(id)
        } catch (e: Throwable) {
            AppToast.show(this, "root 启动失败：${e.message}", true)
        }
    }

    /** 粘贴任意 rootfs 直链 + 容器名，后台下载解压，完成后开新标签。 */
    private fun installFromUrlDialog() {
        val urlCtrl = android.widget.EditText(this).apply {
            hint = "rootfs 直链（.tar.gz / .tar.xz）"
            textSize = 12f
        }
        val nameCtrl = android.widget.EditText(this).apply {
            hint = "容器名（字母数字，如 debian）"
            textSize = 12f
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), 0)
            addView(urlCtrl)
            addView(nameCtrl)
        }
        android.app.AlertDialog.Builder(this)
            .setTitle("从 URL 安装容器")
            .setView(box)
            .setPositiveButton("安装") { _, _ ->
                val url = urlCtrl.text.toString().trim()
                val name = nameCtrl.text.toString().trim()
                if (url.isNotEmpty() && name.isNotEmpty()) runInstall(url, name)
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun runInstall(url: String, name: String) {
        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle("安装 $name")
            .setMessage("准备中…")
            .setCancelable(false)
            .create()
        dialog.show()
        Thread {
            val log = StringBuilder()
            val ok = ProotLauncher.installFromUrl(this, url, name) { line ->
                synchronized(log) { log.appendLine(line) }
                runOnUiThread { runCatching { dialog.setMessage(line) } }
            }
            runOnUiThread {
                runCatching { dialog.dismiss() }
                if (ok) {
                    ProotLauncher.setCurrentEnv(this, name)
                    holder.removeAllViews()
                    holder.addView(view, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    newTab(name)
                } else {
                    android.app.AlertDialog.Builder(this)
                        .setTitle("安装失败")
                        .setMessage(log.toString().takeLast(1500))
                        .setPositiveButton("好", null)
                        .show()
                }
            }
        }.start()
    }

    private fun chooseEnv() {
        val envs = ProotLauncher.listEnvs(this)
        val current = ProotLauncher.currentEnv(this)
        val items = ArrayList<String>()
        for (env in envs) {
            val mark = if (env == current) "● " else "○ "
            val state = if (ProotLauncher.isReady(this, env)) "" else "（未就绪）"
            items.add(mark + "容器：" + env + state)
        }
        items.add("安装 Alpine（约 4MB）")
        items.add("从 URL 安装容器…")
        android.app.AlertDialog.Builder(this)
            .setTitle("容器")
            .setItems(items.toTypedArray()) { _, i ->
                when {
                    i < envs.size -> {
                        val env = envs[i]
                        if (!ProotLauncher.isReady(this, env)) {
                            AppToast.show(this, "$env 未就绪：环境菜单里重新安装", true)
                            return@setItems
                        }
                        ProotLauncher.setCurrentEnv(this, env)
                        newTab(env)
                    }
                    i == envs.size -> runInstall(ProotLauncher.ALPINE_URL, ProotLauncher.ALPINE)
                    else -> installFromUrlDialog()
                }
            }
            .show()
    }

    override fun onResume() {
        super.onResume()
        runCatching {
            view.updateSize()
            view.requestFocus()
        }
        titleTicker.post(titleTask)
    }

    override fun onDestroy() {
        super.onDestroy()
        for (t in tabs) runCatching { t.session.finishIfRunning() }
        tabs.clear()
    }

    private fun PasteKeyMark() {}

    private fun showTermMenu(view: com.termux.view.TerminalView) {
        val items = arrayOf("复制全部输出", "清屏", "粘贴", "字号 +", "字号 −")
        android.app.AlertDialog.Builder(this)
            .setTitle("终端")
            .setItems(items) { _, which ->
                when (which) {
                    0 -> {
                        val txt = current()?.session?.emulator?.screen?.transcriptText ?: ""
                        if (txt.isNotEmpty()) {
                            val cm = getSystemService(android.content.Context.CLIPBOARD_SERVICE)
                                    as android.content.ClipboardManager
                            cm.setPrimaryClip(android.content.ClipData.newPlainText("terminal", txt))
                            AppToast.show(this, "已复制 ${txt.length} 字符")
                        } else {
                            AppToast.show(this, "没有可复制的内容", true)
                        }
                    }
                    1 -> current()?.session?.write("\u000c")
                    2 -> {
                        val cm = getSystemService(android.content.Context.CLIPBOARD_SERVICE)
                                as android.content.ClipboardManager
                        val txt = cm.primaryClip?.getItemAt(0)
                            ?.coerceToText(this)?.toString() ?: ""
                        if (txt.isNotEmpty()) current()?.session?.write(txt)
                    }
                    3 -> changeFont(2)
                    4 -> changeFont(-2)
                }
                view.requestFocus()
            }
            .show()
    }

    private fun changeFont(delta: Int) {
        val p = getSharedPreferences("terminal", android.content.Context.MODE_PRIVATE)
        val cur = p.getInt("fontSize", 26)
        val next = (cur + delta).coerceIn(14, 40)
        p.edit().putInt("fontSize", next).apply()
        view.setTextSize(next)
        AppToast.show(this, "字号 $next")
    }


    private val titleTicker = android.os.Handler(android.os.Looper.getMainLooper())
    private val titleTask = object : Runnable {
        override fun run() {
            refreshTitles()
            titleTicker.postDelayed(this, 2000)
        }
    }

    /** 用 /proc/<pid>/cwd 更新标签标题为当前目录名。 */
    private fun refreshTitles() {
        var changed = false
        for (t in tabs) {
            val name = try {
                val pid = t.session.pid
                if (pid <= 0) null else {
                    val link = java.io.File("/proc/$pid/cwd").canonicalPath
                    val trimmed = link.trimEnd('/')
                    val base = trimmed.substringAfterLast('/')
                    if (base.isEmpty()) "/" else base
                }
            } catch (_: Throwable) {
                null
            }
            // proot 会话的 cwd 在宿主上是 rootfs 目录，名字无意义，只给 root 标签刷新
            if (name != null && t.env == "root") {
                val want = if (t.title.endsWith("(已结束)")) t.title else "root: $name"
                if (want != t.title) {
                    t.title = want
                    changed = true
                }
            }
        }
        if (changed) runCatching { renderTabs() }
    }

    override fun onPause() {
        titleTicker.removeCallbacks(titleTask)
        super.onPause()
    }

}

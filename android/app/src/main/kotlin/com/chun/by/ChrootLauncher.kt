package com.chun.by

import android.content.Context
import android.util.Base64
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/**
 * 有 Root 时用内核原生 chroot 跑容器，绕开 PRoot 的 ptrace 模拟层：
 *  - PRoot：零依赖，任何 Android 8+ 都能跑，但每次系统调用都要被 ptrace 拦截改写，慢，且 uid=0 是假的。
 *  - chroot：内核原生隔离，无系统调用开销，uid=0 是真 root（KernelSU / Magisk 给）。
 *
 * 自动选择：检测到 root 且 rootfs 里有 /bin/sh → 用 chroot；否则回退 PRoot。
 * 两条路共用同一份 rootfs，随时可切换，不用重装容器。
 */
object ChrootLauncher {
    private const val PREFS = "container"
    private const val K_FORCE_PRROT = "force_proot"

    private var cachedRoot: Boolean? = null

    /**
     * 是否拿到真 root（缓存；清缓存用 invalidateRootCache）。
     * 直接起 /system/bin/su 探测，不依赖 libsu 的 Shell 是否初始化过，
     * 避免「有 root 却检测不到」的情况。首次调用会触发一次授权弹窗。
     */
    fun hasRoot(): Boolean {
        cachedRoot?.let { return it }
        val ok = try {
            val p = ProcessBuilder("/system/bin/su", "-c", "id -u")
                .redirectErrorStream(true)
                .start()
            val out = p.inputStream.bufferedReader().use { it.readText() }.trim()
            p.waitFor(6, java.util.concurrent.TimeUnit.SECONDS)
            out == "0" || out.endsWith("\n0") || out.contains("uid=0")
        } catch (e: Throwable) {
            false
        }
        cachedRoot = ok
        return ok
    }

    fun invalidateRootCache() {
        cachedRoot = null
    }

    /** 用户在设置里强制用 PRoot（有些设备 chroot 挂载会失败）。 */
    fun isForceProot(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(K_FORCE_PRROT, false)

    fun setForceProot(ctx: Context, force: Boolean) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(K_FORCE_PRROT, force).apply()
    }

    /** 这个环境能不能用 chroot：有 root + 有 rootfs + rootfs 里有 /bin/sh + 没被强制关掉。 */
    fun canChroot(ctx: Context, env: String = ProotLauncher.currentEnv(ctx)): Boolean {
        if (isForceProot(ctx)) return false
        if (!hasRoot()) return false
        val dir = ProotLauncher.envDir(ctx, env)
        if (!dir.isDirectory) return false
        return File(dir, "bin/sh").exists() || File(dir, "usr/bin/sh").exists()
    }

    /** 当前环境的实际运行方式：chroot / proot / none。 */
    fun modeOf(ctx: Context, env: String = ProotLauncher.currentEnv(ctx)): String = when {
        canChroot(ctx, env) -> "chroot"
        ProotLauncher.isReady(ctx, env) -> "proot"
        else -> "none"
    }

    /**
     * chroot 前要准备的挂载。chroot 只换根，/dev /proc /sys 得自己挂进去，
     * 否则容器里没设备节点、读不到进程信息。已挂载时重复挂会失败，忽略即可。
     */
    private fun mountCmds(ctx: Context, rootfs: String): String {
        val sb = StringBuilder()
        sb.append("mkdir -p '$rootfs/dev' '$rootfs/proc' '$rootfs/sys' '$rootfs/tmp' '$rootfs/sdcard' 2>/dev/null; ")
        sb.append("mount -t proc proc '$rootfs/proc' 2>/dev/null; ")
        sb.append("mount --bind /dev '$rootfs/dev' 2>/dev/null; ")
        sb.append("mount --bind /sys '$rootfs/sys' 2>/dev/null; ")
        sb.append("mount --bind /sdcard '$rootfs/sdcard' 2>/dev/null; ")
        if (File("/storage/emulated/0").exists()) {
            sb.append("mkdir -p '$rootfs/storage/emulated/0' 2>/dev/null; ")
            sb.append("mount --bind /storage/emulated/0 '$rootfs/storage/emulated/0' 2>/dev/null; ")
        }
        // 容器里也能看到别的环境（与 PRoot 的 /opt/envs 对齐）
        val envs = File(ctx.filesDir, "envs")
        envs.mkdirs()
        sb.append("mkdir -p '$rootfs/opt/envs' 2>/dev/null; ")
        sb.append("mount --bind '${envs.absolutePath}' '$rootfs/opt/envs' 2>/dev/null; ")
        return sb.toString()
    }

    /**
     * 交互式 chroot shell 的 argv。
     * 用 su -c 起一个进程：先挂载，再 exec chroot，这样 su 那个进程直接变成 shell，
     * 不额外留 root 进程，关标签页就结束。
     */
    fun interactiveArgs(ctx: Context, env: String = ProotLauncher.currentEnv(ctx)): Array<String> {
        val rootfs = ProotLauncher.rootfs(ctx, env)
        val script = mountCmds(ctx, rootfs) + "exec chroot '$rootfs' /bin/sh -l"
        return arrayOf("su", "-c", script)
    }

    /** 交互式 shell 的环境变量（不能再带 App 的 LD_LIBRARY_PATH，会污染容器）。 */
    fun interactiveEnv(): Array<String> = arrayOf(
        "TERM=xterm-256color",
        "HOME=/root",
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "LANG=C.UTF-8",
    )

    /**
     * 非交互执行一条命令（给 AI 的 containerShell 用）。
     * 命令经 base64 传入，避开引号转义地狱。
     */
    fun exec(ctx: Context, env: String, cmd: String, timeoutSec: Int = 60): Map<String, Any> {
        if (!canChroot(ctx, env)) {
            return mapOf("stdout" to "", "stderr" to "chroot 不可用（需要 root）", "code" to -1, "timeout" to false)
        }
        val rootfs = ProotLauncher.rootfs(ctx, env)
        val b64 = Base64.encodeToString(cmd.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val full = mountCmds(ctx, rootfs) +
            "echo '$b64' | base64 -d | chroot '$rootfs' /bin/sh -s"
        return try {
            val p = ProcessBuilder("/system/bin/su", "-c", full).start()
            val out = StringBuilder()
            val err = StringBuilder()
            val t1 = Thread {
                runCatching {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r -> r.forEachLine { out.appendLine(it) } }
                }
            }
            val t2 = Thread {
                runCatching {
                    BufferedReader(InputStreamReader(p.errorStream)).use { r -> r.forEachLine { err.appendLine(it) } }
                }
            }
            t1.isDaemon = true; t2.isDaemon = true
            t1.start(); t2.start()
            val done = p.waitFor(timeoutSec.toLong(), java.util.concurrent.TimeUnit.SECONDS)
            if (!done) p.destroy()
            t1.join(800); t2.join(800)
            mapOf(
                "stdout" to out.toString(),
                "stderr" to err.toString(),
                "code" to if (done) runCatching { p.exitValue() }.getOrDefault(-1) else -1,
                "timeout" to !done,
            )
        } catch (e: Throwable) {
            mapOf("stdout" to "", "stderr" to (e.message ?: "chroot exec error"), "code" to -1, "timeout" to false)
        }
    }

    /**
     * 流式执行（给 containerShell 用）：实时把 stdout/stderr 逐行吐出来。
     * 直接用 /system/bin/su 起进程，配合 ProcessBuilder 就能真流式；
     * KernelSU/Magisk 对同一 App 只授权一次，不会每条命令都弹窗。
     */
    fun execStream(
        ctx: Context,
        env: String,
        cmd: String,
        timeoutSec: Long = 600,
        tag: String = "",
        onLine: (String) -> Unit,
        onDone: (Int) -> Unit,
    ) {
        if (!canChroot(ctx, env)) {
            onLine("chroot 不可用（需要 root）")
            onDone(-1)
            return
        }
        val rootfs = ProotLauncher.rootfs(ctx, env)
        val b64 = Base64.encodeToString(cmd.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val script = mountCmds(ctx, rootfs) +
            "echo '$b64' | base64 -d | chroot '$rootfs' /bin/sh -s"
        Thread {
            var code = -1
            var tracked: Process? = null
            try {
                val p = ProcessBuilder("/system/bin/su", "-c", script)
                    .redirectErrorStream(true)
                    .start()
                tracked = p
                ProotLauncher.trackProcess(p, tag)
                BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                    r.forEachLine { onLine(it) }
                }
                val done = p.waitFor(timeoutSec, java.util.concurrent.TimeUnit.SECONDS)
                if (!done) p.destroy()
                code = runCatching { p.exitValue() }.getOrDefault(-1)
            } catch (e: Throwable) {
                onLine("ERROR: ${e.message}")
            } finally {
                tracked?.let { ProotLauncher.untrackProcess(it, tag) }
                onDone(code)
            }
        }.start()
    }

    /** 卸载 chroot 时挂进去的东西（停用容器 / 换模式时调用）。 */
    fun unmount(ctx: Context, env: String = ProotLauncher.currentEnv(ctx)) {
        val rootfs = ProotLauncher.rootfs(ctx, env)
        if (!hasRoot()) return
        val cmds = listOf(
            "'$rootfs/storage/emulated/0'", "'$rootfs/opt/envs'", "'$rootfs/sdcard'",
            "'$rootfs/sys'", "'$rootfs/dev'", "'$rootfs/proc'",
        ).joinToString("; ") { "umount $it 2>/dev/null" }
        runCatching {
            ProcessBuilder("/system/bin/su", "-c", cmds).start()
        }
    }
}

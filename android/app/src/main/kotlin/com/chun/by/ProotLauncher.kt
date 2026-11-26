package com.chun.by

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.nio.file.Paths
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream

/**
 * PRoot 容器启动。一个 proot 二进制（aarch64 静态）+ 多个 rootfs 目录。
 * 内置环境 alpine：assets/rootfs.tar.gz 解压到 filesDir/alpine。
 * 其它发行版（ubuntu 等）导入到 filesDir/envs/<name>，与内置环境平级，共用同一个 proot。
 */
object ProotLauncher {
    const val ALPINE = "alpine"

    /** Alpine 官方 arm64 minirootfs（快捷安装用，仍然联网下载，不内置）。 */
    const val ALPINE_URL =
        "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.0-aarch64.tar.gz"

    private const val PREFS = "container"
    private const val K_ENV = "current_env"
    private const val ENVS_DIR = "envs"

    fun currentEnv(ctx: Context): String {
        val saved = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(K_ENV, null)
        val installed = listEnvs(ctx)
        if (saved != null && installed.contains(saved)) return saved
        return installed.firstOrNull() ?: ALPINE
    }

    fun setCurrentEnv(ctx: Context, env: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(K_ENV, env).apply()
    }

    fun envDir(ctx: Context, env: String): File = File(File(ctx.filesDir, ENVS_DIR), env)

    fun rootfs(ctx: Context, env: String = currentEnv(ctx)): String = envDir(ctx, env).absolutePath

    fun prootBin(ctx: Context): String =
        File(ctx.applicationInfo.nativeLibraryDir, "libproot.so").absolutePath

    fun listEnvs(ctx: Context): List<String> =
        File(ctx.filesDir, ENVS_DIR).listFiles()
            ?.filter { it.isDirectory }
            ?.map { it.name }
            ?.sorted()
            ?: emptyList()

    fun envInfo(ctx: Context): List<Map<String, Any>> = listEnvs(ctx).map { env ->
        mapOf(
            "name" to env,
            "ready" to isReady(ctx, env),
            "size" to dirSize(envDir(ctx, env)),
        )
    }

    private fun dirSize(dir: File): Long {
        if (!dir.exists()) return 0L
        var total = 0L
        dir.walkTopDown().forEach { if (it.isFile) total += it.length() }
        return total
    }

    fun isReady(ctx: Context, env: String = currentEnv(ctx)): Boolean {
        val root = envDir(ctx, env)
        if (!File(prootBin(ctx)).exists()) return false
        // 注意：Alpine 的 bin/sh 是指向 /bin/busybox 的绝对符号链接，在宿主上 exists() 会
        // 解析到宿主的 /bin/busybox 而返回 false；Ubuntu 的 bin -> usr/bin 同理。
        // 所以用 NOFOLLOW_LINKS 判断链接本身，并认真实文件。
        val shell = linked(root, "bin/sh") || linked(root, "bin/busybox") ||
            linked(root, "usr/bin/sh") || linked(root, "usr/bin/busybox") ||
            linked(root, "bin/bash") || linked(root, "usr/bin/bash") || linked(root, "bin/dash")
        val loader = linked(root, "lib/ld-musl-aarch64.so.1") ||
            linked(root, "lib/ld-linux-aarch64.so.1") ||
            linked(root, "usr/lib/ld-linux-aarch64.so.1") ||
            linked(root, "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1")
        return shell && loader
    }

    private fun linked(root: File, rel: String): Boolean = runCatching {
        java.nio.file.Files.exists(File(root, rel).toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)
    }.getOrDefault(false)

    /** 环境全部按需下载/导入，prepare 只做就绪检查；缺失时由 UI 引导安装。 */
    @Synchronized
    fun prepare(ctx: Context, env: String = currentEnv(ctx)): Boolean = isReady(ctx, env)

    /** 安装任意 rootfs：文件名后缀不可靠，按魔数识别 gz / xz / 未压缩 tar。 */
    fun importTar(ctx: Context, src: File, env: String, onLine: (String) -> Unit): Boolean {
        if (!env.matches(Regex("[A-Za-z0-9._-]+"))) {
            onLine("环境名无效：只能用字母、数字、. _ -")
            return false
        }
        if (!src.exists() || src.length() == 0L) {
            onLine("文件不存在或为空：${src.absolutePath}")
            return false
        }
        return try {
            val kind = sniffCompression(src)
            val strip = detectStripPrefix { openDecompressed(src, kind) }
            val dest = envDir(ctx, env)
            if (dest.exists()) dest.deleteRecursively()
            dest.mkdirs()
            onLine("解压中…（${src.length() / 1024 / 1024}MB，$kind，strip=$strip）")
            val n = openDecompressed(src, kind).use { input ->
                extractTarStream(input, dest, strip, onProgress = { pct -> onLine("解压 ${pct}MB") })
            }
            onLine("解压完成：$n 个条目")
            initRootfs(dest, env)
            val ok = isReady(ctx, env)
            onLine(if (ok) "导入完成：$env" else "导入后校验失败：缺少 /bin/sh 或动态链接器")
            ok
        } catch (e: Throwable) {
            onLine("导入失败：${e.message}")
            false
        }
    }

    /** 从 URL 直接安装：下到临时文件后按 tar 导入，链接指向哪个发行版都行。 */
    fun installFromUrl(ctx: Context, url: String, env: String, onLine: (String) -> Unit): Boolean {
        if (!env.matches(Regex("[A-Za-z0-9._-]+"))) {
            onLine("环境名无效：只能用字母、数字、. _ -")
            return false
        }
        val tmp = File(ctx.filesDir, "tmp").apply { mkdirs() }
        val dst = File(tmp, "$env-rootfs.bin")
        return try {
            onLine("下载 $url")
            if (!download(url, dst, onLine)) return false
            onLine("下载完成，识别格式…")
            val ok = importTar(ctx, dst, env, onLine)
            runCatching { dst.delete() }
            ok
        } catch (e: Throwable) {
            onLine("安装失败：${e.message}")
            false
        }
    }

    private fun initRootfs(dest: File, env: String) {
        File(dest, "etc").mkdirs()
        runCatching {
            File(dest, "etc/resolv.conf").writeText("nameserver 8.8.8.8\nnameserver 1.1.1.1\n")
            File(dest, "etc/hosts").writeText("127.0.0.1 localhost\n::1 localhost\n")
        }
        // Alpine minirootfs 不带软件源，不写进去 apk add 会报 "no repositories"
        if (File(dest, "etc/alpine-release").exists()) {
            val release = File(dest, "etc/alpine-release").readText().trim()
                .substringBeforeLast('.').takeIf { it.isNotEmpty() } ?: "3.21"
            File(dest, "etc/apk").mkdirs()
            File(dest, "etc/apk/repositories").writeText(
                "https://mirrors.huaweicloud.com/alpine/v$release/main\n" +
                    "https://mirrors.huaweicloud.com/alpine/v$release/community\n"
            )
        }
    }

    /** 读前几个字节判断压缩格式；不为 .tar.gz 时一律当作未压缩 tar。 */
    private fun sniffCompression(f: File): String = FileInputStream(f).use { ins ->
        val b = ByteArray(6)
        val n = ins.read(b)
        when {
            n >= 2 && b[0] == 0x1f.toByte() && b[1] == 0x8b.toByte() -> "gz"
            n >= 6 && b[0] == 0xfd.toByte() && b[1] == 0x37.toByte() && b[2] == 0x7a.toByte() &&
                b[3] == 0x58.toByte() && b[4] == 0x5a.toByte() && b[5] == 0x00.toByte() -> "xz"
            else -> "tar"
        }
    }

    private fun openDecompressed(f: File, kind: String): InputStream {
        val raw = FileInputStream(f)
        return when (kind) {
            "gz" -> GZIPInputStream(raw)
            "xz" -> org.apache.commons.compress.compressors.xz.XZCompressorInputStream(raw)
            else -> raw
        }
    }

    /** 下载 rootfs 到临时文件（支持 302，带进度回调）。 */
    private fun download(url: String, dst: File, onLine: (String) -> Unit): Boolean {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20000
            readTimeout = 60000
            instanceFollowRedirects = true
        }
        return try {
            if (conn.responseCode != 200) {
                onLine("下载失败：HTTP ${conn.responseCode}")
                return false
            }
            val total = conn.contentLengthLong
            conn.inputStream.use { ins ->
                FileOutputStream(dst).use { out ->
                    val buf = ByteArray(1 shl 16)
                    var read = 0L
                    var lastTenth = -1
                    while (true) {
                        val n = ins.read(buf)
                        if (n <= 0) break
                        out.write(buf, 0, n)
                        read += n
                        if (total > 0) {
                            val tenth = (read * 10 / total).toInt()
                            if (tenth != lastTenth) {
                                lastTenth = tenth
                                onLine("下载 ${tenth * 10}%")
                            }
                        }
                    }
                }
            }
            true
        } finally {
            conn.disconnect()
        }
    }

    fun removeEnv(ctx: Context, env: String): Boolean {
        val ok = runCatching { envDir(ctx, env).deleteRecursively() }.getOrDefault(false)
        if (ok && ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(K_ENV, null) == env) {
            setCurrentEnv(ctx, listEnvs(ctx).firstOrNull() ?: ALPINE)
        }
        return ok
    }

    private val running = java.util.concurrent.ConcurrentHashMap<String, Process>()
    private val allRunning = java.util.Collections.newSetFromMap(
        java.util.concurrent.ConcurrentHashMap<Process, Boolean>()
    )

    /** 杀掉所有正在跑的 proot 进程（用户点停止时的急停）。 */
    fun killAll() {
        val snapshot = ArrayList(allRunning)
        for (p in snapshot) runCatching { p.destroy() }
        for (p in snapshot) runCatching { p.waitFor(1, TimeUnit.SECONDS) }
        for (p in snapshot) runCatching { p.destroyForcibly() }
        allRunning.clear()
        running.clear()
    }

    /** 杀掉某个 tag 正在跑的命令（用户点停止）。 */
    fun killStream(tag: String) {
        val p = running.remove(tag) ?: return
        runCatching { p.destroy() }
        runCatching { p.waitFor(2, TimeUnit.SECONDS) }
        runCatching { p.destroyForcibly() }
    }

    /** 流式执行：每读到一行就回调（供插件/抓包实时显示）。 */
    fun execStream(
        ctx: Context,
        cmd: String,
        tag: String = "",
        timeoutSec: Long = 600,
        env: String = currentEnv(ctx),
        onLine: (String) -> Unit,
        onDone: (Int) -> Unit,
    ) {
        Thread {
            var code = -1
            try {
                if (!prepare(ctx, env)) {
                    onLine("容器未就绪：$env 环境解压/导入失败")
                    onDone(-1)
                    return@Thread
                }
                val p = startProot(ctx, env, cmd)
                allRunning.add(p)
                if (tag.isNotEmpty()) running[tag] = p
                val t = Thread {
                    runCatching {
                        BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                            r.forEachLine { onLine(it) }
                        }
                    }
                }
                t.isDaemon = true
                t.start()
                runCatching {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                        r.forEachLine { onLine(it) }
                    }
                }
                val done = p.waitFor(timeoutSec, TimeUnit.SECONDS)
                if (!done) p.destroy()
                code = runCatching { p.exitValue() }.getOrDefault(-1)
                t.join(800)
            } catch (e: Throwable) {
                onLine("ERROR: ${e.message}")
            } finally {
                if (tag.isNotEmpty()) running.remove(tag)
                onDone(code)
            }
        }.start()
    }

    fun exec(ctx: Context, cmd: String, env: String = currentEnv(ctx)): Map<String, Any> {
        if (!prepare(ctx, env)) {
            return mapOf(
                "stdout" to "",
                "stderr" to "容器未就绪：$env 环境解压/导入失败",
                "code" to -1,
                "timeout" to false,
            )
        }
        return try {
            val p = startProot(ctx, env, cmd)
            allRunning.add(p)
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
            val done = p.waitFor(600, TimeUnit.SECONDS)
            if (!done) p.destroy()
            allRunning.remove(p)
            t1.join(1000); t2.join(1000)
            mapOf(
                "stdout" to out.toString(),
                "stderr" to err.toString(),
                "code" to (if (done) p.exitValue() else -1),
                "timeout" to !done,
            )
        } catch (e: Exception) {
            mapOf("stdout" to "", "stderr" to (e.message ?: "proot error"), "code" to -1, "timeout" to false)
        }
    }

    /**
     * 容器绑定：默认把 /sdcard 挂进来（读写用户文件、跑脚本）；
     * filesDir/bindings.conf 每行可追加 `源:目标`（如 /data/local/tmp:/tmp）。
     */
    fun bindings(ctx: Context): List<String> {
        val list = ArrayList<String>()
        list.add("/sdcard:/sdcard")
        // AI 常用 /storage/emulated/0 这种绝对路径，一并挂进来，避免它以为没挂载
        if (File("/storage/emulated/0").exists()) {
            list.add("/storage/emulated/0:/storage/emulated/0")
        }
        // 容器内也能装新容器：/opt/envs 就是 filesDir/envs
        File(ctx.filesDir, "envs").mkdirs()
        list.add(File(ctx.filesDir, "envs").absolutePath + ":/opt/envs")
        val conf = File(ctx.filesDir, "bindings.conf")
        if (conf.exists()) {
            runCatching {
                conf.readLines().map { it.trim() }
                    .filter { it.isNotEmpty() && !it.startsWith("#") }
                    .forEach { list.add(it) }
            }
        }
        return list
    }

    private fun startProot(ctx: Context, env: String, cmd: String): Process {
        val tmp = File(ctx.filesDir, "tmp").apply { mkdirs() }
        val libs = ctx.applicationInfo.nativeLibraryDir
        val args = ArrayList<String>()
        args.addAll(listOf(prootBin(ctx), "-r", rootfs(ctx, env), "-0"))
        args.addAll(listOf("-b", "/dev", "-b", "/proc", "-b", "/sys", "-b", "/system"))
        for (b in bindings(ctx)) {
            args.add("-b")
            args.add(b)
        }
        args.addAll(listOf("-w", "/root", "--link2symlink", "--kill-on-exit", "/bin/sh", "-c", cmd))
        val pb = ProcessBuilder(args)
        pb.environment()["PROOT_TMP_DIR"] = tmp.absolutePath
        pb.environment()["HOME"] = "/root"
        pb.environment()["LD_LIBRARY_PATH"] = "$libs:/system/lib64:/system/lib"
        pb.environment()["PROOT_LOADER"] = "$libs/libproot-loader.so"
        pb.environment()["PROOT_LOADER_32"] = "$libs/libproot-loader32.so"
        return pb.start()
    }

    private fun extractTarStream(
        input: InputStream,
        dest: File,
        stripPrefix: String = "",
        onProgress: ((Int) -> Unit)? = null,
    ): Int {
        dest.mkdirs()
        var entries = 0
        // 已知总量的 tar 才能算百分比，这里按已处理字节粗略估算
        var processedBytes = 0L
        var lastReported = -1
        input.use { gz ->
            val hdr = ByteArray(512)
            var pendingName: String? = null
            while (true) {
                if (!readFully(gz, hdr)) break
                var allZero = true
                for (b in hdr) {
                    if (b.toInt() != 0) { allZero = false; break }
                }
                if (allZero) break
                val size = readOctal(hdr, 124, 12)
                val type = hdr[156].toInt().toChar()
                val storedName = readString(hdr, 0, 100)
                val prefix = readString(hdr, 345, 155)
                val linkName = readString(hdr, 157, 100)
                val pad = (512 - (size % 512).toInt()) % 512
                var name = pendingName ?: (if (prefix.isNotEmpty()) "$prefix/$storedName" else storedName)
                if (stripPrefix.isNotEmpty() && name.startsWith(stripPrefix)) {
                    name = name.substring(stripPrefix.length)
                }
                if (name.isEmpty()) {
                    skipN(gz, size + pad)
                    processedBytes += size + pad
                    continue
                }

                if (type == 'L') {
                    val buf = ByteArray(size.toInt())
                    readFully(gz, buf)
                    pendingName = String(buf).trimEnd('\u0000')
                    skipN(gz, pad.toLong())
                    continue
                }
                if (type == 'x') {
                    val buf = ByteArray(size.toInt())
                    readFully(gz, buf)
                    for (line in String(buf).split('\n')) {
                        val idx = line.indexOf(" path=")
                        if (idx >= 0) pendingName = line.substring(idx + 6)
                    }
                    skipN(gz, pad.toLong())
                    continue
                }
                pendingName = null
                entries++

                val out = File(dest, name)
                // 用 normalize 而不是 canonicalPath：后者会把符号链接解析到宿主路径，误伤 bin/sh 这类条目
                if (!out.toPath().normalize().startsWith(dest.toPath().normalize())) {
                    skipN(gz, size + pad)
                    continue
                }
                when (type) {
                    '5' -> out.mkdirs()
                    '2' -> {
                        out.parentFile?.mkdirs()
                        runCatching { Files.deleteIfExists(out.toPath()) }
                        runCatching { Files.createSymbolicLink(out.toPath(), Paths.get(linkName)) }
                    }
                    '1' -> {
                        out.parentFile?.mkdirs()
                        runCatching { Files.createLink(out.toPath(), File(dest, linkName).toPath()) }
                    }
                    '0', '\u0000', '7' -> {
                        out.parentFile?.mkdirs()
                        FileOutputStream(out).use { fo -> copyN(gz, fo, size) }
                        out.setExecutable(true)
                    }
                    else -> skipN(gz, size)
                }
                skipN(gz, pad.toLong())
                processedBytes += size + pad
                onProgress?.let { cb ->
                    val mb = (processedBytes / (1 shl 20)).toInt()
                    if (mb / 20 != lastReported / 20) {
                        lastReported = mb
                        cb(mb)
                    }
                }
            }
        }
        return entries
    }

    private fun readFully(ins: InputStream, buf: ByteArray): Boolean {
        var off = 0
        while (off < buf.size) {
            val n = ins.read(buf, off, buf.size - off)
            if (n <= 0) return off != 0
            off += n
        }
        return true
    }

    private fun copyN(ins: InputStream, out: FileOutputStream, n: Long) {
        var left = n
        val buf = ByteArray(8192)
        while (left > 0) {
            val r = ins.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
            if (r <= 0) break
            out.write(buf, 0, r)
            left -= r
        }
    }

    private fun skipN(ins: InputStream, n: Long) {
        var left = n
        val buf = ByteArray(8192)
        while (left > 0) {
            val r = ins.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
            if (r <= 0) break
            left -= r
        }
    }

    private fun readString(h: ByteArray, off: Int, len: Int): String {
        var end = off
        val limit = minOf(off + len, h.size)
        while (end < limit && h[end].toInt() != 0) end++
        return String(h, off, end - off)
    }

    private fun readOctal(h: ByteArray, off: Int, len: Int): Long {
        var v = 0L
        var i = off
        val limit = minOf(off + len, h.size)
        while (i < limit) {
            val c = h[i].toInt()
            if (c == 0 || c == ' '.code) { i++; continue }
            if (c < '0'.code || c > '7'.code) break
            v = v * 8 + (c - '0'.code)
            i++
        }
        return v
    }

    /** 若 tar 所有条目都在同一个顶层目录下（如 alpine/ 或 ./），返回该前缀。 */
    private fun detectStripPrefix(open: () -> InputStream): String {
        val names = ArrayList<String>()
        try {
            open().use { gz ->
                val hdr = ByteArray(512)
                var count = 0
                while (count < 60) {
                    if (!readFully(gz, hdr)) break
                    var allZero = true
                    for (b in hdr) {
                        if (b.toInt() != 0) {
                            allZero = false
                            break
                        }
                    }
                    if (allZero) break
                    val size = readOctal(hdr, 124, 12)
                    val type = hdr[156].toInt().toChar()
                    val stored = readString(hdr, 0, 100)
                    val prefix = readString(hdr, 345, 155)
                    val full = if (prefix.isNotEmpty()) "$prefix/$stored" else stored
                    val pad = (512 - (size % 512).toInt()) % 512
                    if (type == 'x' || type == 'L') {
                        skipN(gz, size + pad)
                        continue
                    }
                    if (full.isNotEmpty()) names.add(full)
                    skipN(gz, size + pad)
                    count++
                }
            }
        } catch (_: Throwable) {
            return ""
        }
        val firsts = names.map { it.substringBefore('/') }.distinct()
        if (firsts.size != 1) return ""
        val first = firsts[0]
        if (first.isEmpty()) return ""
        if (first == ".") return "./"
        if (first in listOf("bin", "etc", "lib", "usr", "sbin", "var", "tmp", "root", "dev", "proc", "sys")) return ""
        return "$first/"
    }
}

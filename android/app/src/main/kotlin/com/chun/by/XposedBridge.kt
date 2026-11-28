package com.chun.by

import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/**
 * LSPosed 检测：查 LSPosed 的模块目录。这些目录在 /data/adb/ 下，普通 uid 读不到，
 * 所以优先用 root（su）探测；拿不到 root 时回退到直接 File.exists()（能读多少算多少）。
 */
object XposedBridge {
    private val lsposedDirs = listOf(
        "/data/adb/lspd",
        "/data/adb/modules/zygisk_lsposed",
        "/data/adb/modules/riru_lsposed",
    )

    fun isLsposedActive(): Boolean {
        // 直接读（部分内核 / KernelSU 下 /data/adb 可读）
        if (lsposedDirs.any { File(it).exists() }) return true
        // 有 root 时用 su 探测（普通应用 uid 读不到 /data/adb）
        return runCatching {
            val p = ProcessBuilder("su", "-c", "ls ${lsposedDirs.joinToString(" ")} 2>/dev/null")
                .redirectErrorStream(true)
                .start()
            val out = StringBuilder()
            val reader = Thread {
                runCatching {
                    BufferedReader(InputStreamReader(p.inputStream)).use { r ->
                        r.forEachLine { out.append(it) }
                    }
                }
            }
            reader.isDaemon = true
            reader.start()
            val done = p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)
            if (!done) p.destroyForcibly()
            reader.join(500)
            out.toString().isNotBlank()
        }.getOrDefault(false)
    }
}

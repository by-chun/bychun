package com.chun.by

import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Shizuku 执行后端：借 Shizuku 在宿主系统执行 shell（免 root，需用户授权 Shizuku）。
 */
object ShizukuBridge {
    fun available(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Throwable) {
        false
    }

    fun hasPermission(): Boolean = try {
        available() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Throwable) {
        false
    }

    fun request() {
        try {
            if (available() && !hasPermission()) Shizuku.requestPermission(4242)
        } catch (_: Throwable) {}
    }

    fun exec(cmd: String): Map<String, Any> {
        return try {
            if (!hasPermission()) {
                return mapOf("stdout" to "", "stderr" to "未授权 Shizuku", "code" to -1, "timeout" to false)
            }
            val m = Shizuku::class.java.getDeclaredMethod(
                "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
            )
            m.isAccessible = true
            val p = m.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
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
            val code = p.waitFor()
            t1.join(1000); t2.join(1000)
            mapOf("stdout" to out.toString(), "stderr" to err.toString(), "code" to code, "timeout" to false)
        } catch (e: Exception) {
            mapOf("stdout" to "", "stderr" to (e.message ?: "shizuku error"), "code" to -1, "timeout" to false)
        }
    }
}

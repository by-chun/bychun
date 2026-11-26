package com.chun.by

import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.callbacks.XC_LoadPackage.LoadPackageParam
import org.json.JSONArray
import java.io.File

/**
 * LSPosed 模块入口：被加载进目标进程后执行。
 * 读取 /data/data/com.chun.by/files/xposed_scripts.json（App 的 Xposed 页维护），
 * 找到 enabled 且 targets 含当前包名的脚本并执行其 JS。
 */
class XposedHook : IXposedHookLoadPackage {
    override fun handleLoadPackage(lpparam: LoadPackageParam) {
        try {
            val f = File("/data/data/com.chun.by/files/xposed_scripts.json")
            if (!f.exists()) return
            val arr = JSONArray(f.readText())
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (!o.optBoolean("enabled", true)) continue
                val targets = o.optJSONArray("targets") ?: continue
                var hit = false
                for (j in 0 until targets.length()) {
                    if (targets.optString(j) == lpparam.packageName) { hit = true; break }
                }
                if (!hit) continue
                val code = o.optString("code", "")
                if (code.isBlank()) continue
                XposedBridge.log("Rowan: run '${o.optString("name")}' in ${lpparam.packageName}")
                try {
                    val r = XposedJsEngine.run(code, lpparam.classLoader)
                    XposedBridge.log("Rowan: script $r")
                } catch (t: Throwable) {
                    XposedBridge.log("Rowan: script error ${t.message}")
                }
            }
        } catch (_: Throwable) {}
    }
}

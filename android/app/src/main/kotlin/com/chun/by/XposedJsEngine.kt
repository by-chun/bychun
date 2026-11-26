package com.chun.by

import android.util.Log
import de.robv.android.xposed.XposedBridge as XB
import de.robv.android.xposed.XposedHelpers
import org.mozilla.javascript.Context
import org.mozilla.javascript.ImporterTopLevel
import org.mozilla.javascript.ScriptableObject

/**
 * 在目标进程里用 Rhino 执行用户 JS Hook 脚本。
 * 脚本可直接用 XposedHelpers / XposedBridge（LSPosed 注入的 classic API）和 classLoader。
 */
object XposedJsEngine {
    private const val TAG = "Rowan-Xposed"

    fun run(script: String, loader: ClassLoader): String {
        val cx = Context.enter()
        try {
            cx.optimizationLevel = -1
            cx.languageVersion = Context.VERSION_ES6
            val scope = ImporterTopLevel(cx)
            ScriptableObject.putProperty(scope, "classLoader", Context.javaToJS(loader, scope))
            ScriptableObject.putProperty(scope, "XposedHelpers", Context.javaToJS(XposedHelpers::class.java, scope))
            ScriptableObject.putProperty(scope, "XposedBridge", Context.javaToJS(XB::class.java, scope))
            ScriptableObject.putProperty(scope, "Log", Context.javaToJS(Log::class.java, scope))
            cx.evaluateString(scope, script, "g_hook.js", 1, null)
            return "ok"
        } finally {
            Context.exit()
        }
    }
}

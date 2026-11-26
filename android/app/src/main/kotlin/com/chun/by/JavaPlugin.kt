package com.chun.by

import android.content.Context
import dalvik.system.DexClassLoader
import java.io.File

/**
 * Java 插件运行时：加载容器里编译出来的 dex，反射调用入口。
 * 约定入口：public static void run(android.content.Context ctx)
 *       或：public void run(android.content.Context ctx)
 */
object JavaPlugin {
    private var loader: DexClassLoader? = null

    fun run(ctx: Context, dexPath: String, className: String): String {
        val dex = File(dexPath)
        if (!dex.exists()) return "dex 不存在：$dexPath"
        return try {
            val out = File(ctx.codeCacheDir, "java_plugins").apply { mkdirs() }
            val cl = DexClassLoader(
                dex.absolutePath,
                out.absolutePath,
                null,
                ctx.classLoader,
            )
            loader = cl
            val cls = cl.loadClass(className)
            val method = runCatching { cls.getMethod("run", Context::class.java) }.getOrNull()
            if (method != null) {
                val inst = if (java.lang.reflect.Modifier.isStatic(method.modifiers)) null else cls.getDeclaredConstructor().newInstance()
                method.isAccessible = true
                method.invoke(inst, ctx)
                return "OK"
            }
            // 兼容：无参 entry()
            val entry = runCatching { cls.getMethod("entry") }.getOrNull()
            if (entry != null) {
                val inst = if (java.lang.reflect.Modifier.isStatic(entry.modifiers)) null else cls.getDeclaredConstructor().newInstance()
                entry.isAccessible = true
                entry.invoke(inst)
                return "OK"
            }
            "类里没有 run(Context) 或 entry() 方法：$className"
        } catch (e: Throwable) {
            var cur: Throwable? = e
            val sb = StringBuilder()
            while (cur != null && sb.length < 800) {
                sb.append(cur.javaClass.simpleName).append(": ").append(cur.message).append('\n')
                cur = cur.cause
            }
            "加载失败：\n$sb"
        }
    }
}

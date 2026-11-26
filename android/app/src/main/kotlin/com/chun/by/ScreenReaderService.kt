package com.chun.by

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 无障碍读屏 + 截图 + 点按/滑动/输入（无需 root）。
 * 采集到的数据交给 AI，处理（OCR/解析）放到容器里。
 */
class ScreenReaderService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: ScreenReaderService? = null
            private set

        /** 打开系统无障碍设置（供用户手动开启本服务）。 */
        fun openSettings(c: android.content.Context) {
            runCatching {
                c.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    /** dump 当前屏幕控件树 → 简化节点列表（text/desc/class/坐标/可点击/可编辑/可滚动）。 */
    fun dumpNodes(): List<Map<String, Any?>> {
        val root = rootInActiveWindow ?: return emptyList()
        val out = mutableListOf<Map<String, Any?>>()
        collect(root, out, 0)
        return out
    }

    private fun collect(node: AccessibilityNodeInfo, out: MutableList<Map<String, Any?>>, depth: Int) {
        if (depth > 32) return
        val text = node.text?.toString()?.trim().orEmpty()
        val desc = node.contentDescription?.toString()?.trim().orEmpty()
        val cls = node.className?.toString().orEmpty()
        val rect = Rect().also { node.getBoundsInScreen(it) }
        val clickable = node.isClickable
        val editable = node.isEditable
        val scrollable = node.isScrollable
        if (text.isNotEmpty() || desc.isNotEmpty() || clickable || editable || scrollable) {
            out.add(
                mapOf(
                    "text" to text,
                    "desc" to desc,
                    "cls" to (cls.split(".").lastOrNull() ?: cls),
                    "x" to rect.centerX(),
                    "y" to rect.centerY(),
                    "l" to rect.left, "t" to rect.top, "r" to rect.right, "b" to rect.bottom,
                    "clickable" to clickable,
                    "editable" to editable,
                    "scrollable" to scrollable,
                    "id" to (node.viewIdResourceName ?: ""),
                )
            )
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { collect(it, out, depth + 1) }
        }
    }

    /** 点击坐标。 */
    fun tapAt(x: Int, y: Int): Boolean {
        return gesture(Path().apply { moveTo(x.toFloat(), y.toFloat()) }, 50)
    }

    /** 滑动。 */
    fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long): Boolean {
        return gesture(
            Path().apply { moveTo(x1.toFloat(), y1.toFloat()); lineTo(x2.toFloat(), y2.toFloat()) },
            durationMs
        )
    }

    private fun gesture(path: Path, durationMs: Long): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val desc = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        val latch = CountDownLatch(1)
        val ok = dispatchGesture(
            desc,
            object : GestureResultCallback() {
                override fun onCompleted(g: GestureDescription?) { latch.countDown() }
                override fun onCancelled(g: GestureDescription?) { latch.countDown() }
            },
            null,
        )
        runCatching { latch.await(2, TimeUnit.SECONDS) }
        return ok
    }

    /** 在当前可编辑（聚焦）节点输入文字。 */
    fun typeText(text: String): Boolean {
        val node = findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = android.os.Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** 截图（API 30+ 无障碍 takeScreenshot），返回 PNG 字节，不落盘。 */
    fun captureScreenshot(): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val latch = CountDownLatch(1)
            var out: ByteArray? = null
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        try {
                            val bmp = android.graphics.Bitmap.wrapHardwareBuffer(
                                result.hardwareBuffer, result.colorSpace
                            )
                            val bos = java.io.ByteArrayOutputStream()
                            bmp?.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, bos)
                            out = bos.toByteArray()
                        } catch (_: Throwable) {
                        } finally {
                            latch.countDown()
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        latch.countDown()
                    }
                },
            )
            runCatching { latch.await(3, TimeUnit.SECONDS) }
            out
        } catch (_: Throwable) {
            null
        }
    }
}

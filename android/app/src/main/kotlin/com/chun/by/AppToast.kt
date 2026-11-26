package com.chun.by

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView

/**
 * 应用内自绘的轻提示。
 * 系统 Toast 从 Android 11 起不允许自定义样式，所以统一用 decorView 上的浮层。
 */
object AppToast {
    fun show(activity: Activity, msg: String, error: Boolean = false) {
        activity.runOnUiThread {
            val density = activity.resources.displayMetrics.density
            fun dp(v: Int) = (v * density).toInt()
            val tv = TextView(activity).apply {
                text = msg
                textSize = 12.5f
                setTextColor(if (error) Color.parseColor("#FEE2E2") else Color.parseColor("#E2E8F0"))
                setPadding(dp(16), dp(10), dp(16), dp(10))
                background = GradientDrawable().apply {
                    cornerRadius = dp(12).toFloat()
                    setColor(if (error) Color.parseColor("#DC2626") else Color.parseColor("#0F172A"))
                }
            }
            val root = activity.window.decorView as? FrameLayout ?: return@runOnUiThread
            val lp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(110)
            }
            root.addView(tv, lp)
            tv.alpha = 0f
            tv.animate().alpha(1f).setDuration(140).start()
            tv.postDelayed({
                tv.animate().alpha(0f).setDuration(200).withEndAction { root.removeView(tv) }.start()
            }, 1600)
        }
    }
}

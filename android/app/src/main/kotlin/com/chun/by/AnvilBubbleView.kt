package com.chun.by

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/**
 * 悬浮球：白底圆 + 「A」字形铁砧（A 的两条腿 = 砧身，横杠 = 砧面，下方 = 底座）。
 */
class AnvilBubbleView(context: Context) : View(context) {
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFE2E8F0.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF0B1220.toInt()
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF0B1220.toInt()
        style = Paint.Style.FILL
    }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x220F172A
        style = Paint.Style.FILL
        maskFilter = android.graphics.BlurMaskFilter(6f, android.graphics.BlurMaskFilter.Blur.NORMAL)
    }
    private val legs = Path()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val def = (56 * resources.displayMetrics.density).toInt()
        val w = if (MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.EXACTLY && MeasureSpec.getSize(widthMeasureSpec) > 0)
            MeasureSpec.getSize(widthMeasureSpec) else def
        val h = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.EXACTLY && MeasureSpec.getSize(heightMeasureSpec) > 0)
            MeasureSpec.getSize(heightMeasureSpec) else def
        setMeasuredDimension(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val r = minOf(w, h) / 2f - 3f
        val cx = w / 2f
        val cy = h / 2f

        canvas.drawCircle(cx, cy + 2f, r, shadow)
        canvas.drawCircle(cx, cy, r, bg)
        canvas.drawCircle(cx, cy, r, ring)

        // 按 200x200 视口缩放到球内
        val s = (r * 2f * 0.66f) / 200f
        val ox = cx - 100f * s
        val oy = cy - 100f * s

        stroke.strokeWidth = 16f * s
        legs.reset()
        legs.moveTo(ox + 54f * s, oy + 158f * s)
        legs.lineTo(ox + 100f * s, oy + 50f * s)
        legs.lineTo(ox + 146f * s, oy + 158f * s)
        canvas.drawPath(legs, stroke)

        // 砧面
        val face = Path().apply {
            moveTo(ox + 64f * s, oy + 112f * s)
            lineTo(ox + 136f * s, oy + 112f * s)
            lineTo(ox + 128f * s, oy + 130f * s)
            lineTo(ox + 72f * s, oy + 130f * s)
            close()
        }
        canvas.drawPath(face, fill)

        // 底座
        canvas.drawRoundRect(
            RectF(ox + 84f * s, oy + 134f * s, ox + 116f * s, oy + 144f * s),
            4f * s, 4f * s, fill
        )
    }
}

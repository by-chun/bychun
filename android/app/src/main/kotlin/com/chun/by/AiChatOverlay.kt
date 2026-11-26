package com.chun.by

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * AI 对话浮窗：折叠时是一枚胶囊（状态 + 步数），点开变成小窗，可拖动并自动吸附左右边缘。
 * 所有交互通过 onEvent 回传给 Flutter（send / stop）。
 */
class AiChatOverlay(private val ctx: Context, private val onEvent: (String, String) -> Unit) {
    private val wm: WindowManager =
        ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()

    private var pill: View? = null
    private var card: View? = null
    private var pillLp: WindowManager.LayoutParams? = null
    private var cardLp: WindowManager.LayoutParams? = null
    private var pillState: TextView? = null
    private var cardState: TextView? = null
    private var cardBody: LinearLayout? = null
    private var cardScroll: ScrollView? = null
    private val msgs = mutableListOf<Pair<String, String>>()
    private var state = "待命"

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    private fun bg(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        if (stroke != null) setStroke(dp(1), stroke)
    }

    private fun txt(s: String, size: Float, color: Int, bold: Boolean = false) = TextView(ctx).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        includeFontPadding = false
    }

    fun show() {
        if (pill == null && card == null) {
            try {
                OverlayService.instance?.hideBubble()
                addPill()
            } catch (e: Exception) {
                android.util.Log.e("AiChatOverlay", "addPill failed", e)
            }
        }
    }

    fun hide() {
        removePill()
        removeCard()
        OverlayService.instance?.restoreBubble()
    }

    fun setState(s: String) {
        state = s
        pillState?.text = s
        cardState?.text = s
    }

    fun push(role: String, text: String) {
        msgs.add(role to text)
        while (msgs.size > 10) msgs.removeAt(0)
        render()
        cardScroll?.post { cardScroll?.fullScroll(View.FOCUS_DOWN) }
    }

    // ---------------- 折叠胶囊 ----------------

    private fun addPill() {
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(11), dp(8), dp(14), dp(8))
            background = bg(0xF2FFFFFF.toInt(), 22, 0x40FFFFFF)
            elevation = dp(8).toFloat()
        }
        val dot = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF22C55E.toInt())
            }
        }
        box.addView(dot, LinearLayout.LayoutParams(dp(9), dp(9)).apply { rightMargin = dp(8) })

        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        col.addView(txt("Rowan", 12f, 0xFF0F172A.toInt(), true))
        val s = txt(state, 10f, 0xFF64748B.toInt())
        col.addView(s)
        box.addView(col)
        pillState = s

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = dp(140)
        }
        attachDrag(box, lp) { openCard() }
        wm.addView(box, lp)
        pill = box
        pillLp = lp
    }

    private fun removePill() {
        pill?.let { runCatching { wm.removeView(it) } }
        pill = null
        pillLp = null
        pillState = null
    }

    // ---------------- 展开小窗 ----------------

    private fun openCard() {
        if (card != null) return
        removePill()
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = bg(0xF2FFFFFF.toInt(), 20, 0x4DFFFFFF)
            elevation = dp(14).toFloat()
        }

        // 头部（可拖动）
        val head = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(8), dp(8))
        }
        val avatar = TextView(ctx).apply {
            text = "R"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = bg(0xFF2563EB.toInt(), 7)
        }
        head.addView(avatar, LinearLayout.LayoutParams(dp(22), dp(22)).apply { rightMargin = dp(8) })
        val titleCol = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        titleCol.addView(txt("Rowan", 12f, 0xFF0F172A.toInt(), true))
        val st = txt(state, 9.5f, 0xFF64748B.toInt())
        titleCol.addView(st)
        cardState = st
        head.addView(titleCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val collapse = txt("—", 15f, 0xFF475569.toInt()).apply {
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(2), dp(8), dp(2))
            setOnClickListener { closeCard() }
        }
        val close = txt("✕", 13f, 0xFF475569.toInt()).apply {
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(2), dp(8), dp(2))
            setOnClickListener { hide() }
        }
        head.addView(collapse)
        head.addView(close)
        root.addView(head)

        // 消息区
        val body = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(0), dp(12), dp(6))
        }
        cardBody = body
        val scroll = ScrollView(ctx).apply {
            isFillViewport = false
            addView(body)
        }
        cardScroll = scroll
        // 高度随内容走，不要写死成一大块空白
        root.addView(
            scroll,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = dp(4); bottomMargin = dp(4) },
        )

        // 输入行
        val inputRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(4), dp(10), dp(10))
        }
        val edit = EditText(ctx).apply {
            hint = "说点什么…"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setHintTextColor(0xFF94A3B8.toInt())
            setTextColor(0xFF0F172A.toInt())
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setSingleLine(true)
            background = bg(0xFFF7F9FC.toInt(), 12, 0xFFE2E8F0.toInt())
            setPadding(dp(10), dp(7), dp(10), dp(7))
        }
        inputRow.addView(edit, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val stop = txt("停", 11f, 0xFFDC2626.toInt(), true).apply {
            gravity = Gravity.CENTER
            background = bg(0x14DC2626, 12)
            setPadding(dp(10), dp(7), dp(10), dp(7))
            setOnClickListener { onEvent("stop", "") }
        }
        val send = txt("↑", 14f, Color.WHITE, true).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF2563EB.toInt())
            }
            setOnClickListener {
                val t = edit.text?.toString()?.trim().orEmpty()
                if (t.isNotEmpty()) {
                    edit.setText("")
                    push("user", t)
                    onEvent("send", t)
                }
            }
        }
        inputRow.addView(stop, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(6) })
        inputRow.addView(send, LinearLayout.LayoutParams(dp(30), dp(30)).apply { leftMargin = dp(6) })
        root.addView(inputRow)

        val lp = WindowManager.LayoutParams(
            dp(310),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = dp(90)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        attachDrag(head, lp) { }
        try {
            wm.addView(root, lp)
        } catch (e: Exception) {
            android.util.Log.e("AiChatOverlay", "addView card failed", e)
            return
        }
        card = root
        cardLp = lp
        render()
    }

    private fun closeCard() {
        removeCard()
        if (pill == null) addPill()
    }

    private fun removeCard() {
        card?.let { runCatching { wm.removeView(it) } }
        card = null
        cardLp = null
        cardBody = null
        cardScroll = null
        cardState = null
    }

    private fun render() {
        val body = cardBody ?: return
        body.removeAllViews()
        if (msgs.isEmpty()) {
            body.addView(
                txt("AI 正在操作，需要时可以直接在这里说。", 11.5f, 0xFF94A3B8.toInt()).apply {
                    setPadding(dp(12), dp(10), dp(12), dp(10))
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        for ((role, text) in msgs) {
            val user = role == "user"
            val tv = txt(text, 11.5f, if (user) Color.WHITE else 0xFF0F172A.toInt()).apply {
                setPadding(dp(9), dp(7), dp(9), dp(7))
                background = if (user) bg(0xFF2563EB.toInt(), 11)
                else bg(Color.WHITE, 11, 0xFFEEF2F7.toInt())
                setLineSpacing(dp(2).toFloat(), 1f)
                maxLines = 6
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            val row = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = if (user) Gravity.END else Gravity.START
            }
            row.addView(tv, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { leftMargin = if (user) dp(36) else 0; rightMargin = if (user) 0 else dp(24) })
            body.addView(row, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(6) })
        }
    }

    // ---------------- 拖动 + 吸边 ----------------

    private fun attachDrag(v: View, lp: WindowManager.LayoutParams, onClick: () -> Unit) {
        var sx = 0f
        var sy = 0f
        var ox = 0
        var oy = 0
        var moved = false
        v.setOnTouchListener { view, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    sx = e.rawX
                    sy = e.rawY
                    ox = lp.x
                    oy = lp.y
                    moved = false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!moved &&
                        (kotlin.math.abs(e.rawX - sx) > dp(6) || kotlin.math.abs(e.rawY - sy) > dp(6))
                    ) moved = true
                    if (moved) {
                        lp.x = (ox + (e.rawX - sx)).toInt()
                        lp.y = (oy + (e.rawY - sy)).toInt()
                        runCatching { wm.updateViewLayout(view, lp) }
                    }
                    moved
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        val sw = ctx.resources.displayMetrics.widthPixels
                        lp.x = if (lp.x + view.width / 2 < sw / 2) dp(4) else sw - view.width - dp(4)
                        runCatching { wm.updateViewLayout(view, lp) }
                        true
                    } else {
                        onClick()
                        false
                    }
                }
                else -> false
            }
        }
    }
}

package com.nxg.openclawproot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class AgentOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var statusText: TextView? = null
    private var stepBadge: TextView? = null
    private var pauseBtn: TextView? = null
    private var inputRow: LinearLayout? = null
    private var inputEdit: EditText? = null
    private var inputSend: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isPaused = false
    private var inputVisible = false

    companion object {
        var instance: AgentOverlayService? = null
            private set

        fun show(context: Context, status: String, step: Int) {
            val intent = Intent(context, AgentOverlayService::class.java).apply {
                putExtra("status", status)
                putExtra("step", step)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(status: String, step: Int, paused: Boolean = false) {
            instance?.let { inst ->
                inst.statusText?.post {
                    inst.statusText?.text = status
                    inst.stepBadge?.text = "${step}"
                    inst.isPaused = paused
                    inst.pauseBtn?.text = if (paused) "▶" else "‖"
                    // 暂停时自动显示输入框，恢复时自动隐藏
                    if (paused && !inst.inputVisible) {
                        showInput("输入新指令或反馈...")
                    } else if (!paused && inst.inputVisible) {
                        hideInput()
                    }
                }
            }
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, AgentOverlayService::class.java))
        }

        fun showInput(hint: String) {
            instance?.let { inst ->
                inst.inputEdit?.post {
                    inst.inputEdit?.hint = hint
                    inst.inputEdit?.setText("")
                    inst.inputRow?.visibility = View.VISIBLE
                    inst.inputVisible = true
                    // Expand window and allow keyboard
                    inst.params?.let { p ->
                        p.width = inst.dp(320)
                        p.height = WindowManager.LayoutParams.WRAP_CONTENT
                        p.flags = p.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                    }
                    inst.windowManager?.updateViewLayout(inst.overlayView, inst.params)
                    inst.inputEdit?.requestFocus()
                    // Show keyboard
                    val imm = inst.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                    imm.showSoftInput(inst.inputEdit, InputMethodManager.SHOW_IMPLICIT)
                }
            }
        }

        fun hideInput() {
            instance?.let { inst ->
                inst.inputEdit?.post {
                    inst.inputRow?.visibility = View.GONE
                    inst.inputVisible = false
                    // Restore window size and flags
                    inst.params?.let { p ->
                        p.width = inst.dp(210)
                        p.height = inst.dp(38)
                        p.flags = p.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    }
                    inst.windowManager?.updateViewLayout(inst.overlayView, inst.params)
                    // Hide keyboard
                    val imm = inst.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                    imm.hideSoftInputFromWindow(inst.inputEdit?.windowToken, 0)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val status = intent?.getStringExtra("status") ?: "..."
        val step = intent?.getIntExtra("step", 0) ?: 0
        showOverlay(status, step)
        startForeground(1002, buildNotification())
        return START_STICKY
    }

    private fun showOverlay(status: String, step: Int) {
        if (overlayView != null) {
            statusText?.text = status
            stepBadge?.text = "${step}"
            return
        }

        val pillWidth = dp(210)
        val pillHeight = dp(38)

        // Root container (vertical: row1 + inputRow)
        val rootContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(19).toFloat()
                setColor(Color.argb(185, 18, 18, 18))
                setStroke(dp(1.2f), Color.argb(100, 37, 99, 235))
            }
        }

        // Row 1: pill bar (pause + status + step)
        val row1 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(4), dp(8), dp(4))
        }

        // Pause / Play button
        pauseBtn = TextView(this).apply {
            text = "‖"
            textSize = 13f
            setTextColor(Color.argb(220, 255, 255, 255))
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(dp(28), dp(28)).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(60, 255, 255, 255))
            }
            setOnClickListener {
                if (isPaused) {
                    isPaused = false
                    text = "‖"
                    MainActivity.sendOverlayAction("resume")
                } else {
                    isPaused = true
                    text = "▶"
                    MainActivity.sendOverlayAction("pause")
                }
            }
        }
        row1.addView(pauseBtn)

        // Spacer
        val spacer1 = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(1))
        }
        row1.addView(spacer1)

        // Status text
        statusText = TextView(this).apply {
            text = status
            textSize = 12f
            setTextColor(Color.argb(230, 255, 255, 255))
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ).apply { gravity = Gravity.CENTER_VERTICAL }
        }
        row1.addView(statusText)

        // Spacer
        val spacer2 = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(6), dp(1))
        }
        row1.addView(spacer2)

        // Step badge
        stepBadge = TextView(this).apply {
            text = "${step}"
            textSize = 11f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(dp(22), dp(22)).apply {
                gravity = Gravity.CENTER_VERTICAL
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(120, 37, 99, 235))
            }
        }
        row1.addView(stepBadge)
        rootContainer.addView(row1)

        // Row 2: input (hidden by default)
        inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            setPadding(dp(8), 0, dp(8), dp(6))
        }

        inputEdit = EditText(this).apply {
            textSize = 12f
            setTextColor(Color.WHITE)
            setHintTextColor(Color.argb(120, 255, 255, 255))
            hint = "输入验证码或反馈..."
            setSingleLine(true)
            layoutParams = LinearLayout.LayoutParams(0, dp(34), 1f).apply {
                marginEnd = dp(6)
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(8).toFloat()
                setColor(Color.argb(60, 255, 255, 255))
            }
            setPadding(dp(10), 0, dp(10), 0)
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    sendInput()
                    true
                } else false
            }
        }
        inputRow!!.addView(inputEdit)

        inputSend = TextView(this).apply {
            text = "发送"
            textSize = 12f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(dp(48), dp(34))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(8).toFloat()
                setColor(Color.argb(180, 37, 99, 235))
            }
            setOnClickListener { sendInput() }
        }
        inputRow!!.addView(inputSend)
        rootContainer.addView(inputRow)

        params = WindowManager.LayoutParams(
            pillWidth, pillHeight,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(12)
            y = dp(120)
        }

        // Touch handling for drag (only on row1, not input)
        var dragStartX = 0f
        var dragStartY = 0f
        rootContainer.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params!!.x
                    initialY = params!!.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    dragStartX = event.rawX
                    dragStartY = event.rawY
                    false // don't consume, let children handle
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - dragStartX
                    val dy = event.rawY - dragStartY
                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                        params!!.x = initialX + (event.rawX - initialTouchX).toInt()
                        params!!.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager?.updateViewLayout(rootContainer, params)
                        true
                    } else false
                }
                MotionEvent.ACTION_UP -> false
                else -> false
            }
        }
        overlayView = rootContainer

        windowManager?.addView(overlayView, params)
    }

    private fun sendInput() {
        val text = inputEdit?.text?.toString()?.trim() ?: return
        if (text.isEmpty()) return
        MainActivity.sendOverlayAction("input:$text")
        hideInput()
    }

    private fun dp(v: Number): Int = (v.toFloat() * resources.displayMetrics.density).toInt()

    private fun buildNotification(): Notification {
        val channelId = "agent_overlay_channel"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("手机操控中")
            .setContentText("Agent 正在操作手机")
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "agent_overlay_channel",
                "Agent 操控",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "手机 Agent 操作通知"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        if (overlayView != null) {
            windowManager?.removeView(overlayView)
            overlayView = null
        }
        instance = null
        super.onDestroy()
    }
}

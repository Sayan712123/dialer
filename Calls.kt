package com.example.contacts_dialer

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

object CallHolder {
    var call: Call? = null
    var service: CallService? = null
    var listener: (() -> Unit)? = null
    val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            service?.refreshNotification()
            listener?.invoke()
        }

        override fun onDetailsChanged(call: Call, details: Call.Details) {
            listener?.invoke()
        }
    }
}

/** Android Telecom hands every call to this service once we are the default phone app. */
class CallService : InCallService() {
    override fun onCreate() {
        super.onCreate()
        CallHolder.service = this
    }

    override fun onDestroy() {
        CallHolder.service = null
        super.onDestroy()
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallHolder.call = call
        call.registerCallback(CallHolder.callback)
        refreshNotification()
        try {
            startActivity(
                Intent(this, InCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            // The notification is the fallback way back into the call screen.
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(CallHolder.callback)
        CallHolder.call = calls.firstOrNull { it != call }
        refreshNotification()
        CallHolder.listener?.invoke()
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState?) {
        super.onCallAudioStateChanged(audioState)
        CallHolder.listener?.invoke()
    }

    /** Full-screen notification while ringing, small ongoing notification during a call. */
    fun refreshNotification() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val call = CallHolder.call
        if (call == null) {
            nm.cancel(NOTIF_ID)
            return
        }
        val ringing = call.state == Call.STATE_RINGING
        val channel = if (ringing) CH_INCOMING else CH_ONGOING
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(
                channel,
                if (ringing) "Incoming calls" else "Ongoing calls",
                if (ringing) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_LOW
            )
            ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, InCallActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel)
        else Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(if (ringing) "Incoming call" else "Ongoing call")
            .setContentText(call.details.handle?.schemeSpecificPart ?: "Unknown number")
            .setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(pi)
            .setOngoing(true)
        if (ringing) b.setFullScreenIntent(pi, true)
        nm.notify(NOTIF_ID, b.build())
    }

    companion object {
        const val CH_INCOMING = "incoming_calls"
        const val CH_ONGOING = "ongoing_calls"
        const val NOTIF_ID = 42
    }
}

/** Full-screen call UI styled after the Xiaomi call screen: incoming and ongoing. */
class InCallActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var nameView: TextView
    private lateinit var numberView: TextView
    private lateinit var statusView: TextView
    private lateinit var buttons: LinearLayout
    private var shownNumber: String? = null
    private var shownLabel: String = "Unknown"
    private var lastKey = ""
    private var keypadOpen = false

    private val tick = object : Runnable {
        override fun run() {
            refresh()
            handler.postDelayed(this, 1000)
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.background = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.parseColor("#34539F"), Color.parseColor("#0C1024"), Color.parseColor("#2C3347"))
        )
        root.setPadding(dp(28), dp(120), dp(28), dp(40))

        nameView = TextView(this)
        nameView.setTextColor(Color.WHITE)
        nameView.textSize = 38f
        nameView.typeface = android.graphics.Typeface.create("sans-serif-light", android.graphics.Typeface.NORMAL)

        numberView = TextView(this)
        numberView.setTextColor(Color.parseColor("#E6FFFFFF"))
        numberView.textSize = 20f
        numberView.setPadding(0, dp(6), 0, 0)

        statusView = TextView(this)
        statusView.setTextColor(Color.WHITE)
        statusView.textSize = 26f
        statusView.setPadding(0, dp(36), 0, 0)

        buttons = LinearLayout(this)
        buttons.orientation = LinearLayout.VERTICAL

        root.addView(nameView)
        root.addView(numberView)
        root.addView(statusView)
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(buttons, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        CallHolder.listener = { runOnUiThread { refresh() } }
        handler.post(tick)
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        CallHolder.listener = null
        super.onPause()
    }

    // Back just hides the call screen; the ongoing-call notification brings it back.
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        moveTaskToBack(true)
    }

    private fun lookupName(number: String): String? {
        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)
            )
            contentResolver.query(
                uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst()) return c.getString(0)
            }
        } catch (e: Exception) {
        }
        return null
    }

    private fun elapsed(connectMs: Long): String {
        if (connectMs <= 0L) return "Connected"
        val sec = ((System.currentTimeMillis() - connectMs) / 1000).coerceAtLeast(0)
        return String.format("%02d:%02d", sec / 60, sec % 60)
    }

    private fun refresh() {
        val call = CallHolder.call
        if (call == null) {
            finish()
            return
        }
        val details = call.details
        val number = details.handle?.schemeSpecificPart
        if (number != shownNumber || shownNumber == null) {
            shownNumber = number
            val display = details.callerDisplayName
            shownLabel = (if (number != null) lookupName(number) else null)
                ?: (if (!display.isNullOrEmpty()) display else null)
                ?: number
                ?: "Unknown"
        }
        nameView.text = shownLabel
        numberView.text = if (number != null && number != shownLabel) number else ""

        val state = call.state
        statusView.text = when (state) {
            Call.STATE_RINGING -> "Incall"
            Call.STATE_DIALING, Call.STATE_CONNECTING -> "Calling…"
            Call.STATE_ACTIVE -> elapsed(details.connectTimeMillis)
            Call.STATE_HOLDING -> "On hold"
            Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> "Call ended"
            else -> ""
        }

        val audio = CallHolder.service?.callAudioState
        val muted = audio?.isMuted == true
        val speaker = audio?.route == CallAudioState.ROUTE_SPEAKER
        val kind = when (state) {
            Call.STATE_RINGING -> "ringing"
            Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> "ended"
            Call.STATE_HOLDING -> "holding"
            else -> "active"
        }
        val key = "$kind-$muted-$speaker-$keypadOpen"
        if (key != lastKey) {
            lastKey = key
            buildButtons(call, kind, muted, speaker)
        }
    }

    private val glass get() = Color.argb(64, 255, 255, 255)
    private val glassOn get() = Color.argb(230, 255, 255, 255)

    private fun circle(
        glyph: String,
        caption: String?,
        fill: Int,
        glyphColor: Int = Color.WHITE,
        size: Int = 84,
        rotate: Float = 0f,
        onClick: () -> Unit
    ): LinearLayout {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.gravity = Gravity.CENTER_HORIZONTAL
        col.setPadding(0, dp(10), 0, dp(10))

        val c = TextView(this)
        c.text = glyph
        c.textSize = 28f
        c.setTextColor(glyphColor)
        c.gravity = Gravity.CENTER
        c.rotation = rotate
        val bg = GradientDrawable()
        bg.shape = GradientDrawable.OVAL
        bg.setColor(fill)
        c.background = bg
        col.addView(c, LinearLayout.LayoutParams(dp(size), dp(size)))

        if (caption != null) {
            val t = TextView(this)
            t.text = caption
            t.textSize = 14f
            t.setTextColor(Color.WHITE)
            t.gravity = Gravity.CENTER
            t.setPadding(0, dp(8), 0, 0)
            col.addView(t)
        }
        col.setOnClickListener { onClick() }
        return col
    }

    private fun row3(a: View?, b: View?, c: View?): LinearLayout {
        val r = LinearLayout(this)
        r.orientation = LinearLayout.HORIZONTAL
        for (v in listOf(a, b, c)) {
            r.addView(
                v ?: View(this),
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            )
        }
        return r
    }

    private fun keypadGrid(call: Call): LinearLayout {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        val keys = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#")
        for (r in 0 until 4) {
            val row = LinearLayout(this)
            row.orientation = LinearLayout.HORIZONTAL
            for (k in keys.subList(r * 3, r * 3 + 3)) {
                val t = TextView(this)
                t.text = k
                t.textSize = 30f
                t.setTextColor(Color.WHITE)
                t.gravity = Gravity.CENTER
                t.setPadding(0, dp(12), 0, dp(12))
                t.setOnClickListener {
                    call.playDtmfTone(k[0])
                    handler.postDelayed({ call.stopDtmfTone() }, 150)
                }
                row.addView(t, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            }
            col.addView(row)
        }
        return col
    }

    private fun buildButtons(call: Call, kind: String, muted: Boolean, speaker: Boolean) {
        buttons.removeAllViews()
        val red = Color.parseColor("#EF4444")
        val green = Color.parseColor("#34B948")
        when (kind) {
            "ringing" -> {
                val decline = circle("✆", null, red, size = 88, rotate = 135f) { call.reject(false, null) }
                val answer = circle("✆", null, green, size = 88) { call.answer(VideoProfile.STATE_AUDIO_ONLY) }
                buttons.addView(row3(decline, null, answer))
                val sms = TextView(this)
                sms.text = "SMS reply"
                sms.textSize = 16f
                sms.setTextColor(Color.WHITE)
                sms.gravity = Gravity.CENTER
                sms.setPadding(dp(22), dp(10), dp(22), dp(10))
                val pill = GradientDrawable()
                pill.cornerRadius = dp(24).toFloat()
                pill.setColor(glass)
                sms.background = pill
                sms.setOnClickListener {
                    call.reject(true, "I can't talk right now. I'll call you back.")
                }
                val wrap = LinearLayout(this)
                wrap.gravity = Gravity.CENTER
                wrap.setPadding(0, dp(28), 0, 0)
                wrap.addView(sms)
                buttons.addView(wrap)
            }
            "ended" -> {
            }
            else -> {
                if (keypadOpen) {
                    buttons.addView(keypadGrid(call))
                    buttons.addView(
                        row3(
                            circle("⣿", "Hide", glass) { keypadOpen = false; refresh() },
                            circle("✆", null, red, rotate = 135f) { call.disconnect() },
                            null
                        )
                    )
                } else {
                    buttons.addView(
                        row3(
                            circle("🎙", if (muted) "Unmute" else "Mute", if (muted) glassOn else glass,
                                if (muted) Color.BLACK else Color.WHITE) {
                                CallHolder.service?.setMuted(!muted)
                            },
                            circle("⏸", if (kind == "holding") "Resume" else "Hold",
                                if (kind == "holding") glassOn else glass,
                                if (kind == "holding") Color.BLACK else Color.WHITE) {
                                if (kind == "holding") call.unhold() else call.hold()
                            },
                            circle("＋", "Add call", glass) {
                                startActivity(
                                    Intent(this, MainActivity::class.java)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            }
                        )
                    )
                    buttons.addView(
                        row3(
                            circle("🔊", "Speaker", if (speaker) glassOn else glass,
                                if (speaker) Color.BLACK else Color.WHITE) {
                                CallHolder.service?.setAudioRoute(
                                    if (speaker) CallAudioState.ROUTE_EARPIECE else CallAudioState.ROUTE_SPEAKER
                                )
                            },
                            circle("✆", null, red, rotate = 135f) { call.disconnect() },
                            circle("⣿", "Keypad", glass) { keypadOpen = true; refresh() }
                        )
                    )
                }
            }
        }
    }
}

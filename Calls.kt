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
        if (call.state == Call.STATE_RINGING) showIncoming(call)
        try {
            startActivity(
                Intent(this, InCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            // The full-screen notification below is the fallback.
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(CallHolder.callback)
        CallHolder.call = calls.firstOrNull { it != call }
        getSystemService(NotificationManager::class.java)?.cancel(NOTIF_ID)
        CallHolder.listener?.invoke()
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState?) {
        super.onCallAudioStateChanged(audioState)
        CallHolder.listener?.invoke()
    }

    private fun showIncoming(call: Call) {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL, "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
            ch.setSound(null, null)
            nm.createNotificationChannel(ch)
        }
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, InCallActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle("Incoming call")
            .setContentText(call.details.handle?.schemeSpecificPart ?: "Unknown number")
            .setCategory(Notification.CATEGORY_CALL)
            .setFullScreenIntent(pi, true)
            .setContentIntent(pi)
            .setOngoing(true)
        nm.notify(NOTIF_ID, b.build())
    }

    companion object {
        const val CHANNEL = "incoming_calls"
        const val NOTIF_ID = 42
    }
}

/** Simple full-screen call UI: incoming (answer/decline) and ongoing (mute/speaker/hold/end). */
class InCallActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var nameView: TextView
    private lateinit var statusView: TextView
    private lateinit var buttons: LinearLayout
    private var shownNumber: String? = null
    private var shownLabel: String = "Unknown"
    private var lastKey = ""

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
        root.gravity = Gravity.CENTER_HORIZONTAL
        root.setBackgroundColor(Color.parseColor("#101114"))
        root.setPadding(dp(24), dp(96), dp(24), dp(48))

        nameView = TextView(this)
        nameView.setTextColor(Color.WHITE)
        nameView.textSize = 32f
        nameView.gravity = Gravity.CENTER

        statusView = TextView(this)
        statusView.setTextColor(Color.parseColor("#A0A4AB"))
        statusView.textSize = 16f
        statusView.gravity = Gravity.CENTER
        statusView.setPadding(0, dp(8), 0, 0)

        buttons = LinearLayout(this)
        buttons.orientation = LinearLayout.VERTICAL
        buttons.gravity = Gravity.CENTER_HORIZONTAL

        root.addView(nameView)
        root.addView(statusView)
        root.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(buttons)
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

    // Leaving the call screen with Back would strand the user, so Back does nothing.
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
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

        val state = call.state
        statusView.text = when (state) {
            Call.STATE_RINGING -> "Incoming call"
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
        val key = "$kind-$muted-$speaker"
        if (key != lastKey) {
            lastKey = key
            buildButtons(call, kind, muted, speaker)
        }
    }

    private fun circle(label: String, caption: String, color: Int, onClick: () -> Unit): LinearLayout {
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.gravity = Gravity.CENTER_HORIZONTAL
        col.setPadding(dp(14), dp(8), dp(14), dp(8))

        val c = TextView(this)
        c.text = label
        c.textSize = 24f
        c.setTextColor(Color.WHITE)
        c.gravity = Gravity.CENTER
        val bg = GradientDrawable()
        bg.shape = GradientDrawable.OVAL
        bg.setColor(color)
        c.background = bg
        col.addView(c, LinearLayout.LayoutParams(dp(68), dp(68)))

        val t = TextView(this)
        t.text = caption
        t.textSize = 12f
        t.setTextColor(Color.parseColor("#A0A4AB"))
        t.gravity = Gravity.CENTER
        t.setPadding(0, dp(6), 0, 0)
        col.addView(t)

        col.setOnClickListener { onClick() }
        return col
    }

    private fun row(vararg items: View): LinearLayout {
        val r = LinearLayout(this)
        r.orientation = LinearLayout.HORIZONTAL
        r.gravity = Gravity.CENTER
        for (v in items) r.addView(v)
        return r
    }

    private fun buildButtons(call: Call, kind: String, muted: Boolean, speaker: Boolean) {
        buttons.removeAllViews()
        val grey = Color.parseColor("#2C2E33")
        val blue = Color.parseColor("#0D84FF")
        val green = Color.parseColor("#34B948")
        val red = Color.parseColor("#FA382E")
        when (kind) {
            "ringing" -> buttons.addView(
                row(
                    circle("✕", "Decline", red) { call.reject(false, null) },
                    View(this).also { it.minimumWidth = dp(72) },
                    circle("✆", "Answer", green) { call.answer(VideoProfile.STATE_AUDIO_ONLY) }
                )
            )
            "ended" -> {
            }
            else -> {
                buttons.addView(
                    row(
                        circle("🎤", if (muted) "Unmute" else "Mute", if (muted) blue else grey) {
                            CallHolder.service?.setMuted(!muted)
                        },
                        circle("🔊", "Speaker", if (speaker) blue else grey) {
                            CallHolder.service?.setAudioRoute(
                                if (speaker) CallAudioState.ROUTE_EARPIECE else CallAudioState.ROUTE_SPEAKER
                            )
                        },
                        circle("⏸", if (kind == "holding") "Resume" else "Hold", if (kind == "holding") blue else grey) {
                            if (kind == "holding") call.unhold() else call.hold()
                        }
                    )
                )
                val gap = View(this)
                buttons.addView(gap, LinearLayout.LayoutParams(1, dp(28)))
                buttons.addView(circle("✆", "End", red) { call.disconnect() })
            }
        }
    }
}

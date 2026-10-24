package com.example.contacts_dialer

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.ImageView
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
    private lateinit var photoView: ImageView
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

        photoView = ImageView(this)
        photoView.scaleType = ImageView.ScaleType.CENTER_CROP
        val round = GradientDrawable()
        round.shape = GradientDrawable.OVAL
        round.setColor(Color.argb(40, 255, 255, 255))
        photoView.background = round
        photoView.outlineProvider = ViewOutlineProvider.BACKGROUND
        photoView.clipToOutline = true
        photoView.visibility = View.GONE
        root.addView(photoView, LinearLayout.LayoutParams(dp(112), dp(112)))

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

    private fun lookupPhoto(number: String): Uri? {
        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number)
            )
            contentResolver.query(
                uri, arrayOf(ContactsContract.PhoneLookup.PHOTO_URI), null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val s = c.getString(0)
                    if (!s.isNullOrEmpty()) return Uri.parse(s)
                }
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
        if (number != null && photoView.tag != number) {
            photoView.tag = number
            val pu = lookupPhoto(number)
            if (pu != null) {
                try {
                    photoView.setImageURI(pu)
                    photoView.visibility = View.VISIBLE
                } catch (e: Exception) {
                    photoView.visibility = View.GONE
                }
            } else {
                photoView.visibility = View.GONE
            }
        }
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

        val c = ImageView(this)
        val bmp = IconData.bitmap(glyph)
        if (bmp != null) {
            c.setImageBitmap(bmp)
            c.setColorFilter(glyphColor, PorterDuff.Mode.SRC_IN)
        }
        c.scaleType = ImageView.ScaleType.CENTER_INSIDE
        c.setPadding(dp(size / 4), dp(size / 4), dp(size / 4), dp(size / 4))
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
                val decline = circle("hangup", null, red, size = 88) { call.reject(false, null) }
                val answer = circle("answer", null, green, size = 88) { call.answer(VideoProfile.STATE_AUDIO_ONLY) }
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
                            circle("keypad", "Hide", glass) { keypadOpen = false; refresh() },
                            circle("hangup", null, red) { call.disconnect() },
                            null
                        )
                    )
                } else {
                    buttons.addView(
                        row3(
                            circle("mute", if (muted) "Unmute" else "Mute", if (muted) glassOn else glass,
                                if (muted) Color.BLACK else Color.WHITE) {
                                CallHolder.service?.setMuted(!muted)
                            },
                            circle("hold", if (kind == "holding") "Resume" else "Hold",
                                if (kind == "holding") glassOn else glass,
                                if (kind == "holding") Color.BLACK else Color.WHITE) {
                                if (kind == "holding") call.unhold() else call.hold()
                            },
                            circle("addcall", "Add call", glass) {
                                startActivity(
                                    Intent(this, MainActivity::class.java)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            }
                        )
                    )
                    buttons.addView(
                        row3(
                            circle("speaker", "Speaker", if (speaker) glassOn else glass,
                                if (speaker) Color.BLACK else Color.WHITE) {
                                CallHolder.service?.setAudioRoute(
                                    if (speaker) CallAudioState.ROUTE_EARPIECE else CallAudioState.ROUTE_SPEAKER
                                )
                            },
                            circle("hangup", null, red) { call.disconnect() },
                            circle("keypad", "Keypad", glass) { keypadOpen = true; refresh() }
                        )
                    )
                }
            }
        }
    }
}

/** Icon masks (base64 PNG) cut from the provided Xiaomi call-screen screenshots. */
object IconData {
    private val cache = HashMap<String, Bitmap?>()

    fun bitmap(name: String): Bitmap? {
        if (cache.containsKey(name)) return cache[name]
        val b64 = DATA[name]
        val bmp = if (b64 == null) null else try {
            val bytes = Base64.decode(b64, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (e: Exception) {
            null
        }
        cache[name] = bmp
        return bmp
    }

    private val DATA: Map<String, String> = mapOf(
        "mute" to "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAHjUlEQVR42u1crbqjSBA9d/YaZFlk20jsSF4hz7GvMO8TuxJ7JTayLbJsu1nRRf8DnQDZO9+GiPtNINCn/utUMx+/8WcfP/AG8AbwBvAG8Aaw4/g88d4KAAFgMPhPAqCgQCCQ+4ahATCA8bsDIHTo0Lnls/trP4TxWG18/D528QodVCB7+z0LCEBjxHikHrYBKJCYwNbye/ToIsOBeEF4MAYMx+lhy4Q69FAYcdt4oEKPDiqBhMCMyOmiA0AYK4SyG4BCjx4KBL0qM8LVLX+2esr0QJGp0aZQqo6/fi2f69HhJy4gEBoA90WYf+MnLmjkA7neHgYNgAaAgQFg0KKVcxPMmRrooESqhA4MXtBChz6SsNUCJ3IP9WFzBEPvd+ftMMrORQmE20Lc5+KvtmIWV4WHpwGMAMjpYE5NOQQti6DMfdcBEBTUXgBrPqAxgdBCiUU3UGgxZY+cYKDQwgSfxmnCBP4A8REEHjLtc+U1AABjQoNW3NjIAgw4cj4DLdppgoXO55AsOQXDi8HhAAAWgl2+XThkqVMCYYKRq8hJeYZpViAAE+57YtEWAFvFNCAJgpAwmQbVud5UgfEg0wcKhsUYzgUATE6ORpZvDUoni9KgIMabRQAs541o9S5POA0AoMFogsU1IKgsBM6+QZK6TDEmcfQLYMLXHgC15fQoZZ1yi7KpaEyA3sDgoJyuC6k4WwPWkCY0hVijs7AI0QBlQbOU4HZqoB4AMIGDegeAmBRnEQlZWEXBMwCCeSUAREnHwmgL3cKcyqjQC6Rh1LzKB0JfsAUcu3an5Au+XAjrKaqqkk7uieMKyZZ5wA1DFrcYFHVoiODgGDCPmVCYF+biwgQLM1lQJbF0b3Qm8YOX+kAo3zmd2QWpYoFhJH94BzaR1On1PhD7Qhe0jx2QFdtaqieVGc8jhfcJGpgNybebttgm6ESaRrJHnhFIChPe197v4Ua1SDjsza6iiZRG0U7adGw02sfMaeE/PXHVR8F2vmpwrSdcSf4tAKAQJC3rMxRqpD4iHOk7AKBii49CamMMLn8cWt7tJ3dpAUKqBQuhFw3NprSbej+DXmfJzrkWbpEW+HtooKwTa/FpgQEMQsC/1ITo4cqFHXGFhM1jYURVQMLTnid+Viy/k/DH1aT4HCQ7kXoMbgQkIlFx+Z1Q+pa3470AOlwdk0kYHoBAbkI2FgoMX4ikydByrSzc6bAPAEGhC4yhPgFRwKlyxmAMAjDPB0pGVCxP23ji56Y1sxtN0BPpx/7iiiGLSFa23WIYpbqMUctOc9RheSaI3UBj+VC4grICg4XBKAFgJzw+AgBHBhWf4SpT8hEpT20lnVHU1x0GIDehVAPL9qokteW+kP6GgiB6iAawcpv0DK8akk1t4+odKCm3DwEwN5BckPK2lDiKL9iI7D7B0aroHujIGASFVlggE1Gxxj2ykea+jVjRkjc0Qn2Vr+hxkVFJgzuG7dnBjyoNzM5EbuwXNit6tTr1+db6y1Uq0qWs77eHVM3PPqsB+DF12MMyBtnakZoMRdErLKH7QlD1Uc4PxPmYWghRRWIzs84iSRe1iZTpImwkZysfV5OX3q6D6lmJJgihdigxRfyERit+Yh9a5qSN8w47a5gKvjA/ifFVN8mvA2BkQmmpkAZIHDHM000hM3tO2wSBAYkgEAxIDG74Oo4XMtF8xtLq8WhOy9xLLQ70OCAVGyftFMIklOQd/9SVjbXElsEFrTMiwjyZDB99T3KDiT6czZBJ7qQTCIypfhNCPQA7L26cDNtsOGegMTlJh77AmGSkrWHkPnPeINyzfK7rubpHqEW/z2R26TROWAgTtPy10rT//sKIOzQmNFCAzJVJZsVPN/j1Tb1OWhDCFchqm3DnhI/pYdlMbgwIdx8q3OcUDXiy3MA4YpeLpYMRyd+dYYXfz3N9FnPMx4WnsNMc7JcwgOyigBt01ApiQoNLNO1sC0H1FF5ojNi3eXOrgq7NnFnNP3tUt5CdDye2xmDLBzCPv1m2U+qq5fcB0TsXD8oxESeaUGhIFzcltpmhxQWtq3OarKi2O48uuKLHTxeSG7chp5FrHjSk56hFq+g+qkIpMiUWaJx0WjOtyIH8/e66J7Tw/M5dQid7RUN7DstglhKaoo6LCi0luUGJNcWh3heeJ3ctOcXooxYnZ3NSeGk7qsFQQVjoFovtE9jpEQwtc7GckKUi4egpRw2N0QGA00KZzTuJXteSV1UyTKUECidGw7J4HWiGgi3KBMatBsJRu9eV+1BkSpSwe17uukAi9wGlojHWFBhHDTg0tOjAx5swRs2xiSVOLUU2/ysl+tWvAeCZfx8QVdDfDpLkeIWsGmEnOz612W0k/CoAiAxFoXdchnaz4kfyCwsVNqxp4byXgLRsh+WHUtMo3JOf8fRQa75w5ltMHNG0tcfgtGBNSaHLZjwvAkArfF0NhCrwZwJ4/hiCnLzxlsGrAPDDEMiV2KuDvs8TDYh2bekYwELHD/+dCRGe39rBEj5fmMjyJXCB5n0sFJ9ezNVYvj7vVdDzAFjnm+mv8c96m9UThBRRXaccH+//V+IN4A3gDeAN4H8N4F+PTFctMBPoPQAAAABJRU5ErkJggg==",
        "hold" to "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",
        "addcall" to "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFAklEQVR42u1cu3HjMBB95jFRuC2gBbTAFtTC1XF1OL2QLbAFtIDU4abK7gKCJCgR5GIJyvQMobHHow+0D/t7Cyz88Q8/e1S4AFwALgAXgAvAjlEXnIvC7+HRP8PhWYYHg8MzfDYABjT+IBI/Hhw9PBjuHAAIBgYWNlr5tTFB6ODh9+ri499e8Rs0Ye2xKXoMzoPh4dAFw3o7AArrbhIGsw0HQRMeDk4LQgdgEN4KTEYCxKNDp/MJDQDCHRYGBvRkFvkz8WhQHh3afD3UinjT4B6iTYnRL4EJC9LCH6sBizsalc1LoDA6dOiO00CDpojdpxNhP7uT66HOmN7i9xhzjhgcEiLB4FPqDbVY/CaIf5zwMRFhqUPXYvHvsAdyspg19XEO+CwHwOIOAz7EdRHNOtE8gzsYbRk6bQNZyDMGZHjLnJ9y8IMGTQkNUAiclCn+PFVtaY9nmhiCBoCtoLoNoME903BopGfDX7rIZcYcvcOE8mMPPa1rvvDTJwh2K3RUAufVuCMVyhe9AStNyATKllsAcsT3p7lyc8jgNQZ2jWzXm9FHm5hcRMwo+FF+zTAQ9y4fAClWDbOKK143qzSggf8mK+hqZf1tlB81X8w7rZ9mS5npxBTRtmJbIDsonk3ZwpoGCGcZKzqokhHInAxAsyxPlWSf5qC6S799Y+UAbISXvt0L+u+3y0ZUJR14qlO/Vw+0zm3rBIAzDRr9kl5todqIwecCYqQmdEbxeTmUpgCcVQNGBuAHjXpRfBKpdO21131/FrpqAQAm7MxsE+blrV0Or8bDvZglRbzViDL/omnXag/waOFfyp2piPcv78YiBIYPiZNEXuAkJiRxqJ7ve3EM4dXF4M3CRkynuYhI+VRB6R/nOCfeEfeqd3+hSgM4QgMlkx3pAdYJ6yYBvf294MLT57rZqzZJEDdKxqdZWborsa3Ufq9gSS/TAer83bSw78N7+W+9uP6ys8cpB9AY7GhMZHPyS6uJSp79WQpAardxvUazKk5q6SQumVgGQKoDWjE2XjSuPGCvaYylGsgNfVQ+OCZmYVkY5d3ZmFTibUWgxd6WesXWKGPyZ5FICInE3pY46qgSbF6bd/kgc+IU5asSTN8Vt2W96EPGYDmV8LktF4e5cLyoXg6A9Q1IB2nBpySqVkqMc0AYsnuWBvbpgIpT7l4DyAPQhqJdQ5tfIdAuT+J00Zk+I3NwYUObM0Wnkb757K2Cpfn8U1QUAug/qCe6Bs3smHWP+XQ6AE59TsNBZDvSMD0Av97PWK+K0QlbWpdjhymQEzi0xiprYo8WLtsFObJ6UsexYX+v3dfs4dCNESAvM0xtNqwEwVvmI9uV6GbleR4EjlIRKcC77RbMWjBZC6QOOQ/bSaLQGO73A0BQYvPGcwMO/idogZU1/fUQ7m+E4PAp6+CtxRMSCM3udm9Z5Beufg6AvvmO32BIDC9d/TwACHctmuJdFDw7Vs9Y/VwACJy8iRrRWB1npk0tHlNXn7iyutd//cn7yge+8MANNxBueOChFp9xww03PEKm+IJDi7+59zh0NzgsmnB7hncwfYp0oFh7PYCeHk9XgKBkrDRGfAeXc2egBIBeE814l2bfLaZWvwuy9x6ZiUDIO4so7P6577xHNgljQnfn/A5lmuANwvu1Wvd9AOYljFkFMZhMAcHLA8BTGUMvR0rTo+D4uP4twwXgAnABuABcAH7y+A+RrNAulpGAUwAAAABJRU5ErkJggg==",
        "speaker" to "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAE1klEQVR42u1bMZbjKBD941XisNIJuQJX0BV0hTnHnmPSCX0FrkDaIWmHlTrbDSjJIECWLdBab6Wkn1+7bX7x6/+qgv7xD479XHACOAGcAE4AJ4ATwAngBPD20zX/BoKGAuDg4I4HQEGhFwDmeAA0emgoaABWduFAAHpZPgmVFDQYfAwACgM0tCwetZfdGoDCgAFqes3ttvnSaPm9UIcbi0SDHdAR8w/nAz0GaBBIYk9HAqCgMUAny6aWROqqMl+jB8DgTOTps5NYY0AvsknJYumtcNB+ANTTxKWXgHgZ1vtQiNCLaPLTd64PxwAFBsO2BqClYPDM5wpcJ2gJiMYAgmkJoEePHgQGZZj/Dv9JcskLQQ8FhdvS3l42UqefFliC8KqEcvBz3I0GO/Bg/hhlriKUDAsCyScTAA0NVw5Dt2BKpaV7wqSqU8euHKyQh6ZQodwMdcXUHCJdoc3sXv9Y6eTGsOilVqgryJhnXtlP21aZFreJRmMrVIDQFZZfUnVuEP9c2W1AYo6P3nolgPDP9qAM4Rc4w3EDgpJ8U2Bo2FxQcwB2akUm3R8AEMzMdRkOLtoBlfPlLpPAKVXagdGB3szF0sFObKBSpXXJxIR2iv7YvYWZFwNwcNMcg/KWdsmkKRde14b1kAsGQeFX4j0OdsoNmsCuKCUo2ZM2ScxBeLw5UpIHjx3IkujytPSlZhrkYHGT0oGz/s9CorcaGoo+qI2EWhjYIMY6QyInZV2+11usRql50eBHvg8Iae3JkT9QmsaXVUxt+TwSlaIa6PF7DsrrFwHsIakcKI3PA8oA4EhOXtwBag4hp3mxjBcBdCtEtPS1VA0AR85Pi4yo2FLWdgN68pmU+9bPOORbP0flzwSw4fkMAPS+XHcfsXx6WrTTJ++An29QUL6tUauPAUAy1fYQ3MzWPDwOKqMVAHjn+D8mTLn460he3etG1jb6OjjNzBXPSqojBqBmpd1OSUyL0R+iEY5LJg8qqI2yObCvCs0Xp4Xhvql0yWSCogldltztc4CLu8HRohxsMjZRcnDCpRTepkJb7z1woDkMi9tsgTTrDrID3m5jlbmtJrWBfJok/hTNCFOBLQCwUeKUE5Or0MvIZ5nM1C1O4NXD3VvhTISLTN4ivAxTmD3QzB8KDp0CMKIPNCuxKAOjxi64bC6RXFmAJLGFWQvA85FnQyZOeE/VQHDWIfogiAX+lwHc5KAnNHGedUZqmtXUflQwM13kf9nIxuQqH576y3xtyg490ceHbSH+S07MUas3nxw4EBhDMnjZfslmCJY/8sFsa2i4YGEOCKb79eijI+La5YPuv/5+/8vu+ILDFT/xE1fcJ0m9zt53ld98wcLh/jRYdwBX3PENB4M/y1c1u436YWTbl7yZX6qwzJR7DJM1uMrVqA3aDqrkDBYK4+y6eVPvvbSvmA0OBgRad1W5Tj9g4eCmA9rtQ0eH32tJV6upZxj8FrunCp3F6lK9Xkfmb1fRrIri1h32FhlNn298i0ySyCGLjAJ3fOPrqYz+55M5C4YTh95lQFO/qffl8TAdW9PRADzsTS9fFvtcAN5PGUNyq4vrk6rdXMj/y0k/m+zgOADGhPadlW8L7bEAjKMoXyM9vTTw3vPj/J/6E8AJ4ARwAjgBnABOAP9jAP8C/nixG3XEIOcAAAAASUVORK5CYII=",
        "keypad" to "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",
        "hangup" to "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACo0lEQVR42u2YO3LbMBCGfytuVG7rElfAFXAFXcFXiMuUSevOOUJ4hPAIYZvOaN0ZbTqkIPiQSBAASWnsmR8YQSMNSO63D+wu7zw+9ziAAAQgAAEIQAACEIAABCAAAQhAAAIQgAAEIAABCEAAAhDgk437He+loCCQ0T8y2eNgw+eDAJyC0BLEPRdZZq9xYQIWFg3s7QEEAgUF3etcIvvmAbq1BbH9XDHufJngajQlIWh6uJFNWgQX1isAGOiRxi/FdqshLq1i4VCjyoXIAVAwQXRVoG2XtGbsqi7QazRpjGWA1s91cJeYr7sLv0YIUXcRNcP38CsW5O3aoIFFsxbA4AQN1YvgIgfj4L8uIj5GCmgPgGGVRGy0DmVLAQRfoaF68ZccpcbPHGNPnmB611x+goPFU9QOfm4a/+L/+Ff/7lPj3f/y2mPlFP+S9YxX/9t/92ruHnN5QJ+5Tko7WxJRG66StFXnaj+mdr6f2X7KMOx5Vt1yfLrMI1jBAHhKF3MGpkj8TYVACP2ciAEEGiYNoIp1iI0WyC9fBDoHYFtOXVNX5RcyGQCyg173F9/F8vchslV2d4F1DuhS5eKhoE65Tgws156SetqcBW4n/nzZUWTvwwan2H6IdgdpSc5IAjRFCNVmF6qK6qgmDVBn6sTBLlWJBRYYVLakOhd6hIyeuIqWuefi16h2OUobNFlxZ+fs/eXbdONfPOABRxyjwv+DRYXnnbLFG94gOAI4RkHavuA5vx94xGma9XrdN6inxtz8gsaE/kNmDk8Xuo6CjkzwCDO6VfcKpFnRvOTnZY3TBYQLzhMp25d7YtO38S7UjRbXHgI96gAGte3yXugDDr6dJgABCEAAAhCAAAQgAAEIQAACEIAABCAAAQhAAAIQgAAEuPX4D+yTdeohLmbhAAAAAElFTkSuQmCC",
        "answer" to "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFDklEQVR42u2cK3vjOBRAT7olgpcaihaaDjQtNB3Y+RtL5y+ULtvQsg0dtqZhI2oWUTEvkOw48SN2XnK+jYL61Ul0dN/X11lVPPZ64QnwBHgCPAGeABes10lXCQIIYLHYxwJISdENBFjWbB4DQNBoMrKwdS8B0GgKzDIksaqGt5+RIwg6ABC2bLEUbNgsAWEIQMjJSBvd368awrBhjVmmCmlysnDy0kGrbUMj/IwthX43mvGBbsx2yC8JGdkS40AadL/v/I8llZEuDUDI0BOjA6STr74bQNprumO+Kl0WgG7UZ+9zxixBx5XBy0DacOxzxi0hnyivOwHMWV4GaTwZdAHm+3WfcjxsOi0QUwZ9ErBnIEgsK7iGChEy1CgI3VzIYFoYMsOYFyIBc1amvygVMjOTZHuB6t3ECxnsjGRi/x67HIBaiWSyDGys0ualdzvzrcAuSYWYXbJbiqUBrCci2KA+CwOwbCYB2HDtmmJZRX19suOmbAFDEbfRNQywRk4maJaCz3inP56NFmwwI6dft7eibn88nT7ti4r4XdKX0ei6OUjsjv+7Zh2/ufh64oRNrx1YLGt+soD1clJFulmO1/4Clg9ATw/aIo8EUNvBcdfCLOU+zemivt8XSbxO0FwAy6aT6UjMTtD8tsqmkxkJaeyudL3++HNavZUcdB0UCsGxfRQAh0WToFoIoNlSPgYAlAhp2PgewlLG9kZTAWrdVw2CAhIsBrfcVOLQndK57aTJMXETujkSKHEoEsDhUKjm7+0jSMA7VCFDQikp4S6ZjxUPYQPemL03ksYShAQTyx/NBXAUCPrImMHF8kdzAcBB0HzVCmsKF8cfzQcAg+ONBNdCkGaa6AEAPEISbMHicECCoNjeWwrnAUAJwRJcK8FOUGfZgqBIEGh93sS1Onv0WMj5CEm1NJv2pb6Z9TnpwUTSzDbluRLwCZ73R9J08FR4TZdCSs47KSnf0LyhSdCNZ7t6IOuWm0IWGi/7OSJBT2w3fpC3+n8S3m+DJH5MOYbzJeARvC0IKiQYhMCmKE+ENk1OToq0JKdCpeEtKkVO+7XLAAjK0q6QpeVUy9Htv5MG9P5YoxFccBg3A4AS04S2ejsWFcYPyl5NFr43E3l9ay8LTYIbcwqXA/iTdgdy8F9en2HZOf3v5LxN6GsoFEmoOoZWda1XXv1T7ar22lW76nf1d5UdXfdvVR1dObZ21a7aVR9D33sNCeytITnQaV8vCEmopxO+8U7OWysVZJIUXFOPXNWNdvtHhGnH2ikKNszgmWDs5w7mDFYdqys/BJTx0TNzZ6EJdnLW4YDlk8+uU72eCtWRwaJIgvp4f1QbtQw4zSlq5HD9t9NfufbyXby8GRW3V+miSlBAbi0BL/ACi27qBReaAJcth8V1reD6EiDoqyG/agtY+u3nNgC1KuVhpvSGzfhbPkNjWPN564bL600/3WAwjfe/iRRuYcTHEXoTIqi6yJAtlpKv+wP4XpKvHNzZEBYo2PIrBkCddG9xJAHBzgRxWL76bqy/cq/lo4Mhax5umWtPRV9SfS8J1BBbtpTh9NWM9xm++NVXXq6iPNHtn05LW3nr+Cr4HJrLuK8EDtXJp2cqGPd4ov7XUGW8ivhMve881J2Jw+kw27rK8GM4HL7G239Ij20IdOmBaddA5tRQ1Wohv2rgHyaq67X904LdWY2FAtT1XHrgeSZ0SVfP35V4AjwBngBPgP81wH9vAzCRuY6eJgAAAABJRU5ErkJggg=="
    )
}

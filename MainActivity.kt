package com.example.contacts_dialer

import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.telecom.TelecomManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private val roleRequest = 4711

    private fun dialedNumber(i: Intent?): String? {
        if (i == null) return null
        val d = i.data ?: return null
        return if (d.scheme == "tel") d.schemeSpecificPart else null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dialer")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefault" -> {
                    val tm = getSystemService(TelecomManager::class.java)
                    result.success(tm != null && packageName == tm.defaultDialerPackage)
                }
                "requestDefault" -> {
                    pending = result
                    val roleIntent: Intent = if (Build.VERSION.SDK_INT >= 29) {
                        getSystemService(RoleManager::class.java)
                            .createRequestRoleIntent(RoleManager.ROLE_DIALER)
                    } else {
                        Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                            .putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
                    }
                    startActivityForResult(roleIntent, roleRequest)
                }
                "initialNumber" -> result.success(dialedNumber(intent))
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val n = dialedNumber(intent)
        if (n != null) channel?.invokeMethod("dial", n)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == roleRequest) {
            pending?.success(resultCode == Activity.RESULT_OK)
            pending = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}

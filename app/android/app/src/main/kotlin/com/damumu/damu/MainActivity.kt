package com.damumu.damu

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val permissionRequest = 7401

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.damumu.damu/permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val permission = when (call.arguments as? String) {
                    "camera" -> Manifest.permission.CAMERA
                    "notifications" -> if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null
                    else -> { result.error("unsupported", "Unsupported permission", null); return@setMethodCallHandler }
                }
                if (pending != null) {
                    result.error("busy", "A permission request is already active", null)
                } else if (permission == null || Build.VERSION.SDK_INT < 23 ||
                    checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
                    // Before Android 13 no notification runtime dialog exists.
                    val enabled = permission != null || Build.VERSION.SDK_INT < 24 ||
                        getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()
                    result.success(if (enabled) "granted" else "settings")
                } else {
                    pending = result
                    requestPermissions(arrayOf(permission), permissionRequest)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val result = pending ?: return
        pending = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val permanent = permissions.isNotEmpty() && !shouldShowRequestPermissionRationale(permissions[0])
        result.success(if (granted) "granted" else if (permanent) "settings" else "denied")
    }

    override fun onDestroy() {
        pending?.error("cancelled", "Activity closed", null)
        pending = null
        super.onDestroy()
    }
}

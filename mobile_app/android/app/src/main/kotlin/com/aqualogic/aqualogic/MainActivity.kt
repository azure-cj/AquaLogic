package com.aqualogic.mobile

import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aqualogic.mobile/fcm_fid",
        ).setMethodCallHandler { call, result ->
            if (call.method != "register") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                FirebaseMessaging.getInstance().register()
                    .addOnCompleteListener { task ->
                        if (task.isSuccessful) {
                            result.success(null)
                        } else {
                            result.error(
                                "fcm_fid_registration_failed",
                                "Firebase Messaging registration failed",
                                null,
                            )
                        }
                    }
            } catch (_: Exception) {
                result.error(
                    "fcm_fid_registration_failed",
                    "Firebase Messaging registration failed",
                    null,
                )
            }
        }
    }
}

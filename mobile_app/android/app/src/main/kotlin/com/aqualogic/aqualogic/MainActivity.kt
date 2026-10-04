package com.aqualogic.mobile

import android.content.pm.ActivityInfo
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var consoleOrientation: Int? = null
    private var consoleHadKeepScreenOn = false
    private var consoleSystemUi = 0
    private var consoleStatusVisible = true
    private var consoleNavigationVisible = true
    private var consoleBarsBehavior = 0

    @Suppress("DEPRECATION")
    private fun enterConsoleDisplay() {
        if (consoleOrientation == null) {
            consoleOrientation = requestedOrientation
            consoleHadKeepScreenOn = window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
            consoleSystemUi = window.decorView.systemUiVisibility
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val insets = window.decorView.rootWindowInsets
                consoleStatusVisible = insets?.isVisible(WindowInsets.Type.statusBars()) ?: true
                consoleNavigationVisible = insets?.isVisible(WindowInsets.Type.navigationBars()) ?: true
                consoleBarsBehavior = window.insetsController?.systemBarsBehavior ?: 0
            }
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility = consoleSystemUi or
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }

    @Suppress("DEPRECATION")
    private fun exitConsoleDisplay() {
        val orientation = consoleOrientation ?: return
        requestedOrientation = orientation
        if (!consoleHadKeepScreenOn) window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.systemUiVisibility = consoleSystemUi
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior = consoleBarsBehavior
                if (consoleStatusVisible) show(WindowInsets.Type.statusBars()) else hide(WindowInsets.Type.statusBars())
                if (consoleNavigationVisible) show(WindowInsets.Type.navigationBars()) else hide(WindowInsets.Type.navigationBars())
            }
        }
        consoleOrientation = null
    }

    override fun onResume() {
        super.onResume()
        if (consoleOrientation != null) enterConsoleDisplay()
    }

    override fun onDestroy() {
        exitConsoleDisplay()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.aqualogic.mobile/console_display").setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> { enterConsoleDisplay(); result.success(null) }
                "exit" -> { exitConsoleDisplay(); result.success(null) }
                else -> result.notImplemented()
            }
        }

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

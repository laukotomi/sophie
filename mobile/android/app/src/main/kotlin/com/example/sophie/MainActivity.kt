package com.example.sophie

import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Show over lock screen only when launched by a full-screen notification intent.
        if (intent?.getBooleanExtra("showWhenLocked", false) == true) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sophie/media_scanner",
        ).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARG", "path is required", null)
                    return@setMethodCallHandler
                }
                MediaScannerConnection.scanFile(
                    applicationContext,
                    arrayOf(path),
                    null,
                ) { _, _ -> result.success(null) }
            } else {
                result.notImplemented()
            }
        }
    }
}

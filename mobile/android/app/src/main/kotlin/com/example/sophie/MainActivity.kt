package com.example.sophie

import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var navEventSink: EventChannel.EventSink? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("homeWidgetIsWidgetClick", false)) {
            navEventSink?.success("tasks")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sophie/navigation",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getInitialRoute") {
                val fromWidget = intent.getBooleanExtra("homeWidgetIsWidgetClick", false)
                result.success(if (fromWidget) "tasks" else null)
            } else {
                result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sophie/navigation/events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                navEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                navEventSink = null
            }
        })

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

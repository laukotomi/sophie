package com.example.sophie

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sophie/ringtone",
        ).setMethodCallHandler { call, result ->
            if (call.method == "copyUriToAlarmFile") {
                val rawUri = call.argument<String>("uri")
                val fileName = call.argument<String>("fileName") ?: "alarm_ringtone"
                if (rawUri == null) {
                    result.error("INVALID_ARG", "uri is required", null)
                    return@setMethodCallHandler
                }

                try {
                    val uri = Uri.parse(rawUri)
                    val extension = resolveFileExtension(uri)
                    val directory = File(filesDir, "alarm_ringtones").apply {
                        mkdirs()
                    }
                    val outputFile = File(directory, "$fileName.$extension")

                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(outputFile).use { output ->
                            input.copyTo(output)
                        }
                    } ?: run {
                        result.error("OPEN_FAILED", "Could not open ringtone URI", null)
                        return@setMethodCallHandler
                    }

                    result.success(outputFile.absolutePath)
                } catch (e: Exception) {
                    result.error("COPY_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun resolveFileExtension(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    val ext = name.substringAfterLast('.', "")
                    if (ext.isNotEmpty()) {
                        return ext
                    }
                }
            }
        }

        return when (contentResolver.getType(uri)) {
            "audio/mpeg" -> "mp3"
            "audio/mp4", "audio/aac" -> "m4a"
            "audio/x-wav", "audio/wav" -> "wav"
            "audio/x-aiff", "audio/aiff" -> "aiff"
            "audio/x-caf" -> "caf"
            else -> "bin"
        }
    }
}

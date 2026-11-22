package com.example.timer_main

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/device_timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getLocalTimezone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/reminder_sounds")
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.error("UNSUPPORTED_ANDROID_VERSION", "Notification channels require Android 8.0 or newer.", null)
                    return@setMethodCallHandler
                }
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                when (call.method) {
                    "createReminderChannel" -> {
                        val channelId = call.argument<String>("channelId")
                        val channelName = call.argument<String>("name")
                        val soundFileName = call.argument<String>("soundFileName")
                        if (channelId.isNullOrBlank() || channelName.isNullOrBlank()) {
                            result.error("INVALID_CHANNEL", "A channel ID and name are required.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val soundUri = if (soundFileName.isNullOrBlank()) {
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                            } else {
                                if (!Regex("^[A-Za-z0-9_.-]{1,180}$").matches(soundFileName)) {
                                    result.error("INVALID_SOUND_FILE", "Invalid reminder sound filename.", null)
                                    return@setMethodCallHandler
                                }
                                Uri.parse("content://$packageName.remindersounds/sounds/${Uri.encode(soundFileName)}").also { uri ->
                                    val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    grantUriPermission("android", uri, flags)
                                    grantUriPermission("com.android.systemui", uri, flags)
                                }
                            }
                            val attributes = AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                            val channel = NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                                description = "صدای اختصاصی این یادآوری"
                                enableVibration(true)
                                setSound(soundUri, attributes)
                            }
                            manager.createNotificationChannel(channel)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("CREATE_CHANNEL_FAILED", error.message, null)
                        }
                    }
                    "deleteReminderChannel" -> {
                        val channelId = call.argument<String>("channelId")
                        if (channelId.isNullOrBlank()) {
                            result.error("INVALID_CHANNEL", "A channel ID is required.", null)
                        } else {
                            manager.deleteNotificationChannel(channelId)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

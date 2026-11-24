package com.example.timer_main

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var activityNotificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/device_timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getLocalTimezone") {
                    result.success(java.util.TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/daily_reminder_alarm")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "schedule" -> {
                            val id = call.argument<Int>("id")
                                ?: throw IllegalArgumentException("Reminder id is required")
                            val triggerAtMillis = call.argument<Number>("scheduledAtMillis")?.toLong()
                                ?: throw IllegalArgumentException("Reminder time is required")
                            val soundPath = call.argument<String>("soundPath")
                            val text = call.argument<String>("text") ?: "زمان یادآور فرا رسیده است"
                            val repeatDaily = call.argument<Boolean>("repeatDaily") ?: false
                            DailyReminderAlarmScheduler.schedule(
                                applicationContext, id, triggerAtMillis, soundPath, text, repeatDaily
                            )
                            result.success(true)
                        }
                        "cancel" -> {
                            val id = call.argument<Int>("id")
                                ?: throw IllegalArgumentException("Reminder id is required")
                            DailyReminderAlarmScheduler.cancel(applicationContext, id)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("DAILY_REMINDER_ALARM_ERROR", error.message, null)
                }
            }

        activityNotificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIVITY_NOTIFICATION_CHANNEL
        )
        activityNotificationChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "update" -> {
                        val title = call.argument<String>("title") ?: "نام فعالیت"
                        val elapsedSeconds = call.argument<Number>("elapsedSeconds")?.toLong() ?: 0L
                        val running = call.argument<Boolean>("running") ?: false
                        val serviceIntent = Intent(this, ActivityTimerNotificationService::class.java).apply {
                            action = ActivityTimerNotificationService.ACTION_UPDATE
                            putExtra(ActivityTimerNotificationService.EXTRA_TITLE, title)
                            putExtra(ActivityTimerNotificationService.EXTRA_ELAPSED_SECONDS, elapsedSeconds)
                            putExtra(ActivityTimerNotificationService.EXTRA_RUNNING, running)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, ActivityTimerNotificationService::class.java))
                        result.success(true)
                    }
                    "consumePendingAction" -> {
                        val prefs = getSharedPreferences(ACTIVITY_NOTIFICATION_PREFS, MODE_PRIVATE)
                        val action = prefs.getString(PENDING_ACTION_KEY, null)
                        prefs.edit().remove(PENDING_ACTION_KEY).apply()
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("ACTIVITY_NOTIFICATION_ERROR", error.message, null)
            }
        }

        // Handles notification interactions that launched the app from a cold start.
        storeNotificationActivityName(intent)
        storeNotificationAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_NOTIFICATION_ACTION) ?: return
        activityNotificationChannel?.invokeMethod("notificationAction", action)
    }

    companion object {
        private const val ACTIVITY_NOTIFICATION_CHANNEL = "timer_main/activity_notification"
        private const val ACTIVITY_NOTIFICATION_PREFS = "activity_notification_actions"
        private const val PENDING_ACTION_KEY = "pending_action"
        const val EXTRA_NOTIFICATION_ACTION = "activity_notification_action"
    }
}

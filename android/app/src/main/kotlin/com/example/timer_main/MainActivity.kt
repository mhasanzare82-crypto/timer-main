package com.example.timer_main

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
                            DailyReminderAlarmScheduler.schedule(
                                applicationContext, id, triggerAtMillis, soundPath, text
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
    }
}

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
                if (call.method == "getLocalTimezone") result.success(TimeZone.getDefault().id)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/daily_reminder_alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncReminders" -> {
                        val json = call.argument<String>("reminders")
                        if (json.isNullOrBlank()) {
                            result.error("INVALID_REMINDERS", "Reminder payload is empty", null)
                        } else {
                            try {
                                DailyReminderAlarmScheduler.sync(applicationContext, json)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SYNC_FAILED", e.message ?: "Unable to sync reminder alarms", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

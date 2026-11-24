package com.example.timer_main

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleActivityTimerIntent(intent)
    }

    private fun handleActivityTimerIntent(intent: Intent?) {
        if (intent?.action != ActivityTimerService.ACTION_OPEN_FOR_STOP) return
        val stopIntent = Intent(applicationContext, ActivityTimerService::class.java).apply {
            action = ActivityTimerService.ACTION_STOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(stopIntent)
        } else {
            applicationContext.startService(stopIntent)
        }
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        handleActivityTimerIntent(intent)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/activity_timer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "show" -> {
                            val intent = Intent(applicationContext, ActivityTimerService::class.java).apply {
                                action = ActivityTimerService.ACTION_SHOW
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                            result.success(true)
                        }
                        "sync" -> {
                            val intent = Intent(applicationContext, ActivityTimerService::class.java).apply {
                                action = ActivityTimerService.ACTION_SYNC
                                putExtra(ActivityTimerService.EXTRA_HAS_TIMER, call.argument<Boolean>("hasTimer") ?: false)
                                putExtra(ActivityTimerService.EXTRA_ID, call.argument<String>("id") ?: "")
                                putExtra(ActivityTimerService.EXTRA_NAME, call.argument<String>("name") ?: "")
                                putExtra(ActivityTimerService.EXTRA_STARTED_AT, call.argument<Long>("startedAt") ?: 0L)
                                putExtra(ActivityTimerService.EXTRA_ELAPSED_MS, (call.argument<Number>("elapsedSeconds")?.toLong() ?: 0L) * 1000L)
                                putExtra(ActivityTimerService.EXTRA_RUNNING, call.argument<Boolean>("running") ?: false)
                                putExtra(ActivityTimerService.EXTRA_RUNNING_SINCE, call.argument<Long>("runningSince") ?: 0L)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                            result.success(true)
                        }
                        "finish" -> {
                            val intent = Intent(applicationContext, ActivityTimerService::class.java).apply {
                                action = ActivityTimerService.ACTION_FINISH
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                            result.success(true)
                        }
                        "cancelStop" -> {
                            val intent = Intent(applicationContext, ActivityTimerService::class.java).apply {
                                action = ActivityTimerService.ACTION_CANCEL_STOP
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(intent)
                            } else {
                                applicationContext.startService(intent)
                            }
                            result.success(true)
                        }
                        "getState" -> {
                            val prefs = getSharedPreferences(ActivityTimerService.PREFS_NAME, MODE_PRIVATE)
                            val hasTimer = prefs.getBoolean(ActivityTimerService.KEY_HAS_TIMER, false)
                            val running = prefs.getBoolean(ActivityTimerService.KEY_RUNNING, false)
                            val runningSince = prefs.getLong(ActivityTimerService.KEY_RUNNING_SINCE, 0L)
                            val elapsedMs = prefs.getLong(ActivityTimerService.KEY_ELAPSED_MS, 0L)
                            result.success(mapOf(
                                "hasTimer" to hasTimer,
                                "id" to prefs.getString(ActivityTimerService.KEY_ID, "")!!,
                                "name" to prefs.getString(ActivityTimerService.KEY_NAME, "")!!,
                                "startedAt" to prefs.getLong(ActivityTimerService.KEY_STARTED_AT, 0L),
                                "elapsedSeconds" to (elapsedMs / 1000L),
                                "running" to running,
                                "runningSince" to runningSince,
                                "pendingStop" to prefs.getBoolean(ActivityTimerService.KEY_PENDING_STOP, false)
                            ))
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("ACTIVITY_TIMER_ERROR", error.message, null)
                }
            }

    }
}

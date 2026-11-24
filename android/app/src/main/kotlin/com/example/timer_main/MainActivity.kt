package com.example.timer_main

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    private var activityNotificationChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/app_launcher")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getLaunchableApps" -> result.success(getLaunchableApps())
                        "launchApp" -> {
                            val packageName = call.argument<String>("packageName")
                            if (packageName.isNullOrBlank()) {
                                result.error("INVALID_PACKAGE", "شناسه برنامه معتبر نیست.", null)
                            } else {
                                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                                if (launchIntent == null) result.success(false)
                                else { startActivity(launchIntent); result.success(true) }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("APP_LAUNCHER_ERROR", error.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/device_timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getLocalTimezone") result.success(java.util.TimeZone.getDefault().id)
                else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timer_main/daily_reminder_alarm")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "schedule" -> {
                            val id = call.argument<Int>("id") ?: throw IllegalArgumentException("Reminder id is required")
                            val triggerAtMillis = call.argument<Number>("scheduledAtMillis")?.toLong()
                                ?: throw IllegalArgumentException("Reminder time is required")
                            val soundPath = call.argument<String>("soundPath")
                            val text = call.argument<String>("text") ?: "زمان یادآور فرا رسیده است"
                            val repeatDaily = call.argument<Boolean>("repeatDaily") ?: false
                            DailyReminderAlarmScheduler.schedule(applicationContext, id, triggerAtMillis, soundPath, text, repeatDaily)
                            result.success(true)
                        }
                        "cancel" -> {
                            val id = call.argument<Int>("id") ?: throw IllegalArgumentException("Reminder id is required")
                            DailyReminderAlarmScheduler.cancel(applicationContext, id)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("DAILY_REMINDER_ALARM_ERROR", error.message, null)
                }
            }

        activityNotificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIVITY_NOTIFICATION_CHANNEL)
        activityNotificationChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "update" -> {
                        val title = call.argument<String>("title") ?: "آماده ثبت فعالیت جدید"
                        val elapsedSeconds = call.argument<Number>("elapsedSeconds")?.toLong() ?: 0L
                        val running = call.argument<Boolean>("running") ?: false
                        val serviceIntent = Intent(this, ActivityTimerNotificationService::class.java).apply {
                            action = ActivityTimerNotificationService.ACTION_UPDATE
                            putExtra(ActivityTimerNotificationService.EXTRA_TITLE, title)
                            putExtra(ActivityTimerNotificationService.EXTRA_ELAPSED_SECONDS, elapsedSeconds)
                            putExtra(ActivityTimerNotificationService.EXTRA_RUNNING, running)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(serviceIntent)
                        else startService(serviceIntent)
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
        storeNotificationAction(intent)
    }

    private fun getLaunchableApps(): List<Map<String, String>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(launcherIntent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, PackageManager.MATCH_ALL)
        }
        return activities.mapNotNull { info ->
            val packageName = info.activityInfo?.packageName ?: return@mapNotNull null
            if (packageName == applicationContext.packageName) return@mapNotNull null
            val label = info.loadLabel(packageManager)?.toString()?.trim().orEmpty()
            if (label.isEmpty()) return@mapNotNull null
            mapOf("packageName" to packageName, "label" to label,
                "icon" to drawableToBase64(info.loadIcon(packageManager)))
        }.distinctBy { it["packageName"] }.sortedBy { it["label"]?.lowercase().orEmpty() }
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val width = drawable.intrinsicWidth.coerceAtLeast(1).coerceAtMost(192)
        val height = drawable.intrinsicHeight.coerceAtLeast(1).coerceAtMost(192)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        bitmap.recycle()
        return Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_NOTIFICATION_ACTION) ?: return
        val channel = activityNotificationChannel
        if (channel != null) channel.invokeMethod("notificationAction", action)
        else storeNotificationAction(intent)
    }

    private fun storeNotificationAction(source: Intent?): String? {
        val action = source?.getStringExtra(EXTRA_NOTIFICATION_ACTION) ?: return null
        getSharedPreferences(ACTIVITY_NOTIFICATION_PREFS, MODE_PRIVATE).edit()
            .putString(PENDING_ACTION_KEY, action).apply()
        return action
    }

    companion object {
        private const val ACTIVITY_NOTIFICATION_CHANNEL = "timer_main/activity_notification"
        private const val ACTIVITY_NOTIFICATION_PREFS = "activity_notification_actions"
        private const val PENDING_ACTION_KEY = "pending_action"
        const val EXTRA_NOTIFICATION_ACTION = "activity_notification_action"
    }
}

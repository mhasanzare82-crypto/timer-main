package com.example.timer_main

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Handles notification controls without starting MainActivity or the Flutter UI. */
class ActivityTimerNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        var elapsed = prefs.getLong(KEY_ELAPSED, 0L).coerceAtLeast(0L)
        var running = prefs.getBoolean(KEY_RUNNING, false)
        var startedAt = prefs.getLong(KEY_STARTED_AT, 0L)
        val updatedAt = prefs.getLong(KEY_UPDATED_AT, now)

        if (running) elapsed += ((now - updatedAt).coerceAtLeast(0L) / 1000L)

        when (intent.action) {
            ActivityTimerNotificationService.ACTION_START -> {
                if (!running) {
                    if (startedAt == 0L) startedAt = now - elapsed * 1000L
                    running = true
                }
            }
            ActivityTimerNotificationService.ACTION_PAUSE -> running = false
            ActivityTimerNotificationService.ACTION_STOP -> {
                val remote = RemoteInput.getResultsFromIntent(intent)
                val name = remote?.getCharSequence(KEY_ACTIVITY_NAME)?.toString()?.trim().orEmpty()
                if (name.isEmpty()) return
                saveCompletedActivity(context, name, startedAt.takeIf { it > 0L } ?: (now - elapsed * 1000L), now, elapsed)
                elapsed = 0L
                running = false
                startedAt = 0L
                prefs.edit().putString(KEY_TITLE, "آماده ثبت فعالیت جدید").apply()
            }
            else -> return
        }

        prefs.edit()
            .putLong(KEY_ELAPSED, elapsed)
            .putBoolean(KEY_RUNNING, running)
            .putLong(KEY_STARTED_AT, startedAt)
            .putLong(KEY_UPDATED_AT, now)
            .apply()

        val update = Intent(context, ActivityTimerNotificationService::class.java).apply {
            action = ActivityTimerNotificationService.ACTION_UPDATE
            putExtra(ActivityTimerNotificationService.EXTRA_TITLE, prefs.getString(KEY_TITLE, "آماده ثبت فعالیت جدید"))
            putExtra(ActivityTimerNotificationService.EXTRA_ELAPSED_SECONDS, elapsed)
            putExtra(ActivityTimerNotificationService.EXTRA_RUNNING, running)
            putExtra(ActivityTimerNotificationService.EXTRA_STARTED_AT_MILLIS, startedAt)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(update)
        else context.startService(update)
    }

    private fun saveCompletedActivity(context: Context, name: String, startedAt: Long, endedAt: Long, seconds: Long) {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val activitiesKey = "flutter.completed_activities_jalali_v1"
        val existing = flutterPrefs.getString(activitiesKey, "[]") ?: "[]"
        val activities = try { JSONArray(existing) } catch (_: Exception) { JSONArray() }
        val start = Date(startedAt)
        val end = Date(endedAt)
        val item = JSONObject().apply {
            put("name", name)
            put("startDate", dateFormat("yyyy/MM/dd", start))
            put("startTime", dateFormat("HH:mm:ss", start))
            put("endDate", dateFormat("yyyy/MM/dd", end))
            put("endTime", dateFormat("HH:mm:ss", end))
            put("durationSeconds", seconds.coerceAtLeast(0L))
        }
        val updated = JSONArray().put(item)
        for (i in 0 until activities.length()) updated.put(activities.get(i))
        val editor = flutterPrefs.edit().putString(activitiesKey, updated.toString())

        val namesKey = "flutter.activity_names_v1"
        val names = flutterPrefs.getStringSet(namesKey, emptySet())?.toMutableSet() ?: mutableSetOf()
        names.add(name)
        editor.putStringSet(namesKey, names).apply()
    }

    private fun dateFormat(pattern: String, date: Date): String =
        SimpleDateFormat(pattern, Locale.US).format(date)

    companion object {
        const val KEY_ACTIVITY_NAME = "activity_name"
        private const val PREFS = "activity_stopwatch_notification_state"
        private const val KEY_TITLE = "title"
        private const val KEY_ELAPSED = "elapsed_seconds"
        private const val KEY_RUNNING = "running"
        private const val KEY_UPDATED_AT = "updated_at_millis"
        private const val KEY_STARTED_AT = "started_at_millis"
    }
}

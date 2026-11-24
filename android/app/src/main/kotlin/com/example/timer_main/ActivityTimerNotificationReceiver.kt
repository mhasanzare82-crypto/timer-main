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
            put("startDate", jalaliDate(start))
            put("startTime", persianDigits(dateFormat("HH:mm:ss", start)))
            put("endDate", jalaliDate(end))
            put("endTime", persianDigits(dateFormat("HH:mm:ss", end)))
            put("durationSeconds", seconds.coerceAtLeast(0L))
        }
        val updated = JSONArray().put(item)
        for (i in 0 until activities.length()) updated.put(activities.get(i))
        val editor = flutterPrefs.edit()
            .putString(activitiesKey, updated.toString())
            .putString("flutter.running_activities_v1", "[]")

        val namesKey = "flutter.activity_names_v1"
        val names = try {
            val storedNames = JSONArray(flutterPrefs.getString(namesKey, "[]") ?: "[]")
            buildSet {
                for (i in 0 until storedNames.length()) add(storedNames.getString(i))
            }
        } catch (_: Exception) { emptySet() }.toMutableSet()
        names.add(name)
        val namesJson = JSONArray()
        names.sorted().forEach { namesJson.put(it) }
        editor.putString(namesKey, namesJson.toString()).apply()
    }

    private fun jalaliDate(date: Date): String {
        val calendar = java.util.Calendar.getInstance().apply { time = date }
        val gy = calendar.get(java.util.Calendar.YEAR)
        val gm = calendar.get(java.util.Calendar.MONTH) + 1
        val gd = calendar.get(java.util.Calendar.DAY_OF_MONTH)
        val gDays = intArrayOf(0,31, if (isGregorianLeap(gy)) 29 else 28,31,30,31,30,31,31,30,31,30,31)
        var gy2 = gy - 1600
        var gm2 = gm - 1
        val gd2 = gd - 1
        var gNo = 365 * gy2 + (gy2 + 3) / 4 - (gy2 + 99) / 100 + (gy2 + 399) / 400
        for (i in 0 until gm2) gNo += gDays[i + 1]
        gNo += gd2
        var jNo = gNo - 79
        val jNp = jNo / 12053
        jNo %= 12053
        var jy = 979 + 33 * jNp + 4 * (jNo / 1461)
        jNo %= 1461
        if (jNo >= 366) {
            jy += (jNo - 1) / 365
            jNo = (jNo - 1) % 365
        }
        val jm: Int
        val jd: Int
        if (jNo < 186) {
            jm = 1 + (jNo / 31)
            jd = 1 + (jNo % 31)
        } else {
            jm = 7 + ((jNo - 186) / 30)
            jd = 1 + ((jNo - 186) % 30)
        }
        return persianDigits(String.format(Locale.US, "%04d/%02d/%02d", jy, jm, jd))
    }

    private fun isGregorianLeap(year: Int): Boolean =
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

    private fun persianDigits(value: String): String {
        val digits = "۰۱۲۳۴۵۶۷۸۹"
        return value.map { char -> if (char in '0'..'9') digits[char - '0'] else char }.joinToString("")
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

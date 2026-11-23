package com.example.timer_main

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

internal object DailyReminderAlarmScheduler {
    private const val PREFS = "daily_reminder_native_alarms"
    private const val PREFIX = "alarm_"

    fun schedule(context: Context, id: Int, triggerAtMillis: Long, soundPath: String?, text: String, repeatDaily: Boolean = false) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            throw SecurityException("Exact alarm permission is not granted")
        }

        val record = JSONObject()
            .put("id", id)
            .put("triggerAtMillis", triggerAtMillis)
            .put("soundPath", soundPath ?: JSONObject.NULL)
            .put("text", text)
            .put("repeatDaily", repeatDaily)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(PREFIX + id, record.toString())
            .apply()

        val intent = alarmIntent(context, id, triggerAtMillis, soundPath, text, repeatDaily)
        val pendingIntent = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
    }

    fun cancel(context: Context, id: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context, id, Intent(context, DailyReminderAlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(PREFIX + id)
            .apply()
    }

    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val records = prefs.all.filterKeys { it.startsWith(PREFIX) }.values
        val now = System.currentTimeMillis()
        records.forEach { raw ->
            if (raw !is String) return@forEach
            try {
                val record = JSONObject(raw)
                val triggerAt = record.getLong("triggerAtMillis")
                val repeatDaily = record.optBoolean("repeatDaily", false)
                val nextTrigger = if (triggerAt > now) triggerAt else if (repeatDaily) nextDailyTrigger(triggerAt, now) else null
                if (nextTrigger != null) {
                    val path = if (record.isNull("soundPath")) null else record.getString("soundPath")
                    schedule(
                        context,
                        record.getInt("id"),
                        nextTrigger,
                        path,
                        record.optString("text", "یادآور"),
                        repeatDaily
                    )
                }
            } catch (_: Exception) {
                // Ignore a damaged reminder record without blocking other alarms.
            }
        }
    }

    fun scheduleNextDailyOccurrence(context: Context, intent: Intent) {
        if (!intent.getBooleanExtra(EXTRA_REPEAT_DAILY, false)) return
        val id = intent.getIntExtra(DailyReminderAlarmReceiver.EXTRA_ID, 0)
        val triggerAt = intent.getLongExtra(DailyReminderAlarmReceiver.EXTRA_TRIGGER_AT, 0L)
        if (id == 0 || triggerAt <= 0L) return
        val soundPath = intent.getStringExtra(DailyReminderAlarmReceiver.EXTRA_SOUND_PATH)
        val text = intent.getStringExtra(DailyReminderAlarmReceiver.EXTRA_TEXT) ?: "زمان یادآور فرا رسیده است"
        val next = nextDailyTrigger(triggerAt, System.currentTimeMillis())
        schedule(context, id, next, soundPath, text, true)
    }

    private fun nextDailyTrigger(previousTrigger: Long, now: Long): Long {
        val calendar = java.util.Calendar.getInstance().apply { timeInMillis = previousTrigger }
        do {
            calendar.add(java.util.Calendar.DAY_OF_YEAR, 1)
        } while (calendar.timeInMillis <= now)
        return calendar.timeInMillis
    }

    private fun alarmIntent(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        soundPath: String?,
        text: String,
        repeatDaily: Boolean
    ) = Intent(context, DailyReminderAlarmReceiver::class.java).apply {
        putExtra(DailyReminderAlarmReceiver.EXTRA_ID, id)
        putExtra(DailyReminderAlarmReceiver.EXTRA_TRIGGER_AT, triggerAtMillis)
        putExtra(DailyReminderAlarmReceiver.EXTRA_SOUND_PATH, soundPath)
        putExtra(DailyReminderAlarmReceiver.EXTRA_TEXT, text)
        putExtra(DailyReminderAlarmReceiver.EXTRA_REPEAT_DAILY, repeatDaily)
    }
}

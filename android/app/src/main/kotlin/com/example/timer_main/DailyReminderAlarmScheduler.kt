package com.example.timer_main

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

internal object DailyReminderAlarmScheduler {
    private const val PREF_FILE = "daily_reminder_native"
    private const val PREF_JSON = "reminders_json"
    private const val ACTION_ALARM = "com.example.timer_main.DAILY_REMINDER_ALARM"

    fun sync(context: Context, json: String) {
        val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val previous = runCatching { JSONArray(prefs.getString(PREF_JSON, "[]")) }.getOrDefault(JSONArray())
        val current = JSONArray(json)
        val previousById = (0 until previous.length()).mapNotNull { index ->
            previous.optJSONObject(index)?.let { it.optInt("id") to it }
        }.toMap()
        val currentById = (0 until current.length()).mapNotNull { index ->
            current.optJSONObject(index)?.let { it.optInt("id") to it }
        }.toMap()

        // Only touch alarms whose reminder was added, removed, or actually changed.
        // This avoids cancelling and recreating every alarm when one switch changes.
        for ((id, oldReminder) in previousById) {
            val newReminder = currentById[id]
            if (newReminder == null || oldReminder.toString() != newReminder.toString()) {
                cancel(context, id)
            }
        }
        for ((id, newReminder) in currentById) {
            val oldReminder = previousById[id]
            if (oldReminder == null || oldReminder.toString() != newReminder.toString()) {
                schedule(context, newReminder)
            }
        }

        prefs.edit().putString(PREF_JSON, json).apply()
        val ringingId = context.getSharedPreferences(
            DailyReminderRingingService.PREF_FILE, Context.MODE_PRIVATE
        ).getInt(DailyReminderRingingService.ACTIVE_ID_KEY, -1)
        if (ringingId >= 0 && currentById[ringingId]?.optBoolean("enabled", false) != true) {
            context.startService(Intent(context, DailyReminderRingingService::class.java).apply {
                action = DailyReminderRingingService.STOP_ACTION
            })
        }
    }

    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val reminders = runCatching { JSONArray(prefs.getString(PREF_JSON, "[]")) }.getOrDefault(JSONArray())
        for (i in 0 until reminders.length()) schedule(context, reminders.optJSONObject(i) ?: continue)
    }

    fun scheduleNext(context: Context, extras: android.os.Bundle) {
        val repeat = extras.getString("repeat") ?: "once"
        if (repeat == "once") return
        val reminder = JSONObject().apply {
            put("id", extras.getInt("reminderId"))
            put("text", extras.getString("reminderText") ?: "")
            put("repeat", repeat)
            put("hour", extras.getInt("hour"))
            put("minute", extras.getInt("minute"))
            put("days", JSONArray(extras.getIntArray("days") ?: intArrayOf()))
            put("enabled", true)
            put("soundPath", extras.getString("soundPath"))
        }
        schedule(context, reminder)
    }

    private fun schedule(context: Context, reminder: JSONObject) {
        if (!reminder.optBoolean("enabled", false)) return
        val id = reminder.optInt("id")
        val repeat = reminder.optString("repeat", "once")
        val hour = reminder.optInt("hour", 8)
        val minute = reminder.optInt("minute", 0)
        val trigger = when (repeat) {
            "once" -> reminder.optLong("triggerAtMillis", 0L).takeIf { it > System.currentTimeMillis() }
            "daily" -> nextDaily(hour, minute)
            "weekly" -> nextWeekly(hour, minute, reminder.optJSONArray("days") ?: JSONArray())
            else -> null
        } ?: return
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = alarmIntent(context, reminder)
        val pending = PendingIntent.getBroadcast(context, requestCode(id), intent, pendingFlags())
        try {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
        } catch (_: SecurityException) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
        }
    }

    private fun nextDaily(hour: Int, minute: Int): Long {
        val c = Calendar.getInstance().apply { set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        if (c.timeInMillis <= System.currentTimeMillis()) c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    private fun nextWeekly(hour: Int, minute: Int, days: JSONArray): Long? {
        val wanted = (0 until days.length()).map { days.optInt(it) }.filter { it in 1..7 }.toSet()
        if (wanted.isEmpty()) return null
        for (offset in 0..7) {
            val c = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, offset); set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
            val dartWeekday = if (c.get(Calendar.DAY_OF_WEEK) == Calendar.MONDAY) 1 else ((c.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (dartWeekday in wanted && c.timeInMillis > System.currentTimeMillis()) return c.timeInMillis
        }
        return null
    }

    private fun alarmIntent(context: Context, reminder: JSONObject): Intent = Intent(context, DailyReminderAlarmReceiver::class.java).apply {
        action = ACTION_ALARM
        data = android.net.Uri.parse("timer-daily-reminder://${reminder.optInt("id")}")
        putExtra("reminderId", reminder.optInt("id"))
        putExtra("reminderText", reminder.optString("text", "یادآوری"))
        putExtra("repeat", reminder.optString("repeat", "once"))
        putExtra("hour", reminder.optInt("hour", 8))
        putExtra("minute", reminder.optInt("minute", 0))
        putExtra("days", reminder.optJSONArray("days")?.let { arr -> IntArray(arr.length()) { arr.optInt(it) } } ?: intArrayOf())
        putExtra("soundPath", reminder.optString("soundPath").takeIf { it.isNotBlank() && it != "null" })
    }

    private fun cancel(context: Context, id: Int) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(context, requestCode(id), Intent(context, DailyReminderAlarmReceiver::class.java).apply {
            action = ACTION_ALARM
            data = android.net.Uri.parse("timer-daily-reminder://$id")
        }, pendingFlags())
        alarm.cancel(pending)
        pending.cancel()
    }

    private fun requestCode(id: Int) = 600000 + (id % 1000000)
    private fun pendingFlags() = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
}

class DailyReminderAlarmReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        DailyReminderAlarmScheduler.scheduleNext(context, extras)
        val service = Intent(context, DailyReminderRingingService::class.java).apply { putExtras(extras) }
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
        } catch (e: Exception) {
            android.util.Log.e("DailyReminderAlarm", "Unable to start ringtone service", e)
        }
    }
}

class DailyReminderBootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        DailyReminderAlarmScheduler.restore(context)
    }
}

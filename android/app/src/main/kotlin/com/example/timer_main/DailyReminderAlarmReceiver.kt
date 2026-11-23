package com.example.timer_main

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class DailyReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, DailyReminderAlarmService::class.java).apply {
            action = DailyReminderAlarmService.ACTION_START
            putExtra(EXTRA_ID, intent.getIntExtra(EXTRA_ID, 0))
            putExtra(EXTRA_SOUND_PATH, intent.getStringExtra(EXTRA_SOUND_PATH))
            putExtra(EXTRA_TEXT, intent.getStringExtra(EXTRA_TEXT) ?: "زمان یادآور فرا رسیده است")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }

    companion object {
        const val EXTRA_ID = "daily_reminder_id"
        const val EXTRA_TRIGGER_AT = "daily_reminder_trigger_at"
        const val EXTRA_SOUND_PATH = "daily_reminder_sound_path"
        const val EXTRA_TEXT = "daily_reminder_text"
    }
}

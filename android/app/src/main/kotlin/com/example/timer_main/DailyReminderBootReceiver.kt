package com.example.timer_main

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DailyReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> DailyReminderAlarmScheduler.restore(context)
        }
    }
}

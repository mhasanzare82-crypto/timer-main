package com.example.timer_main

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.SystemClock

class ActivityTimerService : Service() {
    private val prefs by lazy { getSharedPreferences(PREFS_NAME, MODE_PRIVATE) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        // Enter foreground immediately; the service also restores its state after process recreation.
        startForeground(NOTIFICATION_ID, buildNotification())

        when (intent?.action) {
            ACTION_SYNC -> syncFromFlutter(intent)
            ACTION_TOGGLE -> toggleTimer()
            ACTION_STOP -> requestStop()
            ACTION_FINISH -> clearTimer()
            ACTION_CANCEL_STOP -> prefs.edit().putBoolean(KEY_PENDING_STOP, false).apply()
            ACTION_SHOW, null -> {
                if (!prefs.contains(KEY_HAS_TIMER)) {
                    prefs.edit()
                        .putBoolean(KEY_HAS_TIMER, false)
                        .putBoolean(KEY_RUNNING, false)
                        .putBoolean(KEY_PENDING_STOP, false)
                        .putLong(KEY_ELAPSED_MS, 0L)
                        .apply()
                }
            }
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun syncFromFlutter(intent: Intent) {
        val hasTimer = intent.getBooleanExtra(EXTRA_HAS_TIMER, false)
        val editor = prefs.edit()
            .putBoolean(KEY_HAS_TIMER, hasTimer)
            .putBoolean(KEY_PENDING_STOP, false)
            .putBoolean(KEY_RUNNING, hasTimer && intent.getBooleanExtra(EXTRA_RUNNING, false))
        if (hasTimer) {
            editor.putString(KEY_ID, intent.getStringExtra(EXTRA_ID) ?: "")
                .putString(KEY_NAME, intent.getStringExtra(EXTRA_NAME) ?: "")
                .putLong(KEY_STARTED_AT, intent.getLongExtra(EXTRA_STARTED_AT, System.currentTimeMillis()))
                .putLong(KEY_ELAPSED_MS, intent.getLongExtra(EXTRA_ELAPSED_MS, 0L).coerceAtLeast(0L))
                .putLong(KEY_RUNNING_SINCE, intent.getLongExtra(EXTRA_RUNNING_SINCE, 0L))
        } else {
            editor.putString(KEY_ID, "")
                .putString(KEY_NAME, "")
                .putLong(KEY_STARTED_AT, 0L)
                .putLong(KEY_ELAPSED_MS, 0L)
                .putLong(KEY_RUNNING_SINCE, 0L)
        }
        editor.apply()
    }

    private fun toggleTimer() {
        val hasTimer = prefs.getBoolean(KEY_HAS_TIMER, false)
        val running = prefs.getBoolean(KEY_RUNNING, false)
        val now = System.currentTimeMillis()
        if (!hasTimer) {
            prefs.edit()
                .putBoolean(KEY_HAS_TIMER, true)
                .putBoolean(KEY_RUNNING, true)
                .putBoolean(KEY_PENDING_STOP, false)
                .putString(KEY_ID, now.toString())
                .putString(KEY_NAME, "")
                .putLong(KEY_STARTED_AT, now)
                .putLong(KEY_ELAPSED_MS, 0L)
                .putLong(KEY_RUNNING_SINCE, now)
                .apply()
        } else if (running) {
            pauseTimer()
        } else {
            prefs.edit()
                .putBoolean(KEY_RUNNING, true)
                .putBoolean(KEY_PENDING_STOP, false)
                .putLong(KEY_RUNNING_SINCE, now)
                .apply()
        }
    }

    private fun pauseTimer() {
        if (!prefs.getBoolean(KEY_RUNNING, false)) return
        val runningSince = prefs.getLong(KEY_RUNNING_SINCE, 0L)
        val elapsed = prefs.getLong(KEY_ELAPSED_MS, 0L)
        val added = if (runningSince > 0L) (System.currentTimeMillis() - runningSince).coerceAtLeast(0L) else 0L
        prefs.edit()
            .putBoolean(KEY_RUNNING, false)
            .putLong(KEY_ELAPSED_MS, elapsed + added)
            .putLong(KEY_RUNNING_SINCE, 0L)
            .apply()
    }

    private fun requestStop() {
        if (!prefs.getBoolean(KEY_HAS_TIMER, false)) return
        pauseTimer()
        prefs.edit().putBoolean(KEY_PENDING_STOP, true).apply()

    }

    private fun clearTimer() {
        prefs.edit()
            .putBoolean(KEY_HAS_TIMER, false)
            .putBoolean(KEY_RUNNING, false)
            .putBoolean(KEY_PENDING_STOP, false)
            .putString(KEY_ID, "")
            .putString(KEY_NAME, "")
            .putLong(KEY_STARTED_AT, 0L)
            .putLong(KEY_ELAPSED_MS, 0L)
            .putLong(KEY_RUNNING_SINCE, 0L)
            .apply()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "کنترل تایمر فعالیت",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "شروع، مکث و توقف تایمر فعالیت از نوار اعلان"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val hasTimer = prefs.getBoolean(KEY_HAS_TIMER, false)
        val running = prefs.getBoolean(KEY_RUNNING, false)
        val name = prefs.getString(KEY_NAME, "").orEmpty().ifBlank { "فعالیت جدید" }
        val elapsed = currentElapsedMillis()
        val toggleIntent = Intent(this, ActivityTimerService::class.java).apply { action = ACTION_TOGGLE }
        val togglePending = PendingIntent.getService(
            this, REQUEST_TOGGLE, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_FOR_STOP
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val stopPending = PendingIntent.getActivity(
            this, REQUEST_STOP, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openIntent = PendingIntent.getActivity(
            this, REQUEST_OPEN,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(if (hasTimer) name else "تایمر فعالیت")
            .setContentText(
                when {
                    !hasTimer -> "برای شروع فعالیت، دکمه شروع را لمس کن"
                    running -> "در حال اجرا • زمان سپری‌شده"
                    else -> "متوقف موقت • ${formatDuration(elapsed)}"
                }
            )
            .setContentIntent(openIntent)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

        if (hasTimer && running) {
            builder.setUsesChronometer(true)
                .setWhen(SystemClock.elapsedRealtime() - elapsed)
        }
        builder.addAction(
            if (running) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
            if (running) "مکث" else if (hasTimer) "ادامه" else "شروع فعالیت",
            togglePending
        )
        if (hasTimer) {
            builder.addAction(android.R.drawable.ic_media_stop, "توقف و ثبت", stopPending)
        }
        return builder.build()
    }

    private fun currentElapsedMillis(): Long {
        val stored = prefs.getLong(KEY_ELAPSED_MS, 0L)
        if (!prefs.getBoolean(KEY_RUNNING, false)) return stored
        val since = prefs.getLong(KEY_RUNNING_SINCE, 0L)
        return stored + if (since > 0L) (System.currentTimeMillis() - since).coerceAtLeast(0L) else 0L
    }

    private fun formatDuration(milliseconds: Long): String {
        val total = milliseconds / 1000L
        val hours = total / 3600L
        val minutes = (total % 3600L) / 60L
        val seconds = total % 60L
        return String.format("%02d:%02d:%02d", hours, minutes, seconds)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep the ongoing timer notification alive when the app is swiped from recents.
        super.onTaskRemoved(rootIntent)
    }

    companion object {
        const val PREFS_NAME = "activity_timer_notification_state"
        const val KEY_HAS_TIMER = "has_timer"
        const val KEY_ID = "timer_id"
        const val KEY_NAME = "timer_name"
        const val KEY_STARTED_AT = "started_at"
        const val KEY_ELAPSED_MS = "elapsed_ms"
        const val KEY_RUNNING = "running"
        const val KEY_RUNNING_SINCE = "running_since"
        const val KEY_PENDING_STOP = "pending_stop"

        const val EXTRA_HAS_TIMER = "hasTimer"
        const val EXTRA_ID = "id"
        const val EXTRA_NAME = "name"
        const val EXTRA_STARTED_AT = "startedAt"
        const val EXTRA_ELAPSED_MS = "elapsedMs"
        const val EXTRA_RUNNING = "running"
        const val EXTRA_RUNNING_SINCE = "runningSince"

        const val ACTION_SHOW = "com.example.timer_main.activitytimer.SHOW"
        const val ACTION_SYNC = "com.example.timer_main.activitytimer.SYNC"
        const val ACTION_TOGGLE = "com.example.timer_main.activitytimer.TOGGLE"
        const val ACTION_STOP = "com.example.timer_main.activitytimer.STOP"
        const val ACTION_FINISH = "com.example.timer_main.activitytimer.FINISH"
        const val ACTION_CANCEL_STOP = "com.example.timer_main.activitytimer.CANCEL_STOP"
        const val ACTION_OPEN_FOR_STOP = "com.example.timer_main.activitytimer.OPEN_FOR_STOP"

        private const val CHANNEL_ID = "activity_timer_control_v1"
        private const val NOTIFICATION_ID = 850010
        private const val REQUEST_TOGGLE = 850011
        private const val REQUEST_STOP = 850012
        private const val REQUEST_OPEN = 850013
    }
}

package com.example.timer_main

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.widget.RemoteViews

/**
 * Keeps the activity stopwatch controls visible while the Flutter UI is in the background.
 * Button presses reopen the app so the existing Dart activity model remains the source of truth.
 */
class ActivityTimerNotificationService : Service() {
    private var title: String = "آماده ثبت فعالیت جدید"
    private var elapsedSeconds: Long = 0L
    private var running: Boolean = false
    private var stateUpdatedAtMillis: Long = System.currentTimeMillis()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == ACTION_UPDATE) {
            title = intent.getStringExtra(EXTRA_TITLE) ?: "آماده ثبت فعالیت جدید"
            elapsedSeconds = intent.getLongExtra(EXTRA_ELAPSED_SECONDS, 0L).coerceAtLeast(0L)
            running = intent.getBooleanExtra(EXTRA_RUNNING, false)
            stateUpdatedAtMillis = System.currentTimeMillis()
            persistState()
        } else if (intent == null) {
            restoreState()
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    private fun persistState() {
        getSharedPreferences(STATE_PREFS, MODE_PRIVATE).edit()
            .putString(KEY_TITLE, title)
            .putLong(KEY_ELAPSED, elapsedSeconds)
            .putBoolean(KEY_RUNNING, running)
            .putLong(KEY_UPDATED_AT, stateUpdatedAtMillis)
            .apply()
    }

    private fun restoreState() {
        val prefs = getSharedPreferences(STATE_PREFS, MODE_PRIVATE)
        title = prefs.getString(KEY_TITLE, "آماده ثبت فعالیت جدید") ?: "آماده ثبت فعالیت جدید"
        elapsedSeconds = prefs.getLong(KEY_ELAPSED, 0L).coerceAtLeast(0L)
        running = prefs.getBoolean(KEY_RUNNING, false)
        stateUpdatedAtMillis = prefs.getLong(KEY_UPDATED_AT, System.currentTimeMillis())
        if (running) {
            val now = System.currentTimeMillis()
            elapsedSeconds += ((now - stateUpdatedAtMillis).coerceAtLeast(0L) / 1000L)
            stateUpdatedAtMillis = now
            persistState()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "کنترل تایمر فعالیت",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "اعلان دائمی برای شروع، مکث و توقف تایمر فعالیت"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val remote = RemoteViews(packageName, R.layout.activity_timer_notification).apply {
            setTextViewText(R.id.notification_activity_name, title.ifBlank { "نام فعالیت" })
            val elapsedMillis = elapsedSeconds * 1000L
            val base = SystemClock.elapsedRealtime() - elapsedMillis
            if (running) {
                setChronometer(R.id.notification_chronometer, base, "%s", true)
            } else {
                setTextViewText(R.id.notification_chronometer, formatDuration(elapsedSeconds))
            }
            setViewVisibility(R.id.notification_chronometer, android.view.View.VISIBLE)
            setOnClickPendingIntent(R.id.notification_save_name, activityPendingIntent(ACTION_SAVE_NAME, SAVE_NAME_REQUEST_CODE))
            setOnClickPendingIntent(R.id.notification_delete, activityPendingIntent(ACTION_DELETE, DELETE_REQUEST_CODE))
            setOnClickPendingIntent(R.id.notification_activity_name, activityPendingIntent(ACTION_OPEN_APP, CONTENT_REQUEST_CODE))
            setOnClickPendingIntent(R.id.notification_start, activityPendingIntent(ACTION_START, START_REQUEST_CODE))
            setOnClickPendingIntent(R.id.notification_pause, activityPendingIntent(ACTION_PAUSE, PAUSE_REQUEST_CODE))
            setOnClickPendingIntent(R.id.notification_stop, activityPendingIntent(ACTION_STOP, STOP_REQUEST_CODE))
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Timer")
            .setContentText(null)
            .setCustomContentView(remote)
            .setCustomBigContentView(remote)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
    }

    private fun activityPendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_NOTIFICATION_ACTION, action)
        }
        return PendingIntent.getActivity(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun formatDuration(seconds: Long): String {
        val hours = seconds / 3600L
        val minutes = (seconds % 3600L) / 60L
        val secs = seconds % 60L
        return String.format("%02d:%02d:%02d", hours, minutes, secs)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The foreground notification is intentionally retained when the app task is dismissed.
        super.onTaskRemoved(rootIntent)
    }

    companion object {
        const val ACTION_UPDATE = "com.example.timer_main.action.UPDATE_ACTIVITY_NOTIFICATION"
        const val ACTION_START = "start"
        const val ACTION_PAUSE = "pause"
        const val ACTION_STOP = "stop"
        const val ACTION_OPEN_APP = "open_app"
        const val ACTION_SAVE_NAME = "save_name"
        const val ACTION_DELETE = "delete"
        const val EXTRA_TITLE = "activity_notification_title"
        const val EXTRA_ELAPSED_SECONDS = "activity_notification_elapsed_seconds"
        const val EXTRA_RUNNING = "activity_notification_running"

        private const val STATE_PREFS = "activity_stopwatch_notification_state"
        private const val KEY_TITLE = "title"
        private const val KEY_ELAPSED = "elapsed_seconds"
        private const val KEY_RUNNING = "running"
        private const val KEY_UPDATED_AT = "updated_at_millis"
        private const val CHANNEL_ID = "activity_stopwatch_controls_v1"
        private const val NOTIFICATION_ID = 850010
        private const val CONTENT_REQUEST_CODE = 850011
        private const val START_REQUEST_CODE = 850012
        private const val PAUSE_REQUEST_CODE = 850013
        private const val STOP_REQUEST_CODE = 850014
        private const val SAVE_NAME_REQUEST_CODE = 850017
        private const val DELETE_REQUEST_CODE = 850018
    }
}

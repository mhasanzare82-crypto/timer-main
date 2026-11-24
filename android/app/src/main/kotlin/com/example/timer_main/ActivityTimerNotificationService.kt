package com.example.timer_main

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock

/**
 * Keeps the activity stopwatch controls visible while the Flutter UI is in the background.
 * Button presses reopen the app so the existing Dart activity model remains the source of truth.
 */
class ActivityTimerNotificationService : Service() {
    private var title: String = "آماده ثبت فعالیت جدید"
    private var elapsedSeconds: Long = 0L
    private var running: Boolean = false
    private var stateUpdatedAtMillis: Long = System.currentTimeMillis()
    private var startedAtMillis: Long = 0L

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
            startedAtMillis = intent.getLongExtra(EXTRA_STARTED_AT_MILLIS, 0L)
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
            .putLong(KEY_STARTED_AT, startedAtMillis)
            .apply()
    }

    private fun restoreState() {
        val prefs = getSharedPreferences(STATE_PREFS, MODE_PRIVATE)
        title = prefs.getString(KEY_TITLE, "آماده ثبت فعالیت جدید") ?: "آماده ثبت فعالیت جدید"
        elapsedSeconds = prefs.getLong(KEY_ELAPSED, 0L).coerceAtLeast(0L)
        running = prefs.getBoolean(KEY_RUNNING, false)
        stateUpdatedAtMillis = prefs.getLong(KEY_UPDATED_AT, System.currentTimeMillis())
        startedAtMillis = prefs.getLong(KEY_STARTED_AT, 0L)
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
        val contentIntent = PendingIntent.getActivity(
            this,
            CONTENT_REQUEST_CODE,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(
                if (running) "زمان فعالیت در حال سپری شدن است"
                else if (elapsedSeconds > 0L) "زمان سپری‌شده: ${formatDuration(elapsedSeconds)}"
                else "برای ثبت فعالیت جدید، شروع را بزن"
            )
            .setContentIntent(contentIntent)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(running)
            .setUsesChronometer(running)
            .setWhen(if (running) System.currentTimeMillis() - elapsedSeconds * 1000L else 0L)
            .addAction(action(android.R.drawable.ic_media_play, "شروع", ACTION_START, START_REQUEST_CODE))
            .addAction(action(android.R.drawable.ic_media_pause, "مکث", ACTION_PAUSE, PAUSE_REQUEST_CODE))
            .addAction(stopAction())
            .build()
        return notification
    }

    private fun action(icon: Int, label: String, action: String, requestCode: Int): Notification.Action {
        val intent = Intent(this, ActivityTimerNotificationReceiver::class.java).apply { this.action = action }
        val pendingIntent = PendingIntent.getBroadcast(this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Action.Builder(icon, label, pendingIntent).build()
    }

    private fun stopAction(): Notification.Action {
        val intent = Intent(this, ActivityTimerNotificationReceiver::class.java).apply { action = ACTION_STOP }
        val pendingIntent = PendingIntent.getBroadcast(this, STOP_REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
        val remoteInput = RemoteInput.Builder(ActivityTimerNotificationReceiver.KEY_ACTIVITY_NAME)
            .setLabel("نام فعالیت را وارد کن").build()
        return Notification.Action.Builder(R.drawable.ic_notification_stop, "توقف و ثبت", pendingIntent)
            .addRemoteInput(remoteInput).setAllowGeneratedReplies(false).build()
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
        const val EXTRA_TITLE = "activity_notification_title"
        const val EXTRA_ELAPSED_SECONDS = "activity_notification_elapsed_seconds"
        const val EXTRA_RUNNING = "activity_notification_running"
        const val EXTRA_STARTED_AT_MILLIS = "activity_notification_started_at_millis"

        private const val STATE_PREFS = "activity_stopwatch_notification_state"
        private const val KEY_TITLE = "title"
        private const val KEY_ELAPSED = "elapsed_seconds"
        private const val KEY_RUNNING = "running"
        private const val KEY_UPDATED_AT = "updated_at_millis"
        const val KEY_STARTED_AT = "started_at_millis"
        private const val CHANNEL_ID = "activity_stopwatch_controls_v1"
        private const val NOTIFICATION_ID = 850010
        private const val CONTENT_REQUEST_CODE = 850011
        private const val START_REQUEST_CODE = 850012
        private const val PAUSE_REQUEST_CODE = 850013
        private const val STOP_REQUEST_CODE = 850014
    }
}

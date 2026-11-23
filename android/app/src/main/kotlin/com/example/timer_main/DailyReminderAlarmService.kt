package com.example.timer_main

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.Uri
import java.io.File

class DailyReminderAlarmService : Service() {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopAlarm()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        createNotificationChannel()
        val reminderText = intent?.getStringExtra(DailyReminderAlarmReceiver.EXTRA_TEXT)
            ?: "زمان یادآور فرا رسیده است"
        startForeground(NOTIFICATION_ID, buildNotification(reminderText))
        acquireWakeLock()

        val soundPath = intent?.getStringExtra(DailyReminderAlarmReceiver.EXTRA_SOUND_PATH)
        startLoopingPlayback(soundPath)
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "زنگ یادآورهای روزانه",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "زنگ اختصاصی یادآور تا زمان توقف کاربر پخش می‌شود"
                setSound(null, null)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val stopIntent = Intent(this, DailyReminderAlarmService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            STOP_REQUEST_CODE,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("زنگ یادآور")
            .setContentText(text)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    "توقف زنگ",
                    stopPendingIntent
                ).build()
            )
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "timer_main:daily_reminder_alarm"
        ).apply { acquire() }
    }

    private fun startLoopingPlayback(soundPath: String?) {
        releasePlayer()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        try {
            val mediaPlayer = MediaPlayer()
            mediaPlayer.setAudioAttributes(attributes)
            mediaPlayer.isLooping = true
            if (!soundPath.isNullOrBlank() && File(soundPath).isFile) {
                mediaPlayer.setDataSource(soundPath)
            } else {
                val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: throw IllegalStateException("No default alarm sound is available")
                mediaPlayer.setDataSource(this, alarmUri)
            }
            mediaPlayer.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
            mediaPlayer.setOnErrorListener { mp, _, _ ->
                try { mp.release() } catch (_: Exception) {}
                if (player === mp) player = null
                true
            }
            mediaPlayer.prepare()
            mediaPlayer.start()
            player = mediaPlayer
        } catch (_: Exception) {
            releasePlayer()
            try {
                val fallback = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                if (fallback != null) {
                    player = MediaPlayer.create(this, fallback)?.apply {
                        setAudioAttributes(attributes)
                        isLooping = true
                        start()
                    }
                }
            } catch (_: Exception) {
                releasePlayer()
            }
        }
    }

    private fun releasePlayer() {
        val current = player
        player = null
        if (current != null) {
            try { if (current.isPlaying) current.stop() } catch (_: Exception) {}
            try { current.reset() } catch (_: Exception) {}
            try { current.release() } catch (_: Exception) {}
        }
    }

    private fun stopAlarm() {
        releasePlayer()
        wakeLock?.let { lock ->
            try { if (lock.isHeld) lock.release() } catch (_: Exception) {}
        }
        wakeLock = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.example.timer_main.action.START_DAILY_REMINDER"
        const val ACTION_STOP = "com.example.timer_main.action.STOP_DAILY_REMINDER"
        private const val CHANNEL_ID = "daily_reminder_ringing_v1"
        private const val NOTIFICATION_ID = 850001
        private const val STOP_REQUEST_CODE = 850002
    }
}

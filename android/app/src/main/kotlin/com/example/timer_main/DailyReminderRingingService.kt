package com.example.timer_main

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.content.pm.ServiceInfo

class DailyReminderRingingService : Service() {
    companion object {
        const val PREF_FILE = "daily_reminder_ringing_state"
        const val ACTIVE_ID_KEY = "active_reminder_id"
        const val STOP_ACTION = "com.example.timer_main.STOP_DAILY_REMINDER_RING"
        private const val CHANNEL = "daily_reminder_ringing"
        private const val NOTIFICATION_ID = 9731
    }
    private var player: MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP_ACTION) {
            stopAudio()
            clearActiveReminder()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        val text = intent?.getStringExtra("reminderText") ?: "یادآوری"
        val id = intent?.getIntExtra("reminderId", 0) ?: 0
        getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE).edit().putInt(ACTIVE_ID_KEY, id).apply()
        val stopIntent = Intent(this, DailyReminderRingingService::class.java).apply { action = STOP_ACTION }
        val stopPending = PendingIntent.getService(this, 9732, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag())
        val notification = buildNotification(text, stopPending)
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(NOTIFICATION_ID, notification)
        startAudio(intent?.getStringExtra("soundPath"))
        return START_NOT_STICKY
    }

    private fun buildNotification(text: String, stopPending: PendingIntent): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("یادآوری روزانه")
            .setContentText(text)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
            .addAction(android.R.drawable.ic_media_pause, "توقف زنگ", stopPending)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "زنگ یادآور روزانه", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                setVibrationPattern(null)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun startAudio(path: String?) {
        stopAudio()
        val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        try {
            val mp = MediaPlayer()
            mp.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setAudioAttributes(attrs)
            if (!path.isNullOrBlank()) mp.setDataSource(path)
            else {
                val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: return
                mp.setDataSource(this, uri)
            }
            mp.isLooping = true
            mp.setOnErrorListener { _, _, _ -> stopAudio(); clearActiveReminder(); stopForegroundCompat(); stopSelf(); true }
            mp.prepare()
            mp.start()
            player = mp
        } catch (e: Exception) {
            android.util.Log.e("DailyReminderRinging", "Audio playback failed", e)
            if (!path.isNullOrBlank()) startAudio(null)
        }
    }

    private fun clearActiveReminder() { getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE).edit().remove(ACTIVE_ID_KEY).apply() }

    private fun stopAudio() {
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    override fun onDestroy() {
        stopAudio()
        clearActiveReminder()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
    private fun immutableFlag() = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
}

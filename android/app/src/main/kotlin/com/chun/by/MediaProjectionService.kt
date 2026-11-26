package com.chun.by

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * MediaProjection 前台服务（Android 14+ 录屏前必须先启动，否则 getMediaProjection 会失败）。
 */
class MediaProjectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val channelId = "media_projection"
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(channelId, "录屏", NotificationManager.IMPORTANCE_LOW)
        )
        val n = Notification.Builder(this, channelId)
            .setContentTitle("Rowan 录屏")
            .setContentText("正在录屏")
            .setSmallIcon(R.drawable.ic_rowan)
            .build()
        startForeground(1001, n)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }
}

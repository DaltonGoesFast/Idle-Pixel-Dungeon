package com.daltongoesfast.spdtactics.patrol

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log

object PatrolNotify {
    private const val TAG = "PatrolNotify"
    private const val CHANNEL = "spd_patrol_return"

    fun allowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    fun show(ctx: Context, id: String, title: String, body: String) {
        if (!allowed(ctx)) {
            Log.i(TAG, "notification permission not granted; widget still updates")
            return
        }
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, "Patrols", NotificationManager.IMPORTANCE_DEFAULT)
            ch.description = "When a hero's patrol is ready to recall"
            nm.createNotificationChannel(ch)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        val n = builder
            .setSmallIcon(R.drawable.ic_patrol_status)
            .setContentTitle(if (title.isEmpty()) "Patrol back!" else title)
            .setContentText(body)
            .setContentIntent(PatrolOpen.pending(ctx))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .build()
        nm.notify(id.hashCode(), n)
    }
}

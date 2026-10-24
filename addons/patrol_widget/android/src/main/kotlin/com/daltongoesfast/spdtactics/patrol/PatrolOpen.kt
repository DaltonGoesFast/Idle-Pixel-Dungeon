package com.daltongoesfast.spdtactics.patrol

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Tap target shared by the widget and the notification. Starts the game and asks it to open the Guild. */
object PatrolOpen {
    private const val REQUEST = 0x53504401

    fun pending(ctx: Context): PendingIntent {
        val intent = Intent(ctx, PatrolOpenReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, REQUEST, intent, flags)
    }
}

class PatrolOpenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        PatrolStore.setOpen(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        launch.putExtra(PatrolStore.EXTRA_OPEN, "guild")
        context.startActivity(launch)
    }
}

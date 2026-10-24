package com.daltongoesfast.spdtactics.patrol

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Tap target shared by the widget and the notification.
 * The pending intent goes to the exported widget provider. A non-exported receiver is not a
 * reliable click target: the launcher (another app) sends it, and some API 31+ / One UI builds drop it.
 */
object PatrolOpen {
    private const val TAG = "PatrolWidget"
    private const val REQUEST = 0x53504401

    fun pending(ctx: Context): PendingIntent {
        val intent = Intent(ctx, PatrolWidgetProvider::class.java).apply {
            action = PatrolWidgetProvider.ACTION_OPEN
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, REQUEST, intent, flags)
    }

    fun launch(ctx: Context) {
        PatrolStore.setOpen(ctx)
        Log.i(TAG, "pending_open set")
        PatrolWidgetProvider.notifyPluginOfOpen()
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        if (launch == null) {
            Log.w(TAG, "no launch intent for ${ctx.packageName}")
            return
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        launch.putExtra(PatrolStore.EXTRA_OPEN, "guild")
        ctx.startActivity(launch)
        Log.i(TAG, "launch activity for guild")
    }
}

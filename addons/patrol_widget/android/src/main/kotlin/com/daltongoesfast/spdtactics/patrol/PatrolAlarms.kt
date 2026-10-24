package com.daltongoesfast.spdtactics.patrol

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * One wall-clock alarm per patrol still out. AlarmManager is exact when the app may schedule
 * exact alarms, and setAndAllowWhileIdle otherwise (no separate WorkManager job).
 * The receiver refreshes the widget and, when the snapshot asked for it, posts the notification.
 */
object PatrolAlarms {
    private const val TAG = "PatrolWidget"
    private const val MISSED_WINDOW_MS = 6L * 3600L * 1000L

    fun replace(ctx: Context, json: String?, fromBoot: Boolean) {
        val snap = try {
            if (json.isNullOrEmpty()) null else org.json.JSONObject(json)
        } catch (_: Exception) {
            null
        }
        val am = ctx.getSystemService(AlarmManager::class.java)
        for (id in PatrolStore.alarmIds(ctx)) {
            am.cancel(pending(ctx, id, null))
        }
        val fired = if (fromBoot) PatrolStore.firedIds(ctx) else HashSet()
        if (!fromBoot) PatrolStore.putFiredIds(ctx, emptySet())
        val next = HashSet<String>()
        val now = System.currentTimeMillis()
        for (alarm in PatrolJson.alarms(snap)) {
            val atMs = alarm.atSec * 1000L
            if (atMs <= now) {
                if (fromBoot && alarm.notify && alarm.id !in fired && now - atMs < MISSED_WINDOW_MS) {
                    PatrolNotify.show(ctx, alarm.id, alarm.title, alarm.body)
                    fired.add(alarm.id)
                }
                continue
            }
            schedule(am, atMs, pending(ctx, alarm.id, alarm))
            next.add(alarm.id)
        }
        PatrolStore.putAlarmIds(ctx, next)
        if (fromBoot) PatrolStore.putFiredIds(ctx, fired)
    }

    private fun schedule(am: AlarmManager, atMs: Long, pi: PendingIntent) {
        // API 31+ needs the exact-alarm grant. API 23-30 can call setExactAndAllowWhileIdle with no grant.
        val sdk = Build.VERSION.SDK_INT
        val exactOk = sdk < 31 || try {
            am.canScheduleExactAlarms()
        } catch (_: Exception) {
            false
        }
        if (sdk >= 23 && exactOk) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                Log.i(TAG, "exact alarm at $atMs sdk=$sdk")
                return
            } catch (e: SecurityException) {
                Log.w(TAG, "exact alarm denied, using while-idle", e)
            }
        }
        if (sdk >= 23) {
            Log.i(TAG, "inexact alarm at $atMs sdk=$sdk")
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
        } else {
            am.set(AlarmManager.RTC_WAKEUP, atMs, pi)
        }
    }

    fun pending(ctx: Context, id: String, alarm: PatrolAlarm?): PendingIntent {
        val intent = Intent(ctx, PatrolAlarmReceiver::class.java).apply {
            action = PatrolStore.ACTION_RETURN
            putExtra("id", id)
            if (alarm != null) {
                putExtra("notify", alarm.notify)
                putExtra("title", alarm.title)
                putExtra("body", alarm.body)
            }
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(ctx, id.hashCode(), intent, flags)
    }
}

class PatrolAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i("PatrolWidget", "alarm fired id=${intent?.getStringExtra("id")}")
        val id = intent?.getStringExtra("id") ?: ""
        if (id.isNotEmpty() && intent?.getBooleanExtra("notify", false) == true) {
            val fired = PatrolStore.firedIds(context)
            if (id !in fired) {
                PatrolNotify.show(
                    context,
                    id,
                    intent.getStringExtra("title") ?: "Patrol back!",
                    intent.getStringExtra("body") ?: "",
                )
                fired.add(id)
                PatrolStore.putFiredIds(context, fired)
            }
        }
        PatrolWidgetProvider.refresh(context)
    }
}

class PatrolBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        // An update wipes AlarmManager entries. MY_PACKAGE_REPLACED reschedules from the stored snapshot, same as boot.
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        Log.i("PatrolWidget", "reschedule from snapshot on $action ${PatrolStore.describe(context)}")
        val raw = PatrolStore.prefs(context).getString(PatrolStore.KEY_SNAPSHOT, "") ?: ""
        PatrolAlarms.replace(context, raw, fromBoot = true)
        PatrolWidgetProvider.refresh(context)
    }
}

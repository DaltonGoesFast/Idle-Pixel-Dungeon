package com.daltongoesfast.spdtactics.patrol

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.godotengine.godot.plugin.GodotPluginRegistry

/** Home-screen widget. Compact under 100dp tall (Fold cover); the taller layout lists up to four patrols. */
class PatrolWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_OPEN) {
            Log.i(TAG, "widget/notification tap")
            PatrolOpen.launch(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        Log.i(TAG, "onUpdate ids=${appWidgetIds.size} ${PatrolStore.describe(context)}")
        for (id in appWidgetIds) {
            try {
                val opts = appWidgetManager.getAppWidgetOptions(id)
                appWidgetManager.updateAppWidget(id, PatrolViews.render(context, opts))
            } catch (t: Throwable) {
                Log.e(TAG, "onUpdate $id failed", t)
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, PatrolViews.render(context, newOptions))
    }

    companion object {
        private const val TAG = "PatrolWidget"
        const val ACTION_OPEN = "com.daltongoesfast.spdtactics.patrol.OPEN"

        init {
            // This receiver is a manifest component, so R8 keeps it. Godot loads the plugin by
            // Class.forName + getConstructor(Godot). A release minify that ignores consumer rules
            // would otherwise delete that constructor and the singleton would never appear.
            try {
                Class.forName("com.daltongoesfast.spdtactics.patrol.PatrolWidgetPlugin")
                    .getDeclaredConstructor(org.godotengine.godot.Godot::class.java)
            } catch (t: Throwable) {
                Log.w(TAG, "plugin class not reachable from the widget receiver", t)
            }
        }

        fun placedCount(context: Context): Int {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, PatrolWidgetProvider::class.java)
            return mgr.getAppWidgetIds(cn).size
        }

        fun refresh(context: Context): Int {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, PatrolWidgetProvider::class.java)
            val ids = mgr.getAppWidgetIds(cn)
            Log.i(TAG, "refresh widgets=${ids.size} ${PatrolStore.describe(context)}")
            for (id in ids) {
                try {
                    mgr.updateAppWidget(id, PatrolViews.render(context, mgr.getAppWidgetOptions(id)))
                } catch (t: Throwable) {
                    Log.e(TAG, "updateAppWidget $id failed", t)
                }
            }
            return ids.size
        }

        /** Tap while the process is up. Cold start leaves the flag for consumeOpenTarget. */
        fun notifyPluginOfOpen() {
            try {
                val plugin = GodotPluginRegistry.getPluginRegistry().getPlugin("PatrolWidget") as? PatrolWidgetPlugin
                if (plugin == null) {
                    Log.i(TAG, "open flag set, plugin singleton not in the registry")
                    return
                }
                plugin.deliverOpenFromOutside()
            } catch (t: IllegalStateException) {
                Log.i(TAG, "open flag set, plugin registry not ready")
            } catch (t: Throwable) {
                Log.w(TAG, "open notify failed", t)
            }
        }
    }
}

object PatrolViews {
    private const val LARGE_MIN_DP = 100
    private val ROWS = arrayOf(
        intArrayOf(R.id.row0, R.id.name0, R.id.back0, R.id.timer0, R.id.reward0),
        intArrayOf(R.id.row1, R.id.name1, R.id.back1, R.id.timer1, R.id.reward1),
        intArrayOf(R.id.row2, R.id.name2, R.id.back2, R.id.timer2, R.id.reward2),
        intArrayOf(R.id.row3, R.id.name3, R.id.back3, R.id.timer3, R.id.reward3),
    )

    fun render(context: Context, options: Bundle?): RemoteViews {
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
        val views = if (height >= LARGE_MIN_DP) {
            RemoteViews(context.packageName, R.layout.patrol_widget_large)
        } else {
            RemoteViews(context.packageName, R.layout.patrol_widget_compact)
        }
        // @android:id/background is what Android 12+ clips to the system corner radius.
        // clipToOutline is set from values-v31, at inflate time. RemoteViews cannot call it.
        val open = PatrolOpen.pending(context)
        views.setOnClickPendingIntent(android.R.id.background, open)
        views.setOnClickPendingIntent(R.id.root, open)
        val rows = PatrolJson.rows(PatrolStore.readSnapshot(context))
        if (height >= LARGE_MIN_DP) bindLarge(views, rows) else bindCompact(views, rows)
        return views
    }

    private fun bindCompact(views: RemoteViews, rows: List<PatrolRow>) {
        val due = rows.filter { it.isDue() }
        if (rows.isEmpty()) {
            views.setTextViewText(R.id.line, "No patrols out")
            hideChronometer(views, R.id.timer)
            views.setViewVisibility(R.id.back, View.GONE)
            return
        }
        if (due.isNotEmpty()) {
            val line = if (due.size == 1) "${due[0].hero} · ${due[0].biome}" else "${due.size} patrols back"
            views.setTextViewText(R.id.line, line)
            views.setTextViewText(R.id.back, "Patrol back!")
            views.setViewVisibility(R.id.back, View.VISIBLE)
            hideChronometer(views, R.id.timer)
            return
        }
        val next = rows.minBy { it.backAtSec }
        views.setTextViewText(R.id.line, "${next.hero} · ${next.biome}")
        views.setViewVisibility(R.id.back, View.GONE)
        showChronometer(views, R.id.timer, next.backAtSec)
    }

    private fun bindLarge(views: RemoteViews, rows: List<PatrolRow>) {
        if (rows.isEmpty()) {
            views.setViewVisibility(R.id.empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.empty, View.GONE)
        }
        for (i in ROWS.indices) {
            val ids = ROWS[i]
            if (i >= rows.size) {
                views.setViewVisibility(ids[0], View.GONE)
                continue
            }
            val row = rows[i]
            views.setViewVisibility(ids[0], View.VISIBLE)
            views.setTextViewText(ids[1], "${row.hero} · ${row.biome}")
            if (row.reward.isEmpty()) {
                views.setViewVisibility(ids[4], View.GONE)
            } else {
                views.setViewVisibility(ids[4], View.VISIBLE)
                views.setTextViewText(ids[4], row.reward)
            }
            if (row.isDue()) {
                views.setTextViewText(ids[2], "Patrol back!")
                views.setViewVisibility(ids[2], View.VISIBLE)
                hideChronometer(views, ids[3])
            } else {
                views.setViewVisibility(ids[2], View.GONE)
                showChronometer(views, ids[3], row.backAtSec)
            }
        }
    }

    private fun showChronometer(views: RemoteViews, id: Int, backAtSec: Long) {
        val remaining = (backAtSec * 1000L - System.currentTimeMillis()).coerceAtLeast(0L)
        views.setChronometer(id, SystemClock.elapsedRealtime() + remaining, null, true)
        views.setChronometerCountDown(id, true)
        views.setViewVisibility(id, View.VISIBLE)
    }

    private fun hideChronometer(views: RemoteViews, id: Int) {
        views.setChronometer(id, SystemClock.elapsedRealtime(), null, false)
        views.setViewVisibility(id, View.GONE)
    }
}

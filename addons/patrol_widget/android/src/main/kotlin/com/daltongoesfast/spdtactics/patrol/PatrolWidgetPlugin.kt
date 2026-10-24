package com.daltongoesfast.spdtactics.patrol

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot singleton "PatrolWidget". Absent on PC and web; the game checks Engine.has_singleton.
 * Logcat tag is PatrolWidget: `adb logcat -s PatrolWidget:I`.
 */
class PatrolWidgetPlugin(godot: Godot) : GodotPlugin(godot) {
    private var loopStarted = false
    /** True after PatrolBridge connects its signal and reads a cold-start tap. Resume must not clear the flag before that. */
    private var godotReady = false

    init {
        Log.i(TAG, "plugin constructed")
    }

    override fun getPluginName() = "PatrolWidget"

    @Deprecated("Godot 4.7 still calls this. @UsedByGodot is the other registration path.")
    override fun getPluginMethods(): MutableList<String> {
        // Names as well as @UsedByGodot, so a minify pass that drops the annotation still registers the calls.
        return mutableListOf(
            "consumeOpenTarget",
            "needsNotificationPermission",
            "requestNotificationPermission",
            "updateSnapshot",
            "markReady",
            "debugStatus",
        )
    }

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        val out = HashSet<SignalInfo>()
        out.add(SignalInfo("notification_permission", Integer::class.java))
        out.add(SignalInfo("open_guild"))
        return out
    }

    override fun onGodotMainLoopStarted() {
        loopStarted = true
        Log.i(TAG, "main loop started")
    }

    override fun onMainResume() {
        // A resume during startup runs before PatrolBridge._ready. Clearing pending_open here
        // drops the tap: the signal has no listener yet, and consumeOpenTarget then sees nothing.
        if (!loopStarted || !godotReady) {
            val ctx = hostContext()
            if (ctx != null && PatrolStore.peekOpen(ctx)) {
                Log.i(TAG, "resume left pending_open set (loop=$loopStarted bridge=$godotReady)")
            }
            return
        }
        deliverOpen()
    }

    /** PatrolBridge calls this after it connects open_guild and consumes a cold-start tap. */
    @UsedByGodot
    fun markReady() {
        godotReady = true
        Log.i(TAG, "godot bridge connected")
    }

    /** Called from the widget provider when a tap arrives while the game is already running. */
    fun deliverOpenFromOutside() {
        if (!godotReady) {
            Log.i(TAG, "open waiting for godot bridge")
            return
        }
        deliverOpen()
    }

    private fun deliverOpen() {
        val ctx = hostContext() ?: run {
            Log.w(TAG, "open pending but no context")
            return
        }
        if (!PatrolStore.takeOpen(ctx)) return
        Log.i(TAG, "emitting open_guild")
        emitSignal("open_guild")
    }

    /** Guild deep link, once. Cold start reads this because resume can fire before scripts connect. */
    @UsedByGodot
    fun consumeOpenTarget(): String {
        val ctx = hostContext() ?: run {
            Log.w(TAG, "consumeOpenTarget without a context")
            return ""
        }
        if (!PatrolStore.takeOpen(ctx)) return ""
        Log.i(TAG, "consumeOpenTarget guild")
        return "guild"
    }

    @UsedByGodot
    fun needsNotificationPermission(): Boolean {
        val ctx = hostContext() ?: return false
        return Build.VERSION.SDK_INT >= 33 && !PatrolNotify.allowed(ctx)
    }

    @UsedByGodot
    fun requestNotificationPermission() {
        val act = activity
        if (act == null) {
            Log.w(TAG, "notification permission request without an activity")
            emitSignal("notification_permission", 0)
            return
        }
        if (Build.VERSION.SDK_INT < 33 || PatrolNotify.allowed(act)) {
            emitSignal("notification_permission", 1)
            return
        }
        act.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (requestCode != REQ_NOTIF) return
        val ok = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        Log.i(TAG, "notification permission granted=$ok")
        emitSignal("notification_permission", if (ok) 1 else 0)
    }

    /** One line for the in-game Settings readout. Confirms the singleton, the stored snapshot, and placed widgets. */
    @UsedByGodot
    fun debugStatus(): String {
        val ctx = hostContext()
        if (ctx == null) return "plugin loaded, no Android context"
        val placed = PatrolWidgetProvider.placedCount(ctx)
        return "plugin loaded, ${PatrolStore.describe(ctx)}, widgets=$placed"
    }

    /**
     * Replace the stored snapshot, reschedule return alarms, and redraw every placed widget.
     * Uses the application context when the activity is not the caller (Godot invokes this off the UI thread,
     * and getActivity() is null until the host is attached).
     */
    @UsedByGodot
    fun updateSnapshot(json: String) {
        val ctx = hostContext()
        if (ctx == null) {
            Log.e(TAG, "updateSnapshot dropped, no context, ${json.length} chars")
            return
        }
        val work = Runnable {
            try {
                PatrolStore.saveSnapshot(ctx, json)
                PatrolAlarms.replace(ctx, json, fromBoot = false)
                val placed = PatrolWidgetProvider.refresh(ctx)
                Log.i(TAG, "snapshot written ${PatrolStore.describe(ctx)} widgets=$placed")
            } catch (t: Throwable) {
                Log.e(TAG, "snapshot write failed", t)
            }
        }
        val act = activity
        if (act != null) act.runOnUiThread(work) else Handler(Looper.getMainLooper()).post(work)
    }

    private fun hostContext(): Context? {
        val act = activity
        if (act != null) return act.applicationContext
        return try {
            context?.applicationContext
        } catch (t: Throwable) {
            Log.w(TAG, "no host context", t)
            null
        }
    }

    companion object {
        private const val TAG = "PatrolWidget"
        private const val REQ_NOTIF = 0x53504402
    }
}

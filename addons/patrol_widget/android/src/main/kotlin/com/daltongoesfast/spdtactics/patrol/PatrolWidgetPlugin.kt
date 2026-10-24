package com.daltongoesfast.spdtactics.patrol

import android.os.Build
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** Godot singleton "PatrolWidget". Absent on PC and web; the game checks Engine.has_singleton. */
class PatrolWidgetPlugin(godot: Godot) : GodotPlugin(godot) {
    private var loopStarted = false

    override fun getPluginName() = "PatrolWidget"

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        val out = HashSet<SignalInfo>()
        out.add(SignalInfo("notification_permission", Integer::class.java))
        out.add(SignalInfo("open_guild"))
        return out
    }

    override fun onGodotMainLoopStarted() {
        loopStarted = true
    }

    override fun onMainResume() {
        if (!loopStarted) return
        val ctx = activity ?: return
        if (!PatrolStore.peekOpen(ctx)) return
        PatrolStore.clearOpen(ctx)
        emitSignal("open_guild")
    }

    /** Guild deep link, once. Cold start reads this because the resume signal can fire before scripts connect. */
    @UsedByGodot
    fun consumeOpenTarget(): String {
        val ctx = activity ?: return ""
        if (!PatrolStore.peekOpen(ctx)) return ""
        PatrolStore.clearOpen(ctx)
        return "guild"
    }

    @UsedByGodot
    fun needsNotificationPermission(): Boolean {
        val ctx = activity ?: return false
        return Build.VERSION.SDK_INT >= 33 && !PatrolNotify.allowed(ctx)
    }

    @UsedByGodot
    fun requestNotificationPermission() {
        val act = activity
        if (act == null) {
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
        emitSignal("notification_permission", if (ok) 1 else 0)
    }

    /** Replace the stored snapshot, reschedule return alarms, and redraw every placed widget. */
    @UsedByGodot
    fun updateSnapshot(json: String) {
        val ctx = activity
        if (ctx == null) {
            Log.w(TAG, "updateSnapshot without an activity")
            return
        }
        ctx.runOnUiThread {
            PatrolStore.saveSnapshot(ctx, json)
            PatrolAlarms.replace(ctx, json, fromBoot = false)
            PatrolWidgetProvider.refresh(ctx)
        }
    }

    companion object {
        private const val TAG = "PatrolWidget"
        private const val REQ_NOTIF = 0x53504402
    }
}

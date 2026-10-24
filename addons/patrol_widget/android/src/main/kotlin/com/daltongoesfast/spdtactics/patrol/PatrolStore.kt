package com.daltongoesfast.spdtactics.patrol

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Snapshot written by the game. The widget and alarms only read this; they do not run patrol math. */
object PatrolStore {
    private val openLock = Any()
    const val PREFS = "spd_patrol"
    const val KEY_SNAPSHOT = "snapshot"
    const val KEY_ALARM_IDS = "alarm_ids"
    const val KEY_FIRED = "fired_ids"
    const val KEY_OPEN = "pending_open"
    const val EXTRA_OPEN = "spd_open"
    const val ACTION_RETURN = "com.daltongoesfast.spdtactics.patrol.RETURN"

    fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveSnapshot(ctx: Context, json: String) {
        prefs(ctx).edit().putString(KEY_SNAPSHOT, json).commit()
    }

    fun readSnapshot(ctx: Context): JSONObject? {
        val raw = prefs(ctx).getString(KEY_SNAPSHOT, "") ?: ""
        if (raw.isEmpty()) return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    fun peekOpen(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_OPEN, false)

    fun setOpen(ctx: Context) {
        prefs(ctx).edit().putBoolean(KEY_OPEN, true).commit()
    }

    /** Read and clear. One caller wins when resume and the tap receiver both see the flag. */
    fun takeOpen(ctx: Context): Boolean {
        synchronized(openLock) {
            val p = prefs(ctx)
            if (!p.getBoolean(KEY_OPEN, false)) return false
            p.edit().putBoolean(KEY_OPEN, false).commit()
            return true
        }
    }

    fun describe(ctx: Context): String {
        val raw = prefs(ctx).getString(KEY_SNAPSHOT, "") ?: ""
        val rows = PatrolJson.rows(readSnapshot(ctx))
        return "snapshot ${raw.length} chars, ${rows.size} patrols, open=${peekOpen(ctx)}"
    }

    fun alarmIds(ctx: Context): Set<String> {
        val raw = prefs(ctx).getStringSet(KEY_ALARM_IDS, emptySet()) ?: emptySet()
        return HashSet(raw)
    }

    fun putAlarmIds(ctx: Context, ids: Set<String>) {
        prefs(ctx).edit().putStringSet(KEY_ALARM_IDS, HashSet(ids)).commit()
    }

    fun firedIds(ctx: Context): MutableSet<String> {
        val raw = prefs(ctx).getStringSet(KEY_FIRED, emptySet()) ?: emptySet()
        return HashSet(raw)
    }

    fun putFiredIds(ctx: Context, ids: Set<String>) {
        prefs(ctx).edit().putStringSet(KEY_FIRED, HashSet(ids)).commit()
    }
}

data class PatrolRow(
    val id: String,
    val hero: String,
    val biome: String,
    val backAtSec: Long,
    val reward: String,
) {
    fun isDue(nowMs: Long = System.currentTimeMillis()): Boolean = backAtSec * 1000L <= nowMs + 500L
}

data class PatrolAlarm(
    val id: String,
    val atSec: Long,
    val notify: Boolean,
    val title: String,
    val body: String,
)

object PatrolJson {
    fun rows(snap: JSONObject?): List<PatrolRow> {
        if (snap == null) return emptyList()
        val arr = snap.optJSONArray("patrols") ?: return emptyList()
        val out = ArrayList<PatrolRow>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(
                PatrolRow(
                    id = o.optString("id", ""),
                    hero = o.optString("hero", "Hero"),
                    biome = o.optString("biome", ""),
                    backAtSec = longVal(o, "back_at"),
                    reward = o.optString("reward", ""),
                )
            )
        }
        return out
    }

    fun alarms(snap: JSONObject?): List<PatrolAlarm> {
        if (snap == null) return emptyList()
        val arr = snap.optJSONArray("alarms") ?: JSONArray()
        val out = ArrayList<PatrolAlarm>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id", "")
            if (id.isEmpty()) continue
            out.add(
                PatrolAlarm(
                    id = id,
                    atSec = longVal(o, "at"),
                    notify = boolVal(o, "notify"),
                    title = o.optString("title", "Patrol back!"),
                    body = o.optString("body", ""),
                )
            )
        }
        return out
    }

    private fun longVal(o: JSONObject, key: String): Long {
        val v = o.opt(key) ?: return 0L
        return when (v) {
            is Number -> v.toLong()
            else -> v.toString().toDoubleOrNull()?.toLong() ?: 0L
        }
    }

    private fun boolVal(o: JSONObject, key: String): Boolean {
        val v = o.opt(key) ?: return false
        return when (v) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            is String -> v == "true"
            else -> false
        }
    }
}

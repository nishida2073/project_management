package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object UploadLogStore {

    private const val PREFS_NAME = "smstokintone_log"
    private const val KEY_ENTRIES = "entries"
    private const val BODY_PREVIEW_LIMIT = 100
    private const val NO_SMS_ID = -1L

    enum class EntryType {
        RECEIVE,
        SEND_START,
        SEND_COMPLETE;

        companion object {
            fun fromName(name: String?): EntryType =
                entries.firstOrNull { it.name == name } ?: SEND_COMPLETE
        }
    }

    data class Entry(
        val type: EntryType,
        val loggedAtMillis: Long,
        val timestampMillis: Long,
        val sender: String,
        val bodyPreview: String,
        val success: Boolean,
        val message: String,
        val smsId: Long?
    )

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun add(
        context: Context,
        type: EntryType,
        timestampMillis: Long,
        sender: String,
        body: String,
        success: Boolean,
        message: String,
        smsId: Long? = null
    ) {
        val entries = getAll(context).toMutableList()
        entries.add(
            0,
            Entry(
                type = type,
                loggedAtMillis = System.currentTimeMillis(),
                timestampMillis = timestampMillis,
                sender = sender,
                bodyPreview = body.take(BODY_PREVIEW_LIMIT),
                success = success,
                message = message,
                smsId = smsId
            )
        )

        val array = JSONArray()
        entries.forEach { entry ->
            array.put(
                JSONObject()
                    .put("type", entry.type.name)
                    .put("loggedAt", entry.loggedAtMillis)
                    .put("ts", entry.timestampMillis)
                    .put("sender", entry.sender)
                    .put("body", entry.bodyPreview)
                    .put("success", entry.success)
                    .put("message", entry.message)
                    .put("smsId", entry.smsId ?: NO_SMS_ID)
            )
        }

        prefs(context).edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

    fun getAll(context: Context): List<Entry> {
        val json = prefs(context).getString(KEY_ENTRIES, null) ?: return emptyList()
        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val obj = array.getJSONObject(i)
            val smsId = obj.optLong("smsId", NO_SMS_ID)
            Entry(
                type = EntryType.fromName(obj.optString("type", "")),
                loggedAtMillis = obj.optLong("loggedAt", obj.getLong("ts")),
                timestampMillis = obj.getLong("ts"),
                sender = obj.optString("sender", ""),
                bodyPreview = obj.optString("body", ""),
                success = obj.optBoolean("success", false),
                message = obj.optString("message", ""),
                smsId = if (smsId == NO_SMS_ID) null else smsId
            )
        }
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ENTRIES).apply()
    }
}

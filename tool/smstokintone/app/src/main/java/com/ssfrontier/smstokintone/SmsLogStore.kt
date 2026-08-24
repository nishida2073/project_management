package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object SmsLogStore {

    private const val PREFS_NAME = "smstokintone_log"
    private const val KEY_ENTRIES = "entries"
    private const val BODY_PREVIEW_LIMIT = 100
    private const val NO_SMS_ID = -1L

    enum class EntryType {
        RECEIVE,
        SEND_START,
        SEND_COMPLETE,
        AUTO_REPLY;

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
        val smsId: Long?,
        val profileName: String?,
        val manual: Boolean,
        /** 本文から抽出した会社名・氏名・内容。抽出を試みていないエントリはnull */
        val smsParts: SmsParts? = null,
        /** kintoneへの登録時に会社名の変換（半角大文字・全角統一）を適用したかどうか */
        val companyNameConverted: Boolean = false
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
        smsId: Long? = null,
        profileName: String? = null,
        manual: Boolean = false,
        smsParts: SmsParts? = null,
        companyNameConverted: Boolean = false
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
                smsId = smsId,
                profileName = profileName,
                manual = manual,
                smsParts = smsParts,
                companyNameConverted = companyNameConverted
            )
        )

        val array = JSONArray()
        entries.forEach { entry ->
            val obj = JSONObject()
                .put("type", entry.type.name)
                .put("loggedAt", entry.loggedAtMillis)
                .put("ts", entry.timestampMillis)
                .put("sender", entry.sender)
                .put("body", entry.bodyPreview)
                .put("success", entry.success)
                .put("message", entry.message)
                .put("smsId", entry.smsId ?: NO_SMS_ID)
                .put("manual", entry.manual)
                .put("companyNameConverted", entry.companyNameConverted)
            entry.profileName?.let { obj.put("profileName", it) }
            entry.smsParts?.let {
                obj.put(
                    "smsParts",
                    JSONObject()
                        .put("companyName", it.companyName)
                        .put("userName", it.userName)
                        .put("content", it.content)
                )
            }
            array.put(obj)
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
                smsId = if (smsId == NO_SMS_ID) null else smsId,
                profileName = obj.optString("profileName", "").ifBlank { null },
                manual = obj.optBoolean("manual", false),
                companyNameConverted = obj.optBoolean("companyNameConverted", false),
                smsParts = obj.optJSONObject("smsParts")?.let {
                    SmsParts(
                        companyName = it.optString("companyName", ""),
                        userName = it.optString("userName", ""),
                        content = it.optString("content", "")
                    )
                }
            )
        }
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ENTRIES).apply()
    }
}

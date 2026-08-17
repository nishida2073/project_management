package com.ssfrontier.smstokintone

import android.util.Base64
import android.util.Log
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** kintoneへのレコード登録・更新リクエストを組み立てて送信する共通処理 */
object KintoneApi {

    private const val TAG = "KintoneApi"
    private const val ENTRY_SEPARATOR = "ーーーー"

    sealed class PostResult {
        data class Success(val message: String) : PostResult()
        data class Skipped(val message: String) : PostResult()
        data class HttpFailure(val code: Int, val detail: String) : PostResult()
        data class NetworkError(val message: String) : PostResult()
    }

    private data class ExistingRecord(val id: String, val bodyValue: String, val datetimeValue: String)

    /**
     * レコードを登録する。ただし送信元（[profile].fieldSender）が一致し、最終受信日時（[profile].fieldDatetime）
     * の差が[Prefs.KintoneProfile.updateWindowHours]時間以内の既存レコードが見つかった場合は、新規登録
     * ではなくそのレコードの本文に追記する形で更新する。本文には受信日時を先頭に付けて記録する。
     * 既存レコードの最終受信日時と完全に一致する場合（同一SMSの重複配信など）は何も送信せずスキップする。
     */
    fun postRecord(
        profile: Prefs.KintoneProfile,
        senderValue: String,
        bodyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        contentValue: String = ""
    ): PostResult {
        val entryText = buildEntryText(datetimeIsoValue, bodyValue)

        val existing = if (profile.fieldSender.isNotBlank() && profile.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            findExistingRecord(profile, senderValue, datetimeIsoValue)
        } else {
            null
        }

        val isSameMinute = existing != null && datetimeIsoValue != null &&
            isSameMinute(existing.datetimeValue, datetimeIsoValue)

        return if (isSameMinute) {
            PostResult.Skipped("最終受信日時と一致するため、スキップしました")
        } else if (existing != null) {
            val newEntryMillis = datetimeIsoValue?.let { parseIsoDateTime(it) }
            val mergedBody = mergeBody(existing.bodyValue, entryText, newEntryMillis)
            val existingMillis = parseIsoDateTime(existing.datetimeValue)
            val recordDatetimeIsoValue = if (existingMillis != null && newEntryMillis != null && existingMillis > newEntryMillis) {
                existing.datetimeValue
            } else {
                datetimeIsoValue
            }
            val record = buildRecord(profile, senderValue, mergedBody, recordDatetimeIsoValue, companyNameValue, userNameValue, contentValue)
            updateRecord(profile, existing.id, record)
        } else {
            val record = buildRecord(profile, senderValue, entryText, datetimeIsoValue, companyNameValue, userNameValue, contentValue)
            insertRecord(profile, record)
        }
    }

    /**
     * 既存の本文を[ENTRY_SEPARATOR]区切りのエントリに分解し、新しいエントリを受信日時順（古い順）の
     * 正しい位置に挿入する。新しいエントリの日時が不明、または既存エントリの日時が読み取れない場合は
     * 末尾に追加する
     */
    private fun mergeBody(existingBody: String, newEntryText: String, newEntryMillis: Long?): String {
        if (existingBody.isBlank()) return newEntryText

        val separator = "\n\n$ENTRY_SEPARATOR\n\n"
        if (newEntryMillis == null) return "$existingBody$separator$newEntryText"

        val displayFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
        val entries = existingBody.split(separator).toMutableList()
        val insertIndex = entries.indexOfFirst { entry ->
            val entryMillis = try {
                displayFormat.parse(entry.substringBefore("\n\n"))?.time
            } catch (e: ParseException) {
                null
            }
            entryMillis != null && entryMillis > newEntryMillis
        }

        if (insertIndex < 0) entries.add(newEntryText) else entries.add(insertIndex, newEntryText)
        return entries.joinToString(separator)
    }

    /** 受信日時（人が読める形式）と本文を、間に空行を挟んで組み立てる */
    private fun buildEntryText(datetimeIsoValue: String?, bodyValue: String): String {
        val displayDatetime = datetimeIsoValue?.let { formatDisplayDateTime(it) }
        return if (displayDatetime != null) "$displayDatetime\n\n$bodyValue" else bodyValue
    }

    private fun formatDisplayDateTime(datetimeIsoValue: String): String? {
        val baseMillis = parseIsoDateTime(datetimeIsoValue) ?: return null
        return SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN).format(Date(baseMillis))
    }

    private fun parseIsoDateTime(datetimeIsoValue: String): Long? {
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        return try {
            isoFormat.parse(datetimeIsoValue)?.time
        } catch (e: ParseException) {
            null
        }
    }

    /**
     * kintoneの日時フィールドは秒を保持せず分単位に切り捨てられるため、秒を無視して分単位が
     * 一致するかどうかで比較する
     */
    private fun isSameMinute(a: String, b: String): Boolean {
        val aMillis = parseIsoDateTime(a) ?: return false
        val bMillis = parseIsoDateTime(b) ?: return false
        return aMillis / 60_000L == bMillis / 60_000L
    }

    private fun buildRecord(
        profile: Prefs.KintoneProfile,
        senderValue: String,
        bodyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        contentValue: String = ""
    ): JSONObject {
        val record = JSONObject()
        if (profile.fieldSender.isNotBlank()) {
            record.put(profile.fieldSender, JSONObject().put("value", senderValue))
        }
        record.put(profile.fieldBody, JSONObject().put("value", bodyValue))
        if (profile.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            record.put(profile.fieldDatetime, JSONObject().put("value", datetimeIsoValue))
        }
        if (profile.fieldType.isNotBlank()) {
            record.put(profile.fieldType, JSONObject().put("value", Defaults.REGISTRATION_TYPE_VALUE))
        }
        // SMS本文からパースした会社名・氏名・内容。
        // フィールドコードが未設定（空文字）の場合はkintone側に送らない。
        if (profile.fieldCompanyName.isNotBlank() && companyNameValue.isNotBlank()) {
            record.put(profile.fieldCompanyName, JSONObject().put("value", companyNameValue))
        }
        if (profile.fieldUserName.isNotBlank() && userNameValue.isNotBlank()) {
            record.put(profile.fieldUserName, JSONObject().put("value", userNameValue))
        }
        if (profile.fieldContent.isNotBlank() && contentValue.isNotBlank()) {
            record.put(profile.fieldContent, JSONObject().put("value", contentValue))
        }
        return record
    }

    /**
     * 送信元が一致し、最終受信日時の差が[Prefs.KintoneProfile.updateWindowHours]時間以内の既存レコードを
     * 探す。複数件ヒットした場合は最終受信日時が最も新しいものを返す。見つからない・検索に失敗した場合は
     * null
     */
    private fun findExistingRecord(profile: Prefs.KintoneProfile, senderValue: String, datetimeIsoValue: String): ExistingRecord? {
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val baseMillis = parseIsoDateTime(datetimeIsoValue) ?: return null

        val windowMillis = profile.updateWindowHours.coerceAtLeast(0) * 3_600_000L
        val rangeStart = isoFormat.format(Date(baseMillis - windowMillis))
        val rangeEnd = isoFormat.format(Date(baseMillis + windowMillis))

        val typeCondition = if (profile.fieldType.isNotBlank()) {
            "${profile.fieldType} in (\"${escapeForQuery(Defaults.REGISTRATION_TYPE_VALUE)}\") and "
        } else {
            ""
        }
        val query = typeCondition +
            "${profile.fieldSender} = \"${escapeForQuery(senderValue)}\" and " +
            "${profile.fieldDatetime} >= \"$rangeStart\" and " +
            "${profile.fieldDatetime} <= \"$rangeEnd\" " +
            "order by ${profile.fieldDatetime} desc limit 1"

        val url = HttpUrl.Builder()
            .scheme("https")
            .host("${profile.subdomain}.cybozu.com")
            .addPathSegments("k/v1/records.json")
            .addQueryParameter("app", profile.appId)
            .addQueryParameter("query", query)
            .addQueryParameter("fields[0]", "\$id")
            .addQueryParameter("fields[1]", profile.fieldBody)
            .addQueryParameter("fields[2]", profile.fieldDatetime)
            .build()

        val requestBuilder = Request.Builder().url(url).get()
        addAuthHeader(requestBuilder, profile)

        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "既存レコードの検索に失敗しました: ${response.code} ${response.body?.string() ?: ""}")
                    return null
                }
                val records = JSONObject(response.body?.string() ?: "{}").optJSONArray("records")
                val first = records?.optJSONObject(0) ?: return null
                val id = first.getJSONObject("\$id").getString("value")
                val bodyValue = first.optJSONObject(profile.fieldBody)?.optString("value", "") ?: ""
                val datetimeValue = first.optJSONObject(profile.fieldDatetime)?.optString("value", "") ?: ""
                ExistingRecord(id, bodyValue, datetimeValue)
            }
        } catch (e: IOException) {
            Log.w(TAG, "既存レコードの検索で通信エラーが発生しました: ${e.message}")
            null
        }
    }

    private fun escapeForQuery(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    private fun insertRecord(profile: Prefs.KintoneProfile, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", profile.appId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${profile.subdomain}.cybozu.com/k/v1/record.json")
            .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, profile)

        return execute(requestBuilder, successMessage = "登録に成功しました")
    }

    private fun updateRecord(profile: Prefs.KintoneProfile, recordId: String, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", profile.appId)
            .put("id", recordId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${profile.subdomain}.cybozu.com/k/v1/record.json")
            .put(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, profile)

        return execute(requestBuilder, successMessage = "更新に成功しました")
    }

    private fun addAuthHeader(requestBuilder: Request.Builder, profile: Prefs.KintoneProfile) {
        when (profile.authMethod) {
            Prefs.AuthMethod.API_TOKEN ->
                requestBuilder.addHeader("X-Cybozu-API-Token", profile.apiToken)
            Prefs.AuthMethod.PASSWORD -> {
                val credentials = "${profile.loginName}:${profile.loginPassword}"
                val encoded = Base64.encodeToString(
                    credentials.toByteArray(Charsets.UTF_8),
                    Base64.NO_WRAP
                )
                requestBuilder.addHeader("X-Cybozu-Authorization", encoded)
            }
        }
    }

    private fun execute(requestBuilder: Request.Builder, successMessage: String): PostResult {
        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (response.isSuccessful) {
                    PostResult.Success(successMessage)
                } else {
                    PostResult.HttpFailure(response.code, response.body?.string() ?: "")
                }
            }
        } catch (e: IOException) {
            PostResult.NetworkError(e.message ?: "")
        }
    }
}

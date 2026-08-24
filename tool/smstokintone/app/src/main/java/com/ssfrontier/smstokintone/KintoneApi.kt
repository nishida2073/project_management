package com.ssfrontier.smstokintone

import android.content.Context
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

    private sealed class ExistingRecordResult {
        data class Found(val record: ExistingRecord) : ExistingRecordResult()
        object NotFound : ExistingRecordResult()
        data class SearchFailed(val result: PostResult) : ExistingRecordResult()
    }

    /**
     * レコードを登録する。ただし送信元（[sendTarget].fieldSender）が一致し、最終受信日時（[sendTarget].fieldDatetime）
     * の差が[SettingsStore.SendTarget.updateToleranceHours]時間以内の既存レコードが見つかった場合は、新規登録
     * ではなくそのレコードの本文に追記する形で更新する。本文には受信日時を先頭に付けて記録する。
     * 既存レコードの最終受信日時と分単位で一致し（kintoneは秒を保持しないため）、かつ既存レコードの
     * 本文に今回の本文が既に含まれている場合（同一SMSの重複配信など）は何も送信せずスキップする。
     */
    fun postRecord(
        context: Context,
        sendTarget: SettingsStore.SendTarget,
        senderValue: String,
        bodyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        contentValue: String = ""
    ): PostResult {
        val entryText = buildEntryText(datetimeIsoValue, bodyValue)

        val existingResult = if (sendTarget.fieldSender.isNotBlank() && sendTarget.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            findExistingRecord(sendTarget, senderValue, datetimeIsoValue)
        } else {
            ExistingRecordResult.NotFound
        }

        val existing = when (existingResult) {
            is ExistingRecordResult.Found -> existingResult.record
            ExistingRecordResult.NotFound -> null
            // 検索自体が失敗した場合、既存レコードなしとみなして新規登録に進むと、本来更新すべき
            // レコードを見落として重複登録してしまう恐れがあるため、ここで送信失敗として打ち切る
            is ExistingRecordResult.SearchFailed -> return existingResult.result
        }

        val isDuplicate = existing != null && datetimeIsoValue != null &&
            isSameMinute(existing.datetimeValue, datetimeIsoValue) &&
            existing.bodyValue.contains(bodyValue)

        return if (isDuplicate) {
            PostResult.Skipped(context.getString(R.string.message_log_send_complete_skipped_duplicate))
        } else if (existing != null) {
            val newEntryMillis = datetimeIsoValue?.let { parseIsoDateTime(it) }
            val mergedBody = mergeBody(existing.bodyValue, entryText, newEntryMillis)
            val existingMillis = parseIsoDateTime(existing.datetimeValue)
            val recordDatetimeIsoValue = if (existingMillis != null && newEntryMillis != null && existingMillis > newEntryMillis) {
                existing.datetimeValue
            } else {
                datetimeIsoValue
            }
            val record = buildRecord(sendTarget, senderValue, mergedBody, recordDatetimeIsoValue, companyNameValue, userNameValue, contentValue)
            updateRecord(context, sendTarget, existing.id, record)
        } else {
            val record = buildRecord(sendTarget, senderValue, entryText, datetimeIsoValue, companyNameValue, userNameValue, contentValue)
            insertRecord(context, sendTarget, record)
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
        sendTarget: SettingsStore.SendTarget,
        senderValue: String,
        bodyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        contentValue: String = ""
    ): JSONObject {
        val record = JSONObject()
        if (sendTarget.fieldSender.isNotBlank()) {
            record.put(sendTarget.fieldSender, JSONObject().put("value", senderValue))
        }
        record.put(sendTarget.fieldBody, JSONObject().put("value", bodyValue))
        if (sendTarget.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            record.put(sendTarget.fieldDatetime, JSONObject().put("value", datetimeIsoValue))
        }
        if (sendTarget.fieldType.isNotBlank()) {
            record.put(sendTarget.fieldType, JSONObject().put("value", AppConstants.REGISTRATION_TYPE_VALUE))
        }
        // SMS本文からパースした会社名・氏名・内容。
        // フィールドコードが未設定（空文字）、または抽出できた値が空の場合はkintone側に送らない。
        if (sendTarget.fieldCompanyName.isNotBlank() && companyNameValue.isNotBlank()) {
            record.put(sendTarget.fieldCompanyName, JSONObject().put("value", companyNameValue))
        }
        if (sendTarget.fieldUserName.isNotBlank() && userNameValue.isNotBlank()) {
            record.put(sendTarget.fieldUserName, JSONObject().put("value", userNameValue))
        }
        if (sendTarget.fieldContent.isNotBlank() && contentValue.isNotBlank()) {
            record.put(sendTarget.fieldContent, JSONObject().put("value", contentValue))
        }
        return record
    }

    /**
     * 送信元が一致し、最終受信日時の差が[SettingsStore.SendTarget.updateToleranceHours]時間以内の既存レコードを
     * 探す。複数件ヒットした場合は最終受信日時が最も新しいものを返す。見つからない場合は[ExistingRecordResult.NotFound]、
     * 検索自体が失敗した場合は[ExistingRecordResult.SearchFailed]を返す（新規登録との誤判定を防ぐため、
     * 検索失敗と未検出を区別する）
     */
    private fun findExistingRecord(sendTarget: SettingsStore.SendTarget, senderValue: String, datetimeIsoValue: String): ExistingRecordResult {
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val baseMillis = parseIsoDateTime(datetimeIsoValue) ?: return ExistingRecordResult.NotFound

        val toleranceMillis = sendTarget.updateToleranceHours.coerceAtLeast(0) * 3_600_000L
        val rangeStart = isoFormat.format(Date(baseMillis - toleranceMillis))
        val rangeEnd = isoFormat.format(Date(baseMillis + toleranceMillis))

        val typeCondition = if (sendTarget.fieldType.isNotBlank()) {
            "${sendTarget.fieldType} in (\"${escapeForQuery(AppConstants.REGISTRATION_TYPE_VALUE)}\") and "
        } else {
            ""
        }
        val query = typeCondition +
            "${sendTarget.fieldSender} = \"${escapeForQuery(senderValue)}\" and " +
            "${sendTarget.fieldDatetime} >= \"$rangeStart\" and " +
            "${sendTarget.fieldDatetime} <= \"$rangeEnd\" " +
            "order by ${sendTarget.fieldDatetime} desc limit 1"

        val url = HttpUrl.Builder()
            .scheme("https")
            .host("${sendTarget.subdomain}.cybozu.com")
            .addPathSegments("k/v1/records.json")
            .addQueryParameter("app", sendTarget.appId)
            .addQueryParameter("query", query)
            .addQueryParameter("fields[0]", "\$id")
            .addQueryParameter("fields[1]", sendTarget.fieldBody)
            .addQueryParameter("fields[2]", sendTarget.fieldDatetime)
            .build()

        val requestBuilder = Request.Builder().url(url).get()
        addAuthHeader(requestBuilder, sendTarget)

        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    val detail = response.body?.string() ?: ""
                    Log.w(TAG, "既存レコードの検索に失敗しました: ${response.code} $detail")
                    return ExistingRecordResult.SearchFailed(PostResult.HttpFailure(response.code, detail))
                }
                val records = JSONObject(response.body?.string() ?: "{}").optJSONArray("records")
                val first = records?.optJSONObject(0) ?: return ExistingRecordResult.NotFound
                val id = first.getJSONObject("\$id").getString("value")
                val bodyValue = first.optJSONObject(sendTarget.fieldBody)?.optString("value", "") ?: ""
                val datetimeValue = first.optJSONObject(sendTarget.fieldDatetime)?.optString("value", "") ?: ""
                ExistingRecordResult.Found(ExistingRecord(id, bodyValue, datetimeValue))
            }
        } catch (e: IOException) {
            Log.w(TAG, "既存レコードの検索で通信エラーが発生しました: ${e.message}")
            ExistingRecordResult.SearchFailed(PostResult.NetworkError(e.message ?: ""))
        }
    }

    private fun escapeForQuery(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    private fun insertRecord(context: Context, sendTarget: SettingsStore.SendTarget, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", sendTarget.appId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${sendTarget.subdomain}.cybozu.com/k/v1/record.json")
            .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, sendTarget)

        return execute(requestBuilder, successMessage = context.getString(R.string.message_log_send_complete_create_success))
    }

    private fun updateRecord(context: Context, sendTarget: SettingsStore.SendTarget, recordId: String, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", sendTarget.appId)
            .put("id", recordId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${sendTarget.subdomain}.cybozu.com/k/v1/record.json")
            .put(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, sendTarget)

        return execute(requestBuilder, successMessage = context.getString(R.string.message_log_send_complete_update_success))
    }

    private fun addAuthHeader(requestBuilder: Request.Builder, sendTarget: SettingsStore.SendTarget) {
        when (sendTarget.authMethod) {
            SettingsStore.AuthMethod.API_TOKEN ->
                requestBuilder.addHeader("X-Cybozu-API-Token", sendTarget.apiToken)
            SettingsStore.AuthMethod.PASSWORD -> {
                val credentials = "${sendTarget.loginName}:${sendTarget.loginPassword}"
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

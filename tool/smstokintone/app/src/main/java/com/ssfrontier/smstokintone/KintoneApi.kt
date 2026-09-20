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
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Kintone レコード API（登録・更新・検索）を呼び出す。
 * SMS内容をレコードとして登録、または既存レコードの履歴に追記。
 */
object KintoneApi {

    /** [Log] 出力用のタグ。 */
    private const val TAG = "KintoneApi"
    /** [mergeBody] で複数エントリを区切る文字列。 */
    private const val ENTRY_SEPARATOR = "------------------------------"

    /**
     * [postRecord] の結果。呼び出し側は 成功/スキップ/失敗を区別して
     * ログ・通知文言を出し分ける。
     */
    sealed class PostResult {
        /** 新規登録または更新が成功。 */
        data class Success(val message: String) : PostResult()
        /** 重複判定されスキップ。 */
        data class Skipped(val message: String) : PostResult()
        /** Kintone サーバー側エラー。[code] は HTTP ステータス、[detail] はエラー詳細。 */
        data class HttpFailure(val code: Int, val detail: String) : PostResult() {
            /** 5xx またはレート制限（429）はリトライ可能な一時的エラーとみなす。 */
            val isRetryable: Boolean
                get() = code in 500..599 || code == 429
        }
        /** 通信例外で失敗（ネットワークエラー）。 */
        data class NetworkError(val message: String) : PostResult()
    }

    /**
     * [findExistingRecord] でヒットした既存レコード。
     * Kintone 上の $id、履歴フィールド、最終受信日時を保持。
     */
    private data class ExistingRecord(
        /** Kintone レコード ID（$id フィールド）。 */
        val id: String,
        /** 履歴フィールド（複数エントリを区切り文字で保持）。 */
        val historyValue: String,
        /** 最終受信日時（ISO 8601 形式）。 */
        val datetimeValue: String
    )

    /**
     * [findExistingRecord] の結果バリアント。
     * 検索失敗 [SearchFailed] を未検出 [NotFound] と区別することで、
     * エラーを新規登録扱いにして重複登録を防止。
     */
    private sealed class ExistingRecordResult {
        /** 既存レコード見つかった。 */
        data class Found(val record: ExistingRecord) : ExistingRecordResult()
        /** 条件に一致するレコードなし。 */
        object NotFound : ExistingRecordResult()
        /** 検索時エラー（リトライする）。 */
        data class SearchFailed(val result: PostResult) : ExistingRecordResult()
    }

    /**
     * レコードを登録する。ただし送信元（[sendTarget].fieldSender）が一致し、最終受信日時（[sendTarget].fieldDatetime）
     * が[SettingsStore.SendTarget.updateToleranceMode]の条件（同一暦日、または[SettingsStore.SendTarget.updateToleranceHours]
     * 時間以内）に収まる既存レコードが見つかった場合は、新規登録ではなくそのレコードの履歴に追記する形で更新する
     * （詳細は[findExistingRecord]参照）。履歴には受信日時を先頭に付けて記録する。
     * 既存レコードの最終受信日時と分単位で一致し（kintoneは秒を保持しないため）、かつ既存レコードの
     * 履歴に今回の[historyValue]が既に含まれている場合（同一SMSの重複配信など）は何も送信せずスキップする。
     * 更新時、[bodyValue]は今回のSMSの受信日時が既存レコードの最終受信日時より新しい場合のみ上書きする。
     * 古いSMS（過去に届いたが遅れて処理された等）を送信して統合された場合に、既にこのフィールドへ反映済みの
     * 新しい本文が古い本文で巻き戻らないようにするため。会社名・氏名は同一送信元であれば変化しない前提のため、
     * 日時に関わらず常に上書きする
     */
    fun postRecord(
        context: Context,
        sendTarget: SettingsStore.SendTarget,
        senderValue: String,
        historyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        bodyValue: String = ""
    ): PostResult {
        val entryText = buildEntryText(datetimeIsoValue, historyValue)

        val existingResult = if (sendTarget.fieldSender.isNotBlank() && sendTarget.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            findExistingRecord(sendTarget, senderValue, datetimeIsoValue)
        } else {
            ExistingRecordResult.NotFound
        }

        val existing = when (existingResult) {
            is ExistingRecordResult.Found -> existingResult.record
            ExistingRecordResult.NotFound -> null
            // 検索失敗をNotFound扱いにすると、更新対象レコードを見落として重複登録する恐れがあるため打ち切る。
            is ExistingRecordResult.SearchFailed -> return existingResult.result
        }

        val isDuplicate = existing != null && datetimeIsoValue != null &&
            isSameMinute(existing.datetimeValue, datetimeIsoValue) &&
            existing.historyValue.contains(historyValue)

        return if (isDuplicate) {
            PostResult.Skipped(context.getString(R.string.message_log_send_complete_skipped_duplicate))
        } else if (existing != null) {
            val newEntryMillis = datetimeIsoValue?.let { parseIsoDateTime(it) }
            val mergedHistory = mergeBody(existing.historyValue, entryText, newEntryMillis)
            val existingMillis = parseIsoDateTime(existing.datetimeValue)
            val recordDatetimeIsoValue = if (existingMillis != null && newEntryMillis != null && existingMillis > newEntryMillis) {
                existing.datetimeValue
            } else {
                datetimeIsoValue
            }
            // newEntryMillis は [findExistingRecord] でパース済み。失敗していれば
            // [NotFound] となるため、ここで null になるのは既存レコード側の日時が空/未解析の場合のみ。
            // その場合は比較不可なため、従来通り上書きする。
            val isNewEntryNewer = existingMillis == null || newEntryMillis == null || newEntryMillis > existingMillis
            val record = buildRecord(
                sendTarget,
                senderValue,
                mergedHistory,
                recordDatetimeIsoValue,
                companyNameValue = companyNameValue,
                userNameValue = userNameValue,
                bodyValue = if (isNewEntryNewer) bodyValue else ""
            )
            updateRecord(context, sendTarget, existing.id, record)
        } else {
            val record = buildRecord(sendTarget, senderValue, entryText, datetimeIsoValue, companyNameValue, userNameValue, bodyValue)
            insertRecord(context, sendTarget, record)
        }
    }

    /**
     * 既存の履歴に新しいエントリを受信日時の古い順で挿入。
     * 日時解析に失敗した場合は末尾に追加。
     *
     * @param existingHistory 既存の履歴テキスト（[ENTRY_SEPARATOR] で区切られた複数エントリ）
     * @param newEntryText 新しいエントリテキスト
     * @param newEntryMillis 新エントリの受信日時（ミリ秒）。null の場合は末尾追加
     * @return マージされた履歴テキスト
     */
    private fun mergeBody(existingHistory: String, newEntryText: String, newEntryMillis: Long?): String {
        if (existingHistory.isBlank()) return newEntryText

        val separator = "\n\n$ENTRY_SEPARATOR\n\n"
        if (newEntryMillis == null) return "$existingHistory$separator$newEntryText"

        val entries = existingHistory.split(separator).toMutableList()
        val insertIndex = entries.indexOfFirst { entry ->
            val entryMillis = try {
                DateFormats.display().parse(entry.substringBefore("\n\n"))?.time
            } catch (e: ParseException) {
                null
            }
            entryMillis != null && entryMillis > newEntryMillis
        }

        if (insertIndex < 0) entries.add(newEntryText) else entries.add(insertIndex, newEntryText)
        return entries.joinToString(separator)
    }

    /**
     * Kintone 履歴フィールド用の 1 エントリテキストを組み立て。
     * 表示形式の受信日時と本文を改行で区切って連結。
     *
     * @param datetimeIsoValue ISO 8601 形式の受信日時（null 時は日時なしで返す）
     * @param historyEntryBody エントリ本文
     * @return 日時 + "\n\n" + 本文（または本文のみ）
     */
    private fun buildEntryText(datetimeIsoValue: String?, historyEntryBody: String): String {
        val displayDatetime = datetimeIsoValue?.let { formatDisplayDateTime(it) }
        return if (displayDatetime != null) "$displayDatetime\n\n$historyEntryBody" else historyEntryBody
    }

    /**
     * ISO 8601 形式（UTC）の日時を表示用文字列に変換。
     * パース失敗時は null を返す。
     *
     * @param datetimeIsoValue ISO 8601 形式の日時文字列
     * @return 表示形式の日時（失敗時は null）
     */
    private fun formatDisplayDateTime(datetimeIsoValue: String): String? {
        val baseMillis = parseIsoDateTime(datetimeIsoValue) ?: return null
        return DateFormats.display().format(Date(baseMillis))
    }

    /**
     * Kintone 日時フィールド用 ISO 8601（UTC）フォーマッタ。
     * 書き込み・読み取り・検索範囲組み立てで必ずこれを使用。
     * フォーマットズレは既存レコード判定を破壊するため共有必須。
     *
     * @return ISO 8601（UTC）フォーマッタ
     */
    private fun isoDateTimeFormat(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    /**
     * ミリ秒を Kintone 日時フィールド用 ISO 8601（UTC）文字列に変換。
     *
     * @param millis ミリ秒タイムスタンプ
     * @return ISO 8601 形式の日時文字列
     */
    fun formatIsoDateTime(millis: Long): String = isoDateTimeFormat().format(Date(millis))

    /** ISO8601（UTC）の[datetimeIsoValue]をエポックミリ秒に変換する。パースできなければnull */
    private fun parseIsoDateTime(datetimeIsoValue: String): Long? {
        return try {
            isoDateTimeFormat().parse(datetimeIsoValue)?.time
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

    /**
     * kintoneのレコード登録/更新用JSONを組み立てる。[sendTarget]でフィールドコードが未設定（空文字）の項目、
     * および会社名・氏名・本文は値が空の場合はキー自体を含めない（kintone側にフィールドが存在しない場合の
     * エラーを避けるため）
     */
    private fun buildRecord(
        sendTarget: SettingsStore.SendTarget,
        senderValue: String,
        historyValue: String,
        datetimeIsoValue: String?,
        companyNameValue: String = "",
        userNameValue: String = "",
        bodyValue: String = ""
    ): JSONObject {
        val record = JSONObject()
        if (sendTarget.fieldSender.isNotBlank()) {
            record.put(sendTarget.fieldSender, JSONObject().put("value", senderValue))
        }
        record.put(sendTarget.fieldHistory, JSONObject().put("value", historyValue))
        if (sendTarget.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            record.put(sendTarget.fieldDatetime, JSONObject().put("value", datetimeIsoValue))
        }
        if (sendTarget.fieldType.isNotBlank()) {
            record.put(sendTarget.fieldType, JSONObject().put("value", AppConstants.REGISTRATION_TYPE_VALUE))
        }
        if (sendTarget.fieldCompanyName.isNotBlank() && companyNameValue.isNotBlank()) {
            record.put(sendTarget.fieldCompanyName, JSONObject().put("value", companyNameValue))
        }
        if (sendTarget.fieldUserName.isNotBlank() && userNameValue.isNotBlank()) {
            record.put(sendTarget.fieldUserName, JSONObject().put("value", userNameValue))
        }
        if (sendTarget.fieldBody.isNotBlank() && bodyValue.isNotBlank()) {
            record.put(sendTarget.fieldBody, JSONObject().put("value", bodyValue))
        }
        return record
    }

    /**
     * 送信元が一致し、最終受信日時が[SettingsStore.SendTarget.updateToleranceMode]の条件（同一暦日、
     * または[SettingsStore.SendTarget.updateToleranceHours]時間以内）に収まる既存レコードを探す。
     * 複数件ヒットした場合は最終受信日時が最も新しいものを返す。新規登録との誤判定を防ぐため、
     * 未検出（[ExistingRecordResult.NotFound]）と検索失敗（[ExistingRecordResult.SearchFailed]）は区別する
     */
    private fun findExistingRecord(sendTarget: SettingsStore.SendTarget, senderValue: String, datetimeIsoValue: String): ExistingRecordResult {
        val baseMillis = parseIsoDateTime(datetimeIsoValue) ?: return ExistingRecordResult.NotFound

        val rangeStartMillis: Long
        val rangeEndMillis: Long
        when (sendTarget.updateToleranceMode) {
            SettingsStore.UpdateToleranceMode.SAME_DATE -> {
                rangeStartMillis = startOfDayMillis(baseMillis)
                rangeEndMillis = endOfDayMillis(baseMillis)
            }
            SettingsStore.UpdateToleranceMode.HOURS -> {
                val toleranceMillis = sendTarget.updateToleranceHours.coerceAtLeast(0) * 3_600_000L
                rangeStartMillis = baseMillis - toleranceMillis
                rangeEndMillis = baseMillis + toleranceMillis
            }
        }
        val rangeStart = formatIsoDateTime(rangeStartMillis)
        val rangeEnd = formatIsoDateTime(rangeEndMillis)

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
            .addQueryParameter("fields[1]", sendTarget.fieldHistory)
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
                val historyValue = first.optJSONObject(sendTarget.fieldHistory)?.optString("value", "") ?: ""
                val datetimeValue = first.optJSONObject(sendTarget.fieldDatetime)?.optString("value", "") ?: ""
                ExistingRecordResult.Found(ExistingRecord(id, historyValue, datetimeValue))
            }
        } catch (e: IOException) {
            Log.w(TAG, "既存レコードの検索で通信エラーが発生しました: ${e.message}")
            ExistingRecordResult.SearchFailed(PostResult.NetworkError(e.message ?: ""))
        } catch (e: Exception) {
            Log.w(TAG, "既存レコードの検索でJSON解析エラーが発生しました: ${e.message}")
            ExistingRecordResult.SearchFailed(PostResult.HttpFailure(500, "JSON解析エラー: ${e.message}"))
        }
    }

    /** [millis]が属する暦日（端末のデフォルトタイムゾーン）の開始時刻（00:00:00.000）のエポックミリ秒 */
    private fun startOfDayMillis(millis: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    /** [millis]が属する暦日（端末のデフォルトタイムゾーン）の終了時刻（23:59:59.999）のエポックミリ秒 */
    private fun endOfDayMillis(millis: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 23)
            set(Calendar.MINUTE, 59)
            set(Calendar.SECOND, 59)
            set(Calendar.MILLISECOND, 999)
        }.timeInMillis

    /** kintoneのクエリ言語で文字列リテラルとして安全に埋め込めるよう、バックスラッシュとダブルクォートをエスケープする */
    private fun escapeForQuery(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    /** レコードを新規登録する（POST /k/v1/record.json） */
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

    /** 既存レコードを更新する（PUT /k/v1/record.json） */
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

    /**
     * kintoneの認証ヘッダーを付与する。「ログイン名:パスワード」をBase64化した`X-Cybozu-Authorization`を
     * kintone固有のヘッダー名・形式で設定する
     */
    private fun addAuthHeader(requestBuilder: Request.Builder, sendTarget: SettingsStore.SendTarget) {
        val credentials = "${sendTarget.loginName}:${sendTarget.loginPassword}"
        val encoded = Base64.encodeToString(
            credentials.toByteArray(Charsets.UTF_8),
            Base64.NO_WRAP
        )
        requestBuilder.addHeader("X-Cybozu-Authorization", encoded)
    }

    /** [requestBuilder]のリクエストを実行し、成否とレスポンス/例外を[PostResult]に変換する */
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

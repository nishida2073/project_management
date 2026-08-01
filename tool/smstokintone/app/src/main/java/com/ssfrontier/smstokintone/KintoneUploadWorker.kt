package com.ssfrontier.smstokintone

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class KintoneUploadWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val config = Prefs.load(applicationContext)
        val sender = inputData.getString(KEY_SENDER) ?: ""
        val body = inputData.getString(KEY_BODY) ?: ""
        val timestampMillis = inputData.getLong(KEY_TIMESTAMP, System.currentTimeMillis())
        val manual = inputData.getBoolean(KEY_MANUAL, false)
        val smsId = inputData.getLong(KEY_SMS_ID, -1L).let { if (it == -1L) null else it }

        if (!manual && !config.forwardingEnabled) {
            logComplete(config, sender, body, timestampMillis, smsId, success = false, message = "kintoneへの転送が無効になっています")
            return@withContext Result.success()
        }
        if (!config.isValid) {
            logComplete(config, sender, body, timestampMillis, smsId, success = false, message = "kintoneの接続設定が未完了です")
            return@withContext Result.failure()
        }

        logStart(config, sender, body, timestampMillis, smsId)

        val record = JSONObject()
        if (config.fieldPhone.isNotBlank()) {
            record.put(config.fieldPhone, JSONObject().put("value", sender))
        }
        record.put(config.fieldBody, JSONObject().put("value", body))
        if (config.fieldDatetime.isNotBlank()) {
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            record.put(
                config.fieldDatetime,
                JSONObject().put("value", isoFormat.format(Date(timestampMillis)))
            )
        }

        val payload = JSONObject()
            .put("app", config.appId)
            .put("record", record)

        val requestBody = payload.toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())

        val requestBuilder = Request.Builder()
            .url("https://${config.subdomain}.cybozu.com/k/v1/record.json")
            .post(requestBody)

        when (config.authMethod) {
            Prefs.AuthMethod.API_TOKEN ->
                requestBuilder.addHeader("X-Cybozu-API-Token", config.apiToken)
            Prefs.AuthMethod.PASSWORD -> {
                val credentials = "${config.loginName}:${config.loginPassword}"
                val encoded = Base64.encodeToString(
                    credentials.toByteArray(Charsets.UTF_8),
                    Base64.NO_WRAP
                )
                requestBuilder.addHeader("X-Cybozu-Authorization", encoded)
            }
        }

        val request = requestBuilder.build()

        try {
            OkHttpClient().newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    logComplete(config, sender, body, timestampMillis, smsId, success = true, message = "登録成功")
                    Result.success()
                } else {
                    val detail = "${response.code} ${response.body?.string()}"
                    Log.e(TAG, "kintoneへの登録に失敗しました: $detail")
                    logComplete(config, sender, body, timestampMillis, smsId, success = false, message = "送信失敗: $detail")
                    if (response.code in 500..599) Result.retry() else Result.failure()
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "kintoneへの通信でエラーが発生しました", e)
            logComplete(config, sender, body, timestampMillis, smsId, success = false, message = "通信エラー: ${e.message}")
            Result.retry()
        }
    }

    private fun logStart(
        config: Prefs.Config,
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?
    ) {
        if (!config.logEnabled) return
        UploadLogStore.add(
            applicationContext,
            type = UploadLogStore.EntryType.SEND_START,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = true,
            message = "kintoneへの送信を開始しました",
            smsId = smsId
        )
    }

    private fun logComplete(
        config: Prefs.Config,
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        success: Boolean,
        message: String
    ) {
        if (!config.logEnabled) return
        UploadLogStore.add(
            applicationContext,
            type = UploadLogStore.EntryType.SEND_COMPLETE,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = success,
            message = message,
            smsId = smsId
        )
    }

    companion object {
        private const val TAG = "KintoneUploadWorker"
        const val KEY_SENDER = "sender"
        const val KEY_BODY = "body"
        const val KEY_TIMESTAMP = "timestamp"
        const val KEY_MANUAL = "manual"
        const val KEY_SMS_ID = "sms_id"
    }
}

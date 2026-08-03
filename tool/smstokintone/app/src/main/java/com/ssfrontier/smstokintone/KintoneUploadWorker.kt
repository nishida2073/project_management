package com.ssfrontier.smstokintone

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
        // 手動送信時のみ、検索画面で特定済みの確実なSMSプロバイダ上のIDが渡ってくる。
        // 自動受信時はここでは解決せず、「受信済みSMS送信」画面側で送信元・タイムスタンプの
        // 近さによって突き合わせる（SmsMatching参照）。
        val smsId = inputData.getLong(KEY_SMS_ID, -1L).let { if (it == -1L) null else it }

        if (!manual && !config.forwardingEnabled) {
            logComplete(sender, body, timestampMillis, smsId, success = false, message = "kintoneへの自動送信が無効になっています", profileName = null, manual = manual)
            return@withContext Result.success()
        }

        val profile = Prefs.findProfileForBody(applicationContext, body)
        logStart(sender, body, timestampMillis, smsId, profileName = profile?.displayName, manual = manual)

        if (profile == null || !profile.isValid) {
            logComplete(sender, body, timestampMillis, smsId, success = false, message = "本文に一致するkintoneの接続設定が見つからないか未完了です", profileName = profile?.displayName, manual = manual)
            // Result.failure()にすると、複数件をまとめて送信した際に後続のチェーンされた
            // ワーカーが実行されずキャンセルされてしまうため、成否はログのみで管理する
            return@withContext Result.success()
        }

        val datetimeIso = if (profile.fieldDatetime.isNotBlank()) {
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            isoFormat.format(Date(timestampMillis))
        } else {
            null
        }

        when (val result = KintoneApi.postRecord(profile, senderValue = sender, bodyValue = body, datetimeIsoValue = datetimeIso)) {
            is KintoneApi.PostResult.Success -> {
                logComplete(sender, body, timestampMillis, smsId, success = true, message = result.message, profileName = profile.displayName, manual = manual)
                Result.success()
            }
            is KintoneApi.PostResult.HttpFailure -> {
                val detail = "${result.code} ${result.detail}"
                Log.e(TAG, "kintoneへの登録に失敗しました: $detail")
                logComplete(sender, body, timestampMillis, smsId, success = false, message = "送信失敗: $detail", profileName = profile.displayName, manual = manual)
                if (result.code in 500..599) Result.retry() else Result.success()
            }
            is KintoneApi.PostResult.NetworkError -> {
                Log.e(TAG, "kintoneへの通信でエラーが発生しました: ${result.message}")
                logComplete(sender, body, timestampMillis, smsId, success = false, message = "通信エラー: ${result.message}", profileName = profile.displayName, manual = manual)
                Result.retry()
            }
        }
    }

    private fun logStart(
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        profileName: String?,
        manual: Boolean
    ) {
        UploadLogStore.add(
            applicationContext,
            type = UploadLogStore.EntryType.SEND_START,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = true,
            message = "kintoneへの送信を開始しました",
            smsId = smsId,
            profileName = profileName,
            manual = manual
        )
    }

    private fun logComplete(
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        success: Boolean,
        message: String,
        profileName: String?,
        manual: Boolean
    ) {
        UploadLogStore.add(
            applicationContext,
            type = UploadLogStore.EntryType.SEND_COMPLETE,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = success,
            message = message,
            smsId = smsId,
            profileName = profileName,
            manual = manual
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

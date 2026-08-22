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
        val config = SettingsStore.load(applicationContext)
        val sender = inputData.getString(KEY_SENDER) ?: ""
        val body = inputData.getString(KEY_BODY) ?: ""
        val timestampMillis = inputData.getLong(KEY_TIMESTAMP, System.currentTimeMillis())
        val manual = inputData.getBoolean(KEY_MANUAL, false)
        // 手動送信時のみ、検索画面で特定済みの確実なSMSプロバイダ上のIDが渡ってくる。
        // 自動受信時はここでは解決せず、「受信済みSMS送信」画面側で送信元・タイムスタンプの
        // 近さによって突き合わせる（SmsMatching参照）。
        val smsId = inputData.getLong(KEY_SMS_ID, -1L).let { if (it == -1L) null else it }

        val profile = SettingsStore.findProfileForBody(applicationContext, body)

        if (profile == null || !profile.isValid) {
            // 送信先が特定できず何も開始できていないため、送信完了ではなく送信開始として
            // 失敗を記録する
            logStart(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_start_profile_unconfigured), profileName = profile?.displayName(applicationContext), manual = manual)
            // Result.failure()にすると、複数件をまとめて送信した際に後続のチェーンされた
            // ワーカーが実行されずキャンセルされてしまうため、成否はログのみで管理する
            return@withContext Result.success()
        }

        if (!manual && !config.forwardingEnabled) {
            // 送信モードが手動の場合、自動受信時はkintoneへの送信を何も試みないため、
            // 受信完了のログのみとし、送信開始・送信完了は記録しない
            return@withContext Result.success()
        }

        // SMS本文から会社名・氏名・内容を抽出（ラベルの表記ゆれ・記述順の違いに対応）
        val smsParts = SmsPartsGenerator.generateSmsParts(body)

        if (!manual && smsParts.isSplitFailed() && !config.forwardSplitFailedEnabled) {
            // 形式が不正で何も開始できていないため、送信完了ではなく送信開始として失敗を記録する
            logStart(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_start_split_failed_skipped), profileName = profile.displayName(applicationContext), manual = manual)
            return@withContext Result.success()
        }

        logStart(sender, body, timestampMillis, smsId, profileName = profile.displayName(applicationContext), manual = manual)

        val datetimeIso = if (profile.fieldDatetime.isNotBlank()) {
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            isoFormat.format(Date(timestampMillis))
        } else {
            null
        }

        val companyNameValue = if (config.companyNameWidthConversionEnabled) {
            smsParts.companyNameNormalizedWidth
        } else {
            smsParts.companyName
        }

        when (val result = KintoneApi.postRecord(
            applicationContext,
            profile,
            senderValue = sender,
            bodyValue = body,
            datetimeIsoValue = datetimeIso,
            companyNameValue = companyNameValue,
            userNameValue = smsParts.userName,
            contentValue = smsParts.content
        )) {
            is KintoneApi.PostResult.Success -> {
                logComplete(sender, body, timestampMillis, smsId, success = true, message = result.message, profileName = profile.displayName(applicationContext), manual = manual, smsParts = smsParts)
                Result.success()
            }
            is KintoneApi.PostResult.Skipped -> {
                logComplete(sender, body, timestampMillis, smsId, success = true, message = result.message, profileName = profile.displayName(applicationContext), manual = manual, smsParts = smsParts)
                Result.success()
            }
            is KintoneApi.PostResult.HttpFailure -> {
                val detail = "${result.code} ${result.detail}"
                Log.e(TAG, "kintoneへの登録に失敗しました: $detail")
                logComplete(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_complete_failure, detail), profileName = profile.displayName(applicationContext), manual = manual, smsParts = smsParts)
                if ((result.code in 500..599 || result.code == 429) && shouldRetry()) Result.retry() else Result.success()
            }
            is KintoneApi.PostResult.NetworkError -> {
                Log.e(TAG, "kintoneへの通信でエラーが発生しました: ${result.message}")
                logComplete(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_complete_network_error, result.message), profileName = profile.displayName(applicationContext), manual = manual, smsParts = smsParts)
                if (shouldRetry()) Result.retry() else Result.success()
            }
        }
    }

    // WorkManagerはResult.retry()に回数上限を設けていないため、リトライし続けている間は
    // 送信バッチが完了扱いにならず、SmsSearchActivity側の完了通知（トースト）が
    // 表示されないままになる。一定回数で諦めて完了扱いにする
    private fun shouldRetry(): Boolean = runAttemptCount < AppConstants.KINTONE_UPLOAD_MAX_RETRY_ATTEMPTS - 1

    private fun logStart(
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        profileName: String?,
        manual: Boolean,
        success: Boolean = true,
        message: String? = null
    ) {
        SmsLogStore.add(
            applicationContext,
            type = SmsLogStore.EntryType.SEND_START,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = success,
            message = message ?: applicationContext.getString(R.string.message_log_send_start),
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
        manual: Boolean,
        smsParts: SmsParts? = null
    ) {
        SmsLogStore.add(
            applicationContext,
            type = SmsLogStore.EntryType.SEND_COMPLETE,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = success,
            message = message,
            smsId = smsId,
            profileName = profileName,
            manual = manual,
            smsParts = smsParts
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

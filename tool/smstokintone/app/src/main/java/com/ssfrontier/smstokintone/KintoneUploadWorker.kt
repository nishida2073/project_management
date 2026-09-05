package com.ssfrontier.smstokintone

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * SmsReceiverや手動再送UIから渡されたSMS情報をkintoneへ登録するCoroutineWorker。
 * 送信可否・抽出失敗判定・登録結果はいずれもSmsLogStoreへログとして記録する。形式正常だった場合は
 * ContinuationStoreも更新し、以降の継続SMSの引き継ぎに使えるようにする。
 */
class KintoneUploadWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    /** 入力データから送信先を解決し、送信可否判定・kintoneへの登録・ログ記録までを行う */
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val config = SettingsStore.load(applicationContext)
        val sender = inputData.getString(KEY_SENDER) ?: ""
        val body = inputData.getString(KEY_BODY) ?: ""
        val timestampMillis = inputData.getLong(KEY_TIMESTAMP, System.currentTimeMillis())
        val manual = inputData.getBoolean(KEY_MANUAL, false)
        // -1LはKEY_SMS_ID未指定（自動受信）を表す。自動受信時はここで解決せず、
        // 「受信済みSMS送信」画面側で送信元・タイムスタンプの近さによって突き合わせる（SmsMatching参照）
        val smsId = inputData.getLong(KEY_SMS_ID, -1L).let { if (it == -1L) null else it }

        val (resolution, sendTargets) = SettingsStore.resolveSendTargets(applicationContext, sender, body, timestampMillis, config.aiExtractionEnabled, config.continuationEnabled, config.continuationScope)
        val smsParts = resolution.smsParts
        val validSendTargets = sendTargets.filter { it.isValid }

        // 継続SMS自体（引き継ぎ結果）は再保存しても意味が無いため、本文単体で形式正常に解析できた
        // 場合のみ更新する。SmsReceiver側でも同じ条件で更新しており、手動送信のみで運用している場合
        // （SmsReceiverが動かない場合）でもここで引き継ぎ情報を残せるようにする
        if (!resolution.isContinuation && !smsParts.isExtractionFailed()) {
            ContinuationStore.update(
                applicationContext,
                sender = sender,
                companyName = smsParts.companyName,
                userName = smsParts.userName,
                timestampMillis = timestampMillis
            )
        }

        if (validSendTargets.isEmpty()) {
            // 一致した送信先自体が無い場合は送信先名なしの1件、一致したが設定不備で無効な場合は
            // その送信先ごとに1件ずつ「送信先未設定」ログを記録する
            val unconfiguredTargets: List<SettingsStore.SendTarget?> = if (sendTargets.isEmpty()) listOf(null) else sendTargets
            unconfiguredTargets.forEach { sendTarget ->
                val sendTargetName = sendTarget?.displayName(applicationContext)
                logStart(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_start_send_target_unconfigured), sendTargetName = sendTargetName, manual = manual, smsParts = smsParts, isContinuation = resolution.isContinuation)
            }
            // Result.failure()にすると、複数件をまとめて送信した際に後続のチェーンされた
            // ワーカーが実行されずキャンセルされてしまうため、成否はログのみで管理する
            return@withContext Result.success()
        }

        if (!manual && !config.sendEnabled) {
            // 自動送信が無効な場合、自動受信時はkintoneへの送信を何も試みないため、
            // 受信完了のログのみとし送信開始・送信完了は記録しない
            return@withContext Result.success()
        }

        // 一致した送信先ごとに個別にkintoneへ登録し、ログも送信先ごとに分けて記録する。
        // いずれかの送信先で一時的な失敗（リトライ可能）が発生した場合、ワーカー全体をリトライする
        // ため、既に成功した送信先へ再度送信されることがあるが、KintoneApi側の重複判定で実害は防げる
        var shouldRetryAny = false
        for (sendTarget in validSendTargets) {
            if (!manual && smsParts.isExtractionFailed() && !config.sendExtractionFailedEnabled) {
                logStart(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_start_extraction_failed_skipped), sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                continue
            }

            if (!manual && resolution.isContinuation && !config.sendExtractionExcludedEnabled) {
                logStart(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_start_extraction_excluded_skipped), sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                continue
            }

            logStart(sender, body, timestampMillis, smsId, sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)

            val targetDatetimeIso = if (sendTarget.fieldDatetime.isNotBlank()) {
                KintoneApi.formatIsoDateTime(timestampMillis)
            } else {
                null
            }
            val companyNameValue = if (sendTarget.companyNameWidthConversionEnabled) {
                smsParts.companyNameNormalizedWidth
            } else {
                smsParts.companyName
            }

            when (val result = KintoneApi.postRecord(
                applicationContext,
                sendTarget,
                senderValue = sender,
                historyValue = body,
                datetimeIsoValue = targetDatetimeIso,
                companyNameValue = companyNameValue,
                userNameValue = smsParts.userName,
                bodyValue = smsParts.body
            )) {
                is KintoneApi.PostResult.Success -> {
                    logComplete(sender, body, timestampMillis, smsId, success = true, message = result.message, sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                }
                is KintoneApi.PostResult.Skipped -> {
                    logComplete(sender, body, timestampMillis, smsId, success = true, message = result.message, sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                }
                is KintoneApi.PostResult.HttpFailure -> {
                    val detail = "${result.code} ${result.detail}"
                    Log.e(TAG, "kintoneへの登録に失敗しました: $detail")
                    logComplete(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_complete_failure, detail), sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                    if (result.isRetryable) shouldRetryAny = true
                }
                is KintoneApi.PostResult.NetworkError -> {
                    Log.e(TAG, "kintoneへの通信でエラーが発生しました: ${result.message}")
                    logComplete(sender, body, timestampMillis, smsId, success = false, message = applicationContext.getString(R.string.message_log_send_complete_network_error, result.message), sendTargetName = sendTarget.displayName(applicationContext), manual = manual, smsParts = smsParts, companyNameConverted = sendTarget.companyNameWidthConversionEnabled, isContinuation = resolution.isContinuation)
                    shouldRetryAny = true
                }
            }
        }

        if (shouldRetryAny && shouldRetry()) Result.retry() else Result.success()
    }

    /**
     * WorkManagerのResult.retry()に回数上限はなく、リトライし続けている間はSmsSearchActivity側の
     * 完了通知（トースト）が出ないままになるため、一定回数で諦めて完了扱いにする
     */
    private fun shouldRetry(): Boolean = runAttemptCount < AppConstants.KINTONE_UPLOAD_MAX_RETRY_ATTEMPTS - 1

    /**
     * SEND_STARTログを記録する。success/messageのデフォルトは通常の送信開始用で、送信先未設定・
     * 抽出失敗スキップなど送信を行わず終了する場合は呼び出し側でfalseと理由メッセージを指定する
     */
    private fun logStart(
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        sendTargetName: String?,
        manual: Boolean,
        success: Boolean = true,
        message: String? = null,
        smsParts: SmsParts? = null,
        companyNameConverted: Boolean = false,
        isContinuation: Boolean = false
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
            sendTargetName = sendTargetName,
            manual = manual,
            smsParts = smsParts,
            companyNameConverted = companyNameConverted,
            isContinuation = isContinuation
        )
    }

    /**
     * SEND_COMPLETEログを記録する。companyNameConvertedは全角統一変換後の会社名を実際に送信したか
     * どうかを示し、ログ詳細画面（LogActivity）でどちらの表記を表示するかの判定に使われる
     */
    private fun logComplete(
        sender: String,
        body: String,
        timestampMillis: Long,
        smsId: Long?,
        success: Boolean,
        message: String,
        sendTargetName: String?,
        manual: Boolean,
        smsParts: SmsParts? = null,
        companyNameConverted: Boolean = false,
        isContinuation: Boolean = false
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
            sendTargetName = sendTargetName,
            manual = manual,
            smsParts = smsParts,
            companyNameConverted = companyNameConverted,
            isContinuation = isContinuation
        )
    }

    /** [inputData]のキー名とログタグをまとめたコンパニオンオブジェクト */
    companion object {
        /** [Log]出力に使うタグ */
        private const val TAG = "KintoneUploadWorker"
        /** [inputData]内の送信元電話番号のキー */
        const val KEY_SENDER = "sender"
        /** [inputData]内のSMS本文のキー */
        const val KEY_BODY = "body"
        /** [inputData]内の受信/送信対象時刻（ミリ秒）のキー */
        const val KEY_TIMESTAMP = "timestamp"
        /** [inputData]内の、手動再送かどうかを示すフラグのキー */
        const val KEY_MANUAL = "manual"
        /** [inputData]内の、突き合わせ対象SMSのIDのキー（未指定時は-1L） */
        const val KEY_SMS_ID = "sms_id"
    }
}

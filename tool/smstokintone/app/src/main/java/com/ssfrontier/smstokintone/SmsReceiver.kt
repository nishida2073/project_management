package com.ssfrontier.smstokintone

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/**
 * SMS 受信ブロードキャスト受信者。
 * SMS受信を契機に [KintoneUploadWorker] を起動し、受信ログ記録と抽出失敗時の自動返信を実行。
 */
class SmsReceiver : BroadcastReceiver() {

    /**
     * SMS受信ブロードキャストハンドラ。
     * [KintoneUploadWorker] を非同期実行、受信ログ記録、抽出失敗時の自動返信判定を実施。
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // 送信可否・Kintone設定の判定は [KintoneUploadWorker] で行うため、
        // ここで早期 return すると判定結果が受信ログに表示されない。
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // 長文 SMS（分割送信）は複数メッセージに分かれて届くため、本文を連結。
        val sender = messages[0].originatingAddress ?: ""
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
        val timestampMillis = messages[0].timestampMillis

        val data = workDataOf(
            KintoneUploadWorker.KEY_SENDER to sender,
            KintoneUploadWorker.KEY_BODY to body,
            KintoneUploadWorker.KEY_TIMESTAMP to timestampMillis
        )

        val request = OneTimeWorkRequestBuilder<KintoneUploadWorker>()
            .setInputData(data)
            .setBackoffCriteria(
                AppConstants.KINTONE_UPLOAD_RETRY_BACKOFF_POLICY,
                AppConstants.KINTONE_UPLOAD_RETRY_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        WorkManager.getInstance(context).enqueue(request)

        // 送信先名の解決は端末上のAI呼び出しを伴うため、onReceive の同期処理内では
        // 完了を待てない。[goAsync] で実行時間を延長し、コルーチンで判定・記録・返信を実施。
        val config = SettingsStore.load(context)
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                // [KintoneUploadWorker] と同じ [resolveSendTargets] を使用し、
                // 抽出方法のズレによる登録内容と送信先名の食い違いを防止。
                // 1 つの SMS が複数の送信先に一致する場合は、受信ログ内で名前を連結表示。
                val (resolution, sendTargets) = SettingsStore.resolveSendTargets(context, sender, body, timestampMillis, config.extractionAiEnabled, config.extractionCompanyNameEnabled, config.continuationEnabled, config.continuationScope)
                val smsParts = resolution.smsParts
                // 引継ぎ元の送信先が削除・変更された場合、sendTargets は空、
                // 送信先名は「なし」扱い（登録も行われない）。
                val sendTargetName = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(context) }
                // smsParts.companyName は既に会社名変換適用済み。
                // ここでは記録時に変換が有効だったかのフラグ（アイコン表示用）のみ求める。
                val companyNameConverted = config.extractionCompanyNameAutoConversionEnabled || config.extractionCompanyNameFixedConversions.isNotEmpty()

                // 継続 SMS（引継ぎ結果）は再保存しても無意味なため、本文単体で正常に抽出できた
                // 場合のみ更新。[KintoneUploadWorker] 側でも同じ条件で更新。
                if (!resolution.isContinuation && !smsParts.isExtractionFailed()) {
                    ContinuationStore.update(
                        context,
                        sender = sender,
                        companyName = smsParts.companyName,
                        userName = smsParts.userName,
                        timestampMillis = timestampMillis
                    )
                }

                // Kintone への送信完了を待たず、受信時点でログ記録。
                // これにより受信ログ画面で SMS 受信の有無を即座に確認可能。
                // smsId は電話番号表記ゆれや標準 SMS アプリの書き込みタイミングで一致しないため、
                // 特定を試みず、「受信済み SMS 送信」画面で [SmsMatching] により突き合わせ。
                SmsLogStore.add(
                    context,
                    type = SmsLogStore.EntryType.RECEIVE,
                    timestampMillis = timestampMillis,
                    sender = sender,
                    body = body,
                    success = true,
                    message = context.getString(R.string.message_log_receive),
                    sendTargetName = sendTargetName,
                    smsParts = smsParts,
                    companyNameConverted = companyNameConverted,
                    isContinuation = resolution.isContinuation
                )

                if (config.replyEnabled && sender.isNotBlank() && smsParts.isExtractionFailed()) {
                    val now = System.currentTimeMillis()
                    if (AutoReplyThrottle.shouldSend(context, sender, config.replyCooldownSeconds, now)) {
                        if (sendAutoReply(context, sender, config.replyFailedBody)) {
                            SmsLogStore.add(
                                context,
                                type = SmsLogStore.EntryType.AUTO_REPLY,
                                timestampMillis = timestampMillis,
                                sender = sender,
                                body = body,
                                success = true,
                                message = context.getString(R.string.message_log_auto_reply),
                                sendTargetName = sendTargetName,
                                smsParts = smsParts,
                                companyNameConverted = companyNameConverted,
                                replyBody = config.replyFailedBody,
                                isContinuation = resolution.isContinuation
                            )
                        }
                        AutoReplyThrottle.recordSent(context, sender, now)
                    }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    /** 戻り値は送信成功ではなく、送信を試みられたかどうか */
    private fun sendAutoReply(context: Context, sender: String, body: String): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        return try {
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(body)
            smsManager.sendMultipartTextMessage(sender, null, parts, null, null)
            true
        } catch (e: Exception) {
            Log.e(TAG, "自動返信のSMS送信に失敗しました: ${e.message}")
            false
        }
    }

    /** ログ出力用のタグをまとめたコンパニオンオブジェクト */
    companion object {
        /** [Log]出力に使うタグ */
        private const val TAG = "SmsReceiver"
    }
}

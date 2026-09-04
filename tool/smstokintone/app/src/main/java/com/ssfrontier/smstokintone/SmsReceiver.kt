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

/** SMS受信をトリガーにKintoneUploadWorkerを起動し、必要に応じて分割失敗時の自動返信も行うBroadcastReceiver */
class SmsReceiver : BroadcastReceiver() {

    /** SMS受信ブロードキャストを受けてKintoneUploadWorkerを起動し、受信ログの記録と分割失敗時の自動返信を行う */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // 送信可否やkintone設定の完否はKintoneUploadWorker側で判定しログに残すため、
        // ここで早期returnすると判定結果が送信ログ画面に表示されなくなる
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // 分割送信された長文SMSは複数メッセージに分かれて届くため本文を連結する
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

        // 送信先名の解決は端末上のAI呼び出しを伴う場合があり、onReceiveの同期処理内では
        // 待てないため、goAsync()で実行時間を延長しコルーチンで判定・記録・返信を行う
        val config = SettingsStore.load(context)
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                // KintoneUploadWorkerの登録処理と同じresolveSendTargetsを使い、抽出方法のずれによる
                // 登録内容と送信先名の食い違いを防ぐ。1件のSMSが複数の送信先に一致することがあるため、
                // 受信ログ・自動返信ログでは名前を連結して表示する（実際の登録はWorker側で送信先ごとに行う）
                val (resolution, sendTargets) = SettingsStore.resolveSendTargets(context, sender, body, timestampMillis, config.aiParsingEnabled, config.continuationEnabled, config.continuationScope)
                val smsParts = resolution.smsParts
                // 引き継ぎ元の送信先がその後削除・変更されて現在は解決できない場合、sendTargetsは
                // 空になり、送信先名は「なし」扱いになる（実際の登録も行われない）
                val sendTargetName = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(context) }

                // 継続SMS自体（引き継ぎ結果）は再保存しても意味が無いため、本文単体で形式正常に解析
                // できた場合のみ更新する。KintoneUploadWorker側でも同じ条件で更新している
                if (!resolution.isContinuation && !smsParts.isSplitFailed()) {
                    ContinuationStore.update(
                        context,
                        sender = sender,
                        companyName = smsParts.companyName,
                        userName = smsParts.userName,
                        timestampMillis = timestampMillis
                    )
                }

                // kintoneへの送信結果を待たず受信時点でログ記録することで、送信ログ画面でSMS受信の
                // 有無を確認できる。smsIdはこの時点では確実に特定できない（電話番号の表記ゆれや
                // 標準SMSアプリの書き込みタイミング次第で一致しないことがある）ため解決を試みず、
                // 「受信済みSMS送信」画面側でタイムスタンプ近似により突き合わせる（SmsMatching参照）
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
                    companyNameConverted = sendTargets.firstOrNull()?.companyNameWidthConversionEnabled ?: false,
                    isContinuation = resolution.isContinuation
                )

                if (config.autoReplySplitFailedEnabled && sender.isNotBlank() && smsParts.isSplitFailed()) {
                    val now = System.currentTimeMillis()
                    if (AutoReplyThrottle.shouldSend(context, sender, config.autoReplyCooldownSeconds, now)) {
                        if (sendAutoReply(context, sender, config.splitFailedReplyAddition)) {
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
                                companyNameConverted = sendTargets.firstOrNull()?.companyNameWidthConversionEnabled ?: false,
                                replyBody = config.splitFailedReplyAddition,
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

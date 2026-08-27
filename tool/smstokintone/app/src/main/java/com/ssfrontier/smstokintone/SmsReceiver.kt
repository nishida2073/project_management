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

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // 自動送信の有効/無効・kintone設定の完否はKintoneUploadWorker側で判定しログに残す。
        // ここで早期returnすると、その判定結果が送信ログ画面に一切表示されなくなるため行わない。
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // 分割送信された長文SMSは複数メッセージに分かれて届くため本文を連結する
        val sender = messages[0].originatingAddress ?: ""
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
        val timestampMillis = messages[0].timestampMillis

        // kintoneへの送信結果を待たず、受信した時点で即座にログへ記録する。
        // これにより送信ログ画面を見れば、そもそもSMSを受信できているかを確認できる。
        // SMSプロバイダ上の実IDはこの時点で確実には特定できない（電話番号の表記ゆれや、既定の
        // SMSアプリによる書き込みタイミングにより一致しないことがある）ため解決を試みない。
        // 「受信済みSMS送信」画面側で送信元・タイムスタンプの近さによって突き合わせる
        // （SmsMatching参照）。
        val sendTargetName = SettingsStore.findSendTargetForBody(context, body)?.displayName(context)
        SmsLogStore.add(
            context,
            type = SmsLogStore.EntryType.RECEIVE,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = true,
            message = context.getString(R.string.message_log_receive),
            sendTargetName = sendTargetName
        )

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

        // SMS返信はkintoneへの送信設定・送信先送信先の有無とは無関係な機能のため、ここで判定する。
        // 「形式が不正」の判定はAI解析（端末上のAI呼び出し）を伴う場合があり、
        // BroadcastReceiver#onReceiveの同期的な処理では待てないため、goAsync()で実行時間を延長し
        // コルーチンで判定・返信を行う
        val config = SettingsStore.load(context)
        if (config.autoReplySplitFailedEnabled && sender.isNotBlank()) {
            val pendingResult = goAsync()
            CoroutineScope(Dispatchers.Default).launch {
                try {
                    val smsParts = SmsPartsGenerator.resolveSmsParts(body, config.aiParsingEnabled)
                    if (smsParts.isSplitFailed()) {
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
                                    replyBody = config.splitFailedReplyAddition
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
    }

    /** [sender]宛てに[body]をSMSで自動返信する。送信を試みられたかどうかを返す */
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

    companion object {
        private const val TAG = "SmsReceiver"
    }
}

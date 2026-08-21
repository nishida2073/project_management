package com.ssfrontier.smstokintone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
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
        SmsLogStore.add(
            context,
            type = SmsLogStore.EntryType.RECEIVE,
            timestampMillis = timestampMillis,
            sender = sender,
            body = body,
            success = true,
            message = context.getString(R.string.message_log_receive),
            profileName = SettingsStore.findProfileForBody(context, body)?.displayName(context)
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
    }
}

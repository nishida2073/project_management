package com.ssfrontier.smstokintone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.work.BackoffPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // 転送の有効/無効・kintone設定の完否はKintoneUploadWorker側で判定しログに残す。
        // ここで早期returnすると、その判定結果が送信ログ画面に一切表示されなくなるため行わない。
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // 分割送信された長文SMSは複数メッセージに分かれて届くため本文を連結する
        val sender = messages[0].originatingAddress ?: ""
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }
        val timestampMillis = messages[0].timestampMillis

        // 既定のSMSアプリはSMS_DELIVERを先に受け取ってcontent://smsへ書き込んでから
        // SMS_RECEIVEDが他のアプリへブロードキャストされるため、この時点でSMSプロバイダの
        // 実IDを引けることが多い。これを送信済み判定の照合キーとして使う。
        val smsId = findSmsId(context, sender, body)

        // kintoneへの送信結果を待たず、受信した時点で即座にログへ記録する。
        // これにより送信ログ画面を見れば、そもそもSMSを受信できているかを確認できる。
        if (Prefs.load(context).logEnabled) {
            UploadLogStore.add(
                context,
                type = UploadLogStore.EntryType.RECEIVE,
                timestampMillis = timestampMillis,
                sender = sender,
                body = body,
                success = true,
                message = "SMSを受信しました",
                smsId = smsId,
                profileName = Prefs.findProfileForBody(context, body)?.displayName
            )
        }

        val data = workDataOf(
            KintoneUploadWorker.KEY_SENDER to sender,
            KintoneUploadWorker.KEY_BODY to body,
            KintoneUploadWorker.KEY_TIMESTAMP to timestampMillis,
            KintoneUploadWorker.KEY_SMS_ID to (smsId ?: -1L)
        )

        val request = OneTimeWorkRequestBuilder<KintoneUploadWorker>()
            .setInputData(data)
            .setBackoffCriteria(
                BackoffPolicy.LINEAR,
                WorkRequest.MIN_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        WorkManager.getInstance(context).enqueue(request)
    }

    private fun findSmsId(context: Context, sender: String, body: String): Long? {
        return try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(Telephony.Sms._ID),
                "${Telephony.Sms.ADDRESS} = ? AND ${Telephony.Sms.BODY} = ?",
                arrayOf(sender, body),
                "${Telephony.Sms.DATE} DESC"
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getLong(cursor.getColumnIndexOrThrow(Telephony.Sms._ID))
                } else {
                    null
                }
            }
        } catch (e: SecurityException) {
            null
        }
    }
}

package com.ssfrontier.smstokintone

import kotlin.math.abs

/**
 * ログに記録されたSMS（送信元・タイムスタンプ）と、SMSプロバイダ上のSMS（送信元・タイムスタンプ）
 * が同一のSMSを指しているかどうかを判定する。
 *
 * 自動転送では受信時点でSMSプロバイダ上の実IDを確実に特定する手段がない（電話番号の表記ゆれや
 * SMSCタイムスタンプと端末時計のずれで一致に失敗する）ため、実IDを事前に解決して保存するのではなく、
 * 送信元とタイムスタンプの近さで都度突き合わせる方式にしている。
 */
object SmsMatching {

    private const val TIMESTAMP_TOLERANCE_MILLIS = 5 * 60 * 1000L

    fun isLikelySameSms(senderA: String, timestampA: Long, senderB: String, timestampB: Long): Boolean =
        isSameSender(senderA, senderB) && abs(timestampA - timestampB) <= TIMESTAMP_TOLERANCE_MILLIS

    private fun isSameSender(a: String, b: String): Boolean = normalizeSenderKey(a) == normalizeSenderKey(b)

    /** 電話番号は数字のみに絞り末尾8桁を比較キーにする。数字がほぼ無い送信者ID等はそのまま比較する */
    private fun normalizeSenderKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 6) digits.takeLast(8) else address.trim()
    }
}

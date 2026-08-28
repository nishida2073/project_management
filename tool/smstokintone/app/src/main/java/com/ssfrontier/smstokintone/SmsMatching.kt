package com.ssfrontier.smstokintone

import kotlin.math.abs

/**
 * ログに記録されたSMS（送信元・タイムスタンプ）と、端末上のSMS（送信元・タイムスタンプ）
 * が同一のSMSを指しているかどうかを判定する。
 *
 * 自動送信では受信時点で端末上のSMSの実IDを確実に特定する手段がない（電話番号の表記ゆれや
 * SMSCタイムスタンプと端末時計のずれで一致に失敗する）ため、実IDを事前に解決して保存するのではなく、
 * 送信元とタイムスタンプの近さで都度突き合わせる方式にしている。この許容範囲はアプリの設定画面
 * （[SettingsStore.Config.smsMatchToleranceSeconds]、「SMS検索」ブロックの統合範囲）で変更できる。
 *
 * 本文は判定条件には使わない（SMSCタイムスタンプと同様、書き込み時の改行・空白の正規化
 * などで完全一致しないことがあるため）。同じ送信元から似た内容のSMSが許容範囲内に複数届いた場合の
 * 曖昧さは、呼び出し側（[SmsSearchActivity.matchSentEntries]）で1件のログを1件のレコードにしか
 * 割り当てない・時刻が近い方を優先するという方式で軽減している。
 */
object SmsMatching {

    fun isLikelySameSms(
        senderA: String,
        timestampA: Long,
        senderB: String,
        timestampB: Long,
        toleranceMillis: Long
    ): Boolean =
        isSameSender(senderA, senderB) && abs(timestampA - timestampB) <= toleranceMillis

    private fun isSameSender(a: String, b: String): Boolean = normalizeSenderKey(a) == normalizeSenderKey(b)

    /** 電話番号は数字のみに絞り末尾8桁を比較キーにする。数字がほぼ無い送信者ID等はそのまま比較する */
    private fun normalizeSenderKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 6) digits.takeLast(8) else address.trim()
    }
}

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
 * 曖昧さは、[matchEntries]が1件のログを1件のレコードにしか割り当てない・時刻が近い方を優先する
 * という方式で軽減している。
 */
object SmsMatching {

    /**
     * [senderA]/[timestampA]と[senderB]/[timestampB]が同一SMSを指しているとみなせるかを判定する。
     * 送信元が正規化後に一致し、かつタイムスタンプの差が[toleranceMillis]以内であればtrue。
     */
    fun isLikelySameSms(
        senderA: String,
        timestampA: Long,
        senderB: String,
        timestampB: Long,
        toleranceMillis: Long
    ): Boolean =
        isSameSender(senderA, senderB) && abs(timestampA - timestampB) <= toleranceMillis

    /**
     * [records]と[completedEntries]（[SmsLogStore.Entry]）を1対1対応させ、record.idからEntryへの
     * マップを返す。手動送信ログは[SmsLogStore.Entry.smsId]一致で対応付け、IDを持たない自動送信ログは
     * [isLikelySameSms]（送信元・タイムスタンプの近さ）で対応付ける。1件のログが複数レコードに同時
     * マッチしないよう、時刻が近いレコードから順に貪欲に割り当てる。[id]/[sender]/[timestampMillis]は
     * [records]の要素からそれぞれの値を取り出すセレクタ（[records]の型を特定のクラスに固定しないため）。
     */
    fun <T> matchEntries(
        records: List<T>,
        completedEntries: List<SmsLogStore.Entry>,
        toleranceMillis: Long,
        id: (T) -> Long,
        sender: (T) -> String,
        timestampMillis: (T) -> Long
    ): Map<Long, SmsLogStore.Entry> {
        val result = mutableMapOf<Long, SmsLogStore.Entry>()

        val idMatchedEntries = completedEntries.filter { it.smsId != null }.associateBy { it.smsId }
        records.forEach { record ->
            idMatchedEntries[id(record)]?.let { result[id(record)] = it }
        }

        val unclaimedEntries = completedEntries.filter { it.smsId == null }.toMutableList()
        records.filter { id(it) !in result }
            .sortedBy { timestampMillis(it) }
            .forEach { record ->
                val bestIndex = unclaimedEntries.indices
                    .filter { i ->
                        val entry = unclaimedEntries[i]
                        isLikelySameSms(entry.sender, entry.timestampMillis, sender(record), timestampMillis(record), toleranceMillis)
                    }
                    .minByOrNull { i -> abs(unclaimedEntries[i].timestampMillis - timestampMillis(record)) }
                if (bestIndex != null) {
                    result[id(record)] = unclaimedEntries[bestIndex]
                    unclaimedEntries.removeAt(bestIndex)
                }
            }

        return result
    }

    /** [a]と[b]を正規化した上で同一の送信元とみなせるかどうか（電話番号表記のゆれを吸収する） */
    fun isSameSender(a: String, b: String): Boolean = normalizeSenderKey(a) == normalizeSenderKey(b)

    /** 電話番号は数字のみに絞り末尾8桁を比較キーにする。数字がほぼ無い送信者ID等はそのまま比較する */
    private fun normalizeSenderKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 6) digits.takeLast(8) else address.trim()
    }
}

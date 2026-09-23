package com.ssfrontier.smstokintone

import kotlin.math.abs

/**
 * ログに記録されたSMS（送信元・タイムスタンプ）と、端末上のSMS（送信元・タイムスタンプ）
 * が同一のSMSを指しているかどうかを判定する。
 *
 * 自動送信では受信時点で端末上のSMSの実IDを確実に特定する手段がない（電話番号の表記ゆれや
 * SMSCタイムスタンプと端末時計のずれで一致に失敗する）ため、実IDを事前に解決して保存するのではなく、
 * 送信元とタイムスタンプの近さで都度突き合わせる方式にしている。この許容範囲はアプリの設定画面
 * （[SettingsStore.Config.logMatchToleranceSeconds]、「ログ」ブロックの統合範囲）で変更できる。
 *
 * 本文は判定条件には使わない（SMSCタイムスタンプと同様、書き込み時の改行・空白の正規化
 * などで完全一致しないことがあるため）。同じ送信元から似た内容のSMSが許容範囲内に複数届いた場合の
 * 曖昧さは、[matchEntries]が1件のログを1件のレコードにしか割り当てない・時刻が近い方を優先する
 * という方式で軽減している。
 */
object SmsMatching {

    /**
     * [senderA]/[timestampA]と[senderB]/[timestampB]が同一SMSを指しているかを判定する。
     * 送信元が正規化後に一致し、かつタイムスタンプの差が[toleranceMillis]以内ならtrue。
     *
     * @param senderA 送信者A
     * @param timestampA 送信者Aのタイムスタンプ（ミリ秒）
     * @param senderB 送信者B
     * @param timestampB 送信者Bのタイムスタンプ（ミリ秒）
     * @param toleranceMillis タイムスタンプの許容差（ミリ秒）
     * @return 同一SMSとみなせる場合true
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
     * [records]と[completedEntries]を1対1対応させ、record IDからログEntryへのマップを返す。
     * 手動送信ログは[SmsLogStore.Entry.smsId]の一致で対応付け、自動送信ログは[isLikelySameSms]
     * （送信元・タイムスタンプの近さ）で対応付ける。1件のログが複数レコードに同時マッチしないよう、
     * 時刻が近いレコードから順に貪欲に割り当てる。
     *
     * @param T レコード型（型の特定を呼び出し側に委ねるため、セレクタ関数で値を取り出す）
     * @param records 対応付け対象のレコードリスト
     * @param completedEntries 対応付け対象のログエントリリスト
     * @param toleranceMillis タイムスタンプ許容差（ミリ秒）
     * @param id レコード型からIDを取り出すセレクタ関数
     * @param sender レコード型から送信元を取り出すセレクタ関数
     * @param timestampMillis レコード型からタイムスタンプを取り出すセレクタ関数
     * @return record ID→ログEntryのマップ
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

        val idMatchedEntries = completedEntries.filter { it.smsId != null }.groupBy { it.smsId }
        records.forEach { record ->
            idMatchedEntries[id(record)]?.maxByOrNull { it.loggedAtMillis }?.let { result[id(record)] = it }
        }

        val unclaimedEntries = completedEntries.filter { it.smsId == null }.toMutableList()
        records.filter { id(it) !in result }
            .sortedBy { timestampMillis(it) }
            .forEach { record ->
                val matchingIndices = unclaimedEntries.indices
                    .filter { i ->
                        val entry = unclaimedEntries[i]
                        isLikelySameSms(entry.sender, entry.timestampMillis, sender(record), timestampMillis(record), toleranceMillis)
                    }
                val bestIndex = matchingIndices.minByOrNull { i -> abs(unclaimedEntries[i].timestampMillis - timestampMillis(record)) }
                if (bestIndex != null) {
                    result[id(record)] = unclaimedEntries[bestIndex]
                    unclaimedEntries.removeAt(bestIndex)
                }
            }

        return result
    }

    /**
     * [a]と[b]を正規化した上で同一の送信元とみなせるかを判定する。電話番号の表記ゆれを吸収する。
     *
     * @param a 送信元A
     * @param b 送信元B
     * @return 正規化後に一致する場合true
     */
    fun isSameSender(a: String, b: String): Boolean = normalizeSenderKey(a) == normalizeSenderKey(b)

    /**
     * 送信元アドレスを正規化キーに変換する。
     * 電話番号の場合は数字のみに絞り末尾8桁を比較キーにする（6桁以上）。
     * 6桁未満の送信者ID等はそのまま空白を削除して返す。
     *
     * @param address 送信元アドレス（電話番号など）
     * @return 正規化済みのキー文字列
     */
    fun normalizeSenderKey(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 6) digits.takeLast(8) else address.trim()
    }
}

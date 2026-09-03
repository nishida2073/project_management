package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 継続SMS（[SettingsStore.SmsResolution.isContinuation]）の引き継ぎに使う、送信元ごとの最新の
 * 形式正常なSMSの抽出結果を保持する専用のストア。SmsLogStore（全履歴のログ）とは別ファイルで
 * 管理し、ログをクリアしても引き継ぎ情報は失われない。送信元ごとに最新1件のみ保持する
 * （継続SMS自体の結果は保存しない。引き継ぎ元と同じ内容の再保存になり意味が無いため）
 */
object ContinuationStore {

    /** SharedPreferencesのファイル名 */
    private const val PREFS_NAME = "smstokintone_continuation"
    /** 全件をJSON配列文字列として保存するキー */
    private const val KEY_ENTRIES = "entries"

    /** 送信元ごとに保持する、最新の形式正常なSMSの抽出結果 */
    data class Entry(
        /** 会社名 */
        val companyName: String,
        /** 氏名 */
        val userName: String,
        /** 振り分け先となった送信先のID一覧（[SettingsStore.SendTarget.id]） */
        val sendTargetIds: List<String>,
        /** 振り分け先の表示名。解決できなかった場合はnull */
        val sendTargetName: String?,
        /** このSMS自体の受信/送信対象日時 */
        val timestampMillis: Long
    )

    /** 読み書きに使うSharedPreferencesインスタンスを取得する */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** [sender]（[SmsMatching.normalizeSenderKey]で正規化）の最新の抽出結果を上書き保存する */
    fun update(
        context: Context,
        sender: String,
        companyName: String,
        userName: String,
        sendTargetIds: List<String>,
        sendTargetName: String?,
        timestampMillis: Long
    ) {
        val entries = getAll(context).toMutableMap()
        entries[SmsMatching.normalizeSenderKey(sender)] = Entry(companyName, userName, sendTargetIds, sendTargetName, timestampMillis)
        save(context, entries)
    }

    /**
     * [sender]（正規化して比較）の最新の抽出結果を返す（無ければnull）。[sameDayOnly]がtrueの場合、
     * [timestampMillis]と暦日が異なるデータは対象外とする
     */
    fun find(context: Context, sender: String, timestampMillis: Long, sameDayOnly: Boolean): Entry? {
        val entry = getAll(context)[SmsMatching.normalizeSenderKey(sender)] ?: return null
        if (sameDayOnly && !isSameDay(entry.timestampMillis, timestampMillis)) return null
        return entry
    }

    /** 保存済みの全データを削除する */
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ENTRIES).apply()
    }

    /** 正規化した送信元キーをキーとする全データのマップを返す */
    private fun getAll(context: Context): Map<String, Entry> {
        val json = prefs(context).getString(KEY_ENTRIES, null) ?: return emptyMap()
        val array = JSONArray(json)
        return (0 until array.length()).associate { i ->
            val obj = array.getJSONObject(i)
            obj.getString("senderKey") to Entry(
                companyName = obj.optString("companyName", ""),
                userName = obj.optString("userName", ""),
                sendTargetIds = obj.optJSONArray("sendTargetIds")?.let { idsArray ->
                    (0 until idsArray.length()).map { idsArray.getString(it) }
                } ?: emptyList(),
                sendTargetName = obj.optString("sendTargetName", "").ifBlank { null },
                timestampMillis = obj.getLong("timestampMillis")
            )
        }
    }

    /** [entries]（正規化した送信元キーをキーとするマップ）をJSON配列として保存し直す */
    private fun save(context: Context, entries: Map<String, Entry>) {
        val array = JSONArray()
        entries.forEach { (senderKey, entry) ->
            val obj = JSONObject()
                .put("senderKey", senderKey)
                .put("companyName", entry.companyName)
                .put("userName", entry.userName)
                .put("sendTargetIds", JSONArray(entry.sendTargetIds))
                .put("timestampMillis", entry.timestampMillis)
            entry.sendTargetName?.let { obj.put("sendTargetName", it) }
            array.put(obj)
        }
        prefs(context).edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

    /** [aMillis]と[bMillis]が同じ暦日（年・年間通日が一致）かどうか */
    private fun isSameDay(aMillis: Long, bMillis: Long): Boolean {
        val a = Calendar.getInstance().apply { timeInMillis = aMillis }
        val b = Calendar.getInstance().apply { timeInMillis = bMillis }
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }
}

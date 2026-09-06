package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 継続SMS（[SettingsStore.SmsResolution.isContinuation]）の引き継ぎに使う、送信元ごとの最新の
 * 形式正常なSMSの抽出結果を保持する専用のストア。SmsLogStore（全履歴のログ）とは別ファイルで
 * 管理し、ログをクリアしても送信元情報は失われない。送信元ごとに最新1件のみ保持する
 * （継続SMS自体の結果は保存しない。引き継ぎ元と同じ内容の再保存になり意味が無いため）。
 * [SenderInfoActivity]から個別の閲覧・編集・削除もできる。編集画面のように読み込みから保存
 * までに時間が空く操作は[applyIfUnchanged]で楽観的排他制御を行うこと（[lock]は保存時の一致確認と
 * 書き込みのみを保護し、編集中はロックしない）
 */
object ContinuationStore {

    /** SharedPreferencesのファイル名 */
    private const val PREFS_NAME = "smstokintone_continuation"
    /** 全件をJSON配列文字列として保存するキー */
    private const val KEY_ENTRIES = "entries"
    /**
     * [getAll]・[set]・[delete]・[applyIfUnchanged]の排他制御に使うロック。SmsReceiver・
     * KintoneUploadWorker（SMS受信・送信時）とSenderInfoActivity（編集画面）が同一プロセス内から
     * 並行してアクセスし得るため、読み込み→変更→書き込みの間に割り込まれてどちらかの変更が
     * 失われることを防ぐ
     */
    private val lock = Any()

    /**
     * 送信元ごとに保持する、最新の形式正常なSMSの抽出結果。送信先は保持しない。継続SMSの送信先は
     * 常にこの会社名を現在の送信先ルールに通して都度判定するため（[SettingsStore.findSendTargetsForContinuation]
     * 参照）、送信先の設定を変更・削除しても送信元情報側の追随作業は不要になる
     */
    data class Entry(
        /** 会社名 */
        val companyName: String,
        /** 氏名 */
        val userName: String,
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
        timestampMillis: Long
    ) {
        set(context, SmsMatching.normalizeSenderKey(sender), Entry(companyName, userName, timestampMillis))
    }

    /**
     * 正規化済みの送信元キー[senderKey]に対応するデータを[entry]で上書き保存する。[update]と異なり
     * [senderKey]は呼び出し側で既に正規化済みであることを前提とする（送信元情報の編集画面専用）
     */
    fun set(context: Context, senderKey: String, entry: Entry) = synchronized(lock) {
        val entries = getAll(context).toMutableMap()
        entries[senderKey] = entry
        save(context, entries)
    }

    /** 正規化済みの送信元キー[senderKey]のデータを削除する（送信元情報の編集画面専用） */
    fun delete(context: Context, senderKey: String) = synchronized(lock) {
        val entries = getAll(context).toMutableMap()
        entries.remove(senderKey)
        save(context, entries)
    }

    /**
     * 送信元情報の編集画面専用。編集開始時に読み込んだ内容[expectedSnapshot]が現在の保存内容と
     * 一致する場合のみ、[changes]でその内容を書き換えて保存する（一致確認と保存を同じロック内で
     * 行うことでTOCTOU競合を防ぐ）。編集中（画面を開いてから保存するまでの間）はロックを取らない
     * ため、その間にSMSを受信してもブロックされない。一致しない場合＝編集中にSMS受信などで
     * 更新されていた場合は、何も保存せずfalseを返す（呼び出し側で保存失敗として案内すること）
     */
    fun applyIfUnchanged(
        context: Context,
        expectedSnapshot: Map<String, Entry>,
        changes: (MutableMap<String, Entry>) -> Unit
    ): Boolean = synchronized(lock) {
        val current = getAll(context)
        if (current != expectedSnapshot) return@synchronized false
        val updated = current.toMutableMap()
        changes(updated)
        save(context, updated)
        true
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

    /** 正規化した送信元キーをキーとする全データのマップを返す */
    fun getAll(context: Context): Map<String, Entry> = synchronized(lock) {
        val json = prefs(context).getString(KEY_ENTRIES, null) ?: return@synchronized emptyMap()
        val array = JSONArray(json)
        (0 until array.length()).associate { i ->
            val obj = array.getJSONObject(i)
            obj.getString("senderKey") to Entry(
                companyName = obj.optString("companyName", ""),
                userName = obj.optString("userName", ""),
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
                .put("timestampMillis", entry.timestampMillis)
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

package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 継続SMS（[SettingsStore.SmsResolution.isContinuation]）の引き継ぎに使う、送信元ごとの最新の
 * 抽出状況が正常なSMSの抽出結果を保持する専用のストア。SmsLogStore（全履歴のログ）とは別ファイルで
 * 管理し、ログをクリアしても引き継ぎ内容は失われない。送信元ごとに最新1件のみ保持する
 * （継続SMS自体の結果は保存しない。引き継ぎ元と同じ内容の再保存になり意味が無いため）。
 * [ContinuationInfoSettingsActivity]から個別の閲覧・編集・削除もできる。編集画面のように読み込みから保存
 * までに時間が空く操作は[applyIfUnchanged]で楽観的排他制御を行うこと（[lock]は保存時の一致確認と
 * 書き込みのみを保護し、編集中はロックしない）
 */
object ContinuationStore {

    private const val PREFS_NAME = "smstokintone_continuation"
    private const val KEY_ENTRIES = "entries"
    /**
     * [getAll]・[set]・[delete]・[applyIfUnchanged]の排他制御に使うロック。SmsReceiver・
     * KintoneUploadWorker（SMS受信・送信時）とContinuationInfoSettingsActivity（編集画面）が同一プロセス内から
     * 並行してアクセスし得るため、読み込み→変更→書き込みの間に割り込まれてどちらかの変更が
     * 失われることを防ぐ
     */
    private val lock = Any()

    /**
     * 送信元ごとに保持する、最新の抽出状況が正常なSMSの抽出結果。送信先は保持しない。
     * 継続SMSの送信先は常にこの会社名を現在の送信先ルール（[SettingsStore.findSendTargets]）に通して
     * 都度判定するため、送信先の設定を変更・削除しても引き継ぎ内容側の追随作業は不要になる。
     *
     * @property companyName 抽出された会社名
     * @property userName 抽出された氏名
     * @property timestampMillis 引き継ぎ元のSMS受信/送信対象日時（ミリ秒）
     * @property senderAddress 正規化前の元の送信元アドレス。キーは[SmsMatching.normalizeSenderKey]で正規化されて末尾8桁などに削られるため、
     *                         [ContinuationInfoSettingsActivity]の表示専用に別途保持。マッチング処理ではキー側を使う
     */
    data class Entry(
        val companyName: String,
        val userName: String,
        val timestampMillis: Long,
        val senderAddress: String = ""
    )

    /**
     * 引き継ぎ内容の読み書きに使うSharedPreferencesインスタンスを取得する。
     *
     * @param context アプリケーションコンテキスト
     * @return SharedPreferencesインスタンス
     */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * [sender]の最新抽出結果を新規作成・上書き保存する。
     * 送信元は[SmsMatching.normalizeSenderKey]で正規化される。
     *
     * @param context アプリケーションコンテキスト
     * @param sender 送信元アドレス（電話番号など）
     * @param companyName 会社名
     * @param userName 氏名
     * @param timestampMillis SMS受信/送信対象日時（ミリ秒）
     */
    fun update(
        context: Context,
        sender: String,
        companyName: String,
        userName: String,
        timestampMillis: Long
    ) {
        set(context, SmsMatching.normalizeSenderKey(sender), Entry(companyName, userName, timestampMillis, senderAddress = sender))
    }

    /**
     * 正規化済みの送信元キー[senderKey]に対応するデータを[entry]で上書き保存する。
     * [update]と異なり、[senderKey]は呼び出し側で既に正規化済みであることを前提とする。
     * 引き継ぎ内容の編集画面（[ContinuationInfoSettingsActivity]）専用。
     *
     * @param context アプリケーションコンテキスト
     * @param senderKey 正規化済みの送信元キー
     * @param entry 保存する引き継ぎ内容
     */
    fun set(context: Context, senderKey: String, entry: Entry) = synchronized(lock) {
        val entries = getAll(context).toMutableMap()
        entries[senderKey] = entry
        save(context, entries)
    }

    /**
     * 正規化済みの送信元キー[senderKey]のデータを削除する。
     * 引き継ぎ内容の編集画面（[ContinuationInfoSettingsActivity]）専用。
     *
     * @param context アプリケーションコンテキスト
     * @param senderKey 正規化済みの送信元キー
     */
    fun delete(context: Context, senderKey: String) = synchronized(lock) {
        val entries = getAll(context).toMutableMap()
        entries.remove(senderKey)
        save(context, entries)
    }

    /**
     * 引き継ぎ内容の編集画面専用。楽観的排他制御で編集を保存する。
     * 編集開始時に読み込んだ内容[expectedSnapshot]が現在の保存内容と一致する場合のみ、
     * [changes]でその内容を書き換えて保存する。一致確認と保存を同じロック内で行うことで
     * TOCTOU競合を防ぐ。編集中（画面を開いてから保存するまでの間）はロックを取らないため、
     * その間にSMS受信などで更新されてもブロックされない。一致しない場合は何も保存せずfalseを返す。
     *
     * @param context アプリケーションコンテキスト
     * @param expectedSnapshot 編集開始時に読み込んだスナップショット
     * @param changes 書き換え処理を行う関数
     * @return 保存成功時true、編集中に更新されていた場合false
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
     * [sender]の最新抽出結果を返す。該当なしはnull。
     * [sameDayOnly]がtrueの場合、[timestampMillis]と暦日が異なるデータは対象外とする。
     * 継続SMS引き継ぎ有効判定（[SettingsStore.ContinuationScope]）で使用。
     *
     * @param context アプリケーションコンテキスト
     * @param sender 送信元アドレス（電話番号など）
     * @param timestampMillis 判定対象のSMS日時（ミリ秒）
     * @param sameDayOnly 同一暦日に限定する場合true
     * @return 引き継ぎ内容。該当なしはnull
     */
    fun find(context: Context, sender: String, timestampMillis: Long, sameDayOnly: Boolean): Entry? {
        val entry = getAll(context)[SmsMatching.normalizeSenderKey(sender)] ?: return null
        if (sameDayOnly && !isSameDay(entry.timestampMillis, timestampMillis)) return null
        return entry
    }

    /**
     * [entries]（正規化済みの送信元キーをキーとするマップ）で引き継ぎ内容を一括置き換えする。
     * 設定のインポート画面（[SettingsImportExportActivity]）専用。
     *
     * @param context アプリケーションコンテキスト
     * @param entries インポート対象の引き継ぎ内容マップ
     */
    fun importAll(context: Context, entries: Map<String, Entry>) = synchronized(lock) {
        save(context, entries)
    }

    /**
     * 正規化した送信元キーをキーとする全引き継ぎ内容のマップを返す。
     *
     * @param context アプリケーションコンテキスト
     * @return 送信元キー→引き継ぎ内容のマップ
     */
    fun getAll(context: Context): Map<String, Entry> = synchronized(lock) {
        val json = prefs(context).getString(KEY_ENTRIES, null) ?: return@synchronized emptyMap()
        val array = JSONArray(json)
        (0 until array.length()).associate { i ->
            val obj = array.getJSONObject(i)
            obj.getString("senderKey") to Entry(
                companyName = obj.optString("companyName", ""),
                userName = obj.optString("userName", ""),
                timestampMillis = obj.getLong("timestampMillis"),
                senderAddress = obj.optString("senderAddress", "")
            )
        }
    }

    /**
     * 引き継ぎ内容マップをJSON配列として保存し直す。
     *
     * @param context アプリケーションコンテキスト
     * @param entries 保存対象の引き継ぎ内容マップ（正規化済みキー）
     */
    private fun save(context: Context, entries: Map<String, Entry>) {
        val array = JSONArray()
        entries.forEach { (senderKey, entry) ->
            val obj = JSONObject()
                .put("senderKey", senderKey)
                .put("companyName", entry.companyName)
                .put("userName", entry.userName)
                .put("timestampMillis", entry.timestampMillis)
                .put("senderAddress", entry.senderAddress)
            array.put(obj)
        }
        prefs(context).edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

    /**
     * 2つのミリ秒タイムスタンプが同じ暦日（年・年間通日が一致）かを判定する。
     *
     * @param aMillis タイムスタンプA（ミリ秒）
     * @param bMillis タイムスタンプB（ミリ秒）
     * @return 同じ暦日の場合true
     */
    private fun isSameDay(aMillis: Long, bMillis: Long): Boolean {
        val a = Calendar.getInstance().apply { timeInMillis = aMillis }
        val b = Calendar.getInstance().apply { timeInMillis = bMillis }
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }
}

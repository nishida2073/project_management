package com.ssfrontier.smstokintone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * SMS送受信・自動返信の履歴を1件のJSON配列としてSharedPreferencesに永続化するログストア。
 * ログ画面（[LogActivity]）表示用で、DBではないため全件を都度読み書きする。
 */
object SmsLogStore {

    /** SharedPreferencesのファイル名 */
    private const val PREFS_NAME = "smstokintone_log"
    /** ログ全件をJSON配列文字列として保存するキー */
    private const val KEY_ENTRIES = "entries"
    /** [Entry.bodyPreview]として保存する本文の最大文字数 */
    private const val BODY_PREVIEW_LIMIT = 100
    /** JSON上ではLong?のnullを表現できないため、smsId未解決を表す番兵値として使う */
    private const val NO_SMS_ID = -1L

    /** ログエントリの種別 */
    enum class EntryType {
        /** SMS受信時に記録するエントリ */
        RECEIVE,
        /** kintoneへの送信を開始した際に記録するエントリ */
        SEND_START,
        /** kintoneへの送信が完了（成功/失敗いずれも）した際に記録するエントリ */
        SEND_COMPLETE,
        /** 抽出失敗SMSへの自動返信を送信した際に記録するエントリ */
        AUTO_REPLY;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 不明・欠損（旧データ）の場合はSEND_COMPLETE扱いにフォールバックする */
            fun fromName(name: String?): EntryType =
                entries.firstOrNull { it.name == name } ?: SEND_COMPLETE
        }
    }

    /** ログ1件分のレコード。[LogActivity]での一覧表示のほか、[SmsSearchActivity]での送信状況判定にも使う */
    data class Entry(
        /** エントリの種別 */
        val type: EntryType,
        /** このログエントリが記録された時刻（SMS自体の日時は[timestampMillis]） */
        val loggedAtMillis: Long,
        /** SMS本文の受信/送信対象日時。ログの記録時刻は[loggedAtMillis] */
        val timestampMillis: Long,
        /** 送信元電話番号 */
        val sender: String,
        /** SMS本文の先頭[BODY_PREVIEW_LIMIT]文字 */
        val bodyPreview: String,
        /** このエントリが表す処理が成功したかどうか */
        val success: Boolean,
        /** 画面表示用の結果メッセージ */
        val message: String,
        /** 端末上のSMSレコードのID。手動送信ログの突き合わせに使う。自動受信フローでは解決しないためnull */
        val smsId: Long?,
        /** 振り分け先の送信先の表示名。解決できなかった場合はnull */
        val sendTargetName: String?,
        /**
         * 手動操作によるものかどうか。[EntryType.SEND_START]/[EntryType.SEND_COMPLETE]では、手動再送信
         * ならtrue、自動受信をトリガーとした送信ならfalse。[EntryType.RECEIVE]/[EntryType.AUTO_REPLY]は
         * 常にfalse
         */
        val manual: Boolean,
        /** 本文から抽出した会社名・氏名、および本文全体。全エントリ種別で記録時点の抽出結果が設定される */
        val smsParts: SmsParts? = null,
        /** kintone登録時に会社名へ半角大文字・全角統一の変換を適用したか */
        val companyNameConverted: Boolean = false,
        /** [EntryType.AUTO_REPLY]で実際に送信した返信本文。それ以外のエントリはnull */
        val replyBody: String? = null,
        /**
         * このエントリが継続SMS（同一送信元の過去の正常なSMSからの引き継ぎ、
         * [SettingsStore.SmsResolution.isContinuation]参照）によるものかどうか。[smsParts]は
         * 抽出結果のみを表すためこことは別に持つ
         */
        val isContinuation: Boolean = false
    )

    /** ログの読み書きに使うSharedPreferencesインスタンスを取得する */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** ログエントリを1件追加し、先頭（最新）に挿入したうえで全件を保存し直す */
    fun add(
        context: Context,
        type: EntryType,
        timestampMillis: Long,
        sender: String,
        body: String,
        success: Boolean,
        message: String,
        smsId: Long? = null,
        sendTargetName: String? = null,
        manual: Boolean = false,
        smsParts: SmsParts? = null,
        companyNameConverted: Boolean = false,
        replyBody: String? = null,
        isContinuation: Boolean = false
    ) {
        val entries = getAll(context).toMutableList()
        entries.add(
            0,
            Entry(
                type = type,
                loggedAtMillis = System.currentTimeMillis(),
                timestampMillis = timestampMillis,
                sender = sender,
                bodyPreview = body.take(BODY_PREVIEW_LIMIT),
                success = success,
                message = message,
                smsId = smsId,
                sendTargetName = sendTargetName,
                manual = manual,
                smsParts = smsParts,
                companyNameConverted = companyNameConverted,
                replyBody = replyBody,
                isContinuation = isContinuation
            )
        )

        val array = JSONArray()
        entries.forEach { entry ->
            val obj = JSONObject()
                .put("type", entry.type.name)
                .put("loggedAt", entry.loggedAtMillis)
                .put("ts", entry.timestampMillis)
                .put("sender", entry.sender)
                .put("body", entry.bodyPreview)
                .put("success", entry.success)
                .put("message", entry.message)
                .put("smsId", entry.smsId ?: NO_SMS_ID)
                .put("manual", entry.manual)
                .put("companyNameConverted", entry.companyNameConverted)
                .put("isContinuation", entry.isContinuation)
            entry.sendTargetName?.let { obj.put("sendTargetName", it) }
            entry.replyBody?.let { obj.put("replyBody", it) }
            entry.smsParts?.let {
                obj.put(
                    "smsParts",
                    JSONObject()
                        .put("companyName", it.companyName)
                        .put("userName", it.userName)
                        .put("body", it.body)
                        .put("extractedByAi", it.extractedByAi)
                )
            }
            array.put(obj)
        }

        prefs(context).edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

    /** 保存済みの全ログエントリを新しい順で返す */
    fun getAll(context: Context): List<Entry> {
        val json = prefs(context).getString(KEY_ENTRIES, null) ?: return emptyList()
        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val obj = array.getJSONObject(i)
            val smsId = obj.optLong("smsId", NO_SMS_ID)
            Entry(
                type = EntryType.fromName(obj.optString("type", "")),
                // loggedAt導入前の旧データにはこの項目が無いため、tsで代用する
                loggedAtMillis = obj.optLong("loggedAt", obj.getLong("ts")),
                timestampMillis = obj.getLong("ts"),
                sender = obj.optString("sender", ""),
                bodyPreview = obj.optString("body", ""),
                success = obj.optBoolean("success", false),
                message = obj.optString("message", ""),
                smsId = if (smsId == NO_SMS_ID) null else smsId,
                sendTargetName = obj.optString("sendTargetName", "").ifBlank { null },
                manual = obj.optBoolean("manual", false),
                companyNameConverted = obj.optBoolean("companyNameConverted", false),
                replyBody = obj.optString("replyBody", "").ifBlank { null },
                smsParts = obj.optJSONObject("smsParts")?.let {
                    SmsParts(
                        companyName = it.optString("companyName", ""),
                        userName = it.optString("userName", ""),
                        body = it.optString("body", ""),
                        extractedByAi = it.optBoolean("extractedByAi", false)
                    )
                },
                isContinuation = obj.optBoolean("isContinuation", false)
            )
        }
    }

    /** 保存済みの全ログエントリを削除する */
    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ENTRIES).apply()
    }
}

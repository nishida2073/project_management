package com.ssfrontier.smstokintone

import android.content.Context

/**
 * 送信元ごとの自動返信送信時刻を記録し、クールダウン期間中の連投を防ぐ機構。
 * 同一送信元への自動返信は[shouldSend]で許可判定し、実送信後は[recordSent]で時刻を記録する。
 */
object AutoReplyThrottle {

    /**
     * 送信元ごとの最終自動返信時刻を保存するSharedPreferencesのファイル名。
     */
    private const val PREFS_NAME = "smstokintone_auto_reply_throttle"

    /**
     * [sender]への自動返信を送信してもよいかを判定する。
     * [cooldownSeconds]秒以内に既に送信済みならfalseで返す。
     *
     * @param context アプリケーションコンテキスト
     * @param sender 送信元電話番号
     * @param cooldownSeconds クールダウン期間（秒）
     * @param nowMillis 現在時刻（ミリ秒）
     * @return 送信可能ならtrue、クールダウン中ならfalse
     */
    fun shouldSend(context: Context, sender: String, cooldownSeconds: Int, nowMillis: Long): Boolean {
        val lastSentMillis = prefs(context).getLong(sender, -1L)
        if (lastSentMillis == -1L) return true
        val cooldownMillis = cooldownSeconds * 1_000L
        return nowMillis - lastSentMillis >= cooldownMillis
    }

    /**
     * [sender]への自動返信を送信したことを[nowMillis]の時刻で記録する。
     *
     * @param context アプリケーションコンテキスト
     * @param sender 送信元電話番号
     * @param nowMillis 送信時刻（ミリ秒）
     */
    fun recordSent(context: Context, sender: String, nowMillis: Long) {
        prefs(context).edit().putLong(sender, nowMillis).apply()
    }

    /**
     * クールダウン記録用のSharedPreferencesインスタンスを取得する。
     *
     * @param context アプリケーションコンテキスト
     * @return SharedPreferencesインスタンス
     */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

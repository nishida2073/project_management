package com.ssfrontier.smstokintone

import android.content.Context

/**
 * 送信元ごとに、自動返信を最後に送った時刻を記録し、クールダウン期間中の連投を防ぐ
 */
object AutoReplyThrottle {

    private const val PREFS_NAME = "smstokintone_auto_reply_throttle"

    /** [sender]への自動返信が[cooldownSeconds]秒以内に送信済みなら送信可否をfalseで返す */
    fun shouldSend(context: Context, sender: String, cooldownSeconds: Int, nowMillis: Long): Boolean {
        val lastSentMillis = prefs(context).getLong(sender, -1L)
        if (lastSentMillis == -1L) return true
        val cooldownMillis = cooldownSeconds * 1_000L
        return nowMillis - lastSentMillis >= cooldownMillis
    }

    fun recordSent(context: Context, sender: String, nowMillis: Long) {
        prefs(context).edit().putLong(sender, nowMillis).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

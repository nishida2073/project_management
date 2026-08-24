package com.ssfrontier.smstokintone

import androidx.work.BackoffPolicy

/** ユーザーが変更することのない固定値をまとめたもの（UI文言はstrings.xmlを参照） */
object AppConstants {

    const val TEST_SEND_SENDER = "09000000000"

    /** 送信先の絞り込みで「未設定（どの送信先にも一致しない）」を表す選択肢のキー */
    const val SEND_TARGET_FILTER_KEY_UNSET = "__filter_key_unset__"

    /** kintoneへの送信がレートリミット/サーバーエラー/通信エラーで失敗した際の最大リトライ回数 */
    const val KINTONE_UPLOAD_MAX_RETRY_ATTEMPTS = 5

    /**
     * kintoneへの送信リトライ時の初期バックオフ間隔（ミリ秒）。WorkManagerの許容最小値
     * （[androidx.work.WorkRequest.MIN_BACKOFF_MILLIS]）を下回ると例外になるため、
     * 変更する場合はその値以上にすること
     */
    const val KINTONE_UPLOAD_RETRY_BACKOFF_MILLIS = 10_000L

    /** kintoneへの送信リトライ時のバックオフ方式 */
    val KINTONE_UPLOAD_RETRY_BACKOFF_POLICY = BackoffPolicy.LINEAR

    /** 本ツール経由であることを示す選択肢値 */
    const val REGISTRATION_TYPE_VALUE = "外部ツール"

    // [SmsPartsGenerator]がラベル行を判定する際に使う、フィールド名とラベル表記ゆれ一覧の対応。
    val SMS_BODY_FIELD_ALIASES: Map<String, List<String>> = mapOf(
        "companyName" to listOf("会社名", "会社"),
        "userName" to listOf("氏名", "名前"),
        "content" to listOf("理由", "内容", "用件")
    )
}

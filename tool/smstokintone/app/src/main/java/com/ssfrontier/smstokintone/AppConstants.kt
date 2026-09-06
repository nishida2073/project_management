package com.ssfrontier.smstokintone

import androidx.work.BackoffPolicy

/** ユーザーが変更することのない固定値をまとめたもの（UI文言はstrings.xmlを参照） */
object AppConstants {

    /** 送信先設定画面の「テスト送信」で、送信元として使うダミーの電話番号 */
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

    /** kintoneへの送信リトライの間隔を、失敗のたびに一定量ずつ増やす方式 */
    val KINTONE_UPLOAD_RETRY_BACKOFF_POLICY = BackoffPolicy.LINEAR

    /** kintoneへ登録する際の「登録種別」フィールドに設定する値。既存レコードの検索条件にも使う */
    const val REGISTRATION_TYPE_VALUE = "外部ツール"
}

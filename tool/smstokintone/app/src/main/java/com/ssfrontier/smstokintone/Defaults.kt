package com.ssfrontier.smstokintone

/** アプリ全体で使う初期値・ダミー値をまとめたもの（UI文言はstrings.xmlを参照） */
object Defaults {

    const val AUTO_REFRESH_INTERVAL_SECONDS = 30

    const val NEW_PROFILE_SUBDOMAIN = "univ-kyousai-{X}"
    const val NEW_PROFILE_FIELD_SENDER = "sender"
    const val NEW_PROFILE_FIELD_BODY = "body"
    const val NEW_PROFILE_FIELD_DATETIME = "receive_datetime"
    const val NEW_PROFILE_FIELD_TYPE = "registration_type"
    const val NEW_PROFILE_FIELD_COMPANY_NAME = "company_name"
    const val NEW_PROFILE_FIELD_USER_NAME = "user_name"
    const val NEW_PROFILE_FIELD_CONTENT = "content"
    const val NEW_PROFILE_UPDATE_WINDOW_HOURS = 5

    const val TEST_SEND_SENDER = "09000000000"

    /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言の初期値 */
    const val SMS_STANDARD_REPLY_BODY = "NTTデータユニバーシティ\n運営事務局です。\n"

    /** 分割失敗のSMSへの返信時、[SMS_STANDARD_REPLY_BODY]の代わりに使う文言 */
    const val SMS_SPLIT_FAILED_REPLY_BODY = SMS_STANDARD_REPLY_BODY + "下記の形式でご記入のうえ、\n再度SMSのご送信をお願いいたします。\n\n会社名\n氏名\n\n内容"

    /** 本ツール経由であることを示す選択肢値 */
    const val REGISTRATION_TYPE_VALUE = "外部ツール"

    /** 会社名の表記ゆれを正規化する際に付け直す正式な接頭辞 */
    const val SMS_COMPANY_NAME_CANONICAL_PREFIX = "NTTデータ"

    /** 会社名先頭の表記ゆれを検出する正規表現。表記自体は対象外 */
    val SMS_COMPANY_NAME_PREFIX_PATTERN = Regex("^NTT[\\s\\-]?(?:DATA|D)", RegexOption.IGNORE_CASE)

    // [SmsPartsGenerator]がラベル行を判定する際に使う、フィールド名とラベル表記ゆれ一覧の対応。
    val SMS_BODY_FIELD_ALIASES: Map<String, List<String>> = mapOf(
        "companyName" to listOf("会社名", "会社"),
        "userName" to listOf("氏名", "名前"),
        "content" to listOf("理由", "内容", "用件")
    )
}

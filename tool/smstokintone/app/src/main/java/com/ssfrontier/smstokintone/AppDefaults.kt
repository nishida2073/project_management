package com.ssfrontier.smstokintone

/** ユーザーが後から変更できる項目の初期値をまとめたもの（UI文言はstrings.xmlを参照） */
object AppDefaults {

    const val AUTO_REFRESH_INTERVAL_SECONDS = 30

    /** 自動受信SMSのログとSMSプロバイダ上のSMSを突き合わせる際の許容範囲の初期値（秒） */
    const val SMS_MATCH_TOLERANCE_SECONDS = 15

    const val NEW_PROFILE_SUBDOMAIN = "univ-kyousai-{X}"
    const val NEW_PROFILE_FIELD_SENDER = "sender"
    const val NEW_PROFILE_FIELD_BODY = "body"
    const val NEW_PROFILE_FIELD_DATETIME = "receive_datetime"
    const val NEW_PROFILE_FIELD_TYPE = "registration_type"
    const val NEW_PROFILE_FIELD_COMPANY_NAME = "company_name"
    const val NEW_PROFILE_FIELD_USER_NAME = "user_name"
    const val NEW_PROFILE_FIELD_CONTENT = "content"
    const val NEW_PROFILE_UPDATE_WINDOW_HOURS = 5

    /** SMS検索画面を開いた際に検索条件へ初期設定する、開始日〜終了日の範囲の初期値（日） */
    const val SMS_SEARCH_DATE_RANGE_DAYS = 3

    /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言の初期値 */
    const val SMS_STANDARD_REPLY_BODY = "NTTデータユニバーシティ\n運営事務局です。\n"

    /** 分割失敗のSMSへの返信時、[SMS_STANDARD_REPLY_BODY]の代わりに使う文言 */
    const val SMS_SPLIT_FAILED_REPLY_BODY = SMS_STANDARD_REPLY_BODY + "下記の形式でご記入のうえ、\n再度SMSのご送信をお願いいたします。\n\n会社名\n氏名\n\n内容"
}

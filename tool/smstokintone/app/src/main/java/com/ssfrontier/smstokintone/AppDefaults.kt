package com.ssfrontier.smstokintone

/** ユーザーが後から変更できる項目の初期値をまとめたもの（UI文言はstrings.xmlを参照） */
object AppDefaults {

    /** ログ画面の自動更新間隔（秒）の初期値 */
    const val AUTO_REFRESH_INTERVAL_SECONDS = 5

    /** ログとSMSを突き合わせる際の許容範囲（秒）の初期値 */
    const val SMS_MATCH_TOLERANCE_SECONDS = 15

    /** 送信先を新規追加した際の、kintoneサブドメイン欄の初期値 */
    const val NEW_PROFILE_SUBDOMAIN = "univ-kyousai-{X}"
    /** 送信先を新規追加した際の、「送信元」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_SENDER = "sender"
    /** 送信先を新規追加した際の、「履歴」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_HISTORY = "history"
    /** 送信先を新規追加した際の、「受信日時」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_DATETIME = "receive_datetime"
    /** 送信先を新規追加した際の、「登録種別」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_TYPE = "registration_type"
    /** 送信先を新規追加した際の、「会社名」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_COMPANY_NAME = "company_name"
    /** 送信先を新規追加した際の、「氏名」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_USER_NAME = "user_name"
    /** 送信先を新規追加した際の、「本文」フィールドコード欄の初期値 */
    const val NEW_PROFILE_FIELD_BODY = "body"

    /** 送信先を新規追加した際の、既存kintoneレコードへ追記するかどうかを判定する統合範囲（時間）の初期値 */
    const val UPDATE_TOLERANCE_HOURS = 5

    /** SMS検索画面を開いた際の、受信日の範囲（日）の初期値 */
    const val SMS_SEARCH_DATE_RANGE_DAYS = 1

    /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言の初期値 */
    const val SMS_STANDARD_REPLY_BODY = "NTTデータユニバーシティ\n運営事務局です。\n"

    /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言の初期値。（抽出失敗のSMS） */
    const val SMS_EXTRACTION_FAILED_REPLY_BODY = SMS_STANDARD_REPLY_BODY +
        "\n下記の形式でご記入のうえ、\n再度SMSのご送信をお願いします。\n\n" +
        "（記入例）\nNTTデータ〇〇〇\nユニバ太郎\n\nここに内容を入力"

    /** 同一の送信元への自動返信を再送信するまでの間隔（秒）の初期値 */
    const val AUTO_REPLY_COOLDOWN_SECONDS = 10
}

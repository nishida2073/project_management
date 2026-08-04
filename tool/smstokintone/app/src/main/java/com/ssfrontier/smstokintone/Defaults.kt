package com.ssfrontier.smstokintone

/** アプリ全体で使う初期値・ダミー値をまとめたもの（UI文言はstrings.xmlを参照） */
object Defaults {

    const val AUTO_REFRESH_INTERVAL_SECONDS = 30

    const val NEW_PROFILE_SUBDOMAIN = "univ-kyousai-{X}"
    const val NEW_PROFILE_FIELD_SENDER = "sender"
    const val NEW_PROFILE_FIELD_BODY = "content"
    const val NEW_PROFILE_FIELD_DATETIME = "receive_datetime"
    const val NEW_PROFILE_FIELD_TYPE = "registration_type"
    const val NEW_PROFILE_UPDATE_WINDOW_HOURS = 5

    const val TEST_SEND_SENDER = "09000000000"

    /** [Prefs.KintoneProfile.fieldType]に登録・更新のたびに書き込む、本ツール経由であることを示す選択肢値 */
    const val REGISTRATION_TYPE_VALUE = "外部ツール"
}

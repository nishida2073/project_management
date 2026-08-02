package com.ssfrontier.smstokintone

/** アプリ全体で使う初期値・ダミー値をまとめたもの（UI文言はstrings.xmlを参照） */
object Defaults {

    const val AUTO_REFRESH_INTERVAL_SECONDS = 30

    const val NEW_PROFILE_SUBDOMAIN = "univ-kyousai-{X}"
    const val NEW_PROFILE_FIELD_PHONE = "sender"
    const val NEW_PROFILE_FIELD_BODY = "content"
    const val NEW_PROFILE_FIELD_DATETIME = "receive_datetime"

    const val TEST_SEND_PHONE = "09000000000"
}

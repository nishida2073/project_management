package com.ssfrontier.smstokintone

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate

/** アプリ全体のエントリポイント。起動時に保存済み設定からテーマ（ダーク/ライト）を適用する */
class SmsToKintoneApp : Application() {

    /** アプリ起動時に一度だけ呼ばれ、保存済み設定のテーマモードをアプリ全体に適用する */
    override fun onCreate() {
        super.onCreate()
        AppCompatDelegate.setDefaultNightMode(SettingsStore.load(this).themeMode.toNightMode())
    }
}

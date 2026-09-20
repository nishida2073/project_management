package com.ssfrontier.smstokintone

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate

/**
 * アプリ全体のエントリポイント。アプリケーション起動時に一度だけ初期化される。
 * 保存済み設定からテーマ（ダーク/ライト）を適用する。
 */
class SmsToKintoneApp : Application() {

    /**
     * アプリケーション初期化時に呼ばれる。保存済み設定の[SettingsStore.Config.themeMode]を
     * [AppCompatDelegate]へ適用し、アプリ全体に反映する。
     * テーマ変更時には[AppSettingsActivity]および[SettingsImportExportActivity]での
     * [AppCompatDelegate.setDefaultNightMode]呼び出しと組み合わせて、設定変更を即座に反映する。
     */
    override fun onCreate() {
        super.onCreate()
        AppCompatDelegate.setDefaultNightMode(SettingsStore.load(this).themeMode.toNightMode())
    }
}

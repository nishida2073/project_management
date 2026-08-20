package com.ssfrontier.smstokintone

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate

class SmsToKintoneApp : Application() {

    override fun onCreate() {
        super.onCreate()
        AppCompatDelegate.setDefaultNightMode(SettingsStore.load(this).themeMode.toNightMode())
    }
}

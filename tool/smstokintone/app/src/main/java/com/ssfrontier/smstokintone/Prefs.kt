package com.ssfrontier.smstokintone

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

object Prefs {

    private const val PREFS_NAME = "smstokintone_prefs"
    private const val KEY_SUBDOMAIN = "subdomain"
    private const val KEY_APP_ID = "app_id"
    private const val KEY_AUTH_METHOD = "auth_method"
    private const val KEY_API_TOKEN = "api_token"
    private const val KEY_LOGIN_NAME = "login_name"
    private const val KEY_LOGIN_PASSWORD = "login_password"
    private const val KEY_FIELD_PHONE = "field_phone"
    private const val KEY_FIELD_BODY = "field_body"
    private const val KEY_FIELD_DATETIME = "field_datetime"
    private const val KEY_LOG_ENABLED = "log_enabled"
    private const val KEY_FORWARDING_ENABLED = "forwarding_enabled"
    private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
    private const val KEY_AUTO_REFRESH_INTERVAL_SECONDS = "auto_refresh_interval_seconds"
    private const val KEY_THEME_MODE = "theme_mode"
    private const val DEFAULT_AUTO_REFRESH_INTERVAL_SECONDS = 30

    enum class AuthMethod {
        API_TOKEN,
        PASSWORD;

        companion object {
            fun fromName(name: String?): AuthMethod =
                entries.firstOrNull { it.name == name } ?: PASSWORD
        }
    }

    enum class ThemeMode {
        SYSTEM,
        LIGHT,
        DARK;

        fun toNightMode(): Int = when (this) {
            SYSTEM -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }

        companion object {
            fun fromName(name: String?): ThemeMode =
                entries.firstOrNull { it.name == name } ?: SYSTEM
        }
    }

    data class Config(
        val subdomain: String,
        val appId: String,
        val authMethod: AuthMethod,
        val apiToken: String,
        val loginName: String,
        val loginPassword: String,
        val fieldPhone: String,
        val fieldBody: String,
        val fieldDatetime: String,
        val logEnabled: Boolean,
        val forwardingEnabled: Boolean,
        val autoRefreshEnabled: Boolean,
        val autoRefreshIntervalSeconds: Int,
        val themeMode: ThemeMode
    ) {
        val isValid: Boolean
            get() {
                if (subdomain.isBlank() || appId.isBlank() || fieldBody.isBlank()) return false
                return when (authMethod) {
                    AuthMethod.API_TOKEN -> apiToken.isNotBlank()
                    AuthMethod.PASSWORD -> loginName.isNotBlank() && loginPassword.isNotBlank()
                }
            }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, config: Config) {
        prefs(context).edit()
            .putString(KEY_SUBDOMAIN, config.subdomain)
            .putString(KEY_APP_ID, config.appId)
            .putString(KEY_AUTH_METHOD, config.authMethod.name)
            .putString(KEY_API_TOKEN, config.apiToken)
            .putString(KEY_LOGIN_NAME, config.loginName)
            .putString(KEY_LOGIN_PASSWORD, config.loginPassword)
            .putString(KEY_FIELD_PHONE, config.fieldPhone)
            .putString(KEY_FIELD_BODY, config.fieldBody)
            .putString(KEY_FIELD_DATETIME, config.fieldDatetime)
            .putBoolean(KEY_LOG_ENABLED, config.logEnabled)
            .putBoolean(KEY_FORWARDING_ENABLED, config.forwardingEnabled)
            .putBoolean(KEY_AUTO_REFRESH_ENABLED, config.autoRefreshEnabled)
            .putInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, config.autoRefreshIntervalSeconds)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .apply()
    }

    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            subdomain = p.getString(KEY_SUBDOMAIN, "") ?: "",
            appId = p.getString(KEY_APP_ID, "") ?: "",
            authMethod = AuthMethod.fromName(p.getString(KEY_AUTH_METHOD, null)),
            apiToken = p.getString(KEY_API_TOKEN, "") ?: "",
            loginName = p.getString(KEY_LOGIN_NAME, "") ?: "",
            loginPassword = p.getString(KEY_LOGIN_PASSWORD, "") ?: "",
            fieldPhone = p.getString(KEY_FIELD_PHONE, "") ?: "",
            fieldBody = p.getString(KEY_FIELD_BODY, "") ?: "",
            fieldDatetime = p.getString(KEY_FIELD_DATETIME, "") ?: "",
            logEnabled = p.getBoolean(KEY_LOG_ENABLED, true),
            forwardingEnabled = p.getBoolean(KEY_FORWARDING_ENABLED, true),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, true),
            autoRefreshIntervalSeconds = p.getInt(
                KEY_AUTO_REFRESH_INTERVAL_SECONDS,
                DEFAULT_AUTO_REFRESH_INTERVAL_SECONDS
            ),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null))
        )
    }
}

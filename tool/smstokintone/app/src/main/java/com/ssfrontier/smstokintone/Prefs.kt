package com.ssfrontier.smstokintone

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object Prefs {

    private const val PREFS_NAME = "smstokintone_prefs"
    private const val KEY_FORWARDING_ENABLED = "forwarding_enabled"
    private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
    private const val KEY_AUTO_REFRESH_INTERVAL_SECONDS = "auto_refresh_interval_seconds"
    private const val KEY_THEME_MODE = "theme_mode"
    private const val DEFAULT_AUTO_REFRESH_INTERVAL_SECONDS = 30

    private const val KEY_KINTONE_PROFILES = "kintone_profiles"

    // 旧バージョン（単一設定のみ）で使われていたキー。移行専用。
    private const val LEGACY_KEY_SUBDOMAIN = "subdomain"
    private const val LEGACY_KEY_APP_ID = "app_id"
    private const val LEGACY_KEY_AUTH_METHOD = "auth_method"
    private const val LEGACY_KEY_API_TOKEN = "api_token"
    private const val LEGACY_KEY_LOGIN_NAME = "login_name"
    private const val LEGACY_KEY_LOGIN_PASSWORD = "login_password"
    private const val LEGACY_KEY_FIELD_PHONE = "field_phone"
    private const val LEGACY_KEY_FIELD_BODY = "field_body"
    private const val LEGACY_KEY_FIELD_DATETIME = "field_datetime"

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

    /** アプリ全体の設定（kintoneへの接続設定は含まない。接続設定は[KintoneProfile]を参照） */
    data class Config(
        val forwardingEnabled: Boolean,
        val autoRefreshEnabled: Boolean,
        val autoRefreshIntervalSeconds: Int,
        val themeMode: ThemeMode
    )

    /**
     * kintoneへの接続設定の1プロファイル。SMS本文に[keywords]のいずれかが含まれる場合にこの
     * プロファイルが使われる。[keywords]が空の場合はどのプロファイルにも一致しなかった時の
     * デフォルト（フォールバック）として扱われる。
     */
    data class KintoneProfile(
        val id: String,
        val name: String,
        val keywords: String,
        val subdomain: String,
        val appId: String,
        val authMethod: AuthMethod,
        val apiToken: String,
        val loginName: String,
        val loginPassword: String,
        val fieldPhone: String,
        val fieldBody: String,
        val fieldDatetime: String
    ) {
        val keywordList: List<String>
            get() = keywords.split(",").map { it.trim() }.filter { it.isNotEmpty() }

        val isDefault: Boolean
            get() = keywordList.isEmpty()

        /** ログ表示用の名称。表示名が未設定の場合のフォールバック文字列を返す */
        val displayName: String
            get() = name.ifBlank { "(名称未設定)" }

        val isValid: Boolean
            get() {
                if (subdomain.isBlank() || appId.isBlank() || fieldBody.isBlank()) return false
                return when (authMethod) {
                    AuthMethod.API_TOKEN -> apiToken.isNotBlank()
                    AuthMethod.PASSWORD -> loginName.isNotBlank() && loginPassword.isNotBlank()
                }
            }

        fun matches(body: String): Boolean = keywordList.any { body.contains(it) }

        companion object {
            fun newEmpty(): KintoneProfile = KintoneProfile(
                id = UUID.randomUUID().toString(),
                name = "",
                keywords = "",
                subdomain = "",
                appId = "",
                authMethod = AuthMethod.PASSWORD,
                apiToken = "",
                loginName = "",
                loginPassword = "",
                fieldPhone = "",
                fieldBody = "",
                fieldDatetime = ""
            )
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, config: Config) {
        prefs(context).edit()
            .putBoolean(KEY_FORWARDING_ENABLED, config.forwardingEnabled)
            .putBoolean(KEY_AUTO_REFRESH_ENABLED, config.autoRefreshEnabled)
            .putInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, config.autoRefreshIntervalSeconds)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .apply()
    }

    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            forwardingEnabled = p.getBoolean(KEY_FORWARDING_ENABLED, true),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, true),
            autoRefreshIntervalSeconds = p.getInt(
                KEY_AUTO_REFRESH_INTERVAL_SECONDS,
                DEFAULT_AUTO_REFRESH_INTERVAL_SECONDS
            ),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null))
        )
    }

    fun saveProfiles(context: Context, profiles: List<KintoneProfile>) {
        val array = JSONArray()
        profiles.forEach { profile ->
            array.put(
                JSONObject()
                    .put("id", profile.id)
                    .put("name", profile.name)
                    .put("keywords", profile.keywords)
                    .put("subdomain", profile.subdomain)
                    .put("appId", profile.appId)
                    .put("authMethod", profile.authMethod.name)
                    .put("apiToken", profile.apiToken)
                    .put("loginName", profile.loginName)
                    .put("loginPassword", profile.loginPassword)
                    .put("fieldPhone", profile.fieldPhone)
                    .put("fieldBody", profile.fieldBody)
                    .put("fieldDatetime", profile.fieldDatetime)
            )
        }
        prefs(context).edit().putString(KEY_KINTONE_PROFILES, array.toString()).apply()
    }

    fun loadProfiles(context: Context): List<KintoneProfile> {
        val json = prefs(context).getString(KEY_KINTONE_PROFILES, null)
            ?: return migrateLegacyProfile(context)

        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val obj = array.getJSONObject(i)
            KintoneProfile(
                id = obj.optString("id", UUID.randomUUID().toString()),
                name = obj.optString("name", ""),
                keywords = obj.optString("keywords", ""),
                subdomain = obj.optString("subdomain", ""),
                appId = obj.optString("appId", ""),
                authMethod = AuthMethod.fromName(obj.optString("authMethod", "")),
                apiToken = obj.optString("apiToken", ""),
                loginName = obj.optString("loginName", ""),
                loginPassword = obj.optString("loginPassword", ""),
                fieldPhone = obj.optString("fieldPhone", ""),
                fieldBody = obj.optString("fieldBody", ""),
                fieldDatetime = obj.optString("fieldDatetime", "")
            )
        }
    }

    /** 旧バージョンの単一kintone設定を、キーワード未設定（デフォルト）の1プロファイルとして移行する */
    private fun migrateLegacyProfile(context: Context): List<KintoneProfile> {
        val p = prefs(context)
        val legacyProfile = KintoneProfile(
            id = UUID.randomUUID().toString(),
            name = "",
            keywords = "",
            subdomain = p.getString(LEGACY_KEY_SUBDOMAIN, "") ?: "",
            appId = p.getString(LEGACY_KEY_APP_ID, "") ?: "",
            authMethod = AuthMethod.fromName(p.getString(LEGACY_KEY_AUTH_METHOD, null)),
            apiToken = p.getString(LEGACY_KEY_API_TOKEN, "") ?: "",
            loginName = p.getString(LEGACY_KEY_LOGIN_NAME, "") ?: "",
            loginPassword = p.getString(LEGACY_KEY_LOGIN_PASSWORD, "") ?: "",
            fieldPhone = p.getString(LEGACY_KEY_FIELD_PHONE, "") ?: "",
            fieldBody = p.getString(LEGACY_KEY_FIELD_BODY, "") ?: "",
            fieldDatetime = p.getString(LEGACY_KEY_FIELD_DATETIME, "") ?: ""
        )
        val profiles = listOf(legacyProfile)
        saveProfiles(context, profiles)
        return profiles
    }

    /**
     * SMS本文に一致するプロファイルを探す。キーワードを持つプロファイルのうち本文に一致する
     * 最初のものを優先し、一致するものがなければキーワード未設定（デフォルト）のプロファイルに
     * フォールバックする。該当するものがなければnullを返す。
     */
    fun findProfileForBody(context: Context, body: String): KintoneProfile? {
        val profiles = loadProfiles(context)
        profiles.firstOrNull { !it.isDefault && it.matches(body) }?.let { return it }
        return profiles.firstOrNull { it.isDefault }
    }
}

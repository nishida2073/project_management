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
    private const val KEY_DEFAULT_REPLY_BODY = "default_reply_body"
    private const val KEY_SPLIT_FAILED_REPLY_ADDITION = "split_failed_reply_addition"

    private const val KEY_KINTONE_PROFILES = "kintone_profiles"

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
        val themeMode: ThemeMode,
        /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言 */
        val defaultReplyBody: String,
        /** 分割失敗のSMSへの返信時、[defaultReplyBody]の代わりに使う文言 */
        val splitFailedReplyAddition: String
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
        val fieldSender: String,
        val fieldBody: String,
        val fieldDatetime: String,
        val fieldType: String,
        val updateWindowHours: Int,
        val fieldCompanyName: String = "",
        val fieldUserName: String = "",
        val fieldContent: String = ""
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
                if (name.isBlank() || subdomain.isBlank() || appId.isBlank()) return false
                if (fieldSender.isBlank() || fieldBody.isBlank() || fieldDatetime.isBlank() || fieldType.isBlank()) return false
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
                subdomain = Defaults.NEW_PROFILE_SUBDOMAIN,
                appId = "",
                authMethod = AuthMethod.PASSWORD,
                apiToken = "",
                loginName = "",
                loginPassword = "",
                fieldSender = Defaults.NEW_PROFILE_FIELD_SENDER,
                fieldBody = Defaults.NEW_PROFILE_FIELD_BODY,
                fieldDatetime = Defaults.NEW_PROFILE_FIELD_DATETIME,
                fieldType = Defaults.NEW_PROFILE_FIELD_TYPE,
                updateWindowHours = Defaults.NEW_PROFILE_UPDATE_WINDOW_HOURS,
                fieldCompanyName = Defaults.NEW_PROFILE_FIELD_COMPANY_NAME,
                fieldUserName = Defaults.NEW_PROFILE_FIELD_USER_NAME,
                fieldContent = Defaults.NEW_PROFILE_FIELD_CONTENT
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
            .putString(KEY_DEFAULT_REPLY_BODY, config.defaultReplyBody)
            .putString(KEY_SPLIT_FAILED_REPLY_ADDITION, config.splitFailedReplyAddition)
            .apply()
    }

    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            forwardingEnabled = p.getBoolean(KEY_FORWARDING_ENABLED, true),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, true),
            autoRefreshIntervalSeconds = p.getInt(
                KEY_AUTO_REFRESH_INTERVAL_SECONDS,
                Defaults.AUTO_REFRESH_INTERVAL_SECONDS
            ),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null)),
            defaultReplyBody = p.getString(KEY_DEFAULT_REPLY_BODY, Defaults.SMS_STANDARD_REPLY_BODY) ?: Defaults.SMS_STANDARD_REPLY_BODY,
            splitFailedReplyAddition = p.getString(KEY_SPLIT_FAILED_REPLY_ADDITION, Defaults.SMS_SPLIT_FAILED_REPLY_BODY)
                ?: Defaults.SMS_SPLIT_FAILED_REPLY_BODY
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
                    .put("fieldSender", profile.fieldSender)
                    .put("fieldBody", profile.fieldBody)
                    .put("fieldDatetime", profile.fieldDatetime)
                    .put("fieldType", profile.fieldType)
                    .put("updateWindowHours", profile.updateWindowHours)
                    .put("fieldCompanyName", profile.fieldCompanyName)
                    .put("fieldUserName", profile.fieldUserName)
                    .put("fieldContent", profile.fieldContent)
            )
        }
        prefs(context).edit().putString(KEY_KINTONE_PROFILES, array.toString()).apply()
    }

    fun loadProfiles(context: Context): List<KintoneProfile> {
        val json = prefs(context).getString(KEY_KINTONE_PROFILES, null)
            ?: return createDefaultProfile(context)

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
                fieldSender = obj.optString("fieldSender", ""),
                fieldBody = obj.optString("fieldBody", ""),
                fieldDatetime = obj.optString("fieldDatetime", ""),
                fieldType = obj.optString("fieldType", ""),
                updateWindowHours = obj.optInt("updateWindowHours", Defaults.NEW_PROFILE_UPDATE_WINDOW_HOURS),
                fieldCompanyName = obj.optString("fieldCompanyName", ""),
                fieldUserName = obj.optString("fieldUserName", ""),
                fieldContent = obj.optString("fieldContent", "")
            )
        }
    }

    /** 保存済みのプロファイルが1件もない場合に、初期値のみの空プロファイルを1件作成する */
    private fun createDefaultProfile(context: Context): List<KintoneProfile> {
        val profiles = listOf(KintoneProfile.newEmpty())
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

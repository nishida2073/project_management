package com.ssfrontier.smstokintone

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

object SettingsStore {

    private const val PREFS_NAME = "smstokintone_prefs"
    private const val KEY_SEND_ENABLED = "send_enabled"
    private const val KEY_SEND_SPLIT_FAILED_ENABLED = "send_split_failed_enabled"
    private const val KEY_SEARCH_SPLIT_FAILED_ENABLED = "search_split_failed_enabled"
    private const val KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED = "search_send_target_unconfigured_enabled"
    private const val KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED = "auto_reply_split_failed_enabled"
    private const val KEY_AUTO_REPLY_COOLDOWN_SECONDS = "auto_reply_cooldown_seconds"
    private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
    private const val KEY_AUTO_REFRESH_INTERVAL_SECONDS = "auto_refresh_interval_seconds"
    private const val KEY_SMS_MATCH_TOLERANCE_SECONDS = "sms_match_tolerance_seconds"
    private const val KEY_THEME_MODE = "theme_mode"
    private const val KEY_SMS_SEARCH_DATE_RANGE_DAYS = "sms_search_date_range_days"
    private const val KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT = "search_filters_visible_by_default"
    private const val KEY_DEFAULT_REPLY_BODY = "default_reply_body"
    private const val KEY_SPLIT_FAILED_REPLY_ADDITION = "split_failed_reply_addition"
    private const val KEY_DEFAULT_SEND_TARGET_FILTER_ID = "default_send_target_filter_id"
    private const val KEY_AI_PARSING_ENABLED = "ai_parsing_enabled"
    private const val KEY_DEFAULT_SEND_NONE_ONLY_ENABLED = "default_send_none_only_enabled"
    private const val KEY_DEFAULT_SPLIT_FAILED_ONLY_ENABLED = "default_split_failed_only_enabled"
    private const val KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED = "default_sent_auto_only_enabled"
    private const val KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED = "default_sent_manual_only_enabled"

    private const val KEY_SEND_TARGETS = "send_targets"

    enum class AuthMethod {
        API_TOKEN,
        PASSWORD;

        companion object {
            fun fromName(name: String?): AuthMethod =
                entries.firstOrNull { it.name == name } ?: PASSWORD
        }
    }

    /** 送信先の振り分け（[SendTarget.keywords]）の照合対象。[BODY]はSMS本文そのもの、[COMPANY_NAME]はそこから抽出した会社名 */
    enum class MatchTarget {
        BODY,
        COMPANY_NAME;

        companion object {
            fun fromName(name: String?): MatchTarget =
                entries.firstOrNull { it.name == name } ?: BODY
        }
    }

    enum class ThemeMode {
        LIGHT,
        DARK;

        fun toNightMode(): Int = when (this) {
            LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }

        companion object {
            fun fromName(name: String?): ThemeMode =
                entries.firstOrNull { it.name == name } ?: LIGHT
        }
    }

    /** アプリ全体の設定（kintoneへの接続設定は含まない。接続設定は[SendTarget]を参照） */
    data class Config(
        val sendEnabled: Boolean,
        /** 自動送信時、本文の形式が不正なSMS（会社名・氏名・内容に分割できなかったSMS）も送信するかどうか */
        val sendSplitFailedEnabled: Boolean,
        /** SMS検索画面で、本文の形式が不正なSMSを選択可能にするかどうか */
        val searchSplitFailedEnabled: Boolean,
        /** SMS検索画面で、送信先が未設定（一致する送信先が無い、または不正）のSMSを選択可能にするかどうか */
        val searchSendTargetUnconfiguredEnabled: Boolean,
        /** 自動受信時、本文の形式が不正なSMSに対して[splitFailedReplyAddition]の文言でSMSへ自動返信するかどうか */
        val autoReplySplitFailedEnabled: Boolean,
        /** 同一の送信元への自動返信を再送信するまでの間隔（秒）。連投を防ぐためのクールダウン */
        val autoReplyCooldownSeconds: Int,
        val autoRefreshEnabled: Boolean,
        val autoRefreshIntervalSeconds: Int,
        /** 自動受信SMSのログとSMSプロバイダ上のSMSを突き合わせる際の許容範囲（秒） */
        val smsMatchToleranceSeconds: Int,
        val themeMode: ThemeMode,
        /** SMS検索画面を開いた際に検索条件へ初期設定する、開始日〜終了日の範囲（日） */
        val smsSearchDateRangeDays: Int,
        /** SMS検索画面を開いた際に検索条件エリアを表示した状態にするかどうか */
        val searchFiltersVisibleByDefault: Boolean,
        /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言 */
        val defaultReplyBody: String,
        /** 分割失敗のSMSへの返信時、[defaultReplyBody]の代わりに使う文言 */
        val splitFailedReplyAddition: String,
        /**
         * SMS検索画面を開いた際に「送信先」フィルタへ初期設定する送信先ID。
         * nullは「すべて」、[AppConstants.SEND_TARGET_FILTER_KEY_UNSET]は「未設定」を表す
         */
        val defaultSendTargetFilterId: String?,
        /** 本文からの会社名・氏名・内容の抽出に、ルールベースの代わりに端末上のAI（ML Kit GenAI / Gemini Nano）を
         * 使うかどうか。非対応端末では自動的にルールベースにフォールバックする */
        val aiParsingEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「未」チェックボックスを初期状態でONにするかどうか */
        val defaultSendNoneOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「内容」の「形式が不正」チェックボックスを初期状態でONにするかどうか */
        val defaultSplitFailedOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（自動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentAutoOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（手動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentManualOnlyEnabled: Boolean
    )

    /**
     * kintoneへの接続設定の1送信先。[matchTarget]で指定した対象に[keywords]のいずれかが
     * 含まれる場合にこの送信先が使われる（[SettingsStore.resolveSendTarget]参照）。
     * [keywords]が空の場合はどの送信先にも一致しなかった時のフォールバックとして扱われる。
     */
    data class SendTarget(
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
        val updateToleranceHours: Int,
        val fieldCompanyName: String = "",
        val fieldUserName: String = "",
        val fieldContent: String = "",
        /** kintoneへの送信時、会社名に[SmsParts.companyNameNormalizedWidth]（英数字は半角・それ以外は全角に統一した文字列）を使うかどうか。
         * falseの場合は[SmsParts.companyName]（変換なし）をそのまま使う */
        val companyNameWidthConversionEnabled: Boolean = false,
        /** [keywords]をSMS本文そのものと会社名（抽出結果）のどちらに対して照合するか */
        val matchTarget: MatchTarget = MatchTarget.BODY
    ) {
        val keywordList: List<String>
            get() = keywords.split(",", "\n").map { it.trim() }.filter { it.isNotEmpty() }

        val isDefault: Boolean
            get() = keywordList.isEmpty()

        /** 表示名が未設定の場合のフォールバック文字列を返す */
        fun displayName(context: Context): String =
            name.ifBlank { context.getString(R.string.label_send_target_name_unset) }

        val isValid: Boolean
            get() {
                if (name.isBlank() || subdomain.isBlank() || appId.isBlank()) return false
                if (fieldSender.isBlank() || fieldBody.isBlank() || fieldDatetime.isBlank() || fieldType.isBlank()) return false
                return when (authMethod) {
                    AuthMethod.API_TOKEN -> apiToken.isNotBlank()
                    AuthMethod.PASSWORD -> loginName.isNotBlank() && loginPassword.isNotBlank()
                }
            }

        /** [matchTarget]に応じて[body]か[companyName]のどちらかを[keywords]と照合する */
        fun matches(body: String, companyName: String): Boolean {
            val text = if (matchTarget == MatchTarget.BODY) body else companyName
            return keywordList.any { TextNormalization.matches(text, it) }
        }

        /**
         * キーワード一致でこの送信先に実際に振り分けられるかどうか。デフォルト送信先（[isDefault]、
         * キーワード未設定でフォールバック用）は対象外とする。本番の振り分け（[SettingsStore.findSendTarget]）
         * とテスト送信プレビューで判定基準がずれないよう、一致判定は必ずこれを使うこと。
         */
        fun routesTo(body: String, companyName: String): Boolean = !isDefault && matches(body, companyName)

        companion object {
            fun newEmpty(): SendTarget = SendTarget(
                id = UUID.randomUUID().toString(),
                name = "",
                keywords = "",
                subdomain = AppDefaults.NEW_PROFILE_SUBDOMAIN,
                appId = "",
                authMethod = AuthMethod.PASSWORD,
                apiToken = "",
                loginName = "",
                loginPassword = "",
                fieldSender = AppDefaults.NEW_PROFILE_FIELD_SENDER,
                fieldBody = AppDefaults.NEW_PROFILE_FIELD_BODY,
                fieldDatetime = AppDefaults.NEW_PROFILE_FIELD_DATETIME,
                fieldType = AppDefaults.NEW_PROFILE_FIELD_TYPE,
                updateToleranceHours = AppDefaults.UPDATE_TOLERANCE_HOURS,
                fieldCompanyName = AppDefaults.NEW_PROFILE_FIELD_COMPANY_NAME,
                fieldUserName = AppDefaults.NEW_PROFILE_FIELD_USER_NAME,
                fieldContent = AppDefaults.NEW_PROFILE_FIELD_CONTENT
            )
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, config: Config) {
        val editor = prefs(context).edit()
            .putBoolean(KEY_SEND_ENABLED, config.sendEnabled)
            .putBoolean(KEY_SEND_SPLIT_FAILED_ENABLED, config.sendSplitFailedEnabled)
            .putBoolean(KEY_SEARCH_SPLIT_FAILED_ENABLED, config.searchSplitFailedEnabled)
            .putBoolean(KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED, config.searchSendTargetUnconfiguredEnabled)
            .putBoolean(KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED, config.autoReplySplitFailedEnabled)
            .putInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, config.autoReplyCooldownSeconds)
            .putBoolean(KEY_AUTO_REFRESH_ENABLED, config.autoRefreshEnabled)
            .putInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, config.autoRefreshIntervalSeconds)
            .putInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, config.smsMatchToleranceSeconds)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .putInt(KEY_SMS_SEARCH_DATE_RANGE_DAYS, config.smsSearchDateRangeDays)
            .putBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, config.searchFiltersVisibleByDefault)
            .putString(KEY_DEFAULT_REPLY_BODY, config.defaultReplyBody)
            .putString(KEY_SPLIT_FAILED_REPLY_ADDITION, config.splitFailedReplyAddition)
            .putBoolean(KEY_AI_PARSING_ENABLED, config.aiParsingEnabled)
            .putBoolean(KEY_DEFAULT_SEND_NONE_ONLY_ENABLED, config.defaultSendNoneOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SPLIT_FAILED_ONLY_ENABLED, config.defaultSplitFailedOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED, config.defaultSentAutoOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED, config.defaultSentManualOnlyEnabled)
        if (config.defaultSendTargetFilterId != null) {
            editor.putString(KEY_DEFAULT_SEND_TARGET_FILTER_ID, config.defaultSendTargetFilterId)
        } else {
            editor.remove(KEY_DEFAULT_SEND_TARGET_FILTER_ID)
        }
        editor.apply()
    }

    /**
     * [Config]の既定値。[load]のフォールバックと[resetToDefaults]の両方が参照する。
     * 別々に書くと「初回起動時のデフォルト」と「初期化後の値」が食い違う恐れがあるため1箇所にまとめる
     */
    private val DEFAULT_CONFIG = Config(
        sendEnabled = true,
        sendSplitFailedEnabled = false,
        searchSplitFailedEnabled = false,
        searchSendTargetUnconfiguredEnabled = false,
        autoReplySplitFailedEnabled = false,
        autoReplyCooldownSeconds = AppDefaults.AUTO_REPLY_COOLDOWN_SECONDS,
        autoRefreshEnabled = true,
        autoRefreshIntervalSeconds = AppDefaults.AUTO_REFRESH_INTERVAL_SECONDS,
        smsMatchToleranceSeconds = AppDefaults.SMS_MATCH_TOLERANCE_SECONDS,
        themeMode = ThemeMode.LIGHT,
        smsSearchDateRangeDays = AppDefaults.SMS_SEARCH_DATE_RANGE_DAYS,
        searchFiltersVisibleByDefault = true,
        defaultReplyBody = AppDefaults.SMS_STANDARD_REPLY_BODY,
        splitFailedReplyAddition = AppDefaults.SMS_SPLIT_FAILED_REPLY_BODY,
        defaultSendTargetFilterId = null,
        aiParsingEnabled = false,
        defaultSendNoneOnlyEnabled = false,
        defaultSplitFailedOnlyEnabled = false,
        defaultSentAutoOnlyEnabled = false,
        defaultSentManualOnlyEnabled = false
    )

    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            sendEnabled = p.getBoolean(KEY_SEND_ENABLED, DEFAULT_CONFIG.sendEnabled),
            sendSplitFailedEnabled = p.getBoolean(KEY_SEND_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.sendSplitFailedEnabled),
            searchSplitFailedEnabled = p.getBoolean(KEY_SEARCH_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.searchSplitFailedEnabled),
            searchSendTargetUnconfiguredEnabled = p.getBoolean(
                KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED,
                DEFAULT_CONFIG.searchSendTargetUnconfiguredEnabled
            ),
            autoReplySplitFailedEnabled = p.getBoolean(KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.autoReplySplitFailedEnabled),
            autoReplyCooldownSeconds = p.getInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, DEFAULT_CONFIG.autoReplyCooldownSeconds),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, DEFAULT_CONFIG.autoRefreshEnabled),
            autoRefreshIntervalSeconds = p.getInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, DEFAULT_CONFIG.autoRefreshIntervalSeconds),
            smsMatchToleranceSeconds = p.getInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, DEFAULT_CONFIG.smsMatchToleranceSeconds),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null)),
            smsSearchDateRangeDays = p.getInt(KEY_SMS_SEARCH_DATE_RANGE_DAYS, DEFAULT_CONFIG.smsSearchDateRangeDays),
            searchFiltersVisibleByDefault = p.getBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, DEFAULT_CONFIG.searchFiltersVisibleByDefault),
            defaultReplyBody = p.getString(KEY_DEFAULT_REPLY_BODY, DEFAULT_CONFIG.defaultReplyBody) ?: DEFAULT_CONFIG.defaultReplyBody,
            splitFailedReplyAddition = p.getString(KEY_SPLIT_FAILED_REPLY_ADDITION, DEFAULT_CONFIG.splitFailedReplyAddition)
                ?: DEFAULT_CONFIG.splitFailedReplyAddition,
            defaultSendTargetFilterId = p.getString(KEY_DEFAULT_SEND_TARGET_FILTER_ID, DEFAULT_CONFIG.defaultSendTargetFilterId),
            aiParsingEnabled = p.getBoolean(KEY_AI_PARSING_ENABLED, DEFAULT_CONFIG.aiParsingEnabled),
            defaultSendNoneOnlyEnabled = p.getBoolean(KEY_DEFAULT_SEND_NONE_ONLY_ENABLED, DEFAULT_CONFIG.defaultSendNoneOnlyEnabled),
            defaultSplitFailedOnlyEnabled = p.getBoolean(KEY_DEFAULT_SPLIT_FAILED_ONLY_ENABLED, DEFAULT_CONFIG.defaultSplitFailedOnlyEnabled),
            defaultSentAutoOnlyEnabled = p.getBoolean(KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED, DEFAULT_CONFIG.defaultSentAutoOnlyEnabled),
            defaultSentManualOnlyEnabled = p.getBoolean(KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED, DEFAULT_CONFIG.defaultSentManualOnlyEnabled)
        )
    }

    /** 設定画面の変更リスナーで繰り返す「読み込み→copyで1項目だけ変更→保存」をまとめたもの */
    fun update(context: Context, change: (Config) -> Config) {
        save(context, change(load(context)))
    }

    /** アプリの設定（[Config]）をすべて既定値に戻す。送信先の設定（[SendTarget]）は対象外で変更されない */
    fun resetToDefaults(context: Context) {
        save(context, DEFAULT_CONFIG)
    }

    /**
     * SMS検索画面・アプリ設定画面の「送信先」選択肢（すべて／各送信先／未設定）を
     * キーと表示ラベルの組で返す。キーがnullの選択肢は「すべて」、
     * [AppConstants.SEND_TARGET_FILTER_KEY_UNSET]は「未設定」を表す
     */
    fun sendTargetFilterOptions(context: Context): List<Pair<String?, String>> {
        val sendTargets = loadSendTargets(context)
        return listOf(null to context.getString(R.string.filter_send_target_all)) +
            sendTargets.map { it.id to it.displayName(context) } +
            listOf(AppConstants.SEND_TARGET_FILTER_KEY_UNSET to context.getString(R.string.label_send_target_none))
    }

    fun saveSendTargets(context: Context, sendTargets: List<SendTarget>) {
        val array = JSONArray()
        sendTargets.forEach { sendTarget ->
            array.put(
                JSONObject()
                    .put("id", sendTarget.id)
                    .put("name", sendTarget.name)
                    .put("keywords", sendTarget.keywords)
                    .put("subdomain", sendTarget.subdomain)
                    .put("appId", sendTarget.appId)
                    .put("authMethod", sendTarget.authMethod.name)
                    .put("apiToken", sendTarget.apiToken)
                    .put("loginName", sendTarget.loginName)
                    .put("loginPassword", sendTarget.loginPassword)
                    .put("fieldSender", sendTarget.fieldSender)
                    .put("fieldBody", sendTarget.fieldBody)
                    .put("fieldDatetime", sendTarget.fieldDatetime)
                    .put("fieldType", sendTarget.fieldType)
                    .put("updateToleranceHours", sendTarget.updateToleranceHours)
                    .put("fieldCompanyName", sendTarget.fieldCompanyName)
                    .put("fieldUserName", sendTarget.fieldUserName)
                    .put("fieldContent", sendTarget.fieldContent)
                    .put("companyNameWidthConversionEnabled", sendTarget.companyNameWidthConversionEnabled)
                    .put("matchTarget", sendTarget.matchTarget.name)
            )
        }
        prefs(context).edit().putString(KEY_SEND_TARGETS, array.toString()).apply()
    }

    fun loadSendTargets(context: Context): List<SendTarget> {
        val json = prefs(context).getString(KEY_SEND_TARGETS, null)
            ?: return createDefaultSendTarget(context)

        val array = JSONArray(json)
        return (0 until array.length()).map { i ->
            val obj = array.getJSONObject(i)
            SendTarget(
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
                updateToleranceHours = obj.optInt("updateToleranceHours", AppDefaults.UPDATE_TOLERANCE_HOURS),
                fieldCompanyName = obj.optString("fieldCompanyName", ""),
                fieldUserName = obj.optString("fieldUserName", ""),
                fieldContent = obj.optString("fieldContent", ""),
                companyNameWidthConversionEnabled = obj.optBoolean("companyNameWidthConversionEnabled", false),
                matchTarget = MatchTarget.fromName(obj.optString("matchTarget", ""))
            )
        }
    }

    private fun createDefaultSendTarget(context: Context): List<SendTarget> {
        val sendTargets = listOf(SendTarget.newEmpty())
        saveSendTargets(context, sendTargets)
        return sendTargets
    }

    /**
     * キーワードが一致する送信先のうち最初のものを優先し、無ければキーワード未設定
     * （デフォルト）の送信先にフォールバックする。該当が無ければnull。[resolveSendTarget]専用
     */
    private fun findSendTarget(context: Context, body: String, companyName: String): SendTarget? {
        val sendTargets = loadSendTargets(context)
        sendTargets.firstOrNull { it.routesTo(body, companyName) }?.let { return it }
        return sendTargets.firstOrNull { it.isDefault }
    }

    /**
     * SMS本文から[SmsParts]を抽出し、対応する送信先を判定する。抽出結果と送信先判定の両方が
     * 必要な箇所（kintone登録・受信ログ記録・SMS検索画面・テスト送信など）は、抽出方法
     * （ルールベース／AI）のずれで登録内容と振り分け結果が食い違わないよう必ずこれを使うこと。
     */
    suspend fun resolveSendTarget(context: Context, body: String, aiParsingEnabled: Boolean): Pair<SmsParts, SendTarget?> {
        val smsParts = SmsPartsGenerator.resolveSmsParts(body, aiParsingEnabled)
        return smsParts to findSendTarget(context, body, smsParts.companyName)
    }
}

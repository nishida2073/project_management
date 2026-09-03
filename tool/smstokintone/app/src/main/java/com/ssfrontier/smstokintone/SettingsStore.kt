package com.ssfrontier.smstokintone

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** アプリの設定（[Config]）と送信先設定（[SendTarget]）をSharedPreferencesで永続化する */
object SettingsStore {

    /** SharedPreferencesのファイル名 */
    private const val PREFS_NAME = "smstokintone_prefs"
    /** SharedPreferencesのキー名。各キーが対応する設定の意味は[Config]の同名フィールドのKDocを参照 */
    /** [Config.sendEnabled]のキー */
    private const val KEY_SEND_ENABLED = "send_enabled"
    /** [Config.sendSplitFailedEnabled]のキー */
    private const val KEY_SEND_SPLIT_FAILED_ENABLED = "send_split_failed_enabled"
    /** [Config.sendSplitExcludedEnabled]のキー */
    private const val KEY_SEND_SPLIT_EXCLUDED_ENABLED = "send_split_excluded_enabled"
    /** [Config.searchSplitFailedEnabled]のキー */
    private const val KEY_SEARCH_SPLIT_FAILED_ENABLED = "search_split_failed_enabled"
    /** [Config.searchSplitExcludedEnabled]のキー */
    private const val KEY_SEARCH_SPLIT_EXCLUDED_ENABLED = "search_split_excluded_enabled"
    /** [Config.searchSendTargetUnconfiguredEnabled]のキー */
    private const val KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED = "search_send_target_unconfigured_enabled"
    /** [Config.autoReplySplitFailedEnabled]のキー */
    private const val KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED = "auto_reply_split_failed_enabled"
    /** [Config.autoReplyCooldownSeconds]のキー */
    private const val KEY_AUTO_REPLY_COOLDOWN_SECONDS = "auto_reply_cooldown_seconds"
    /** [Config.autoRefreshEnabled]のキー */
    private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
    /** [Config.autoRefreshIntervalSeconds]のキー */
    private const val KEY_AUTO_REFRESH_INTERVAL_SECONDS = "auto_refresh_interval_seconds"
    /** [Config.smsMatchToleranceSeconds]のキー */
    private const val KEY_SMS_MATCH_TOLERANCE_SECONDS = "sms_match_tolerance_seconds"
    /** [Config.continuationEnabled]のキー */
    private const val KEY_CONTINUATION_ENABLED = "continuation_enabled"
    /** [Config.continuationScope]のキー */
    private const val KEY_CONTINUATION_SCOPE = "continuation_scope"
    /** [Config.themeMode]のキー */
    private const val KEY_THEME_MODE = "theme_mode"
    /** [Config.smsSearchDateRangeDays]のキー */
    private const val KEY_SMS_SEARCH_DATE_RANGE_DAYS = "sms_search_date_range_days"
    /** [Config.searchFiltersVisibleByDefault]のキー */
    private const val KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT = "search_filters_visible_by_default"
    /** [Config.defaultReplyBody]のキー */
    private const val KEY_DEFAULT_REPLY_BODY = "default_reply_body"
    /** [Config.splitFailedReplyAddition]のキー */
    private const val KEY_SPLIT_FAILED_REPLY_ADDITION = "split_failed_reply_addition"
    /** [Config.defaultSendTargetFilterId]のキー */
    private const val KEY_DEFAULT_SEND_TARGET_FILTER_ID = "default_send_target_filter_id"
    /** [Config.aiParsingEnabled]のキー */
    private const val KEY_AI_PARSING_ENABLED = "ai_parsing_enabled"
    /** [Config.defaultSendNoneOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SEND_NONE_ONLY_ENABLED = "default_send_none_only_enabled"
    /** [Config.defaultSplitFailedOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SPLIT_FAILED_ONLY_ENABLED = "default_split_failed_only_enabled"
    /** [Config.defaultSplitSucceededOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SPLIT_SUCCEEDED_ONLY_ENABLED = "default_split_succeeded_only_enabled"
    /** [Config.defaultSplitExcludedOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SPLIT_EXCLUDED_ONLY_ENABLED = "default_split_excluded_only_enabled"
    /** [Config.defaultSentAutoOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED = "default_sent_auto_only_enabled"
    /** [Config.defaultSentManualOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED = "default_sent_manual_only_enabled"

    /** [SendTarget]のリスト全体をJSON配列として保存するキー。[Config]とは別枠で[saveSendTargets]/[loadSendTargets]が読み書きする */
    private const val KEY_SEND_TARGETS = "send_targets"

    /** kintoneへの接続認証方式 */
    enum class AuthMethod {
        API_TOKEN,
        PASSWORD;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[SendTarget.newEmpty]と同じPASSWORDにフォールバックする */
            fun fromName(name: String?): AuthMethod =
                entries.firstOrNull { it.name == name } ?: PASSWORD
        }
    }

    /** 送信先の振り分け（[SendTarget.keywords]）の照合対象。[BODY]はSMS本文そのもの、[COMPANY_NAME]はそこから抽出した会社名 */
    enum class MatchTarget {
        BODY,
        COMPANY_NAME;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[SendTarget.matchTarget]の既定値と同じCOMPANY_NAMEにフォールバックする */
            fun fromName(name: String?): MatchTarget =
                entries.firstOrNull { it.name == name } ?: COMPANY_NAME
        }
    }

    /**
     * 既存レコードに追記するか新規登録するかを判定する条件（[SendTarget.updateToleranceHours]、
     * [KintoneApi.findExistingRecord]参照）。[SAME_DATE]は最終受信日時が端末の暦日で同じ既存レコードを
     * 対象にする。[HOURS]は[SendTarget.updateToleranceHours]で指定した時間以内の既存レコードを対象にする
     */
    enum class UpdateToleranceMode {
        SAME_DATE,
        HOURS;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[SendTarget.updateToleranceMode]の既定値と同じSAME_DATEにフォールバックする */
            fun fromName(name: String?): UpdateToleranceMode =
                entries.firstOrNull { it.name == name } ?: SAME_DATE
        }
    }

    /** アプリの配色モード */
    enum class ThemeMode {
        LIGHT,
        DARK;

        /** [AppCompatDelegate.setDefaultNightMode]に渡すモード値に変換する */
        fun toNightMode(): Int = when (this) {
            LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[DEFAULT_CONFIG]と同じLIGHTにフォールバックする */
            fun fromName(name: String?): ThemeMode =
                entries.firstOrNull { it.name == name } ?: LIGHT
        }
    }

    /**
     * 継続SMS（[SmsResolution.isContinuation]）の引き継ぎを、送信元ごとにどこまで遡って有効とするか。
     * [UNLIMITED]は日付を問わず過去に一度でも形式正常なSMSがあれば常に引き継ぐ。[SAME_DAY]は
     * 引き継ぎ元のSMSと暦日が同じ場合のみ有効とし、日付が変わると引き継ぎがリセットされる
     */
    enum class ContinuationScope {
        UNLIMITED,
        SAME_DAY;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[DEFAULT_CONFIG]と同じSAME_DAYにフォールバックする */
            fun fromName(name: String?): ContinuationScope =
                entries.firstOrNull { it.name == name } ?: SAME_DAY
        }
    }

    /** アプリ全体の設定（kintoneへの接続設定は含まない。接続設定は[SendTarget]を参照） */
    data class Config(
        /** trueなら自動送信モード、falseなら手動送信モード（[KintoneUploadWorker]が参照） */
        val sendEnabled: Boolean,
        /** 自動送信時、本文の形式が異常なSMS（会社名・氏名・内容に分割できなかったSMS）も送信するかどうか */
        val sendSplitFailedEnabled: Boolean,
        /** 自動送信時、形式が除外（継続SMS、[SmsResolution.isContinuation]）のSMSも送信するかどうか */
        val sendSplitExcludedEnabled: Boolean,
        /** SMS検索画面で、本文の形式が異常なSMSを選択可能にするかどうか */
        val searchSplitFailedEnabled: Boolean,
        /** SMS検索画面で、形式が除外（継続SMS、[SmsResolution.isContinuation]）のSMSを選択可能にするかどうか */
        val searchSplitExcludedEnabled: Boolean,
        /** SMS検索画面で、送信先が未設定（一致する送信先が無い、または不正）のSMSを選択可能にするかどうか */
        val searchSendTargetUnconfiguredEnabled: Boolean,
        /** 自動受信時、本文の形式が異常なSMSに対して[splitFailedReplyAddition]の文言でSMSへ自動返信するかどうか */
        val autoReplySplitFailedEnabled: Boolean,
        /** 同一の送信元への自動返信を再送信するまでの間隔（秒）。連投を防ぐためのクールダウン */
        val autoReplyCooldownSeconds: Int,
        /** SMS送信履歴画面（[LogActivity]）を[autoRefreshIntervalSeconds]間隔で自動再読み込みするかどうか */
        val autoRefreshEnabled: Boolean,
        /** [autoRefreshEnabled]が有効な場合の自動再読み込み間隔（秒） */
        val autoRefreshIntervalSeconds: Int,
        /** 自動受信SMSのログと端末上のSMSを突き合わせる際の許容範囲（秒） */
        val smsMatchToleranceSeconds: Int,
        /** 継続SMSの引き継ぎ（[SmsResolution.isContinuation]）機能自体を有効にするかどうか */
        val continuationEnabled: Boolean,
        /** 継続SMSの引き継ぎ（[SmsResolution.isContinuation]）を送信元ごとにどこまで遡って有効とするか */
        val continuationScope: ContinuationScope,
        /** アプリの配色モード */
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
        /** SMS検索画面を開いた際に「形式」の「異常」チェックボックスを初期状態でONにするかどうか */
        val defaultSplitFailedOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「形式」の「正常」チェックボックスを初期状態でONにするかどうか */
        val defaultSplitSucceededOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「形式」の「除外」チェックボックスを初期状態でONにするかどうか */
        val defaultSplitExcludedOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（自動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentAutoOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（手動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentManualOnlyEnabled: Boolean
    )

    /**
     * kintoneへの接続設定の1送信先。[matchTarget]で指定した対象に[keywords]のいずれかが
     * 含まれる場合にこの送信先が使われる（[SettingsStore.resolveSendTargets]参照）。
     * [keywords]が空の場合はどの送信先にも一致しなかった時のフォールバックとして扱われる。
     */
    data class SendTarget(
        /** 送信先を一意に識別するID（UUID文字列） */
        val id: String,
        /** 表示名。空の場合は[displayName]がフォールバック文字列を返す */
        val name: String,
        /** 振り分け条件のキーワード（カンマまたは改行区切り）。分割済みリストは[keywordList]を参照 */
        val keywords: String,
        /** kintoneのサブドメイン（https://{subdomain}.cybozu.com のホスト名部分） */
        val subdomain: String,
        /** kintoneアプリのID */
        val appId: String,
        /** kintoneへの接続認証方式 */
        val authMethod: AuthMethod,
        /** APIトークン認証（[AuthMethod.API_TOKEN]）時に使う値。パスワード認証時は未使用 */
        val apiToken: String,
        /** パスワード認証（[AuthMethod.PASSWORD]）時に使うログイン名。APIトークン認証時は未使用 */
        val loginName: String,
        /** パスワード認証（[AuthMethod.PASSWORD]）時に使うパスワード。APIトークン認証時は未使用 */
        val loginPassword: String,
        /** 送信元電話番号を書き込むkintoneフィールドのフィールドコード */
        val fieldSender: String,
        /** 本文を書き込むkintoneフィールドのフィールドコード */
        val fieldBody: String,
        /** 最終受信日時を書き込むkintoneフィールドのフィールドコード。既存レコード検索（[KintoneApi.findExistingRecord]）にも使う */
        val fieldDatetime: String,
        /** 登録種別（[AppConstants.REGISTRATION_TYPE_VALUE]）を書き込むkintoneフィールドのフィールドコード。既存レコード検索の絞り込みにも使う */
        val fieldType: String,
        /**
         * 同一送信元の既存レコードに追記するか新規登録するかを判定する許容時間（時間単位、[KintoneApi.postRecord]参照）。
         * [updateToleranceMode]が[UpdateToleranceMode.HOURS]の場合のみ使われる
         */
        val updateToleranceHours: Int,
        /** 同一送信元の既存レコードに追記するか新規登録するかを判定する条件 */
        val updateToleranceMode: UpdateToleranceMode = UpdateToleranceMode.SAME_DATE,
        /** 抽出した会社名を書き込むkintoneフィールドのフィールドコード。空なら書き込まない */
        val fieldCompanyName: String = "",
        /** 抽出した氏名を書き込むkintoneフィールドのフィールドコード。空なら書き込まない */
        val fieldUserName: String = "",
        /** 抽出した内容（用件）を書き込むkintoneフィールドのフィールドコード。空なら書き込まない */
        val fieldContent: String = "",
        /** kintoneへの送信時、会社名に[SmsParts.companyNameNormalizedWidth]（英数字は半角・それ以外は全角に統一した文字列）を使うかどうか。
         * falseの場合は[SmsParts.companyName]（変換なし）をそのまま使う */
        val companyNameWidthConversionEnabled: Boolean = false,
        /** [keywords]をSMS本文そのものと会社名（抽出結果）のどちらに対して照合するか */
        val matchTarget: MatchTarget = MatchTarget.COMPANY_NAME
    ) {
        /** [keywords]をカンマ・改行で分割し、前後の空白を除いた上で空要素を取り除いたリスト */
        val keywordList: List<String>
            get() = keywords.split(",", "\n").map { it.trim() }.filter { it.isNotEmpty() }

        /** [keywords]が未設定で、どの送信先にも一致しなかった場合のフォールバックとして扱われる送信先かどうか */
        val isDefault: Boolean
            get() = keywordList.isEmpty()

        /** 表示名が未設定の場合のフォールバック文字列を返す */
        fun displayName(context: Context): String =
            name.ifBlank { context.getString(R.string.label_send_target_name_unset) }

        /** kintoneへの送信に必要な項目（認証情報含む）が揃っているかどうか。[keywords]の有無や[fieldCompanyName]等の任意項目は問わない */
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
         * キーワード未設定でフォールバック用）は対象外とする。本番の振り分け（[SettingsStore.findSendTargets]）
         * とテスト送信プレビューで判定基準がずれないよう、一致判定は必ずこれを使うこと。
         */
        fun routesTo(body: String, companyName: String): Boolean = !isDefault && matches(body, companyName)

        /** [newEmpty]を提供するコンパニオンオブジェクト */
        companion object {
            /** 送信先を新規追加する際の初期値。フィールドコード等の既定値は[AppDefaults]を参照 */
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

    /** 設定の読み書きに使うSharedPreferencesインスタンスを取得する */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** [Config]をSharedPreferencesに保存する。送信先設定（[SendTarget]）は対象外で[saveSendTargets]を使うこと */
    fun save(context: Context, config: Config) {
        val editor = prefs(context).edit()
            .putBoolean(KEY_SEND_ENABLED, config.sendEnabled)
            .putBoolean(KEY_SEND_SPLIT_FAILED_ENABLED, config.sendSplitFailedEnabled)
            .putBoolean(KEY_SEND_SPLIT_EXCLUDED_ENABLED, config.sendSplitExcludedEnabled)
            .putBoolean(KEY_SEARCH_SPLIT_FAILED_ENABLED, config.searchSplitFailedEnabled)
            .putBoolean(KEY_SEARCH_SPLIT_EXCLUDED_ENABLED, config.searchSplitExcludedEnabled)
            .putBoolean(KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED, config.searchSendTargetUnconfiguredEnabled)
            .putBoolean(KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED, config.autoReplySplitFailedEnabled)
            .putInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, config.autoReplyCooldownSeconds)
            .putBoolean(KEY_AUTO_REFRESH_ENABLED, config.autoRefreshEnabled)
            .putInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, config.autoRefreshIntervalSeconds)
            .putInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, config.smsMatchToleranceSeconds)
            .putBoolean(KEY_CONTINUATION_ENABLED, config.continuationEnabled)
            .putString(KEY_CONTINUATION_SCOPE, config.continuationScope.name)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .putInt(KEY_SMS_SEARCH_DATE_RANGE_DAYS, config.smsSearchDateRangeDays)
            .putBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, config.searchFiltersVisibleByDefault)
            .putString(KEY_DEFAULT_REPLY_BODY, config.defaultReplyBody)
            .putString(KEY_SPLIT_FAILED_REPLY_ADDITION, config.splitFailedReplyAddition)
            .putBoolean(KEY_AI_PARSING_ENABLED, config.aiParsingEnabled)
            .putBoolean(KEY_DEFAULT_SEND_NONE_ONLY_ENABLED, config.defaultSendNoneOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SPLIT_FAILED_ONLY_ENABLED, config.defaultSplitFailedOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SPLIT_SUCCEEDED_ONLY_ENABLED, config.defaultSplitSucceededOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SPLIT_EXCLUDED_ONLY_ENABLED, config.defaultSplitExcludedOnlyEnabled)
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
        sendSplitExcludedEnabled = true,
        searchSplitFailedEnabled = false,
        searchSplitExcludedEnabled = false,
        searchSendTargetUnconfiguredEnabled = false,
        autoReplySplitFailedEnabled = false,
        autoReplyCooldownSeconds = AppDefaults.AUTO_REPLY_COOLDOWN_SECONDS,
        autoRefreshEnabled = true,
        autoRefreshIntervalSeconds = AppDefaults.AUTO_REFRESH_INTERVAL_SECONDS,
        smsMatchToleranceSeconds = AppDefaults.SMS_MATCH_TOLERANCE_SECONDS,
        continuationEnabled = true,
        continuationScope = ContinuationScope.SAME_DAY,
        themeMode = ThemeMode.LIGHT,
        smsSearchDateRangeDays = AppDefaults.SMS_SEARCH_DATE_RANGE_DAYS,
        searchFiltersVisibleByDefault = true,
        defaultReplyBody = AppDefaults.SMS_STANDARD_REPLY_BODY,
        splitFailedReplyAddition = AppDefaults.SMS_SPLIT_FAILED_REPLY_BODY,
        defaultSendTargetFilterId = null,
        aiParsingEnabled = false,
        defaultSendNoneOnlyEnabled = false,
        defaultSplitFailedOnlyEnabled = false,
        defaultSplitSucceededOnlyEnabled = false,
        defaultSplitExcludedOnlyEnabled = false,
        defaultSentAutoOnlyEnabled = false,
        defaultSentManualOnlyEnabled = false
    )

    /** [save]で保存した設定を読み込む。未保存のキーは[DEFAULT_CONFIG]の値で補う */
    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            sendEnabled = p.getBoolean(KEY_SEND_ENABLED, DEFAULT_CONFIG.sendEnabled),
            sendSplitFailedEnabled = p.getBoolean(KEY_SEND_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.sendSplitFailedEnabled),
            sendSplitExcludedEnabled = p.getBoolean(KEY_SEND_SPLIT_EXCLUDED_ENABLED, DEFAULT_CONFIG.sendSplitExcludedEnabled),
            searchSplitFailedEnabled = p.getBoolean(KEY_SEARCH_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.searchSplitFailedEnabled),
            searchSplitExcludedEnabled = p.getBoolean(KEY_SEARCH_SPLIT_EXCLUDED_ENABLED, DEFAULT_CONFIG.searchSplitExcludedEnabled),
            searchSendTargetUnconfiguredEnabled = p.getBoolean(
                KEY_SEARCH_SEND_TARGET_UNCONFIGURED_ENABLED,
                DEFAULT_CONFIG.searchSendTargetUnconfiguredEnabled
            ),
            autoReplySplitFailedEnabled = p.getBoolean(KEY_AUTO_REPLY_SPLIT_FAILED_ENABLED, DEFAULT_CONFIG.autoReplySplitFailedEnabled),
            autoReplyCooldownSeconds = p.getInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, DEFAULT_CONFIG.autoReplyCooldownSeconds),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, DEFAULT_CONFIG.autoRefreshEnabled),
            autoRefreshIntervalSeconds = p.getInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, DEFAULT_CONFIG.autoRefreshIntervalSeconds),
            smsMatchToleranceSeconds = p.getInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, DEFAULT_CONFIG.smsMatchToleranceSeconds),
            continuationEnabled = p.getBoolean(KEY_CONTINUATION_ENABLED, DEFAULT_CONFIG.continuationEnabled),
            continuationScope = ContinuationScope.fromName(p.getString(KEY_CONTINUATION_SCOPE, null)),
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
            defaultSplitSucceededOnlyEnabled = p.getBoolean(KEY_DEFAULT_SPLIT_SUCCEEDED_ONLY_ENABLED, DEFAULT_CONFIG.defaultSplitSucceededOnlyEnabled),
            defaultSplitExcludedOnlyEnabled = p.getBoolean(KEY_DEFAULT_SPLIT_EXCLUDED_ONLY_ENABLED, DEFAULT_CONFIG.defaultSplitExcludedOnlyEnabled),
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

    /** [SendTarget]のリストをJSON配列にシリアライズして保存する。読み込みは[loadSendTargets]を使うこと */
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
                    .put("updateToleranceMode", sendTarget.updateToleranceMode.name)
                    .put("fieldCompanyName", sendTarget.fieldCompanyName)
                    .put("fieldUserName", sendTarget.fieldUserName)
                    .put("fieldContent", sendTarget.fieldContent)
                    .put("companyNameWidthConversionEnabled", sendTarget.companyNameWidthConversionEnabled)
                    .put("matchTarget", sendTarget.matchTarget.name)
            )
        }
        prefs(context).edit().putString(KEY_SEND_TARGETS, array.toString()).apply()
    }

    /** [saveSendTargets]で保存した送信先設定を読み込む。未保存（初回起動など）の場合は[createDefaultSendTarget]で1件生成する */
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
                updateToleranceMode = UpdateToleranceMode.fromName(obj.optString("updateToleranceMode", "")),
                fieldCompanyName = obj.optString("fieldCompanyName", ""),
                fieldUserName = obj.optString("fieldUserName", ""),
                fieldContent = obj.optString("fieldContent", ""),
                companyNameWidthConversionEnabled = obj.optBoolean("companyNameWidthConversionEnabled", false),
                matchTarget = MatchTarget.fromName(obj.optString("matchTarget", ""))
            )
        }
    }

    /** 送信先が1件も保存されていない場合に、空の送信先を1件作成して保存する（[loadSendTargets]専用） */
    private fun createDefaultSendTarget(context: Context): List<SendTarget> {
        val sendTargets = listOf(SendTarget.newEmpty())
        saveSendTargets(context, sendTargets)
        return sendTargets
    }

    /**
     * キーワードが一致する送信先を（複数あれば）すべて返す。1件も一致しなければ、キーワード
     * 未設定（デフォルト）の送信先1件にフォールバックする。該当が無ければ空リスト。[resolveSendTargets]専用
     */
    private fun findSendTargets(context: Context, body: String, companyName: String): List<SendTarget> {
        val sendTargets = loadSendTargets(context)
        val matched = sendTargets.filter { it.routesTo(body, companyName) }
        if (matched.isNotEmpty()) return matched
        return listOfNotNull(sendTargets.firstOrNull { it.isDefault })
    }

    /**
     * [resolveSendTargets]の結果。[SmsParts]は本文からの抽出結果のみを表すため、それが継続SMS
     * （同一送信元の過去の正常なSMSからの引き継ぎ）によるものかどうかという振り分け固有のメタ情報は
     * ここで別に持つ。[SmsSearchActivity]など[SmsLogStore.Entry]を経由せず端末上のSMSをその場で
     * 解決する画面でも必要なため、[SmsLogStore.Entry]側だけに寄せることはできない
     */
    data class SmsResolution(
        /** 本文から抽出した会社名・氏名・内容 */
        val smsParts: SmsParts,
        /**
         * 同一送信元が過去に一度でも形式正常なSMSを送っていたため、その直近1件から会社名・氏名と
         * 送信先を引き継いだ結果かどうか。今回の本文自体が単独で解析できるかどうかは問わない。
         * trueの場合、形式・送信先のアイコン表示は通常の⭕/❌・📍/🚫ではなく専用のアイコンに切り替える
         */
        val isContinuation: Boolean = false,
        /**
         * [isContinuation]がtrueの場合の、引き継ぎ元エントリの送信先表示名（[SmsLogStore.Entry.sendTargetName]）。
         * 引き継ぎ元の送信先がその後削除・変更されて現在の設定から解決できなくなった場合の表示用フォールバック
         */
        val inheritedSendTargetName: String? = null
    )

    /**
     * SMS本文から[SmsParts]を抽出し、対応する送信先（複数一致し得る）を判定する。抽出結果と
     * 送信先判定の両方が必要な箇所（kintone登録・受信ログ記録・SMS検索画面・テスト送信など）は、
     * 抽出方法（ルールベース／AI）のずれで登録内容と振り分け結果が食い違わないよう必ずこれを使うこと。
     *
     * [continuationEnabled]がtrueの場合、[sender]と同じ送信元から過去に一度でも形式正常なSMS
     * （[SmsLogStore.findLatestValidEntry]、[continuationScope]が[ContinuationScope.UNLIMITED]なら
     * 日付は問わない）が届いていれば、今回のSMS自体の形式（本文単体で解析できるかどうか）に関わらず、
     * 常にその直近1件から会社名・氏名・送信先を引き継ぐ（内容は今回の本文そのもの）。一度識別できた
     * 送信元は[continuationScope]の範囲内でずっと同じ会社名・氏名・送信先として扱う（例:
     * 「NTTデータ／石田直樹／腹痛です」の後に届いた「とても痛いです」を同一人物の追加内容として扱う）。
     * [continuationEnabled]がfalse、または該当する過去のSMSが無い送信元は、今回の本文を実際に
     * 解析して振り分ける
     */
    suspend fun resolveSendTargets(
        context: Context,
        sender: String,
        body: String,
        timestampMillis: Long,
        aiParsingEnabled: Boolean,
        continuationEnabled: Boolean,
        continuationScope: ContinuationScope
    ): Pair<SmsResolution, List<SendTarget>> {
        val previousEntry = if (continuationEnabled) {
            SmsLogStore.findLatestValidEntry(context, sender, timestampMillis, sameDayOnly = continuationScope == ContinuationScope.SAME_DAY)
        } else {
            null
        }
        val previousParts = previousEntry?.smsParts
        if (previousEntry != null && previousParts != null) {
            val smsParts = SmsParts(
                companyName = previousParts.companyName,
                userName = previousParts.userName,
                content = body.trim()
            )
            val resolution = SmsResolution(
                smsParts = smsParts,
                isContinuation = true,
                inheritedSendTargetName = previousEntry.sendTargetName
            )
            // 送信先も本文からのキーワード一致では再現できないため、前回の判定結果をそのまま引き継ぐ
            val sendTargets = loadSendTargets(context).filter { it.id in previousEntry.sendTargetIds }
            return resolution to sendTargets
        }
        val extracted = SmsPartsGenerator.resolveSmsParts(body, aiParsingEnabled)
        return SmsResolution(smsParts = extracted) to findSendTargets(context, body, extracted.companyName)
    }
}

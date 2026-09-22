package com.ssfrontier.smstokintone

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

/**
 * アプリ全体の設定と送信先設定を SharedPreferences で永続化・管理。
 * [Config] でアプリ全体の動作制御、[SendTarget] で個別の Kintone 連携設定を保持。
 */
object SettingsStore {

    private const val PREFS_NAME = "smstokintone_prefs"

    private const val KEY_SEND_ENABLED = "send_enabled"
    private const val KEY_SEND_EXTRACTION_FAILED_ENABLED = "send_extraction_failed_enabled"
    private const val KEY_SEND_EXTRACTION_CONTINUATION_ENABLED = "send_extraction_continuation_enabled"
    private const val KEY_SEARCH_EXTRACTION_FAILED_ENABLED = "search_extraction_failed_enabled"
    private const val KEY_SEARCH_EXTRACTION_CONTINUATION_ENABLED = "search_extraction_continuation_enabled"
    private const val KEY_REPLY_ENABLED = "reply_enabled"
    private const val KEY_REPLY_COOLDOWN_SECONDS = "reply_cooldown_seconds"
    private const val KEY_LOG_REFRESH_ENABLED = "log_refresh_enabled"
    private const val KEY_LOG_REFRESH_INTERVAL_SECONDS = "log_refresh_interval_seconds"
    private const val KEY_LOG_MATCH_TOLERANCE_SECONDS = "log_match_tolerance_seconds"
    private const val KEY_LOG_BODY_EXCERPT_LENGTH = "log_body_excerpt_length"
    private const val KEY_CONTINUATION_ENABLED = "continuation_enabled"
    private const val KEY_CONTINUATION_SCOPE = "continuation_scope"
    private const val KEY_CONTINUATION_SHOW_USER_NAME_ENABLED = "continuation_show_user_name_enabled"
    private const val KEY_THEME_MODE = "theme_mode"
    private const val KEY_SEARCH_DATE_RANGE_DAYS = "search_date_range_days"
    private const val KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT = "search_filters_visible_by_default"
    private const val KEY_REPLY_SUCCESS_BODY = "reply_success_body"
    private const val KEY_REPLY_FAILED_BODY = "reply_failed_body"
    private const val KEY_SEARCH_SEND_TARGET_FILTER_NAME = "search_send_target_filter_name"
    private const val KEY_EXTRACTION_AI_ENABLED = "extraction_ai_enabled"
    private const val KEY_EXTRACTION_COMPANY_NAME_ENABLED = "extraction_company_name_enabled"
    private const val KEY_EXTRACTION_COMPANY_NAME_AUTO_CONVERSION_ENABLED = "extraction_company_name_auto_conversion_enabled"
    private const val KEY_EXTRACTION_COMPANY_NAME_FIXED_CONVERSIONS = "extraction_company_name_fixed_conversions"
    private const val KEY_SEARCH_SEND_NONE_ONLY_ENABLED = "search_send_none_only_enabled"
    private const val KEY_SEARCH_EXTRACTION_FAILED_ONLY_ENABLED = "search_extraction_failed_only_enabled"
    private const val KEY_SEARCH_EXTRACTION_SUCCEEDED_ONLY_ENABLED = "search_extraction_succeeded_only_enabled"
    private const val KEY_SEARCH_EXTRACTION_CONTINUATION_ONLY_ENABLED = "search_extraction_continuation_only_enabled"
    private const val KEY_SEARCH_SENT_AUTO_ONLY_ENABLED = "search_sent_auto_only_enabled"
    private const val KEY_SEARCH_SENT_MANUAL_ONLY_ENABLED = "search_sent_manual_only_enabled"

    private const val KEY_SEND_TARGETS = "send_targets"

    /**
     * 既存レコード判定時の日時許容範囲の定義方法。[KintoneApi.findExistingRecord] で使用。
     *
     * [SAME_DATE]: 最終受信日時が端末の暦日で同じ既存レコードを対象。
     * [HOURS]: [SendTarget.updateToleranceHours] で指定した時間以内の既存レコードを対象。
     */
    enum class UpdateToleranceMode {
        /** 暦日で判定（最終受信日が同じ日）。 */
        SAME_DATE,
        /** 時間差で判定（[SendTarget.updateToleranceHours] 以内）。 */
        HOURS;

        /** 保存値からの復元用ファクトリ。 */
        companion object {
            /** 保存値から復元。未知の値は [SAME_DATE] にデフォルト。 */
            fun fromName(name: String?): UpdateToleranceMode =
                entries.firstOrNull { it.name == name } ?: SAME_DATE
        }
    }

    /**
     * 固定変換ルール1行（[Config.extractionCompanyNameFixedConversions] の要素）。
     * [from] に一致する部分文字列を [to] に置換。
     */
    data class FixedConversion(
        /** 変換前の文字列（パターン）。 */
        val from: String = "",
        /** 変換後の文字列。 */
        val to: String = ""
    )

    /** アプリの配色モード。 */
    enum class ThemeMode {
        /** ライトテーマ（昼間）。 */
        LIGHT,
        /** ダークテーマ（夜間）。 */
        DARK;

        /** [AppCompatDelegate.setDefaultNightMode] に渡すモード値に変換。 */
        fun toNightMode(): Int = when (this) {
            LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }

        /** 保存値からの復元用ファクトリ。 */
        companion object {
            /** 保存値から復元。未知の値は [LIGHT] にデフォルト。 */
            fun fromName(name: String?): ThemeMode =
                entries.firstOrNull { it.name == name } ?: LIGHT
        }
    }

    /**
     * 継続SMS の引継ぎ有効範囲。送信元ごとにどこまで遡って継続を認めるか。
     *
     * [UNLIMITED]: 日付を問わず、過去に一度でも正常に抽出されたら常に引き継ぐ。
     * [SAME_DAY]: 引継ぎ元と暦日が同じ場合のみ引継ぎ有効。日付が変わるとリセット。
     */
    enum class ContinuationScope {
        /** 期限なし（無制限に過去へ遡る）。 */
        UNLIMITED,
        /** 同日のみ有効（日付が変わるとリセット）。 */
        SAME_DAY;

        /** 保存値からの復元用ファクトリ。 */
        companion object {
            /** 保存値から復元。未知の値は [UNLIMITED] にデフォルト。 */
            fun fromName(name: String?): ContinuationScope =
                entries.firstOrNull { it.name == name } ?: UNLIMITED
        }
    }

    /**
     * アプリ全体の設定。kintoneへの接続設定は含まない（接続設定は[SendTarget]を参照）。
     *
     * @property sendEnabled trueなら自動送信モード、falseなら手動送信モード。[KintoneUploadWorker]が参照
     * @property sendExtractionFailedEnabled 自動送信時、抽出失敗のSMS（会社名・氏名を抽出できなかったSMS）も送信するかどうか
     * @property sendExtractionContinuationEnabled 自動送信時、抽出引継ぎ（継続SMS、[SmsResolution.isContinuation]）のSMSも送信するかどうか
     * @property searchExtractionFailedEnabled SMS検索画面で、抽出失敗のSMSを選択可能にするかどうか
     * @property searchExtractionContinuationEnabled SMS検索画面で、抽出引継ぎ（継続SMS、[SmsResolution.isContinuation]）のSMSを選択可能にするかどうか
     * @property replyEnabled 自動受信時、抽出失敗のSMSに対して[replyFailedBody]の文言で自動返信するかどうか
     * @property replyCooldownSeconds 同一送信元への自動返信再送信までの間隔（秒）。連投防止用クールダウン
     * @property logRefreshEnabled SMS送信履歴画面（[LogActivity]）を[logRefreshIntervalSeconds]間隔で自動再読み込みするかどうか
     * @property logRefreshIntervalSeconds 自動再読み込み間隔（秒）。[logRefreshEnabled]が有効な場合に使用
     * @property logMatchToleranceSeconds 自動受信SMSのログと端末上のSMSを突き合わせる際の許容範囲（秒）
     * @property logBodyExcerptLength ログ一覧（[LogActivity]）に表示する本文抜粋（[SmsLogStore.Entry.bodyExcerpt]）の文字数
     * @property continuationEnabled 継続SMSの引継ぎ（[SmsResolution.isContinuation]）機能全体の有効/無効
     * @property continuationScope 継続SMSの引継ぎを送信元ごとにどこまで遡って有効とするか
     * @property continuationShowUserNameEnabled SMS検索画面・ログ画面で、継続SMSの場合は送信元電話番号の代わりに引き継いだ氏名を表示するかどうか
     * @property themeMode アプリの配色モード（ライト/ダーク）
     * @property searchDateRangeDays SMS検索画面を開いた際に検索条件へ初期設定する日付範囲（日）
     * @property searchFiltersVisibleByDefault SMS検索画面を開いた際に検索条件エリアを表示した状態にするかどうか
     * @property replySuccessBody SMS検索画面で長押しした際に開く返信画面に自動入力する文言
     * @property replyFailedBody 抽出失敗のSMSへの返信時に使う文言。[replySuccessBody]の代わり
     * @property searchSendTargetFilterName SMS検索画面の「送信先」フィルタの初期値。nullは「すべて」、[AppConstants.SEND_TARGET_FILTER_KEY_UNSET]は「未設定」
     * @property extractionAiEnabled 本文からの会社名・氏名の抽出に端末上のAI（ML Kit GenAI / Gemini Nano）を使うかどうか。非対応端末は自動フォールバック
     * @property extractionCompanyNameEnabled 本文からの会社名・氏名の抽出機能全体の有効/無効
     * @property extractionCompanyNameAutoConversionEnabled 抽出結果の会社名に、英数字は半角大文字・それ以外は全角に統一する変換を適用するかどうか。[resolveSendTargets]で抽出直後に適用
     * @property extractionCompanyNameFixedConversions 抽出結果の会社名に適用する固定変換ルール。[FixedConversion.from]に一致する部分を[FixedConversion.to]に置換。[extractionCompanyNameAutoConversionEnabled]の後に適用
     * @property searchSendNoneOnlyEnabled SMS検索画面で「送信」の「未」チェックボックスの初期状態
     * @property searchExtractionFailedOnlyEnabled SMS検索画面で「抽出状況」の「異常」チェックボックスの初期状態
     * @property searchExtractionSucceededOnlyEnabled SMS検索画面で「抽出状況」の「正常」チェックボックスの初期状態
     * @property searchExtractionContinuationOnlyEnabled SMS検索画面で「抽出状況」の「引継ぎ」チェックボックスの初期状態
     * @property searchSentAutoOnlyEnabled SMS検索画面で「送信」の「済（自動）」チェックボックスの初期状態
     * @property searchSentManualOnlyEnabled SMS検索画面で「送信」の「済（手動）」チェックボックスの初期状態
     */
    data class Config(
        val sendEnabled: Boolean,
        val sendExtractionFailedEnabled: Boolean,
        val sendExtractionContinuationEnabled: Boolean,
        val searchExtractionFailedEnabled: Boolean,
        val searchExtractionContinuationEnabled: Boolean,
        val replyEnabled: Boolean,
        val replyCooldownSeconds: Int,
        val logRefreshEnabled: Boolean,
        val logRefreshIntervalSeconds: Int,
        val logMatchToleranceSeconds: Int,
        val logBodyExcerptLength: Int,
        val continuationEnabled: Boolean,
        val continuationScope: ContinuationScope,
        val continuationShowUserNameEnabled: Boolean,
        val themeMode: ThemeMode,
        val searchDateRangeDays: Int,
        val searchFiltersVisibleByDefault: Boolean,
        val replySuccessBody: String,
        val replyFailedBody: String,
        val searchSendTargetFilterName: String?,
        val extractionAiEnabled: Boolean,
        val extractionCompanyNameEnabled: Boolean,
        val extractionCompanyNameAutoConversionEnabled: Boolean = true,
        val extractionCompanyNameFixedConversions: List<FixedConversion> = emptyList(),
        val searchSendNoneOnlyEnabled: Boolean,
        val searchExtractionFailedOnlyEnabled: Boolean,
        val searchExtractionSucceededOnlyEnabled: Boolean,
        val searchExtractionContinuationOnlyEnabled: Boolean,
        val searchSentAutoOnlyEnabled: Boolean,
        val searchSentManualOnlyEnabled: Boolean
    )

    /**
     * kintoneへの接続設定の1送信先。会社名に[keywords]のいずれかが含まれる場合にこの送信先が
     * 使われる（[SettingsStore.resolveSendTargets]参照）。
     * [keywords]が空の場合はどの送信先にも一致しなかった時のフォールバックとして扱われる。
     */
    data class SendTarget(
        /** 送信先を一意に識別するID（UUID文字列） */
        val id: String,
        /** 表示名。空の場合は[displayName]がフォールバック文字列を返す */
        val name: String,
        val companyName: String = "",
        /** 振り分け条件のキーワード。行ごとに1件、UI上で追加・削除できる */
        val keywords: List<String>,
        /** kintoneのサブドメイン（https://{subdomain}.cybozu.com のホスト名部分） */
        val subdomain: String,
        /** kintoneアプリのID */
        val appId: String,
        /** パスワード認証（kintoneのログイン名とパスワード）でkintoneへ接続する */
        val loginName: String,
        /** パスワード認証で使うkintoneのパスワード */
        val loginPassword: String,
        /** 送信元電話番号を書き込むkintoneフィールドのフィールドコード */
        val fieldSender: String,
        /** 本文（統合範囲内で複数件が連結される場合は履歴として蓄積される）を書き込むkintoneフィールドのフィールドコード */
        val fieldHistory: String,
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
        /** SMS本文全体（原文、[SmsParts.body]）を書き込むkintoneフィールドのフィールドコード。空なら書き込まない */
        val fieldBody: String = ""
    ) {
        /** [keywords]が未設定で、どの送信先にも一致しなかった場合のフォールバックとして扱われる送信先かどうか */
        val isDefault: Boolean
            get() = keywords.isEmpty()

        /** 表示名が未設定の場合のフォールバック文字列を返す */
        fun displayName(context: Context): String =
            name.ifBlank { context.getString(R.string.label_send_target_name_unset) }

        /** kintoneへの送信に必要な項目（認証情報含む）が揃っているかどうか。[keywords]の有無や[fieldCompanyName]等の任意項目は問わない */
        val isValid: Boolean
            get() {
                if (name.isBlank() || subdomain.isBlank() || appId.isBlank()) return false
                if (fieldSender.isBlank() || fieldHistory.isBlank() || fieldDatetime.isBlank() || fieldType.isBlank()) return false
                return loginName.isNotBlank() && loginPassword.isNotBlank()
            }

        /**
         * 会社名を[keywords]と照合する。呼び出し元（[resolveSendTargets]）が渡す時点で、既にアプリ全体の
         * 会社名変換（[Config.extractionCompanyNameAutoConversionEnabled]・[Config.extractionCompanyNameFixedConversions]）が
         * 適用済みであることを前提とする
         */
        fun matches(companyName: String): Boolean = keywords.any { TextNormalization.matches(companyName, it) }

        /**
         * キーワード一致でこの送信先に実際に振り分けられるかどうか。デフォルト送信先（[isDefault]、
         * キーワード未設定でフォールバック用）は対象外とする。本番の振り分け（[SettingsStore.findSendTargets]）
         * とテスト送信プレビューで判定基準がずれないよう、一致判定は必ずこれを使うこと。
         */
        fun routesTo(companyName: String): Boolean = !isDefault && matches(companyName)

        /** [newEmpty]を提供するコンパニオンオブジェクト */
        companion object {
            /** 送信先を新規追加する際の初期値。フィールドコード等の既定値は[AppDefaults]を参照 */
            fun newEmpty(): SendTarget = SendTarget(
                id = UUID.randomUUID().toString(),
                name = "",
                keywords = emptyList(),
                subdomain = AppDefaults.NEW_PROFILE_SUBDOMAIN,
                appId = "",
                loginName = "",
                loginPassword = "",
                fieldSender = AppDefaults.NEW_PROFILE_FIELD_SENDER,
                fieldHistory = AppDefaults.NEW_PROFILE_FIELD_HISTORY,
                fieldDatetime = AppDefaults.NEW_PROFILE_FIELD_DATETIME,
                fieldType = AppDefaults.NEW_PROFILE_FIELD_TYPE,
                updateToleranceHours = AppDefaults.UPDATE_TOLERANCE_HOURS,
                fieldCompanyName = AppDefaults.NEW_PROFILE_FIELD_COMPANY_NAME,
                fieldUserName = AppDefaults.NEW_PROFILE_FIELD_USER_NAME,
                fieldBody = AppDefaults.NEW_PROFILE_FIELD_BODY
            )
        }
    }

    /** 設定の読み書きに使うSharedPreferencesインスタンスを取得する */
    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** [Config]をSharedPreferencesに保存 */
    fun save(context: Context, config: Config) {
        val editor = prefs(context).edit()
            .putBoolean(KEY_SEND_ENABLED, config.sendEnabled)
            .putBoolean(KEY_SEND_EXTRACTION_FAILED_ENABLED, config.sendExtractionFailedEnabled)
            .putBoolean(KEY_SEND_EXTRACTION_CONTINUATION_ENABLED, config.sendExtractionContinuationEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_FAILED_ENABLED, config.searchExtractionFailedEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_CONTINUATION_ENABLED, config.searchExtractionContinuationEnabled)
            .putBoolean(KEY_REPLY_ENABLED, config.replyEnabled)
            .putInt(KEY_REPLY_COOLDOWN_SECONDS, config.replyCooldownSeconds)
            .putBoolean(KEY_LOG_REFRESH_ENABLED, config.logRefreshEnabled)
            .putInt(KEY_LOG_REFRESH_INTERVAL_SECONDS, config.logRefreshIntervalSeconds)
            .putInt(KEY_LOG_MATCH_TOLERANCE_SECONDS, config.logMatchToleranceSeconds)
            .putInt(KEY_LOG_BODY_EXCERPT_LENGTH, config.logBodyExcerptLength)
            .putBoolean(KEY_CONTINUATION_ENABLED, config.continuationEnabled)
            .putString(KEY_CONTINUATION_SCOPE, config.continuationScope.name)
            .putBoolean(KEY_CONTINUATION_SHOW_USER_NAME_ENABLED, config.continuationShowUserNameEnabled)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .putInt(KEY_SEARCH_DATE_RANGE_DAYS, config.searchDateRangeDays)
            .putBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, config.searchFiltersVisibleByDefault)
            .putString(KEY_REPLY_SUCCESS_BODY, config.replySuccessBody)
            .putString(KEY_REPLY_FAILED_BODY, config.replyFailedBody)
            .putBoolean(KEY_EXTRACTION_AI_ENABLED, config.extractionAiEnabled)
            .putBoolean(KEY_EXTRACTION_COMPANY_NAME_ENABLED, config.extractionCompanyNameEnabled)
            .putBoolean(KEY_EXTRACTION_COMPANY_NAME_AUTO_CONVERSION_ENABLED, config.extractionCompanyNameAutoConversionEnabled)
            .putString(
                KEY_EXTRACTION_COMPANY_NAME_FIXED_CONVERSIONS,
                JSONArray().apply {
                    config.extractionCompanyNameFixedConversions.forEach { rule ->
                        put(JSONObject().put("from", rule.from).put("to", rule.to))
                    }
                }.toString()
            )
            .putBoolean(KEY_SEARCH_SEND_NONE_ONLY_ENABLED, config.searchSendNoneOnlyEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_FAILED_ONLY_ENABLED, config.searchExtractionFailedOnlyEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_SUCCEEDED_ONLY_ENABLED, config.searchExtractionSucceededOnlyEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_CONTINUATION_ONLY_ENABLED, config.searchExtractionContinuationOnlyEnabled)
            .putBoolean(KEY_SEARCH_SENT_AUTO_ONLY_ENABLED, config.searchSentAutoOnlyEnabled)
            .putBoolean(KEY_SEARCH_SENT_MANUAL_ONLY_ENABLED, config.searchSentManualOnlyEnabled)
        if (config.searchSendTargetFilterName != null) {
            editor.putString(KEY_SEARCH_SEND_TARGET_FILTER_NAME, config.searchSendTargetFilterName)
        } else {
            editor.remove(KEY_SEARCH_SEND_TARGET_FILTER_NAME)
        }
        editor.apply()
    }

    /** [Config]の既定値（[load]と[resetToDefaults]で共用） */
    private val DEFAULT_CONFIG = Config(
        sendEnabled = true,
        sendExtractionFailedEnabled = false,
        sendExtractionContinuationEnabled = true,
        searchExtractionFailedEnabled = false,
        searchExtractionContinuationEnabled = true,
        replyEnabled = false,
        replyCooldownSeconds = AppDefaults.REPLY_COOLDOWN_SECONDS,
        logRefreshEnabled = true,
        logRefreshIntervalSeconds = AppDefaults.LOG_REFRESH_INTERVAL_SECONDS,
        logMatchToleranceSeconds = AppDefaults.LOG_MATCH_TOLERANCE_SECONDS,
        logBodyExcerptLength = AppDefaults.LOG_BODY_EXCERPT_LENGTH,
        continuationEnabled = true,
        continuationScope = ContinuationScope.UNLIMITED,
        continuationShowUserNameEnabled = true,
        themeMode = ThemeMode.LIGHT,
        searchDateRangeDays = AppDefaults.SEARCH_DATE_RANGE_DAYS,
        searchFiltersVisibleByDefault = true,
        replySuccessBody = AppDefaults.REPLY_SUCCESS_BODY,
        replyFailedBody = AppDefaults.REPLY_FAILED_BODY,
        searchSendTargetFilterName = null,
        extractionAiEnabled = false,
        extractionCompanyNameEnabled = true,
        extractionCompanyNameAutoConversionEnabled = true,
        extractionCompanyNameFixedConversions = emptyList(),
        searchSendNoneOnlyEnabled = false,
        searchExtractionFailedOnlyEnabled = false,
        searchExtractionSucceededOnlyEnabled = false,
        searchExtractionContinuationOnlyEnabled = false,
        searchSentAutoOnlyEnabled = false,
        searchSentManualOnlyEnabled = false
    )

    /** 保存済みの設定を読み込む */
    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            sendEnabled = p.getBoolean(KEY_SEND_ENABLED, DEFAULT_CONFIG.sendEnabled),
            sendExtractionFailedEnabled = p.getBoolean(KEY_SEND_EXTRACTION_FAILED_ENABLED, DEFAULT_CONFIG.sendExtractionFailedEnabled),
            sendExtractionContinuationEnabled = p.getBoolean(KEY_SEND_EXTRACTION_CONTINUATION_ENABLED, DEFAULT_CONFIG.sendExtractionContinuationEnabled),
            searchExtractionFailedEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_FAILED_ENABLED, DEFAULT_CONFIG.searchExtractionFailedEnabled),
            searchExtractionContinuationEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_CONTINUATION_ENABLED, DEFAULT_CONFIG.searchExtractionContinuationEnabled),
            replyEnabled = p.getBoolean(KEY_REPLY_ENABLED, DEFAULT_CONFIG.replyEnabled),
            replyCooldownSeconds = p.getInt(KEY_REPLY_COOLDOWN_SECONDS, DEFAULT_CONFIG.replyCooldownSeconds),
            logRefreshEnabled = p.getBoolean(KEY_LOG_REFRESH_ENABLED, DEFAULT_CONFIG.logRefreshEnabled),
            logRefreshIntervalSeconds = p.getInt(KEY_LOG_REFRESH_INTERVAL_SECONDS, DEFAULT_CONFIG.logRefreshIntervalSeconds),
            logMatchToleranceSeconds = p.getInt(KEY_LOG_MATCH_TOLERANCE_SECONDS, DEFAULT_CONFIG.logMatchToleranceSeconds),
            logBodyExcerptLength = p.getInt(KEY_LOG_BODY_EXCERPT_LENGTH, DEFAULT_CONFIG.logBodyExcerptLength),
            continuationEnabled = p.getBoolean(KEY_CONTINUATION_ENABLED, DEFAULT_CONFIG.continuationEnabled),
            continuationScope = ContinuationScope.fromName(p.getString(KEY_CONTINUATION_SCOPE, null)),
            continuationShowUserNameEnabled = p.getBoolean(KEY_CONTINUATION_SHOW_USER_NAME_ENABLED, DEFAULT_CONFIG.continuationShowUserNameEnabled),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null)),
            searchDateRangeDays = p.getInt(KEY_SEARCH_DATE_RANGE_DAYS, DEFAULT_CONFIG.searchDateRangeDays),
            searchFiltersVisibleByDefault = p.getBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, DEFAULT_CONFIG.searchFiltersVisibleByDefault),
            replySuccessBody = p.getString(KEY_REPLY_SUCCESS_BODY, DEFAULT_CONFIG.replySuccessBody) ?: DEFAULT_CONFIG.replySuccessBody,
            replyFailedBody = p.getString(KEY_REPLY_FAILED_BODY, DEFAULT_CONFIG.replyFailedBody)
                ?: DEFAULT_CONFIG.replyFailedBody,
            searchSendTargetFilterName = p.getString(KEY_SEARCH_SEND_TARGET_FILTER_NAME, DEFAULT_CONFIG.searchSendTargetFilterName),
            extractionAiEnabled = p.getBoolean(KEY_EXTRACTION_AI_ENABLED, DEFAULT_CONFIG.extractionAiEnabled),
            extractionCompanyNameEnabled = p.getBoolean(KEY_EXTRACTION_COMPANY_NAME_ENABLED, DEFAULT_CONFIG.extractionCompanyNameEnabled),
            extractionCompanyNameAutoConversionEnabled = p.getBoolean(KEY_EXTRACTION_COMPANY_NAME_AUTO_CONVERSION_ENABLED, DEFAULT_CONFIG.extractionCompanyNameAutoConversionEnabled),
            extractionCompanyNameFixedConversions = p.getString(KEY_EXTRACTION_COMPANY_NAME_FIXED_CONVERSIONS, null)?.let { json ->
                val arr = JSONArray(json)
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    FixedConversion(from = obj.optString("from", ""), to = obj.optString("to", ""))
                }
            } ?: DEFAULT_CONFIG.extractionCompanyNameFixedConversions,
            searchSendNoneOnlyEnabled = p.getBoolean(KEY_SEARCH_SEND_NONE_ONLY_ENABLED, DEFAULT_CONFIG.searchSendNoneOnlyEnabled),
            searchExtractionFailedOnlyEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_FAILED_ONLY_ENABLED, DEFAULT_CONFIG.searchExtractionFailedOnlyEnabled),
            searchExtractionSucceededOnlyEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_SUCCEEDED_ONLY_ENABLED, DEFAULT_CONFIG.searchExtractionSucceededOnlyEnabled),
            searchExtractionContinuationOnlyEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_CONTINUATION_ONLY_ENABLED, DEFAULT_CONFIG.searchExtractionContinuationOnlyEnabled),
            searchSentAutoOnlyEnabled = p.getBoolean(KEY_SEARCH_SENT_AUTO_ONLY_ENABLED, DEFAULT_CONFIG.searchSentAutoOnlyEnabled),
            searchSentManualOnlyEnabled = p.getBoolean(KEY_SEARCH_SENT_MANUAL_ONLY_ENABLED, DEFAULT_CONFIG.searchSentManualOnlyEnabled)
        )
    }

    /** [Config]をJSONオブジェクトへ変換 */
    fun configToJson(config: Config): JSONObject = JSONObject()
        .put("sendEnabled", config.sendEnabled)
        .put("sendExtractionFailedEnabled", config.sendExtractionFailedEnabled)
        .put("sendExtractionContinuationEnabled", config.sendExtractionContinuationEnabled)
        .put("searchExtractionFailedEnabled", config.searchExtractionFailedEnabled)
        .put("searchExtractionContinuationEnabled", config.searchExtractionContinuationEnabled)
        .put("replyEnabled", config.replyEnabled)
        .put("replyCooldownSeconds", config.replyCooldownSeconds)
        .put("logRefreshEnabled", config.logRefreshEnabled)
        .put("logRefreshIntervalSeconds", config.logRefreshIntervalSeconds)
        .put("logMatchToleranceSeconds", config.logMatchToleranceSeconds)
        .put("logBodyExcerptLength", config.logBodyExcerptLength)
        .put("continuationEnabled", config.continuationEnabled)
        .put("continuationScope", config.continuationScope.name)
        .put("continuationShowUserNameEnabled", config.continuationShowUserNameEnabled)
        .put("themeMode", config.themeMode.name)
        .put("searchDateRangeDays", config.searchDateRangeDays)
        .put("searchFiltersVisibleByDefault", config.searchFiltersVisibleByDefault)
        .put("replySuccessBody", config.replySuccessBody)
        .put("replyFailedBody", config.replyFailedBody)
        .put("searchSendTargetFilterName", config.searchSendTargetFilterName ?: JSONObject.NULL)
        .put("extractionAiEnabled", config.extractionAiEnabled)
        .put("extractionCompanyNameEnabled", config.extractionCompanyNameEnabled)
        .put("extractionCompanyNameAutoConversionEnabled", config.extractionCompanyNameAutoConversionEnabled)
        .put("extractionCompanyNameFixedConversions", JSONArray().apply {
            config.extractionCompanyNameFixedConversions.forEach { rule ->
                put(JSONObject().put("from", rule.from).put("to", rule.to))
            }
        })
        .put("searchSendNoneOnlyEnabled", config.searchSendNoneOnlyEnabled)
        .put("searchExtractionFailedOnlyEnabled", config.searchExtractionFailedOnlyEnabled)
        .put("searchExtractionSucceededOnlyEnabled", config.searchExtractionSucceededOnlyEnabled)
        .put("searchExtractionContinuationOnlyEnabled", config.searchExtractionContinuationOnlyEnabled)
        .put("searchSentAutoOnlyEnabled", config.searchSentAutoOnlyEnabled)
        .put("searchSentManualOnlyEnabled", config.searchSentManualOnlyEnabled)

    /** JSONオブジェクトから[Config]を復元。未定義の属性は[existingConfig]の値を保持 */
    fun configFromJson(json: JSONObject, existingConfig: Config? = null): Config {
        val fallback = existingConfig ?: DEFAULT_CONFIG
        return Config(
            sendEnabled = json.optBoolean("sendEnabled", fallback.sendEnabled),
            sendExtractionFailedEnabled = json.optBoolean("sendExtractionFailedEnabled", fallback.sendExtractionFailedEnabled),
            sendExtractionContinuationEnabled = json.optBoolean("sendExtractionContinuationEnabled", fallback.sendExtractionContinuationEnabled),
            searchExtractionFailedEnabled = json.optBoolean("searchExtractionFailedEnabled", fallback.searchExtractionFailedEnabled),
            searchExtractionContinuationEnabled = json.optBoolean("searchExtractionContinuationEnabled", fallback.searchExtractionContinuationEnabled),
            replyEnabled = json.optBoolean("replyEnabled", fallback.replyEnabled),
            replyCooldownSeconds = json.optInt("replyCooldownSeconds", fallback.replyCooldownSeconds),
            logRefreshEnabled = json.optBoolean("logRefreshEnabled", fallback.logRefreshEnabled),
            logRefreshIntervalSeconds = json.optInt("logRefreshIntervalSeconds", fallback.logRefreshIntervalSeconds),
            logMatchToleranceSeconds = json.optInt("logMatchToleranceSeconds", fallback.logMatchToleranceSeconds),
            logBodyExcerptLength = json.optInt("logBodyExcerptLength", fallback.logBodyExcerptLength),
            continuationEnabled = json.optBoolean("continuationEnabled", fallback.continuationEnabled),
            continuationScope = if (json.has("continuationScope")) ContinuationScope.fromName(json.optString("continuationScope", "")) else fallback.continuationScope,
            continuationShowUserNameEnabled = json.optBoolean("continuationShowUserNameEnabled", fallback.continuationShowUserNameEnabled),
            themeMode = if (json.has("themeMode")) ThemeMode.fromName(json.optString("themeMode", "")) else fallback.themeMode,
            searchDateRangeDays = json.optInt("searchDateRangeDays", fallback.searchDateRangeDays),
            searchFiltersVisibleByDefault = json.optBoolean("searchFiltersVisibleByDefault", fallback.searchFiltersVisibleByDefault),
            replySuccessBody = json.optString("replySuccessBody", fallback.replySuccessBody),
            replyFailedBody = json.optString("replyFailedBody", fallback.replyFailedBody),
            searchSendTargetFilterName = if (json.has("searchSendTargetFilterName") && !json.isNull("searchSendTargetFilterName")) {
                json.optString("searchSendTargetFilterName")
            } else if (json.has("searchSendTargetFilterName")) {
                null
            } else {
                fallback.searchSendTargetFilterName
            },
            extractionAiEnabled = json.optBoolean("extractionAiEnabled", fallback.extractionAiEnabled),
            extractionCompanyNameEnabled = json.optBoolean("extractionCompanyNameEnabled", fallback.extractionCompanyNameEnabled),
            extractionCompanyNameAutoConversionEnabled = json.optBoolean("extractionCompanyNameAutoConversionEnabled", fallback.extractionCompanyNameAutoConversionEnabled),
            extractionCompanyNameFixedConversions = json.optJSONArray("extractionCompanyNameFixedConversions")?.let { arr ->
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    FixedConversion(from = obj.optString("from", ""), to = obj.optString("to", ""))
                }
            } ?: fallback.extractionCompanyNameFixedConversions,
            searchSendNoneOnlyEnabled = json.optBoolean("searchSendNoneOnlyEnabled", fallback.searchSendNoneOnlyEnabled),
            searchExtractionFailedOnlyEnabled = json.optBoolean("searchExtractionFailedOnlyEnabled", fallback.searchExtractionFailedOnlyEnabled),
            searchExtractionSucceededOnlyEnabled = json.optBoolean("searchExtractionSucceededOnlyEnabled", fallback.searchExtractionSucceededOnlyEnabled),
            searchExtractionContinuationOnlyEnabled = json.optBoolean("searchExtractionContinuationOnlyEnabled", fallback.searchExtractionContinuationOnlyEnabled),
            searchSentAutoOnlyEnabled = json.optBoolean("searchSentAutoOnlyEnabled", fallback.searchSentAutoOnlyEnabled),
            searchSentManualOnlyEnabled = json.optBoolean("searchSentManualOnlyEnabled", fallback.searchSentManualOnlyEnabled)
        )
    }

    /** [SendTarget]のデフォルト値を持つインスタンスを返す（UUIDは新規採番） */
    private fun createDefaultSendTarget(): SendTarget = SendTarget(
        id = UUID.randomUUID().toString(),
        name = "",
        companyName = "",
        keywords = emptyList(),
        subdomain = AppDefaults.NEW_PROFILE_SUBDOMAIN,
        appId = "",
        loginName = "",
        loginPassword = "",
        fieldSender = AppDefaults.NEW_PROFILE_FIELD_SENDER,
        fieldHistory = AppDefaults.NEW_PROFILE_FIELD_HISTORY,
        fieldDatetime = AppDefaults.NEW_PROFILE_FIELD_DATETIME,
        fieldType = AppDefaults.NEW_PROFILE_FIELD_TYPE,
        updateToleranceHours = AppDefaults.UPDATE_TOLERANCE_HOURS,
        updateToleranceMode = UpdateToleranceMode.SAME_DATE,
        fieldCompanyName = AppDefaults.NEW_PROFILE_FIELD_COMPANY_NAME,
        fieldUserName = AppDefaults.NEW_PROFILE_FIELD_USER_NAME,
        fieldBody = AppDefaults.NEW_PROFILE_FIELD_BODY
    )

    /** [SendTarget]をJSONオブジェクトへ変換（IDは含めない） */
    fun sendTargetToJson(sendTarget: SendTarget): JSONObject = JSONObject()
        .put("name", sendTarget.name)
        .put("companyName", sendTarget.companyName)
        .put("keywords", JSONArray(sendTarget.keywords))
        .put("subdomain", sendTarget.subdomain)
        .put("appId", sendTarget.appId)
        .put("loginName", sendTarget.loginName)
        .put("loginPassword", sendTarget.loginPassword)
        .put("fieldSender", sendTarget.fieldSender)
        .put("fieldHistory", sendTarget.fieldHistory)
        .put("fieldDatetime", sendTarget.fieldDatetime)
        .put("fieldType", sendTarget.fieldType)
        .put("updateToleranceHours", sendTarget.updateToleranceHours)
        .put("updateToleranceMode", sendTarget.updateToleranceMode.name)
        .put("fieldCompanyName", sendTarget.fieldCompanyName)
        .put("fieldUserName", sendTarget.fieldUserName)
        .put("fieldBody", sendTarget.fieldBody)

    /** JSONオブジェクトから[SendTarget]を復元。未定義の属性は[existingSendTarget]の値を保持 */
    fun sendTargetFromJson(obj: JSONObject, existingSendTarget: SendTarget? = null): SendTarget {
        val default = existingSendTarget ?: createDefaultSendTarget()
        return default.copy(
            id = existingSendTarget?.id ?: UUID.randomUUID().toString(),
            name = if (obj.has("name")) obj.optString("name", default.name) else default.name,
            companyName = if (obj.has("companyName")) obj.optString("companyName", default.companyName) else default.companyName,
            keywords = if (obj.has("keywords")) {
                obj.optJSONArray("keywords")?.let { array ->
                    (0 until array.length()).map { array.getString(it) }
                } ?: default.keywords
            } else {
                default.keywords
            },
            subdomain = if (obj.has("subdomain")) obj.optString("subdomain", default.subdomain) else default.subdomain,
            appId = if (obj.has("appId")) obj.optString("appId", default.appId) else default.appId,
            loginName = if (obj.has("loginName")) obj.optString("loginName", default.loginName) else default.loginName,
            loginPassword = if (obj.has("loginPassword")) obj.optString("loginPassword", default.loginPassword) else default.loginPassword,
            fieldSender = if (obj.has("fieldSender")) obj.optString("fieldSender", default.fieldSender) else default.fieldSender,
            fieldHistory = if (obj.has("fieldHistory")) obj.optString("fieldHistory", default.fieldHistory) else default.fieldHistory,
            fieldDatetime = if (obj.has("fieldDatetime")) obj.optString("fieldDatetime", default.fieldDatetime) else default.fieldDatetime,
            fieldType = if (obj.has("fieldType")) obj.optString("fieldType", default.fieldType) else default.fieldType,
            updateToleranceHours = if (obj.has("updateToleranceHours")) obj.optInt("updateToleranceHours", default.updateToleranceHours) else default.updateToleranceHours,
            updateToleranceMode = if (obj.has("updateToleranceMode")) UpdateToleranceMode.fromName(obj.optString("updateToleranceMode", "")) else default.updateToleranceMode,
            fieldCompanyName = if (obj.has("fieldCompanyName")) obj.optString("fieldCompanyName", default.fieldCompanyName) else default.fieldCompanyName,
            fieldUserName = if (obj.has("fieldUserName")) obj.optString("fieldUserName", default.fieldUserName) else default.fieldUserName,
            fieldBody = if (obj.has("fieldBody")) obj.optString("fieldBody", default.fieldBody) else default.fieldBody
        )
    }

    /**
     * 現在の設定を読み込み、[change]で変更してから保存する。
     *
     * @param context アプリケーションコンテキスト
     * @param change 現在の[Config]を受け取って、変更版を返す変換関数
     */
    fun update(context: Context, change: (Config) -> Config) {
        save(context, change(load(context)))
    }

    /**
     * アプリ設定をデフォルト値に戻す。
     *
     * @param context アプリケーションコンテキスト
     */
    fun resetToDefaults(context: Context) {
        save(context, DEFAULT_CONFIG)
    }

    /**
     * 「送信先」フィルタの選択肢を返す。
     * 「すべて」（null）、各送信先の名前、「未設定」の順
     *
     * @param context アプリケーションコンテキスト
     * @return キー→表示ラベルの[Pair]リスト
     */
    fun sendTargetFilterOptions(context: Context): List<Pair<String?, String>> {
        val sendTargets = loadSendTargets(context)
        return listOf(null to context.getString(R.string.filter_send_target_all)) +
            sendTargets.map { it.name to it.displayName(context) } +
            listOf(AppConstants.SEND_TARGET_FILTER_KEY_UNSET to context.getString(R.string.label_send_target_none))
    }

    /**
     * [SendTarget]のリストを保存する。
     *
     * @param context アプリケーションコンテキスト
     * @param sendTargets 保存する送信先リスト
     */
    fun saveSendTargets(context: Context, sendTargets: List<SendTarget>) {
        val array = JSONArray()
        sendTargets.forEach { array.put(sendTargetToJson(it)) }
        prefs(context).edit().putString(KEY_SEND_TARGETS, array.toString()).apply()
    }

    /**
     * インポート送信先を既存リストにマージする。送信先名をキーに既存送信先とマージし、
     * JSON に含まれない属性は既存値を保持。新規送信先は追加する。
     *
     * @param context アプリケーションコンテキスト
     * @param importedJsonArray インポート元のJSON配列（属性の有無を確認するため）
     * @return マージされた送信先リスト
     */
    fun mergeImportSendTargets(context: Context, importedJsonArray: JSONArray): List<SendTarget> {
        val merged = loadSendTargets(context).toMutableList()
        for (i in 0 until importedJsonArray.length()) {
            val obj = importedJsonArray.getJSONObject(i)
            val importedName = obj.optString("name", "")
            val index = merged.indexOfFirst { it.name == importedName }
            val existingTarget = if (index >= 0) merged[index] else null
            val mergedTarget = sendTargetFromJson(obj, existingTarget)
            if (index >= 0) {
                merged[index] = mergedTarget
            } else {
                merged.add(mergedTarget)
            }
        }
        return merged
    }

    /**
     * 保存済みの送信先設定を読み込む。初回起動で保存済みデータがない場合はデフォルト送信先を作成。
     *
     * @param context アプリケーションコンテキスト
     * @return 送信先リスト
     */
    fun loadSendTargets(context: Context): List<SendTarget> {
        val json = prefs(context).getString(KEY_SEND_TARGETS, null)
            ?: return createDefaultSendTarget(context)

        val array = JSONArray(json)
        return (0 until array.length()).map { i -> sendTargetFromJson(array.getJSONObject(i)) }
    }

    /**
     * 初回起動時にデフォルト送信先を作成して保存し、戻す。
     *
     * @param context アプリケーションコンテキスト
     * @return デフォルト送信先を含むリスト
     */
    private fun createDefaultSendTarget(context: Context): List<SendTarget> {
        val sendTargets = listOf(SendTarget.newEmpty())
        saveSendTargets(context, sendTargets)
        return sendTargets
    }

    /**
     * 会社名に対して、アプリ全体の会社名変換（幅統一→固定変換）を適用する。
     *
     * @param companyName 変換対象の会社名
     * @param config 変換設定
     * @return 変換済みの会社名
     */
    fun applyCompanyNameConversion(companyName: String, config: Config): String {
        val autoConverted = if (config.extractionCompanyNameAutoConversionEnabled) {
            TextNormalization.normalizeWidth(companyName)
        } else {
            companyName
        }
        return config.extractionCompanyNameFixedConversions.fold(autoConverted) { acc, rule ->
            if (rule.from.isNotEmpty()) acc.replace(rule.from, rule.to) else acc
        }
    }

    /**
     * 会社名に一致する送信先を返す。一致する送信先がない場合はデフォルト送信先にフォールバック。
     *
     * @param context アプリケーションコンテキスト
     * @param companyName 照合対象の会社名
     * @return 一致した送信先リスト（一致なしの場合はデフォルト送信先）
     */
    fun findSendTargets(context: Context, companyName: String): List<SendTarget> {
        val sendTargets = loadSendTargets(context)
        val matched = sendTargets.filter { it.routesTo(companyName) }
        if (matched.isNotEmpty()) return matched
        return listOfNotNull(sendTargets.firstOrNull { it.isDefault })
    }

    /**
     * [resolveSendTargets]の結果。[SmsParts]は本文からの抽出結果のみを表すため、それが継続SMS
     * （同一送信元の過去の正常なSMSからの引継ぎ）によるものかどうかという振り分け固有のメタ情報は
     * ここで別に持つ。[SmsSearchActivity]など[SmsLogStore.Entry]を経由せず端末上のSMSをその場で
     * 解決する画面でも必要なため、[SmsLogStore.Entry]側だけに寄せることはできない
     */
    data class SmsResolution(
        /** 本文から抽出した会社名・氏名、および本文全体 */
        val smsParts: SmsParts,
        /**
         * 同一送信元が過去に一度でも抽出状況が正常なSMSを送っていたため、その直近1件から会社名・氏名と
         * 送信先を引き継いだ結果かどうか。今回の本文自体が単独で解析できるかどうかは問わない。
         * trueの場合、抽出・送信先のアイコン表示は通常の⭕/❌・📍/🚫ではなく専用のアイコンに切り替える
         */
        val isContinuation: Boolean = false
    )

    /**
     * SMS本文から[SmsParts]を抽出し、対応する送信先（複数一致し得る）を判定する。抽出結果と振り分けの
     * 両方が必要な箇所は、ずれないよう必ずこれを使うこと。
     *
     * - 引継ぎ：[continuationEnabled]で同一送信元の直近の抽出成功結果があれば、その会社名・氏名を
     *   引き継いで[isContinuation]をtrueにする（本文は今回分）。送信先は引き継いだ会社名を現在の送信先
     *   ルールに通して都度判定するため、設定の変更・削除が即時反映される。
     * - 通常解析：本文を解析し、抽出直後に会社名変換（[applyCompanyNameConversion]）を一度適用する。
     *   以降は戻り値の会社名をそのまま使えばよい。
     * - 会社名抽出が無効：[extractionCompanyNameEnabled]がfalse。本文から抽出せず振り分けもせず、
     *   全送信先へ送る。共有[SmsParts]の会社名は先頭の送信先の設定値（変換済み）をプレースホルダとし、
     *   kintone登録・送信ログでは[KintoneUploadWorker]が送信先ごとの設定値を使う。
     *
     * この関数自体は[ContinuationStore]を更新しない（プレビューなど送信を伴わない呼び出しからも使われる）。
     * 更新は受信・送信を処理する[SmsReceiver]・[KintoneUploadWorker]が、抽出成功時にのみ行うこと。
     */
    suspend fun resolveSendTargets(
        context: Context,
        sender: String,
        body: String,
        timestampMillis: Long,
        extractionAiEnabled: Boolean,
        extractionCompanyNameEnabled: Boolean,
        continuationEnabled: Boolean,
        continuationScope: ContinuationScope
    ): Pair<SmsResolution, List<SendTarget>> {
        val previousEntry = if (continuationEnabled) {
            ContinuationStore.find(context, sender, timestampMillis, sameDayOnly = continuationScope == ContinuationScope.SAME_DAY)
        } else {
            null
        }
        if (previousEntry != null) {
            val config = load(context)
            val convertedCompanyName = applyCompanyNameConversion(previousEntry.companyName, config)
            val smsParts = SmsParts(
                companyName = convertedCompanyName,
                userName = previousEntry.userName,
                body = body.trim(),
                extractionPerformed = false
            )
            val resolution = SmsResolution(smsParts = smsParts, isContinuation = true)
            // 引き継いだ会社名（変換済み）で送信先を都度判定
            val sendTargets = if (extractionCompanyNameEnabled) {
                findSendTargets(context, convertedCompanyName)
            } else {
                loadSendTargets(context)
            }
            return resolution to sendTargets
        }
        val extracted = SmsPartsGenerator.resolveSmsParts(body, extractionAiEnabled, extractionCompanyNameEnabled)
        val config = load(context)
        val convertedCompanyName = if (extractionCompanyNameEnabled) {
            applyCompanyNameConversion(extracted.companyName, config)
        } else {
            extracted.companyName
        }
        val sendTargets = if (extractionCompanyNameEnabled) {
            findSendTargets(context, convertedCompanyName)
        } else {
            loadSendTargets(context)
        }
        // 抽出が無効な場合は会社名を空のまま（各送信先ごとに KintoneUploadWorker で設定）
        val companyNameSource = if (extractionCompanyNameEnabled) {
            convertedCompanyName
        } else {
            ""
        }
        val finalParts = extracted.copy(companyName = companyNameSource)
        return SmsResolution(smsParts = finalParts) to sendTargets
    }

    /**
     * インポート JSON から設定をマージして反映する。
     * JSON に含まれないセクション・属性・エントリは変更されない。
     *
     * @param context アプリケーションコンテキスト
     * @param json インポート JSON
     */
    fun mergeFromJson(context: Context, json: JSONObject) {
        json.optJSONObject("appConfig")?.takeIf { it.length() > 0 }?.let {
            val config = configFromJson(it, load(context))
            save(context, config)
        }
        json.optJSONArray("sendTargetConfig")?.let {
            saveSendTargets(context, mergeImportSendTargets(context, it))
        }
        json.optJSONArray("continuationInfoConfig")?.let {
            val existing = ContinuationStore.getAll(context)
            ContinuationStore.importAll(context, parseContinuationInfoFromJson(it, existing))
        }
    }

    /**
     * 引継ぎ内容の JSON 配列をパースする（インポート用）。
     * 属性が未定義の場合は既存エントリの値を保持、存在しなければデフォルト値で埋める。
     *
     * @param array continuationInfoConfig の JSON 配列
     * @param existingEntries 既存の引継ぎ内容（マージ用）
     * @return 正規化済みキー→Entry のマップ
     */
    fun parseContinuationInfoFromJson(array: JSONArray, existingEntries: Map<String, ContinuationStore.Entry>): Map<String, ContinuationStore.Entry> {
        val duplicateKeys = mutableSetOf<String>()
        val seenKeys = mutableSetOf<String>()
        val entries = mutableMapOf<String, ContinuationStore.Entry>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val senderAddress = obj.optString("senderAddress", "")
            val senderKey = SmsMatching.normalizeSenderKey(senderAddress)
            if (senderKey.isBlank()) {
                throw JSONException("senderAddress is required at index ${i + 1}")
            }
            if (!seenKeys.add(senderKey)) duplicateKeys.add(senderKey)
            val existingEntry = existingEntries[senderKey]
            entries[senderKey] = ContinuationStore.Entry(
                companyName = if (obj.has("companyName")) obj.optString("companyName", "") else (existingEntry?.companyName ?: ""),
                userName = if (obj.has("userName")) obj.optString("userName", "") else (existingEntry?.userName ?: ""),
                timestampMillis = if (obj.has("timestampMillis")) obj.optLong("timestampMillis", System.currentTimeMillis()) else (existingEntry?.timestampMillis ?: System.currentTimeMillis()),
                senderAddress = senderAddress
            )
        }
        if (duplicateKeys.isNotEmpty()) {
            throw JSONException("Duplicate sender addresses: ${duplicateKeys.sorted().joinToString(", ")}")
        }
        return entries
    }
}

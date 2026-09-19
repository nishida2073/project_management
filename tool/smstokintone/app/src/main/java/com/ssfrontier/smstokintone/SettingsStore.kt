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
    /** [Config.sendExtractionFailedEnabled]のキー */
    private const val KEY_SEND_EXTRACTION_FAILED_ENABLED = "send_extraction_failed_enabled"
    /** [Config.sendExtractionNotPerformedEnabled]のキー */
    private const val KEY_SEND_EXTRACTION_NOT_PERFORMED_ENABLED = "send_extraction_not_performed_enabled"
    /** [Config.searchExtractionFailedEnabled]のキー */
    private const val KEY_SEARCH_EXTRACTION_FAILED_ENABLED = "search_extraction_failed_enabled"
    /** [Config.searchExtractionNotPerformedEnabled]のキー */
    private const val KEY_SEARCH_EXTRACTION_NOT_PERFORMED_ENABLED = "search_extraction_not_performed_enabled"
    /** [Config.autoReplyExtractionFailedEnabled]のキー */
    private const val KEY_AUTO_REPLY_EXTRACTION_FAILED_ENABLED = "auto_reply_extraction_failed_enabled"
    /** [Config.autoReplyCooldownSeconds]のキー */
    private const val KEY_AUTO_REPLY_COOLDOWN_SECONDS = "auto_reply_cooldown_seconds"
    /** [Config.autoRefreshEnabled]のキー */
    private const val KEY_AUTO_REFRESH_ENABLED = "auto_refresh_enabled"
    /** [Config.autoRefreshIntervalSeconds]のキー */
    private const val KEY_AUTO_REFRESH_INTERVAL_SECONDS = "auto_refresh_interval_seconds"
    /** [Config.smsMatchToleranceSeconds]のキー */
    private const val KEY_SMS_MATCH_TOLERANCE_SECONDS = "sms_match_tolerance_seconds"
    /** [Config.bodyExcerptLength]のキー */
    private const val KEY_BODY_EXCERPT_LENGTH = "body_excerpt_length"
    /** [Config.continuationEnabled]のキー */
    private const val KEY_CONTINUATION_ENABLED = "continuation_enabled"
    /** [Config.continuationScope]のキー */
    private const val KEY_CONTINUATION_SCOPE = "continuation_scope"
    /** [Config.continuationShowUserNameEnabled]のキー */
    private const val KEY_CONTINUATION_SHOW_USER_NAME_ENABLED = "continuation_show_user_name_enabled"
    /** [Config.themeMode]のキー */
    private const val KEY_THEME_MODE = "theme_mode"
    /** [Config.smsSearchDateRangeDays]のキー */
    private const val KEY_SMS_SEARCH_DATE_RANGE_DAYS = "sms_search_date_range_days"
    /** [Config.searchFiltersVisibleByDefault]のキー */
    private const val KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT = "search_filters_visible_by_default"
    /** [Config.smsExtractionSuccessReplyBody]のキー */
    private const val KEY_SMS_EXTRACTION_SUCCESS_REPLY_BODY = "sms_extraction_success_reply_body"
    /** [Config.smsExtractionFailedReplyBody]のキー */
    private const val KEY_SMS_EXTRACTION_FAILED_REPLY_BODY = "sms_extraction_failed_reply_body"
    /** [Config.defaultSendTargetFilterName]のキー */
    private const val KEY_DEFAULT_SEND_TARGET_FILTER_NAME = "default_send_target_filter_name"
    /** [Config.aiExtractionEnabled]のキー */
    private const val KEY_AI_EXTRACTION_ENABLED = "ai_extraction_enabled"
    /** [Config.companyNameExtractionEnabled]のキー */
    private const val KEY_COMPANY_NAME_EXTRACTION_ENABLED = "company_name_extraction_enabled"
    /** [Config.companyNameAutoConversionEnabled]のキー */
    private const val KEY_COMPANY_NAME_AUTO_CONVERSION_ENABLED = "company_name_auto_conversion_enabled"
    /** [Config.companyNameFixedConversions]のキー。JSON配列文字列として保存する */
    private const val KEY_COMPANY_NAME_FIXED_CONVERSIONS = "company_name_fixed_conversions"
    /** [Config.defaultSendNoneOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SEND_NONE_ONLY_ENABLED = "default_send_none_only_enabled"
    /** [Config.defaultExtractionFailedOnlyEnabled]のキー */
    private const val KEY_DEFAULT_EXTRACTION_FAILED_ONLY_ENABLED = "default_extraction_failed_only_enabled"
    /** [Config.defaultExtractionSucceededOnlyEnabled]のキー */
    private const val KEY_DEFAULT_EXTRACTION_SUCCEEDED_ONLY_ENABLED = "default_extraction_succeeded_only_enabled"
    /** [Config.defaultExtractionNotPerformedOnlyEnabled]のキー */
    private const val KEY_DEFAULT_EXTRACTION_NOT_PERFORMED_ONLY_ENABLED = "default_extraction_not_performed_only_enabled"
    /** [Config.defaultSentAutoOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED = "default_sent_auto_only_enabled"
    /** [Config.defaultSentManualOnlyEnabled]のキー */
    private const val KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED = "default_sent_manual_only_enabled"

    /** [SendTarget]のリスト全体をJSON配列として保存するキー。[Config]とは別枠で[saveSendTargets]/[loadSendTargets]が読み書きする */
    private const val KEY_SEND_TARGETS = "send_targets"

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

    /** 固定変換の1行（[Config.companyNameFixedConversions]）。[from]に一致する部分文字列を[to]に置換する */
    data class FixedConversion(
        val from: String = "",
        val to: String = ""
    )

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
     * [UNLIMITED]は日付を問わず過去に一度でも抽出状況が正常なSMSがあれば常に引き継ぐ。[SAME_DAY]は
     * 引き継ぎ元のSMSと暦日が同じ場合のみ有効とし、日付が変わると引き継ぎがリセットされる
     */
    enum class ContinuationScope {
        UNLIMITED,
        SAME_DAY;

        /** [fromName]を提供するコンパニオンオブジェクト */
        companion object {
            /** 保存値からの復元用。未知の値やnullは[DEFAULT_CONFIG]と同じUNLIMITEDにフォールバックする */
            fun fromName(name: String?): ContinuationScope =
                entries.firstOrNull { it.name == name } ?: UNLIMITED
        }
    }

    /** アプリ全体の設定（kintoneへの接続設定は含まない。接続設定は[SendTarget]を参照） */
    data class Config(
        /** trueなら自動送信モード、falseなら手動送信モード（[KintoneUploadWorker]が参照） */
        val sendEnabled: Boolean,
        /** 自動送信時、本文の抽出状況が異常なSMS（会社名・氏名を抽出できなかったSMS）も送信するかどうか */
        val sendExtractionFailedEnabled: Boolean,
        /** 自動送信時、抽出状況が未実施（継続SMS、[SmsResolution.isContinuation]）のSMSも送信するかどうか */
        val sendExtractionNotPerformedEnabled: Boolean,
        /** SMS検索画面で、本文の抽出状況が異常なSMSを選択可能にするかどうか */
        val searchExtractionFailedEnabled: Boolean,
        /** SMS検索画面で、抽出状況が未実施（継続SMS、[SmsResolution.isContinuation]）のSMSを選択可能にするかどうか */
        val searchExtractionNotPerformedEnabled: Boolean,
        /** 自動受信時、本文の抽出状況が異常なSMSに対して[smsExtractionFailedReplyBody]の文言でSMSへ自動返信するかどうか */
        val autoReplyExtractionFailedEnabled: Boolean,
        /** 同一の送信元への自動返信を再送信するまでの間隔（秒）。連投を防ぐためのクールダウン */
        val autoReplyCooldownSeconds: Int,
        /** SMS送信履歴画面（[LogActivity]）を[autoRefreshIntervalSeconds]間隔で自動再読み込みするかどうか */
        val autoRefreshEnabled: Boolean,
        /** [autoRefreshEnabled]が有効な場合の自動再読み込み間隔（秒） */
        val autoRefreshIntervalSeconds: Int,
        /** 自動受信SMSのログと端末上のSMSを突き合わせる際の許容範囲（秒） */
        val smsMatchToleranceSeconds: Int,
        /** ログ一覧（[LogActivity]）に表示する本文抜粋（[SmsLogStore.Entry.bodyExcerpt]）の文字数 */
        val bodyExcerptLength: Int,
        /** 継続SMSの引き継ぎ（[SmsResolution.isContinuation]）機能自体を有効にするかどうか */
        val continuationEnabled: Boolean,
        /** 継続SMSの引き継ぎ（[SmsResolution.isContinuation]）を送信元ごとにどこまで遡って有効とするか */
        val continuationScope: ContinuationScope,
        /**
         * SMS検索画面・ログ画面の一覧で、継続SMS（[SmsResolution.isContinuation]）については
         * 送信元電話番号の代わりに引き継いだ氏名を表示するかどうか
         */
        val continuationShowUserNameEnabled: Boolean,
        /** アプリの配色モード */
        val themeMode: ThemeMode,
        /** SMS検索画面を開いた際に検索条件へ初期設定する、開始日〜終了日の範囲（日） */
        val smsSearchDateRangeDays: Int,
        /** SMS検索画面を開いた際に検索条件エリアを表示した状態にするかどうか */
        val searchFiltersVisibleByDefault: Boolean,
        /** SMS検索画面で長押しした際に開く返信画面に自動入力する文言 */
        val smsExtractionSuccessReplyBody: String,
        /** 抽出失敗のSMSへの返信時、[smsExtractionSuccessReplyBody]の代わりに使う文言 */
        val smsExtractionFailedReplyBody: String,
        /** SMS検索画面を開いた際に「送信先」フィルタへ初期設定する送信先名。
         * nullは「すべて」、[AppConstants.SEND_TARGET_FILTER_KEY_UNSET]は「未設定」を表す
         * （送信先はnameで一意に管理するため名前で参照する） */
        val defaultSendTargetFilterName: String?,
        /** 本文からの会社名・氏名の抽出に、ルールベースの代わりに端末上のAI（ML Kit GenAI / Gemini Nano）を
         * 使うかどうか。非対応端末では自動的にルールベースにフォールバックする */
        val aiExtractionEnabled: Boolean,
        val companyNameExtractionEnabled: Boolean,
        /** 本文からの抽出結果の会社名に、英数字は半角大文字・それ以外は全角に統一する変換を適用するかどうか。
         * [resolveSendTargets]で抽出直後に適用され、送信先の判定・送信元情報の登録・kintoneへの送信すべてに反映される */
        val companyNameAutoConversionEnabled: Boolean = false,
        /** 本文からの抽出結果の会社名に適用する固定変換。[FixedConversion.from]に一致する部分文字列を
         * [FixedConversion.to]に置換する。複数件は先頭から順番に、[companyNameAutoConversionEnabled]の後に適用される */
        val companyNameFixedConversions: List<FixedConversion> = emptyList(),
        /** SMS検索画面を開いた際に「送信」の「未」チェックボックスを初期状態でONにするかどうか */
        val defaultSendNoneOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「抽出状況」の「異常」チェックボックスを初期状態でONにするかどうか */
        val defaultExtractionFailedOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「抽出状況」の「正常」チェックボックスを初期状態でONにするかどうか */
        val defaultExtractionSucceededOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「抽出状況」の「未実施」チェックボックスを初期状態でONにするかどうか */
        val defaultExtractionNotPerformedOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（自動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentAutoOnlyEnabled: Boolean,
        /** SMS検索画面を開いた際に「送信」の「済（手動）」チェックボックスを初期状態でONにするかどうか */
        val defaultSentManualOnlyEnabled: Boolean
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
         * 会社名変換（[Config.companyNameAutoConversionEnabled]・[Config.companyNameFixedConversions]）が
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

    /** [Config]をSharedPreferencesに保存する。送信先設定（[SendTarget]）は対象外で[saveSendTargets]を使うこと */
    fun save(context: Context, config: Config) {
        val editor = prefs(context).edit()
            .putBoolean(KEY_SEND_ENABLED, config.sendEnabled)
            .putBoolean(KEY_SEND_EXTRACTION_FAILED_ENABLED, config.sendExtractionFailedEnabled)
            .putBoolean(KEY_SEND_EXTRACTION_NOT_PERFORMED_ENABLED, config.sendExtractionNotPerformedEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_FAILED_ENABLED, config.searchExtractionFailedEnabled)
            .putBoolean(KEY_SEARCH_EXTRACTION_NOT_PERFORMED_ENABLED, config.searchExtractionNotPerformedEnabled)
            .putBoolean(KEY_AUTO_REPLY_EXTRACTION_FAILED_ENABLED, config.autoReplyExtractionFailedEnabled)
            .putInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, config.autoReplyCooldownSeconds)
            .putBoolean(KEY_AUTO_REFRESH_ENABLED, config.autoRefreshEnabled)
            .putInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, config.autoRefreshIntervalSeconds)
            .putInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, config.smsMatchToleranceSeconds)
            .putInt(KEY_BODY_EXCERPT_LENGTH, config.bodyExcerptLength)
            .putBoolean(KEY_CONTINUATION_ENABLED, config.continuationEnabled)
            .putString(KEY_CONTINUATION_SCOPE, config.continuationScope.name)
            .putBoolean(KEY_CONTINUATION_SHOW_USER_NAME_ENABLED, config.continuationShowUserNameEnabled)
            .putString(KEY_THEME_MODE, config.themeMode.name)
            .putInt(KEY_SMS_SEARCH_DATE_RANGE_DAYS, config.smsSearchDateRangeDays)
            .putBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, config.searchFiltersVisibleByDefault)
            .putString(KEY_SMS_EXTRACTION_SUCCESS_REPLY_BODY, config.smsExtractionSuccessReplyBody)
            .putString(KEY_SMS_EXTRACTION_FAILED_REPLY_BODY, config.smsExtractionFailedReplyBody)
            .putBoolean(KEY_AI_EXTRACTION_ENABLED, config.aiExtractionEnabled)
            .putBoolean(KEY_COMPANY_NAME_EXTRACTION_ENABLED, config.companyNameExtractionEnabled)
            .putBoolean(KEY_COMPANY_NAME_AUTO_CONVERSION_ENABLED, config.companyNameAutoConversionEnabled)
            .putString(
                KEY_COMPANY_NAME_FIXED_CONVERSIONS,
                JSONArray().apply {
                    config.companyNameFixedConversions.forEach { rule ->
                        put(JSONObject().put("from", rule.from).put("to", rule.to))
                    }
                }.toString()
            )
            .putBoolean(KEY_DEFAULT_SEND_NONE_ONLY_ENABLED, config.defaultSendNoneOnlyEnabled)
            .putBoolean(KEY_DEFAULT_EXTRACTION_FAILED_ONLY_ENABLED, config.defaultExtractionFailedOnlyEnabled)
            .putBoolean(KEY_DEFAULT_EXTRACTION_SUCCEEDED_ONLY_ENABLED, config.defaultExtractionSucceededOnlyEnabled)
            .putBoolean(KEY_DEFAULT_EXTRACTION_NOT_PERFORMED_ONLY_ENABLED, config.defaultExtractionNotPerformedOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED, config.defaultSentAutoOnlyEnabled)
            .putBoolean(KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED, config.defaultSentManualOnlyEnabled)
        if (config.defaultSendTargetFilterName != null) {
            editor.putString(KEY_DEFAULT_SEND_TARGET_FILTER_NAME, config.defaultSendTargetFilterName)
        } else {
            editor.remove(KEY_DEFAULT_SEND_TARGET_FILTER_NAME)
        }
        editor.apply()
    }

    /**
     * [Config]の既定値。[load]のフォールバックと[resetToDefaults]の両方が参照する。
     * 別々に書くと「初回起動時のデフォルト」と「初期化後の値」が食い違う恐れがあるため1箇所にまとめる
     */
    private val DEFAULT_CONFIG = Config(
        sendEnabled = true,
        sendExtractionFailedEnabled = false,
        sendExtractionNotPerformedEnabled = true,
        searchExtractionFailedEnabled = false,
        searchExtractionNotPerformedEnabled = true,
        autoReplyExtractionFailedEnabled = false,
        autoReplyCooldownSeconds = AppDefaults.AUTO_REPLY_COOLDOWN_SECONDS,
        autoRefreshEnabled = true,
        autoRefreshIntervalSeconds = AppDefaults.AUTO_REFRESH_INTERVAL_SECONDS,
        smsMatchToleranceSeconds = AppDefaults.SMS_MATCH_TOLERANCE_SECONDS,
        bodyExcerptLength = AppDefaults.BODY_EXCERPT_LENGTH,
        continuationEnabled = true,
        continuationScope = ContinuationScope.UNLIMITED,
        continuationShowUserNameEnabled = true,
        themeMode = ThemeMode.LIGHT,
        smsSearchDateRangeDays = AppDefaults.SMS_SEARCH_DATE_RANGE_DAYS,
        searchFiltersVisibleByDefault = true,
        smsExtractionSuccessReplyBody = AppDefaults.SMS_EXTRACTION_SUCCESS_REPLY_BODY,
        smsExtractionFailedReplyBody = AppDefaults.SMS_EXTRACTION_FAILED_REPLY_BODY,
        defaultSendTargetFilterName = null,
        aiExtractionEnabled = false,
        companyNameExtractionEnabled = true,
        companyNameAutoConversionEnabled = false,
        companyNameFixedConversions = emptyList(),
        defaultSendNoneOnlyEnabled = false,
        defaultExtractionFailedOnlyEnabled = false,
        defaultExtractionSucceededOnlyEnabled = false,
        defaultExtractionNotPerformedOnlyEnabled = false,
        defaultSentAutoOnlyEnabled = false,
        defaultSentManualOnlyEnabled = false
    )

    /** [save]で保存した設定を読み込む。未保存のキーは[DEFAULT_CONFIG]の値で補う */
    fun load(context: Context): Config {
        val p = prefs(context)
        return Config(
            sendEnabled = p.getBoolean(KEY_SEND_ENABLED, DEFAULT_CONFIG.sendEnabled),
            sendExtractionFailedEnabled = p.getBoolean(KEY_SEND_EXTRACTION_FAILED_ENABLED, DEFAULT_CONFIG.sendExtractionFailedEnabled),
            sendExtractionNotPerformedEnabled = p.getBoolean(KEY_SEND_EXTRACTION_NOT_PERFORMED_ENABLED, DEFAULT_CONFIG.sendExtractionNotPerformedEnabled),
            searchExtractionFailedEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_FAILED_ENABLED, DEFAULT_CONFIG.searchExtractionFailedEnabled),
            searchExtractionNotPerformedEnabled = p.getBoolean(KEY_SEARCH_EXTRACTION_NOT_PERFORMED_ENABLED, DEFAULT_CONFIG.searchExtractionNotPerformedEnabled),
            autoReplyExtractionFailedEnabled = p.getBoolean(KEY_AUTO_REPLY_EXTRACTION_FAILED_ENABLED, DEFAULT_CONFIG.autoReplyExtractionFailedEnabled),
            autoReplyCooldownSeconds = p.getInt(KEY_AUTO_REPLY_COOLDOWN_SECONDS, DEFAULT_CONFIG.autoReplyCooldownSeconds),
            autoRefreshEnabled = p.getBoolean(KEY_AUTO_REFRESH_ENABLED, DEFAULT_CONFIG.autoRefreshEnabled),
            autoRefreshIntervalSeconds = p.getInt(KEY_AUTO_REFRESH_INTERVAL_SECONDS, DEFAULT_CONFIG.autoRefreshIntervalSeconds),
            smsMatchToleranceSeconds = p.getInt(KEY_SMS_MATCH_TOLERANCE_SECONDS, DEFAULT_CONFIG.smsMatchToleranceSeconds),
            bodyExcerptLength = p.getInt(KEY_BODY_EXCERPT_LENGTH, DEFAULT_CONFIG.bodyExcerptLength),
            continuationEnabled = p.getBoolean(KEY_CONTINUATION_ENABLED, DEFAULT_CONFIG.continuationEnabled),
            continuationScope = ContinuationScope.fromName(p.getString(KEY_CONTINUATION_SCOPE, null)),
            continuationShowUserNameEnabled = p.getBoolean(KEY_CONTINUATION_SHOW_USER_NAME_ENABLED, DEFAULT_CONFIG.continuationShowUserNameEnabled),
            themeMode = ThemeMode.fromName(p.getString(KEY_THEME_MODE, null)),
            smsSearchDateRangeDays = p.getInt(KEY_SMS_SEARCH_DATE_RANGE_DAYS, DEFAULT_CONFIG.smsSearchDateRangeDays),
            searchFiltersVisibleByDefault = p.getBoolean(KEY_SEARCH_FILTERS_VISIBLE_BY_DEFAULT, DEFAULT_CONFIG.searchFiltersVisibleByDefault),
            smsExtractionSuccessReplyBody = p.getString(KEY_SMS_EXTRACTION_SUCCESS_REPLY_BODY, DEFAULT_CONFIG.smsExtractionSuccessReplyBody) ?: DEFAULT_CONFIG.smsExtractionSuccessReplyBody,
            smsExtractionFailedReplyBody = p.getString(KEY_SMS_EXTRACTION_FAILED_REPLY_BODY, DEFAULT_CONFIG.smsExtractionFailedReplyBody)
                ?: DEFAULT_CONFIG.smsExtractionFailedReplyBody,
            defaultSendTargetFilterName = p.getString(KEY_DEFAULT_SEND_TARGET_FILTER_NAME, DEFAULT_CONFIG.defaultSendTargetFilterName),
            aiExtractionEnabled = p.getBoolean(KEY_AI_EXTRACTION_ENABLED, DEFAULT_CONFIG.aiExtractionEnabled),
            companyNameExtractionEnabled = p.getBoolean(KEY_COMPANY_NAME_EXTRACTION_ENABLED, DEFAULT_CONFIG.companyNameExtractionEnabled),
            companyNameAutoConversionEnabled = p.getBoolean(KEY_COMPANY_NAME_AUTO_CONVERSION_ENABLED, DEFAULT_CONFIG.companyNameAutoConversionEnabled),
            companyNameFixedConversions = p.getString(KEY_COMPANY_NAME_FIXED_CONVERSIONS, null)?.let { json ->
                val arr = JSONArray(json)
                (0 until arr.length()).map { i ->
                    val obj = arr.getJSONObject(i)
                    FixedConversion(from = obj.optString("from", ""), to = obj.optString("to", ""))
                }
            } ?: DEFAULT_CONFIG.companyNameFixedConversions,
            defaultSendNoneOnlyEnabled = p.getBoolean(KEY_DEFAULT_SEND_NONE_ONLY_ENABLED, DEFAULT_CONFIG.defaultSendNoneOnlyEnabled),
            defaultExtractionFailedOnlyEnabled = p.getBoolean(KEY_DEFAULT_EXTRACTION_FAILED_ONLY_ENABLED, DEFAULT_CONFIG.defaultExtractionFailedOnlyEnabled),
            defaultExtractionSucceededOnlyEnabled = p.getBoolean(KEY_DEFAULT_EXTRACTION_SUCCEEDED_ONLY_ENABLED, DEFAULT_CONFIG.defaultExtractionSucceededOnlyEnabled),
            defaultExtractionNotPerformedOnlyEnabled = p.getBoolean(KEY_DEFAULT_EXTRACTION_NOT_PERFORMED_ONLY_ENABLED, DEFAULT_CONFIG.defaultExtractionNotPerformedOnlyEnabled),
            defaultSentAutoOnlyEnabled = p.getBoolean(KEY_DEFAULT_SENT_AUTO_ONLY_ENABLED, DEFAULT_CONFIG.defaultSentAutoOnlyEnabled),
            defaultSentManualOnlyEnabled = p.getBoolean(KEY_DEFAULT_SENT_MANUAL_ONLY_ENABLED, DEFAULT_CONFIG.defaultSentManualOnlyEnabled)
        )
    }

    /**
     * [Config]をインポートファイル用のJSONオブジェクトへ変換する。復元は[configFromJson]を参照
     */
    fun configToJson(config: Config): JSONObject = JSONObject()
        .put("sendEnabled", config.sendEnabled)
        .put("sendExtractionFailedEnabled", config.sendExtractionFailedEnabled)
        .put("sendExtractionNotPerformedEnabled", config.sendExtractionNotPerformedEnabled)
        .put("searchExtractionFailedEnabled", config.searchExtractionFailedEnabled)
        .put("searchExtractionNotPerformedEnabled", config.searchExtractionNotPerformedEnabled)
        .put("autoReplyExtractionFailedEnabled", config.autoReplyExtractionFailedEnabled)
        .put("autoReplyCooldownSeconds", config.autoReplyCooldownSeconds)
        .put("autoRefreshEnabled", config.autoRefreshEnabled)
        .put("autoRefreshIntervalSeconds", config.autoRefreshIntervalSeconds)
        .put("smsMatchToleranceSeconds", config.smsMatchToleranceSeconds)
        .put("bodyExcerptLength", config.bodyExcerptLength)
        .put("continuationEnabled", config.continuationEnabled)
        .put("continuationScope", config.continuationScope.name)
        .put("continuationShowUserNameEnabled", config.continuationShowUserNameEnabled)
        .put("themeMode", config.themeMode.name)
        .put("smsSearchDateRangeDays", config.smsSearchDateRangeDays)
        .put("searchFiltersVisibleByDefault", config.searchFiltersVisibleByDefault)
        .put("smsExtractionSuccessReplyBody", config.smsExtractionSuccessReplyBody)
        .put("smsExtractionFailedReplyBody", config.smsExtractionFailedReplyBody)
        .put("defaultSendTargetFilterName", config.defaultSendTargetFilterName ?: JSONObject.NULL)
        .put("aiExtractionEnabled", config.aiExtractionEnabled)
        .put("companyNameExtractionEnabled", config.companyNameExtractionEnabled)
        .put("companyNameAutoConversionEnabled", config.companyNameAutoConversionEnabled)
        .put("companyNameFixedConversions", JSONArray().apply {
            config.companyNameFixedConversions.forEach { rule ->
                put(JSONObject().put("from", rule.from).put("to", rule.to))
            }
        })
        .put("defaultSendNoneOnlyEnabled", config.defaultSendNoneOnlyEnabled)
        .put("defaultExtractionFailedOnlyEnabled", config.defaultExtractionFailedOnlyEnabled)
        .put("defaultExtractionSucceededOnlyEnabled", config.defaultExtractionSucceededOnlyEnabled)
        .put("defaultExtractionNotPerformedOnlyEnabled", config.defaultExtractionNotPerformedOnlyEnabled)
        .put("defaultSentAutoOnlyEnabled", config.defaultSentAutoOnlyEnabled)
        .put("defaultSentManualOnlyEnabled", config.defaultSentManualOnlyEnabled)

    /**
     * インポートファイルのJSONオブジェクトから[Config]を復元する。欠落したキーは[load]と同じ
     * 既定値（[DEFAULT_CONFIG]）で補うため、部分的な指定にも対応する
     */
    fun configFromJson(json: JSONObject): Config = Config(
        sendEnabled = json.optBoolean("sendEnabled", DEFAULT_CONFIG.sendEnabled),
        sendExtractionFailedEnabled = json.optBoolean("sendExtractionFailedEnabled", DEFAULT_CONFIG.sendExtractionFailedEnabled),
        sendExtractionNotPerformedEnabled = json.optBoolean("sendExtractionNotPerformedEnabled", DEFAULT_CONFIG.sendExtractionNotPerformedEnabled),
        searchExtractionFailedEnabled = json.optBoolean("searchExtractionFailedEnabled", DEFAULT_CONFIG.searchExtractionFailedEnabled),
        searchExtractionNotPerformedEnabled = json.optBoolean("searchExtractionNotPerformedEnabled", DEFAULT_CONFIG.searchExtractionNotPerformedEnabled),
        autoReplyExtractionFailedEnabled = json.optBoolean("autoReplyExtractionFailedEnabled", DEFAULT_CONFIG.autoReplyExtractionFailedEnabled),
        autoReplyCooldownSeconds = json.optInt("autoReplyCooldownSeconds", DEFAULT_CONFIG.autoReplyCooldownSeconds),
        autoRefreshEnabled = json.optBoolean("autoRefreshEnabled", DEFAULT_CONFIG.autoRefreshEnabled),
        autoRefreshIntervalSeconds = json.optInt("autoRefreshIntervalSeconds", DEFAULT_CONFIG.autoRefreshIntervalSeconds),
        smsMatchToleranceSeconds = json.optInt("smsMatchToleranceSeconds", DEFAULT_CONFIG.smsMatchToleranceSeconds),
        bodyExcerptLength = json.optInt("bodyExcerptLength", DEFAULT_CONFIG.bodyExcerptLength),
        continuationEnabled = json.optBoolean("continuationEnabled", DEFAULT_CONFIG.continuationEnabled),
        continuationScope = ContinuationScope.fromName(json.optString("continuationScope", "")),
        continuationShowUserNameEnabled = json.optBoolean("continuationShowUserNameEnabled", DEFAULT_CONFIG.continuationShowUserNameEnabled),
        themeMode = ThemeMode.fromName(json.optString("themeMode", "")),
        smsSearchDateRangeDays = json.optInt("smsSearchDateRangeDays", DEFAULT_CONFIG.smsSearchDateRangeDays),
        searchFiltersVisibleByDefault = json.optBoolean("searchFiltersVisibleByDefault", DEFAULT_CONFIG.searchFiltersVisibleByDefault),
        smsExtractionSuccessReplyBody = json.optString("smsExtractionSuccessReplyBody", DEFAULT_CONFIG.smsExtractionSuccessReplyBody),
        smsExtractionFailedReplyBody = json.optString("smsExtractionFailedReplyBody", DEFAULT_CONFIG.smsExtractionFailedReplyBody),
        defaultSendTargetFilterName = if (json.has("defaultSendTargetFilterName") && !json.isNull("defaultSendTargetFilterName")) {
            json.optString("defaultSendTargetFilterName")
        } else {
            DEFAULT_CONFIG.defaultSendTargetFilterName
        },
        aiExtractionEnabled = json.optBoolean("aiExtractionEnabled", DEFAULT_CONFIG.aiExtractionEnabled),
        companyNameExtractionEnabled = json.optBoolean("companyNameExtractionEnabled", DEFAULT_CONFIG.companyNameExtractionEnabled),
        companyNameAutoConversionEnabled = json.optBoolean("companyNameAutoConversionEnabled", DEFAULT_CONFIG.companyNameAutoConversionEnabled),
        companyNameFixedConversions = json.optJSONArray("companyNameFixedConversions")?.let { arr ->
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                FixedConversion(from = obj.optString("from", ""), to = obj.optString("to", ""))
            }
        } ?: DEFAULT_CONFIG.companyNameFixedConversions,
        defaultSendNoneOnlyEnabled = json.optBoolean("defaultSendNoneOnlyEnabled", DEFAULT_CONFIG.defaultSendNoneOnlyEnabled),
        defaultExtractionFailedOnlyEnabled = json.optBoolean("defaultExtractionFailedOnlyEnabled", DEFAULT_CONFIG.defaultExtractionFailedOnlyEnabled),
        defaultExtractionSucceededOnlyEnabled = json.optBoolean("defaultExtractionSucceededOnlyEnabled", DEFAULT_CONFIG.defaultExtractionSucceededOnlyEnabled),
        defaultExtractionNotPerformedOnlyEnabled = json.optBoolean("defaultExtractionNotPerformedOnlyEnabled", DEFAULT_CONFIG.defaultExtractionNotPerformedOnlyEnabled),
        defaultSentAutoOnlyEnabled = json.optBoolean("defaultSentAutoOnlyEnabled", DEFAULT_CONFIG.defaultSentAutoOnlyEnabled),
        defaultSentManualOnlyEnabled = json.optBoolean("defaultSentManualOnlyEnabled", DEFAULT_CONFIG.defaultSentManualOnlyEnabled)
    )

    /**
     * インポートファイル用に[SendTarget]をJSONオブジェクトへ変換する。送信先ID（[SendTarget.id]）は
     * セッション内のカード追跡専用のため、エクスポート対象に含めない（送信先名[SendTarget.name]を
     * 一意キーとして扱う）。復元は[sendTargetFromJson]を参照
     */
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

    /** インポートファイルのJSONオブジェクトから[SendTarget]を復元する。欠落したキーは既定値で補う。
     * idはインポート/エクスポートファイルに含めない（[sendTargetToJson]参照）ため、常に新規UUIDを採番する。
     * つまり同じ送信先名[SendTarget.name]でもインポートのたびに別のIDになる（送信先名が一意キーで、
     * IDはセッション内のカード追跡専用） */
    fun sendTargetFromJson(obj: JSONObject): SendTarget = SendTarget(
        id = UUID.randomUUID().toString(),
        name = obj.optString("name", ""),
        companyName = obj.optString("companyName", ""),
        keywords = obj.optJSONArray("keywords")?.let { array ->
            (0 until array.length()).map { array.getString(it) }
        } ?: emptyList(),
        subdomain = obj.optString("subdomain", ""),
        appId = obj.optString("appId", ""),
        loginName = obj.optString("loginName", ""),
        loginPassword = obj.optString("loginPassword", ""),
        fieldSender = obj.optString("fieldSender", ""),
        fieldHistory = obj.optString("fieldHistory", ""),
        fieldDatetime = obj.optString("fieldDatetime", ""),
        fieldType = obj.optString("fieldType", ""),
        updateToleranceHours = obj.optInt("updateToleranceHours", AppDefaults.UPDATE_TOLERANCE_HOURS),
        updateToleranceMode = UpdateToleranceMode.fromName(obj.optString("updateToleranceMode", "")),
        fieldCompanyName = obj.optString("fieldCompanyName", ""),
        fieldUserName = obj.optString("fieldUserName", ""),
        fieldBody = obj.optString("fieldBody", "")
    )

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
     * [AppConstants.SEND_TARGET_FILTER_KEY_UNSET]は「未設定」を表す。
     * キーは送信先名[SendTarget.name]（送信先ID[SendTarget.id]はファイル外のセッション追跡専用なので使わない）
     */
    fun sendTargetFilterOptions(context: Context): List<Pair<String?, String>> {
        val sendTargets = loadSendTargets(context)
        return listOf(null to context.getString(R.string.filter_send_target_all)) +
            sendTargets.map { it.name to it.displayName(context) } +
            listOf(AppConstants.SEND_TARGET_FILTER_KEY_UNSET to context.getString(R.string.label_send_target_none))
    }

    /** [SendTarget]のリストをJSON配列にシリアライズして保存する。読み込みは[loadSendTargets]を使うこと */
    fun saveSendTargets(context: Context, sendTargets: List<SendTarget>) {
        val array = JSONArray()
        sendTargets.forEach { array.put(sendTargetToJson(it)) }
        prefs(context).edit().putString(KEY_SEND_TARGETS, array.toString()).apply()
    }

    /**
     * 設定のインポート用に、既存の送信先一覧へ[imported]（ファイルから読み込んだ送信先）を
     * 送信先名（[SendTarget.name]）をキーにマージする。既存に同じ送信先名があればその内容を
     * インポート内容で上書きし、ID（[SendTarget.id]）は既存のまま保持する
     * （[Config.defaultSendTargetFilterName]などからの参照を維持するため）。同じ送信先名が無ければ
     * インポート内容を新規追加し、ファイルに含まれない既存の送信先は変更しない
     */
    fun mergeImportSendTargets(context: Context, imported: List<SendTarget>): List<SendTarget> {
        val merged = loadSendTargets(context).toMutableList()
        imported.forEach { from ->
            val index = merged.indexOfFirst { it.name == from.name }
            if (index >= 0) {
                merged[index] = merged[index].copy(
                    companyName = from.companyName,
                    keywords = from.keywords,
                    subdomain = from.subdomain,
                    appId = from.appId,
                    loginName = from.loginName,
                    loginPassword = from.loginPassword,
                    fieldSender = from.fieldSender,
                    fieldHistory = from.fieldHistory,
                    fieldDatetime = from.fieldDatetime,
                    fieldType = from.fieldType,
                    updateToleranceHours = from.updateToleranceHours,
                    updateToleranceMode = from.updateToleranceMode,
                    fieldCompanyName = from.fieldCompanyName,
                    fieldUserName = from.fieldUserName,
                    fieldBody = from.fieldBody
                )
            } else {
                merged.add(from)
            }
        }
        return merged
    }

    /** [saveSendTargets]で保存した送信先設定を読み込む。未保存（初回起動など）の場合は[createDefaultSendTarget]で1件生成する */
    fun loadSendTargets(context: Context): List<SendTarget> {
        val json = prefs(context).getString(KEY_SEND_TARGETS, null)
            ?: return createDefaultSendTarget(context)

        val array = JSONArray(json)
        return (0 until array.length()).map { i -> sendTargetFromJson(array.getJSONObject(i)) }
    }

    /** 送信先が1件も保存されていない場合に、空の送信先を1件作成して保存する（[loadSendTargets]専用） */
    private fun createDefaultSendTarget(context: Context): List<SendTarget> {
        val sendTargets = listOf(SendTarget.newEmpty())
        saveSendTargets(context, sendTargets)
        return sendTargets
    }

    /**
     * 抽出結果の会社名に、アプリ全体の会社名変換（[Config.companyNameAutoConversionEnabled]の
     * 幅変換、続いて[Config.companyNameFixedConversions]の固定変換の順）を適用する。[resolveSendTargets]で
     * 抽出直後に一度だけ呼び、以降（送信先の判定・送信元情報の登録・kintoneへの送信・ログ表示）は
     * すべてこの変換済みの値をそのまま使う
     */
    fun applyCompanyNameConversion(companyName: String, config: Config): String {
        val autoConverted = if (config.companyNameAutoConversionEnabled) {
            TextNormalization.normalizeWidth(companyName)
        } else {
            companyName
        }
        return config.companyNameFixedConversions.fold(autoConverted) { acc, rule ->
            if (rule.from.isNotEmpty()) acc.replace(rule.from, rule.to) else acc
        }
    }

    /**
     * 会社名にキーワードが一致する送信先を（複数あれば）すべて返す。1件も一致しなければ、キーワード
     * 未設定（デフォルト）の送信先1件にフォールバックする。該当が無ければ空リスト
     */
    fun findSendTargets(context: Context, companyName: String): List<SendTarget> {
        val sendTargets = loadSendTargets(context)
        val matched = sendTargets.filter { it.routesTo(companyName) }
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
     * - 引き継ぎ：[continuationEnabled]で同一送信元の直近の抽出成功結果があれば、その会社名・氏名を
     *   引き継いで[isContinuation]をtrueにする（本文は今回分）。送信先は引き継いだ会社名を現在の送信先
     *   ルールに通して都度判定するため、設定の変更・削除が即時反映される。
     * - 通常解析：本文を解析し、抽出直後に会社名変換（[applyCompanyNameConversion]）を一度適用する。
     *   以降は戻り値の会社名をそのまま使えばよい。
     * - 会社名抽出が無効：[companyNameExtractionEnabled]がfalse。本文から抽出せず振り分けもせず、
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
        aiExtractionEnabled: Boolean,
        companyNameExtractionEnabled: Boolean,
        continuationEnabled: Boolean,
        continuationScope: ContinuationScope
    ): Pair<SmsResolution, List<SendTarget>> {
        val previousEntry = if (continuationEnabled) {
            ContinuationStore.find(context, sender, timestampMillis, sameDayOnly = continuationScope == ContinuationScope.SAME_DAY)
        } else {
            null
        }
        if (previousEntry != null) {
            val smsParts = SmsParts(
                companyName = previousEntry.companyName,
                userName = previousEntry.userName,
                body = body.trim()
            )
            val resolution = SmsResolution(smsParts = smsParts, isContinuation = true)
            // 送信先は保持せず、引き継いだ会社名を現在の送信先ルールに通して都度判定する
            val sendTargets = if (companyNameExtractionEnabled) {
                findSendTargets(context, previousEntry.companyName)
            } else {
                loadSendTargets(context)
            }
            return resolution to sendTargets
        }
        val extracted = SmsPartsGenerator.resolveSmsParts(body, aiExtractionEnabled, companyNameExtractionEnabled)
        val config = load(context)
        val sendTargets = if (companyNameExtractionEnabled) {
            findSendTargets(context, extracted.companyName)
        } else {
            loadSendTargets(context)
        }
        // 会社名抽出が無効な場合は本文から会社名を抽出しないため、共有SmsPartsには先頭の送信先の会社名を
        // 変換適用した値をプレースホルダとして入れる（検索画面・受信ログなど送信先ごとに分かれない表示用）。
        // 実際のkintone登録・送信ログではKintoneUploadWorkerが送信先ごとの「会社名」を使う
        val companyNameSource = if (companyNameExtractionEnabled) {
            extracted.companyName
        } else {
            sendTargets.firstOrNull()?.companyName.orEmpty()
        }
        val finalParts = extracted.copy(companyName = applyCompanyNameConversion(companyNameSource, config))
        return SmsResolution(smsParts = finalParts) to sendTargets
    }
}

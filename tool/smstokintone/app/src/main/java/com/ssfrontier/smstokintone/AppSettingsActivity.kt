package com.ssfrontier.smstokintone

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.text.TextWatcher
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.widget.addTextChangedListener
import com.ssfrontier.smstokintone.databinding.ActivityAppSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemFixedConversionBinding

/**
 * アプリの設定画面。すべての設定項目の変更はリアルタイムで [SettingsStore] へ保存される
 * （確定ボタンはない）。他画面での設定変更を反映するため [onResume] ごとに表示を更新。
 */
class AppSettingsActivity : BaseActivity() {

    /** ビューバインディング（レイアウト要素へのアクセス）。 */
    private lateinit var binding: ActivityAppSettingsBinding

    /**
     * 「送信先」スピナー選択位置と対応する送信先リスト。
     * [SettingsStore.sendTargetFilterOptions] の並び順に対応。
     */
    private var searchSendTargetFilterNames: List<String?> = emptyList()

    /** SMS受信権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updatePermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_app_settings_sms_receive_permission_denied)
        }

    /** SMS送信権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestSendSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateSendPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_app_settings_sms_send_permission_denied)
        }

    /** SMS読み取り権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestReadSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateReadPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_app_settings_sms_read_permission_denied)
        }

    /** 権限拒否時のトースト表示。 */
    private fun showPermissionDeniedToast(messageResId: Int) {
        Toast.makeText(this, getString(messageResId), Toast.LENGTH_LONG).show()
    }


    /**
     * EditText の入力値が 1 以上の正整数のときだけ [onChanged] を実行。
     * クールダウン秒・自動更新間隔・統合範囲など、数値設定の重複検証を避けるためのヘルパー。
     *
     * @param onChanged 有効な正整数入力時に実行するコールバック
     */
    private fun EditText.onPositiveIntChanged(onChanged: (Int) -> Unit) {
        val watcher = simpleTextWatcher { text ->
            val value = text.toIntOrNull() ?: return@simpleTextWatcher
            if (value < 1) return@simpleTextWatcher
            onChanged(value)
        }
        setupManaged(watcher)
    }

    /**
     * 固定変換ルール（名前変換）の行をコンテナに追加。
     * 行内容の変更時に [saveFixedConversions] で自動保存。
     *
     * @param container 行を追加する親レイアウト
     * @param from 変換前の文字列
     * @param to 変換後の文字列
     */
    private fun addFixedConversionRow(container: LinearLayout, from: String, to: String, enabled: Boolean = true) {
        val rowBinding = ItemFixedConversionBinding.inflate(layoutInflater, container, false)
        rowBinding.etFixConversionBefore.setText(from)
        rowBinding.etFixConversionAfter.setText(to)
        rowBinding.etFixConversionBefore.isEnabled = enabled
        rowBinding.etFixConversionAfter.isEnabled = enabled
        rowBinding.btnDeleteFixedConversion.isEnabled = enabled

        val beforeWatcher = simpleTextWatcher { saveFixedConversions() }
        val afterWatcher = simpleTextWatcher { saveFixedConversions() }

        rowBinding.etFixConversionBefore.setupManaged(beforeWatcher)
        rowBinding.etFixConversionAfter.setupManaged(afterWatcher)

        val deleteListener = View.OnClickListener {
            container.removeView(rowBinding.root)
            saveFixedConversions()
        }
        rowBinding.btnDeleteFixedConversion.setupManaged(deleteListener)
        container.addView(rowBinding.root)
    }

    /**
     * llFixedConversionsContainer 内の全行の現在内容で [SettingsStore.Config.extractionCompanyNameFixedConversions] を保存。
     * 各行の EditText 内容を読み取り、[SettingsStore.FixedConversion] リストに変換して永続化。
     */
    private fun saveFixedConversions() {
        val rules = (0 until binding.llFixedConversionsContainer.childCount).map { index ->
            val row = binding.llFixedConversionsContainer.getChildAt(index)
            SettingsStore.FixedConversion(
                from = row.findViewById<EditText>(R.id.etFixConversionBefore).text.toString().trim(),
                to = row.findViewById<EditText>(R.id.etFixConversionAfter).text.toString().trim()
            )
        }
        SettingsStore.update(this) { it.copy(extractionCompanyNameFixedConversions = rules) }
    }


    /**
     * llFixedConversionsContainer 内の全行の EditText と Button の Enable/Disable 状態を更新。
     */
    private fun updateFixedConversionsRowState(enabled: Boolean) {
        for (i in 0 until binding.llFixedConversionsContainer.childCount) {
            val row = binding.llFixedConversionsContainer.getChildAt(i)
            row.findViewById<EditText>(R.id.etFixConversionBefore).isEnabled = enabled
            row.findViewById<EditText>(R.id.etFixConversionAfter).isEnabled = enabled
            row.findViewById<android.widget.Button>(R.id.btnDeleteFixedConversion).isEnabled = enabled
        }
    }

    /**
     * UI 初期化と設定値の反映。
     * すべての設定項目に現在値を反映し、変更時に [SettingsStore] へ自動保存するリスナーを登録。
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityAppSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val config = SettingsStore.load(this)
        val sendEnabled = config.sendEnabled
        binding.rbSendAuto.isChecked = sendEnabled
        binding.rbSendManual.isChecked = !sendEnabled
        binding.swSendExtractionFailedEnabled.isEnabled = sendEnabled
        binding.swSendExtractionContinuationEnabled.isEnabled = sendEnabled
        val sendModeListener = RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSendAuto.id
            SettingsStore.update(this) { it.copy(sendEnabled = enabled) }
            binding.swSendExtractionFailedEnabled.isEnabled = enabled
            binding.swSendExtractionContinuationEnabled.isEnabled = enabled
        }
        binding.rgSendMode.setupManaged(sendModeListener)

        binding.swSendExtractionFailedEnabled.isChecked = config.sendExtractionFailedEnabled
        val sendFailedListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(sendExtractionFailedEnabled = isChecked) }
        }
        binding.swSendExtractionFailedEnabled.setupManaged(sendFailedListener)

        binding.swSendExtractionContinuationEnabled.isChecked = config.sendExtractionContinuationEnabled
        val sendContinuationListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(sendExtractionContinuationEnabled = isChecked) }
        }
        binding.swSendExtractionContinuationEnabled.setupManaged(sendContinuationListener)

        binding.swAiExtractionEnabled.isChecked = config.extractionAiEnabled
        val aiExtractionListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(extractionAiEnabled = isChecked) }
        }
        binding.swAiExtractionEnabled.setupManaged(aiExtractionListener)

        val bodyExtractionConfig = config
        var previousCompanyNameExtractionEnabled = bodyExtractionConfig.extractionCompanyNameEnabled
        binding.swCompanyNameExtractionEnabled.isChecked = previousCompanyNameExtractionEnabled
        val companyNameExtractionListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            if (isChecked && !previousCompanyNameExtractionEnabled) {
                val noCompanyNameCount = ContinuationStore.getAll(this).values.count { it.companyName.isBlank() }
                if (noCompanyNameCount > 0) {
                    AlertDialog.Builder(this)
                        .setTitle(R.string.dialog_title_continuation_info_settings_company_name_extraction_warning)
                        .setMessage(getString(R.string.dialog_message_continuation_info_settings_company_name_extraction_warning, noCompanyNameCount))
                        .setPositiveButton(android.R.string.ok) { _, _ ->
                            SettingsStore.update(this) { it.copy(extractionCompanyNameEnabled = isChecked) }
                            previousCompanyNameExtractionEnabled = isChecked
                            binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                            binding.btnAddFixedConversion.isEnabled = isChecked
                            updateFixedConversionsRowState(isChecked)
                        }
                        .setNegativeButton(android.R.string.cancel) { _, _ ->
                            binding.swCompanyNameExtractionEnabled.isChecked = previousCompanyNameExtractionEnabled
                        }
                        .show().setupManaged()
                } else {
                    SettingsStore.update(this) { it.copy(extractionCompanyNameEnabled = isChecked) }
                    previousCompanyNameExtractionEnabled = isChecked
                    binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                    binding.btnAddFixedConversion.isEnabled = isChecked
                    updateFixedConversionsRowState(isChecked)
                }
            } else {
                SettingsStore.update(this) { it.copy(extractionCompanyNameEnabled = isChecked) }
                previousCompanyNameExtractionEnabled = isChecked
                binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                binding.btnAddFixedConversion.isEnabled = isChecked
                updateFixedConversionsRowState(isChecked)
            }
        }
        binding.swCompanyNameExtractionEnabled.setupManaged(companyNameExtractionListener)

        binding.swCompanyNameAutoConversionEnabled.isChecked = bodyExtractionConfig.extractionCompanyNameAutoConversionEnabled
        binding.swCompanyNameAutoConversionEnabled.isEnabled = bodyExtractionConfig.extractionCompanyNameEnabled
        val companyNameAutoConversionListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(extractionCompanyNameAutoConversionEnabled = isChecked) }
        }
        binding.swCompanyNameAutoConversionEnabled.setupManaged(companyNameAutoConversionListener)
        bodyExtractionConfig.extractionCompanyNameFixedConversions.forEach { addFixedConversionRow(binding.llFixedConversionsContainer, it.from, it.to, enabled = bodyExtractionConfig.extractionCompanyNameEnabled) }
        binding.btnAddFixedConversion.isEnabled = bodyExtractionConfig.extractionCompanyNameEnabled
        val addFixedConversionListener = View.OnClickListener { addFixedConversionRow(binding.llFixedConversionsContainer, "", "", enabled = bodyExtractionConfig.extractionCompanyNameEnabled) }
        binding.btnAddFixedConversion.setupManaged(addFixedConversionListener)

        binding.swSearchExtractionFailedEnabled.isChecked = config.searchExtractionFailedEnabled
        val searchFailedListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionFailedEnabled = isChecked) }
        }
        binding.swSearchExtractionFailedEnabled.setupManaged(searchFailedListener)

        binding.swSearchExtractionContinuationEnabled.isChecked = config.searchExtractionContinuationEnabled
        val searchContinuationListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionContinuationEnabled = isChecked) }
        }
        binding.swSearchExtractionContinuationEnabled.setupManaged(searchContinuationListener)

        // SMS返信の手動/自動は、SMS送信の送信モードとは独立して管理する
        val replyEnabled = config.replyEnabled
        binding.rbSmsReplyModeAuto.isChecked = replyEnabled
        binding.rbSmsReplyModeManual.isChecked = !replyEnabled
        binding.tilReplyCooldownSeconds.isEnabled = replyEnabled
        val smsReplyModeListener = RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSmsReplyModeAuto.id
            SettingsStore.update(this) { it.copy(replyEnabled = enabled) }
            binding.tilReplyCooldownSeconds.isEnabled = enabled
        }
        binding.rgSmsReplyMode.setupManaged(smsReplyModeListener)

        binding.etReplyCooldownSeconds.setText(config.replyCooldownSeconds.toString())
        binding.etReplyCooldownSeconds.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(replyCooldownSeconds = seconds) }
        }

        binding.swLogRefreshEnabled.isChecked = config.logRefreshEnabled
        binding.etLogRefreshInterval.setText(config.logRefreshIntervalSeconds.toString())
        binding.tilLogRefreshInterval.isEnabled = config.logRefreshEnabled

        val logRefreshEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(logRefreshEnabled = isChecked) }
            binding.tilLogRefreshInterval.isEnabled = isChecked
        }
        binding.swLogRefreshEnabled.setupManaged(logRefreshEnabledListener)
        binding.etLogRefreshInterval.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(logRefreshIntervalSeconds = seconds) }
        }

        binding.etLogMatchToleranceSeconds.setText(config.logMatchToleranceSeconds.toString())
        binding.etLogMatchToleranceSeconds.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(logMatchToleranceSeconds = seconds) }
        }

        binding.etLogBodyExcerptLength.setText(config.logBodyExcerptLength.toString())
        binding.etLogBodyExcerptLength.onPositiveIntChanged { length ->
            SettingsStore.update(this) { it.copy(logBodyExcerptLength = length) }
        }

        binding.swContinuationEnabled.isChecked = config.continuationEnabled
        binding.btnEditContinuationInfo.isEnabled = config.continuationEnabled
        binding.rbContinuationScopeUnlimited.isEnabled = config.continuationEnabled
        binding.rbContinuationScopeSameDay.isEnabled = config.continuationEnabled
        binding.swContinuationShowUserNameEnabled.isEnabled = config.continuationEnabled
        val continuationEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(continuationEnabled = isChecked) }
            binding.btnEditContinuationInfo.isEnabled = isChecked
            binding.rbContinuationScopeUnlimited.isEnabled = isChecked
            binding.rbContinuationScopeSameDay.isEnabled = isChecked
            binding.swContinuationShowUserNameEnabled.isEnabled = isChecked
        }
        binding.swContinuationEnabled.setupManaged(continuationEnabledListener)

        binding.rbContinuationScopeUnlimited.isChecked = config.continuationScope == SettingsStore.ContinuationScope.UNLIMITED
        binding.rbContinuationScopeSameDay.isChecked = config.continuationScope == SettingsStore.ContinuationScope.SAME_DAY
        val continuationScopeListener = RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val scope = if (checkedId == binding.rbContinuationScopeSameDay.id) {
                SettingsStore.ContinuationScope.SAME_DAY
            } else {
                SettingsStore.ContinuationScope.UNLIMITED
            }
            SettingsStore.update(this) { it.copy(continuationScope = scope) }
        }
        binding.rgContinuationScope.setupManaged(continuationScopeListener)

        binding.swContinuationShowUserNameEnabled.isChecked = config.continuationShowUserNameEnabled
        val continuationShowUserNameListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(continuationShowUserNameEnabled = isChecked) }
        }
        binding.swContinuationShowUserNameEnabled.setupManaged(continuationShowUserNameListener)

        val editContinuationInfoListener = View.OnClickListener {
            startActivity(Intent(this, ContinuationInfoSettingsActivity::class.java))
        }
        binding.btnEditContinuationInfo.setupManaged(editContinuationInfoListener)

        binding.etSmsSearchDateRangeDays.setText(config.searchDateRangeDays.toString())
        binding.etSmsSearchDateRangeDays.onPositiveIntChanged { days ->
            SettingsStore.update(this) { it.copy(searchDateRangeDays = days) }
        }

        binding.rbSearchFiltersVisible.isChecked = config.searchFiltersVisibleByDefault
        binding.rbSearchFiltersHidden.isChecked = !config.searchFiltersVisibleByDefault
        val searchFiltersVisibilityListener = RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val visible = checkedId == binding.rbSearchFiltersVisible.id
            SettingsStore.update(this) { it.copy(searchFiltersVisibleByDefault = visible) }
        }
        binding.rgSearchFiltersVisibility.setupManaged(searchFiltersVisibilityListener)

        binding.cbSearchSendNoneOnlyEnabled.isChecked = config.searchSendNoneOnlyEnabled
        val searchSendNoneOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchSendNoneOnlyEnabled = isChecked) }
        }
        binding.cbSearchSendNoneOnlyEnabled.setupManaged(searchSendNoneOnlyEnabledListener)

        binding.cbSearchSentAutoOnlyEnabled.isChecked = config.searchSentAutoOnlyEnabled
        val searchSentAutoOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchSentAutoOnlyEnabled = isChecked) }
        }
        binding.cbSearchSentAutoOnlyEnabled.setupManaged(searchSentAutoOnlyEnabledListener)

        binding.cbSearchSentManualOnlyEnabled.isChecked = config.searchSentManualOnlyEnabled
        val searchSentManualOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchSentManualOnlyEnabled = isChecked) }
        }
        binding.cbSearchSentManualOnlyEnabled.setupManaged(searchSentManualOnlyEnabledListener)

        binding.cbSearchExtractionFailedOnlyEnabled.isChecked = config.searchExtractionFailedOnlyEnabled
        val searchExtractionFailedOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionFailedOnlyEnabled = isChecked) }
        }
        binding.cbSearchExtractionFailedOnlyEnabled.setupManaged(searchExtractionFailedOnlyEnabledListener)

        binding.cbSearchExtractionSucceededOnlyEnabled.isChecked = config.searchExtractionSucceededOnlyEnabled
        val searchExtractionSucceededOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionSucceededOnlyEnabled = isChecked) }
        }
        binding.cbSearchExtractionSucceededOnlyEnabled.setupManaged(searchExtractionSucceededOnlyEnabledListener)

        binding.cbSearchExtractionContinuationOnlyEnabled.isChecked = config.searchExtractionContinuationOnlyEnabled
        val searchExtractionContinuationOnlyEnabledListener = CompoundButton.OnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionContinuationOnlyEnabled = isChecked) }
        }
        binding.cbSearchExtractionContinuationOnlyEnabled.setupManaged(searchExtractionContinuationOnlyEnabledListener)

        val spinnerListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val sendTargetName = searchSendTargetFilterNames.getOrNull(position)
                SettingsStore.update(this@AppSettingsActivity) { it.copy(searchSendTargetFilterName = sendTargetName) }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        binding.spDefaultSendTargetFilter.setupManaged(spinnerListener)

        applyThemeSelection(config.themeMode)

        val themeLightDarkListener = RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val themeMode = if (checkedId == binding.rbThemeDark.id) {
                SettingsStore.ThemeMode.DARK
            } else {
                SettingsStore.ThemeMode.LIGHT
            }
            SettingsStore.update(this) { it.copy(themeMode = themeMode) }
            pendingScrollY = binding.svAppSettings.scrollY
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }
        binding.rgThemeLightDark.setupManaged(themeLightDarkListener)

        val requestPermissionListener = View.OnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
        }
        binding.btnRequestPermission.setupManaged(requestPermissionListener)

        val requestSendPermissionListener = View.OnClickListener {
            requestSendSmsPermissionLauncher.launch(Manifest.permission.SEND_SMS)
        }
        binding.btnRequestSendPermission.setupManaged(requestSendPermissionListener)

        val requestReadPermissionListener = View.OnClickListener {
            requestReadSmsPermissionLauncher.launch(Manifest.permission.READ_SMS)
        }
        binding.btnRequestReadPermission.setupManaged(requestReadPermissionListener)

        binding.etReplySuccessBody.setText(config.replySuccessBody)
        val replySuccessBodyWatcher = simpleTextWatcher { text ->
            SettingsStore.update(this) { it.copy(replySuccessBody = text) }
        }
        binding.etReplySuccessBody.setupManaged(replySuccessBodyWatcher)

        binding.etReplyFailedBody.setText(config.replyFailedBody)
        val replyFailedBodyWatcher = simpleTextWatcher { text ->
            SettingsStore.update(this) { it.copy(replyFailedBody = text) }
        }
        binding.etReplyFailedBody.setupManaged(replyFailedBodyWatcher)

        val resetSettingsListener = View.OnClickListener {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_app_settings_confirm_reset_settings)
                .setMessage(R.string.dialog_message_app_settings_confirm_reset_settings)
                .setNegativeButton(R.string.btn_cancel, null)
                .setPositiveButton(R.string.btn_reset) { _, _ ->
                    SettingsStore.resetToDefaults(this)
                    // resetToDefaults()は既定のライトテーマを保存するだけで、実際に適用中の
                    // AppCompatDelegateの夜間モードまでは切り替えないため、ここで明示的に反映する
                    AppCompatDelegate.setDefaultNightMode(SettingsStore.ThemeMode.LIGHT.toNightMode())
                    // recreate()は破棄前の画面状態（ラジオボタンの選択状態など）を復元してしまい、
                    // リセット直後の値がUIに反映されないため、状態を持ち越さない新しいIntentで開き直す
                    finish()
                    startActivity(Intent(this, AppSettingsActivity::class.java))
                }
                .show().setupManaged()
        }
        binding.btnResetSettings.setupManaged(resetSettingsListener)

        // テーマ切り替え時にスクロール位置を復元
        pendingScrollY?.let { y ->
            pendingScrollY = null
            binding.svAppSettings.post { binding.svAppSettings.scrollTo(0, y) }
        }
    }

    /**
     * [themeMode]をライト/ダークのラジオボタン選択状態に反映する。
     */
    private fun applyThemeSelection(themeMode: SettingsStore.ThemeMode) {
        binding.rbThemeDark.isChecked = themeMode == SettingsStore.ThemeMode.DARK
        binding.rbThemeLight.isChecked = themeMode != SettingsStore.ThemeMode.DARK
    }

    /**
     * 他画面（権限リクエストや送信先設定）から戻ってきた際に、権限状態と送信先選択肢を最新化する。
     */
    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
        updateSendPermissionStatus()
        updateReadPermissionStatus()
        refreshDefaultSendTargetFilterOptions()
    }

    /**
     * 「送信先」スピナーの選択肢を最新の送信先一覧で更新する。
     */
    private fun refreshDefaultSendTargetFilterOptions() {
        val config = SettingsStore.load(this)
        // 送信先が1件の場合は「すべて」に固定されるため、項目を隠す
        if (SettingsStore.loadSendTargets(this).size == 1) {
            binding.llDefaultSendTargetFilter.visibility = View.GONE
            if (config.searchSendTargetFilterName != null) {
                SettingsStore.update(this) { it.copy(searchSendTargetFilterName = null) }
            }
            return
        }
        binding.llDefaultSendTargetFilter.visibility = View.VISIBLE

        val options = SettingsStore.sendTargetFilterOptions(this)
        searchSendTargetFilterNames = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spDefaultSendTargetFilter.adapter = adapter

        val selectedIndex = searchSendTargetFilterNames.indexOf(config.searchSendTargetFilterName)
        binding.spDefaultSendTargetFilter.setSelection(if (selectedIndex >= 0) selectedIndex else 0)
    }

    /**
     * 権限の許可状態を確認し、ステータス表示・許可ボタン・案内文を更新する。
     */
    private fun updatePermissionUi(
        permission: String,
        statusText: TextView,
        requestButton: View,
        helperText: View,
        grantedLabelResId: Int
    ) {
        val granted = ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

        statusText.text = getString(grantedLabelResId)
        statusText.visibility = if (granted) View.VISIBLE else View.GONE
        requestButton.visibility = if (granted) View.GONE else View.VISIBLE
        helperText.visibility = if (granted) View.GONE else View.VISIBLE
    }

    /**
     * SMS受信権限（[Manifest.permission.RECEIVE_SMS]）の許可状態を画面に反映する。
     */
    private fun updatePermissionStatus() = updatePermissionUi(
        Manifest.permission.RECEIVE_SMS,
        binding.tvPermissionStatus,
        binding.btnRequestPermission,
        binding.tvReceivePermissionHelper,
        R.string.label_app_settings_permission_sms_receive_granted
    )

    /**
     * SMS送信権限（[Manifest.permission.SEND_SMS]）の許可状態を画面に反映する。
     */
    private fun updateSendPermissionStatus() = updatePermissionUi(
        Manifest.permission.SEND_SMS,
        binding.tvSendPermissionStatus,
        binding.btnRequestSendPermission,
        binding.tvSendPermissionHelper,
        R.string.label_app_settings_permission_sms_send_granted
    )

    /**
     * SMS読み取り権限（[Manifest.permission.READ_SMS]）の許可状態を画面に反映する。
     */
    private fun updateReadPermissionStatus() = updatePermissionUi(
        Manifest.permission.READ_SMS,
        binding.tvReadPermissionStatus,
        binding.btnRequestReadPermission,
        binding.tvReadPermissionHelper,
        R.string.label_app_settings_permission_sms_read_granted
    )

    companion object {
        private var pendingScrollY: Int? = null
    }
}

package com.ssfrontier.smstokintone

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.widget.addTextChangedListener
import com.ssfrontier.smstokintone.databinding.ActivityAppSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemFixedConversionBinding

/**
 * アプリの設定画面。すべての設定項目の変更はリアルタイムで [SettingsStore] へ保存される
 * （確定ボタンはない）。他画面での設定変更を反映するため [onResume] ごとに表示を更新。
 */
class AppSettingsActivity : AppCompatActivity() {

    /** ビューバインディング（レイアウト要素へのアクセス）。 */
    private lateinit var binding: ActivityAppSettingsBinding

    /**
     * 「送信先」スピナー選択位置と対応する送信先リスト。
     * [SettingsStore.sendTargetFilterOptions] の並び順に対応。
     */
    private var defaultSendTargetFilterNames: List<String?> = emptyList()

    /** SMS受信権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updatePermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_receive_permission_denied)
        }

    /** SMS送信権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestSendSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateSendPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_send_permission_denied)
        }

    /** SMS読み取り権限リクエスト結果ハンドラ。許可時は表示更新、拒否時はトースト表示。 */
    private val requestReadSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateReadPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_read_permission_denied)
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
        addTextChangedListener { text ->
            val value = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (value < 1) return@addTextChangedListener
            onChanged(value)
        }
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
        rowBinding.etFixConversionBefore.addTextChangedListener { saveFixedConversions() }
        rowBinding.etFixConversionAfter.addTextChangedListener { saveFixedConversions() }
        rowBinding.btnDeleteFixedConversion.setOnClickListener {
            container.removeView(rowBinding.root)
            saveFixedConversions()
        }
        container.addView(rowBinding.root)
    }

    /**
     * llFixedConversionsContainer 内の全行の現在内容で [SettingsStore.Config.companyNameFixedConversions] を保存。
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
        SettingsStore.update(this) { it.copy(companyNameFixedConversions = rules) }
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
        binding.swSendExtractionNotPerformedEnabled.isEnabled = sendEnabled
        binding.rgSendMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSendAuto.id
            SettingsStore.update(this) { it.copy(sendEnabled = enabled) }
            binding.swSendExtractionFailedEnabled.isEnabled = enabled
            binding.swSendExtractionNotPerformedEnabled.isEnabled = enabled
        }

        binding.swSendExtractionFailedEnabled.isChecked = config.sendExtractionFailedEnabled
        binding.swSendExtractionFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(sendExtractionFailedEnabled = isChecked) }
        }

        binding.swSendExtractionNotPerformedEnabled.isChecked = config.sendExtractionNotPerformedEnabled
        binding.swSendExtractionNotPerformedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(sendExtractionNotPerformedEnabled = isChecked) }
        }

        binding.swAiExtractionEnabled.isChecked = config.aiExtractionEnabled
        binding.swAiExtractionEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(aiExtractionEnabled = isChecked) }
        }

        val bodyExtractionConfig = config
        var previousCompanyNameExtractionEnabled = bodyExtractionConfig.companyNameExtractionEnabled
        binding.swCompanyNameExtractionEnabled.isChecked = previousCompanyNameExtractionEnabled
        binding.swCompanyNameExtractionEnabled.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !previousCompanyNameExtractionEnabled) {
                val noCompanyNameCount = ContinuationStore.getAll(this).values.count { it.companyName.isBlank() }
                if (noCompanyNameCount > 0) {
                    AlertDialog.Builder(this)
                        .setTitle(R.string.dialog_title_company_name_extraction_warning)
                        .setMessage(getString(R.string.dialog_message_company_name_extraction_warning, noCompanyNameCount))
                        .setPositiveButton(android.R.string.ok) { _, _ ->
                            SettingsStore.update(this) { it.copy(companyNameExtractionEnabled = isChecked) }
                            previousCompanyNameExtractionEnabled = isChecked
                            binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                            binding.btnAddFixedConversion.isEnabled = isChecked
                            updateFixedConversionsRowState(isChecked)
                        }
                        .setNegativeButton(android.R.string.cancel) { _, _ ->
                            binding.swCompanyNameExtractionEnabled.isChecked = previousCompanyNameExtractionEnabled
                        }
                        .show()
                } else {
                    SettingsStore.update(this) { it.copy(companyNameExtractionEnabled = isChecked) }
                    previousCompanyNameExtractionEnabled = isChecked
                    binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                    binding.btnAddFixedConversion.isEnabled = isChecked
                    updateFixedConversionsRowState(isChecked)
                }
            } else {
                SettingsStore.update(this) { it.copy(companyNameExtractionEnabled = isChecked) }
                previousCompanyNameExtractionEnabled = isChecked
                binding.swCompanyNameAutoConversionEnabled.isEnabled = isChecked
                binding.btnAddFixedConversion.isEnabled = isChecked
                updateFixedConversionsRowState(isChecked)
            }
        }
        binding.swCompanyNameAutoConversionEnabled.isChecked = bodyExtractionConfig.companyNameAutoConversionEnabled
        binding.swCompanyNameAutoConversionEnabled.isEnabled = bodyExtractionConfig.companyNameExtractionEnabled
        binding.swCompanyNameAutoConversionEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(companyNameAutoConversionEnabled = isChecked) }
        }
        bodyExtractionConfig.companyNameFixedConversions.forEach { addFixedConversionRow(binding.llFixedConversionsContainer, it.from, it.to, enabled = bodyExtractionConfig.companyNameExtractionEnabled) }
        binding.btnAddFixedConversion.isEnabled = bodyExtractionConfig.companyNameExtractionEnabled
        binding.btnAddFixedConversion.setOnClickListener { addFixedConversionRow(binding.llFixedConversionsContainer, "", "", enabled = bodyExtractionConfig.companyNameExtractionEnabled) }

        binding.swSearchExtractionFailedEnabled.isChecked = config.searchExtractionFailedEnabled
        binding.swSearchExtractionFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionFailedEnabled = isChecked) }
        }

        binding.swSearchExtractionNotPerformedEnabled.isChecked = config.searchExtractionNotPerformedEnabled
        binding.swSearchExtractionNotPerformedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchExtractionNotPerformedEnabled = isChecked) }
        }

        // SMS返信の手動/自動は、SMS送信の送信モードとは独立して管理する
        val autoReplyExtractionFailedEnabled = config.autoReplyExtractionFailedEnabled
        binding.rbSmsReplyModeAuto.isChecked = autoReplyExtractionFailedEnabled
        binding.rbSmsReplyModeManual.isChecked = !autoReplyExtractionFailedEnabled
        binding.tilAutoReplyCooldownSeconds.isEnabled = autoReplyExtractionFailedEnabled
        binding.rgSmsReplyMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSmsReplyModeAuto.id
            SettingsStore.update(this) { it.copy(autoReplyExtractionFailedEnabled = enabled) }
            binding.tilAutoReplyCooldownSeconds.isEnabled = enabled
        }

        binding.etAutoReplyCooldownSeconds.setText(config.autoReplyCooldownSeconds.toString())
        binding.etAutoReplyCooldownSeconds.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(autoReplyCooldownSeconds = seconds) }
        }

        binding.swAutoRefreshEnabled.isChecked = config.autoRefreshEnabled
        binding.etAutoRefreshInterval.setText(config.autoRefreshIntervalSeconds.toString())
        binding.tilAutoRefreshInterval.isEnabled = config.autoRefreshEnabled

        binding.swAutoRefreshEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(autoRefreshEnabled = isChecked) }
            binding.tilAutoRefreshInterval.isEnabled = isChecked
        }
        binding.etAutoRefreshInterval.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(autoRefreshIntervalSeconds = seconds) }
        }

        binding.etSmsMatchToleranceSeconds.setText(config.smsMatchToleranceSeconds.toString())
        binding.etSmsMatchToleranceSeconds.onPositiveIntChanged { seconds ->
            SettingsStore.update(this) { it.copy(smsMatchToleranceSeconds = seconds) }
        }

        binding.etBodyExcerptLength.setText(config.bodyExcerptLength.toString())
        binding.etBodyExcerptLength.onPositiveIntChanged { length ->
            SettingsStore.update(this) { it.copy(bodyExcerptLength = length) }
        }

        binding.swContinuationEnabled.isChecked = config.continuationEnabled
        binding.btnEditContinuationInfo.isEnabled = config.continuationEnabled
        binding.rbContinuationScopeUnlimited.isEnabled = config.continuationEnabled
        binding.rbContinuationScopeSameDay.isEnabled = config.continuationEnabled
        binding.swContinuationShowUserNameEnabled.isEnabled = config.continuationEnabled
        binding.swContinuationEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(continuationEnabled = isChecked) }
            binding.btnEditContinuationInfo.isEnabled = isChecked
            binding.rbContinuationScopeUnlimited.isEnabled = isChecked
            binding.rbContinuationScopeSameDay.isEnabled = isChecked
            binding.swContinuationShowUserNameEnabled.isEnabled = isChecked
        }

        binding.rbContinuationScopeUnlimited.isChecked = config.continuationScope == SettingsStore.ContinuationScope.UNLIMITED
        binding.rbContinuationScopeSameDay.isChecked = config.continuationScope == SettingsStore.ContinuationScope.SAME_DAY
        binding.rgContinuationScope.setOnCheckedChangeListener { _, checkedId ->
            val scope = if (checkedId == binding.rbContinuationScopeSameDay.id) {
                SettingsStore.ContinuationScope.SAME_DAY
            } else {
                SettingsStore.ContinuationScope.UNLIMITED
            }
            SettingsStore.update(this) { it.copy(continuationScope = scope) }
        }

        binding.swContinuationShowUserNameEnabled.isChecked = config.continuationShowUserNameEnabled
        binding.swContinuationShowUserNameEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(continuationShowUserNameEnabled = isChecked) }
        }

        binding.btnEditContinuationInfo.setOnClickListener {
            startActivity(Intent(this, ContinuationInfoSettingsActivity::class.java))
        }

        binding.etSmsSearchDateRangeDays.setText(config.smsSearchDateRangeDays.toString())
        binding.etSmsSearchDateRangeDays.onPositiveIntChanged { days ->
            SettingsStore.update(this) { it.copy(smsSearchDateRangeDays = days) }
        }

        binding.rbSearchFiltersVisible.isChecked = config.searchFiltersVisibleByDefault
        binding.rbSearchFiltersHidden.isChecked = !config.searchFiltersVisibleByDefault
        binding.rgSearchFiltersVisibility.setOnCheckedChangeListener { _, checkedId ->
            val visible = checkedId == binding.rbSearchFiltersVisible.id
            SettingsStore.update(this) { it.copy(searchFiltersVisibleByDefault = visible) }
        }

        binding.cbDefaultSendNoneOnlyEnabled.isChecked = config.defaultSendNoneOnlyEnabled
        binding.cbDefaultSendNoneOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultSendNoneOnlyEnabled = isChecked) }
        }

        binding.cbDefaultSentAutoOnlyEnabled.isChecked = config.defaultSentAutoOnlyEnabled
        binding.cbDefaultSentAutoOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultSentAutoOnlyEnabled = isChecked) }
        }

        binding.cbDefaultSentManualOnlyEnabled.isChecked = config.defaultSentManualOnlyEnabled
        binding.cbDefaultSentManualOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultSentManualOnlyEnabled = isChecked) }
        }

        binding.cbDefaultExtractionFailedOnlyEnabled.isChecked = config.defaultExtractionFailedOnlyEnabled
        binding.cbDefaultExtractionFailedOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultExtractionFailedOnlyEnabled = isChecked) }
        }

        binding.cbDefaultExtractionSucceededOnlyEnabled.isChecked = config.defaultExtractionSucceededOnlyEnabled
        binding.cbDefaultExtractionSucceededOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultExtractionSucceededOnlyEnabled = isChecked) }
        }

        binding.cbDefaultExtractionNotPerformedOnlyEnabled.isChecked = config.defaultExtractionNotPerformedOnlyEnabled
        binding.cbDefaultExtractionNotPerformedOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultExtractionNotPerformedOnlyEnabled = isChecked) }
        }

            binding.spDefaultSendTargetFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    val sendTargetName = defaultSendTargetFilterNames.getOrNull(position)
                    SettingsStore.update(this@AppSettingsActivity) { it.copy(defaultSendTargetFilterName = sendTargetName) }
                }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        applyThemeSelection(config.themeMode)

        binding.rgThemeLightDark.setOnCheckedChangeListener { _, checkedId ->
            val themeMode = if (checkedId == binding.rbThemeDark.id) {
                SettingsStore.ThemeMode.DARK
            } else {
                SettingsStore.ThemeMode.LIGHT
            }
            SettingsStore.update(this) { it.copy(themeMode = themeMode) }
            pendingScrollY = binding.svAppSettings.scrollY
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }

        binding.btnRequestPermission.setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
        }

        binding.btnRequestSendPermission.setOnClickListener {
            requestSendSmsPermissionLauncher.launch(Manifest.permission.SEND_SMS)
        }

        binding.btnRequestReadPermission.setOnClickListener {
            requestReadSmsPermissionLauncher.launch(Manifest.permission.READ_SMS)
        }

        binding.etSmsExtractionSuccessReplyBody.setText(config.smsExtractionSuccessReplyBody)
        binding.etSmsExtractionSuccessReplyBody.addTextChangedListener { text ->
            SettingsStore.update(this) { it.copy(smsExtractionSuccessReplyBody = text.toString()) }
        }

        binding.etSmsExtractionFailedReplyBody.setText(config.smsExtractionFailedReplyBody)
        binding.etSmsExtractionFailedReplyBody.addTextChangedListener { text ->
            SettingsStore.update(this) { it.copy(smsExtractionFailedReplyBody = text.toString()) }
        }

        binding.btnResetSettings.setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_confirm_reset_settings)
                .setMessage(R.string.dialog_message_confirm_reset_settings)
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
                .show()
        }

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
            if (config.defaultSendTargetFilterName != null) {
                SettingsStore.update(this) { it.copy(defaultSendTargetFilterName = null) }
            }
            return
        }
        binding.llDefaultSendTargetFilter.visibility = View.VISIBLE

        val options = SettingsStore.sendTargetFilterOptions(this)
        defaultSendTargetFilterNames = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spDefaultSendTargetFilter.adapter = adapter

        val selectedIndex = defaultSendTargetFilterNames.indexOf(config.defaultSendTargetFilterName)
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
        R.string.label_permission_sms_receive_granted
    )

    /**
     * SMS送信権限（[Manifest.permission.SEND_SMS]）の許可状態を画面に反映する。
     */
    private fun updateSendPermissionStatus() = updatePermissionUi(
        Manifest.permission.SEND_SMS,
        binding.tvSendPermissionStatus,
        binding.btnRequestSendPermission,
        binding.tvSendPermissionHelper,
        R.string.label_permission_sms_send_granted
    )

    /**
     * SMS読み取り権限（[Manifest.permission.READ_SMS]）の許可状態を画面に反映する。
     */
    private fun updateReadPermissionStatus() = updatePermissionUi(
        Manifest.permission.READ_SMS,
        binding.tvReadPermissionStatus,
        binding.btnRequestReadPermission,
        binding.tvReadPermissionHelper,
        R.string.label_permission_sms_read_granted
    )

    companion object {
        private var pendingScrollY: Int? = null
    }
}

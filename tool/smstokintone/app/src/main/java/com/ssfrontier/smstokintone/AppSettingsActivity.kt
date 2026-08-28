package com.ssfrontier.smstokintone

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.widget.addTextChangedListener
import com.ssfrontier.smstokintone.databinding.ActivityAppSettingsBinding

class AppSettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityAppSettingsBinding

    private var defaultSendTargetFilterKeys: List<String?> = emptyList()

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updatePermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_receive_permission_denied)
        }

    private val requestSendSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateSendPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_send_permission_denied)
        }

    private val requestReadSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateReadPermissionStatus()
            if (!granted) showPermissionDeniedToast(R.string.toast_sms_read_permission_denied)
        }

    private fun showPermissionDeniedToast(messageResId: Int) {
        Toast.makeText(this, getString(messageResId), Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityAppSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val sendEnabled = SettingsStore.load(this).sendEnabled
        binding.rbSendAuto.isChecked = sendEnabled
        binding.rbSendManual.isChecked = !sendEnabled
        binding.swSendSplitFailedEnabled.isEnabled = sendEnabled
        binding.rgSendMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSendAuto.id
            SettingsStore.update(this) { it.copy(sendEnabled = enabled) }
            binding.swSendSplitFailedEnabled.isEnabled = enabled
        }

        binding.swSendSplitFailedEnabled.isChecked = SettingsStore.load(this).sendSplitFailedEnabled
        binding.swSendSplitFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(sendSplitFailedEnabled = isChecked) }
        }

        binding.swAiParsingEnabled.isChecked = SettingsStore.load(this).aiParsingEnabled
        binding.swAiParsingEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(aiParsingEnabled = isChecked) }
        }

        binding.swSearchSplitFailedEnabled.isChecked = SettingsStore.load(this).searchSplitFailedEnabled
        binding.swSearchSplitFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchSplitFailedEnabled = isChecked) }
        }

        binding.swSearchSendTargetUnconfiguredEnabled.isChecked = SettingsStore.load(this).searchSendTargetUnconfiguredEnabled
        binding.swSearchSendTargetUnconfiguredEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(searchSendTargetUnconfiguredEnabled = isChecked) }
        }

        // SMS返信の手動/自動は、SMS送信の送信モードとは独立して管理する
        val autoReplySplitFailedEnabled = SettingsStore.load(this).autoReplySplitFailedEnabled
        binding.rbSmsReplyModeAuto.isChecked = autoReplySplitFailedEnabled
        binding.rbSmsReplyModeManual.isChecked = !autoReplySplitFailedEnabled
        binding.tilAutoReplyCooldownSeconds.isEnabled = autoReplySplitFailedEnabled
        binding.rgSmsReplyMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSmsReplyModeAuto.id
            SettingsStore.update(this) { it.copy(autoReplySplitFailedEnabled = enabled) }
            binding.tilAutoReplyCooldownSeconds.isEnabled = enabled
        }

        binding.etAutoReplyCooldownSeconds.setText(SettingsStore.load(this).autoReplyCooldownSeconds.toString())
        binding.etAutoReplyCooldownSeconds.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.update(this) { it.copy(autoReplyCooldownSeconds = seconds) }
        }

        val config = SettingsStore.load(this)
        binding.swAutoRefreshEnabled.isChecked = config.autoRefreshEnabled
        binding.etAutoRefreshInterval.setText(config.autoRefreshIntervalSeconds.toString())
        binding.tilAutoRefreshInterval.isEnabled = config.autoRefreshEnabled

        binding.swAutoRefreshEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(autoRefreshEnabled = isChecked) }
            binding.tilAutoRefreshInterval.isEnabled = isChecked
        }
        binding.etAutoRefreshInterval.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.update(this) { it.copy(autoRefreshIntervalSeconds = seconds) }
        }

        binding.etSmsMatchToleranceSeconds.setText(config.smsMatchToleranceSeconds.toString())
        binding.etSmsMatchToleranceSeconds.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.update(this) { it.copy(smsMatchToleranceSeconds = seconds) }
        }

        binding.etSmsSearchDateRangeDays.setText(config.smsSearchDateRangeDays.toString())
        binding.etSmsSearchDateRangeDays.addTextChangedListener { text ->
            val days = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (days < 1) return@addTextChangedListener
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

        binding.cbDefaultSplitFailedOnlyEnabled.isChecked = config.defaultSplitFailedOnlyEnabled
        binding.cbDefaultSplitFailedOnlyEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.update(this) { it.copy(defaultSplitFailedOnlyEnabled = isChecked) }
        }

        binding.spDefaultSendTargetFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val sendTargetId = defaultSendTargetFilterKeys.getOrNull(position)
                SettingsStore.update(this@AppSettingsActivity) { it.copy(defaultSendTargetFilterId = sendTargetId) }
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

        binding.etDefaultReplyBody.setText(config.defaultReplyBody)
        binding.etDefaultReplyBody.addTextChangedListener { text ->
            SettingsStore.update(this) { it.copy(defaultReplyBody = text.toString()) }
        }

        binding.etSplitFailedReplyAddition.setText(config.splitFailedReplyAddition)
        binding.etSplitFailedReplyAddition.addTextChangedListener { text ->
            SettingsStore.update(this) { it.copy(splitFailedReplyAddition = text.toString()) }
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

        // ライト/ダーク切り替え時、AppCompatDelegateがActivityを再生成するためスクロール位置が失われる。
        // 切り替え直前の位置を復元し、画面が先頭へ飛んで見えないようにする
        pendingScrollY?.let { y ->
            pendingScrollY = null
            binding.svAppSettings.post { binding.svAppSettings.scrollTo(0, y) }
        }
    }

    private fun applyThemeSelection(themeMode: SettingsStore.ThemeMode) {
        binding.rbThemeDark.isChecked = themeMode == SettingsStore.ThemeMode.DARK
        binding.rbThemeLight.isChecked = themeMode != SettingsStore.ThemeMode.DARK
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
        updateSendPermissionStatus()
        updateReadPermissionStatus()
        refreshDefaultSendTargetFilterOptions()
    }

    private fun refreshDefaultSendTargetFilterOptions() {
        // 送信先が1件しかない場合はSMS検索画面側で常に「すべて」に固定されるため、
        // ここで初期値を設定しても意味を持たない。項目ごと隠して値も「すべて」に揃える
        if (SettingsStore.loadSendTargets(this).size == 1) {
            binding.llDefaultSendTargetFilter.visibility = View.GONE
            if (SettingsStore.load(this).defaultSendTargetFilterId != null) {
                SettingsStore.update(this) { it.copy(defaultSendTargetFilterId = null) }
            }
            return
        }
        binding.llDefaultSendTargetFilter.visibility = View.VISIBLE

        val options = SettingsStore.sendTargetFilterOptions(this)
        defaultSendTargetFilterKeys = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spDefaultSendTargetFilter.adapter = adapter

        val selectedIndex = defaultSendTargetFilterKeys.indexOf(SettingsStore.load(this).defaultSendTargetFilterId)
        binding.spDefaultSendTargetFilter.setSelection(if (selectedIndex >= 0) selectedIndex else 0)
    }

    /**
     * 権限の許可状態を確認し、ステータス表示・許可ボタン・案内文の表示/非表示を切り替える。
     * SMSの受信・送信・読み取りの3権限で同じロジックを繰り返さないよう、対象のビュー一式を
     * 引数で受け取る形にまとめている
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

    private fun updatePermissionStatus() = updatePermissionUi(
        Manifest.permission.RECEIVE_SMS,
        binding.tvPermissionStatus,
        binding.btnRequestPermission,
        binding.tvReceivePermissionHelper,
        R.string.label_permission_sms_receive_granted
    )

    private fun updateSendPermissionStatus() = updatePermissionUi(
        Manifest.permission.SEND_SMS,
        binding.tvSendPermissionStatus,
        binding.btnRequestSendPermission,
        binding.tvSendPermissionHelper,
        R.string.label_permission_sms_send_granted
    )

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

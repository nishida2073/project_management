package com.ssfrontier.smstokintone

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
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
            if (!granted) {
                Toast.makeText(
                    this,
                    getString(R.string.toast_sms_receive_permission_denied),
                    Toast.LENGTH_LONG
                ).show()
            }
        }

    private val requestSendSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateSendPermissionStatus()
            if (!granted) {
                Toast.makeText(this, getString(R.string.toast_sms_send_permission_denied), Toast.LENGTH_LONG).show()
            }
        }

    private val requestReadSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updateReadPermissionStatus()
            if (!granted) {
                Toast.makeText(this, getString(R.string.toast_sms_read_permission_denied), Toast.LENGTH_LONG).show()
            }
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
            SettingsStore.save(this, SettingsStore.load(this).copy(sendEnabled = enabled))
            binding.swSendSplitFailedEnabled.isEnabled = enabled
        }

        binding.swSendSplitFailedEnabled.isChecked = SettingsStore.load(this).sendSplitFailedEnabled
        binding.swSendSplitFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(sendSplitFailedEnabled = isChecked))
        }

        binding.swAiParsingEnabled.isChecked = SettingsStore.load(this).aiParsingEnabled
        binding.swAiParsingEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(aiParsingEnabled = isChecked))
        }

        binding.swSearchSplitFailedEnabled.isChecked = SettingsStore.load(this).searchSplitFailedEnabled
        binding.swSearchSplitFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(searchSplitFailedEnabled = isChecked))
        }

        binding.swSearchSendTargetUnconfiguredEnabled.isChecked = SettingsStore.load(this).searchSendTargetUnconfiguredEnabled
        binding.swSearchSendTargetUnconfiguredEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(searchSendTargetUnconfiguredEnabled = isChecked))
        }

        // SMS返信の手動/自動は、SMS送信の送信モードとは独立して管理する
        val autoReplySplitFailedEnabled = SettingsStore.load(this).autoReplySplitFailedEnabled
        binding.rbSmsReplyModeAuto.isChecked = autoReplySplitFailedEnabled
        binding.rbSmsReplyModeManual.isChecked = !autoReplySplitFailedEnabled
        binding.tilAutoReplyCooldownSeconds.isEnabled = autoReplySplitFailedEnabled
        binding.rgSmsReplyMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbSmsReplyModeAuto.id
            SettingsStore.save(this, SettingsStore.load(this).copy(autoReplySplitFailedEnabled = enabled))
            binding.tilAutoReplyCooldownSeconds.isEnabled = enabled
        }

        binding.etAutoReplyCooldownSeconds.setText(SettingsStore.load(this).autoReplyCooldownSeconds.toString())
        binding.etAutoReplyCooldownSeconds.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.save(this, SettingsStore.load(this).copy(autoReplyCooldownSeconds = seconds))
        }

        val config = SettingsStore.load(this)
        binding.swAutoRefreshEnabled.isChecked = config.autoRefreshEnabled
        binding.etAutoRefreshInterval.setText(config.autoRefreshIntervalSeconds.toString())
        binding.tilAutoRefreshInterval.isEnabled = config.autoRefreshEnabled

        binding.swAutoRefreshEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(autoRefreshEnabled = isChecked))
            binding.tilAutoRefreshInterval.isEnabled = isChecked
        }
        binding.etAutoRefreshInterval.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.save(this, SettingsStore.load(this).copy(autoRefreshIntervalSeconds = seconds))
        }

        binding.etSmsMatchToleranceSeconds.setText(config.smsMatchToleranceSeconds.toString())
        binding.etSmsMatchToleranceSeconds.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            SettingsStore.save(this, SettingsStore.load(this).copy(smsMatchToleranceSeconds = seconds))
        }

        binding.etSmsSearchDateRangeDays.setText(config.smsSearchDateRangeDays.toString())
        binding.etSmsSearchDateRangeDays.addTextChangedListener { text ->
            val days = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (days < 1) return@addTextChangedListener
            SettingsStore.save(this, SettingsStore.load(this).copy(smsSearchDateRangeDays = days))
        }

        binding.rbSearchFiltersVisible.isChecked = config.searchFiltersVisibleByDefault
        binding.rbSearchFiltersHidden.isChecked = !config.searchFiltersVisibleByDefault
        binding.rgSearchFiltersVisibility.setOnCheckedChangeListener { _, checkedId ->
            val visible = checkedId == binding.rbSearchFiltersVisible.id
            SettingsStore.save(this, SettingsStore.load(this).copy(searchFiltersVisibleByDefault = visible))
        }

        binding.spDefaultSendTargetFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val sendTargetId = defaultSendTargetFilterKeys.getOrNull(position)
                SettingsStore.save(this@AppSettingsActivity, SettingsStore.load(this@AppSettingsActivity).copy(defaultSendTargetFilterId = sendTargetId))
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
            SettingsStore.save(this, SettingsStore.load(this).copy(themeMode = themeMode))
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
            SettingsStore.save(this, SettingsStore.load(this).copy(defaultReplyBody = text.toString()))
        }

        binding.etSplitFailedReplyAddition.setText(config.splitFailedReplyAddition)
        binding.etSplitFailedReplyAddition.addTextChangedListener { text ->
            SettingsStore.save(this, SettingsStore.load(this).copy(splitFailedReplyAddition = text.toString()))
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
        val options = SettingsStore.sendTargetFilterOptions(this)
        defaultSendTargetFilterKeys = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spDefaultSendTargetFilter.adapter = adapter

        val selectedIndex = defaultSendTargetFilterKeys.indexOf(SettingsStore.load(this).defaultSendTargetFilterId)
        binding.spDefaultSendTargetFilter.setSelection(if (selectedIndex >= 0) selectedIndex else 0)
    }

    private fun updatePermissionStatus() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED

        binding.tvPermissionStatus.text = getString(R.string.label_permission_sms_receive_granted)
        binding.tvPermissionStatus.visibility = if (granted) View.VISIBLE else View.GONE
        binding.btnRequestPermission.visibility = if (granted) View.GONE else View.VISIBLE
        binding.tvReceivePermissionHelper.visibility = if (granted) View.GONE else View.VISIBLE
    }

    private fun updateSendPermissionStatus() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        binding.tvSendPermissionStatus.text = getString(R.string.label_permission_sms_send_granted)
        binding.tvSendPermissionStatus.visibility = if (granted) View.VISIBLE else View.GONE
        binding.btnRequestSendPermission.visibility = if (granted) View.GONE else View.VISIBLE
        binding.tvSendPermissionHelper.visibility = if (granted) View.GONE else View.VISIBLE
    }

    private fun updateReadPermissionStatus() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_SMS
        ) == PackageManager.PERMISSION_GRANTED

        binding.tvReadPermissionStatus.text = getString(R.string.label_permission_sms_read_granted)
        binding.tvReadPermissionStatus.visibility = if (granted) View.VISIBLE else View.GONE
        binding.btnRequestReadPermission.visibility = if (granted) View.GONE else View.VISIBLE
        binding.tvReadPermissionHelper.visibility = if (granted) View.GONE else View.VISIBLE
    }

    companion object {
        private var pendingScrollY: Int? = null
    }
}

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

    private var defaultProfileFilterKeys: List<String?> = emptyList()

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityAppSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val forwardingEnabled = SettingsStore.load(this).forwardingEnabled
        binding.rbForwardingAuto.isChecked = forwardingEnabled
        binding.rbForwardingManual.isChecked = !forwardingEnabled
        binding.swForwardSplitFailedEnabled.isEnabled = forwardingEnabled
        binding.rgForwardingMode.setOnCheckedChangeListener { _, checkedId ->
            val enabled = checkedId == binding.rbForwardingAuto.id
            SettingsStore.save(this, SettingsStore.load(this).copy(forwardingEnabled = enabled))
            binding.swForwardSplitFailedEnabled.isEnabled = enabled
        }

        binding.swForwardSplitFailedEnabled.isChecked = SettingsStore.load(this).forwardSplitFailedEnabled
        binding.swForwardSplitFailedEnabled.setOnCheckedChangeListener { _, isChecked ->
            SettingsStore.save(this, SettingsStore.load(this).copy(forwardSplitFailedEnabled = isChecked))
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

        binding.spDefaultProfileFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val profileId = defaultProfileFilterKeys.getOrNull(position)
                SettingsStore.save(this@AppSettingsActivity, SettingsStore.load(this@AppSettingsActivity).copy(defaultProfileFilterId = profileId))
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        applyThemeSelection(config.themeMode)

        binding.swThemeFollowSystem.setOnCheckedChangeListener { _, isChecked ->
            binding.rbThemeLight.isEnabled = !isChecked
            binding.rbThemeDark.isEnabled = !isChecked
            val themeMode = if (isChecked) {
                SettingsStore.ThemeMode.SYSTEM
            } else if (binding.rbThemeDark.isChecked) {
                SettingsStore.ThemeMode.DARK
            } else {
                SettingsStore.ThemeMode.LIGHT
            }
            SettingsStore.save(this, SettingsStore.load(this).copy(themeMode = themeMode))
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }
        binding.rgThemeLightDark.setOnCheckedChangeListener { _, checkedId ->
            if (binding.swThemeFollowSystem.isChecked) return@setOnCheckedChangeListener
            val themeMode = if (checkedId == binding.rbThemeDark.id) {
                SettingsStore.ThemeMode.DARK
            } else {
                SettingsStore.ThemeMode.LIGHT
            }
            SettingsStore.save(this, SettingsStore.load(this).copy(themeMode = themeMode))
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }

        binding.btnRequestPermission.setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
        }

        binding.etDefaultReplyBody.setText(config.defaultReplyBody)
        binding.etDefaultReplyBody.addTextChangedListener { text ->
            SettingsStore.save(this, SettingsStore.load(this).copy(defaultReplyBody = text.toString()))
        }

        binding.etSplitFailedReplyAddition.setText(config.splitFailedReplyAddition)
        binding.etSplitFailedReplyAddition.addTextChangedListener { text ->
            SettingsStore.save(this, SettingsStore.load(this).copy(splitFailedReplyAddition = text.toString()))
        }
    }

    private fun applyThemeSelection(themeMode: SettingsStore.ThemeMode) {
        val followSystem = themeMode == SettingsStore.ThemeMode.SYSTEM
        binding.swThemeFollowSystem.isChecked = followSystem
        binding.rbThemeDark.isChecked = themeMode == SettingsStore.ThemeMode.DARK
        binding.rbThemeLight.isChecked = themeMode != SettingsStore.ThemeMode.DARK
        binding.rbThemeLight.isEnabled = !followSystem
        binding.rbThemeDark.isEnabled = !followSystem
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
        refreshDefaultProfileFilterOptions()
    }

    private fun refreshDefaultProfileFilterOptions() {
        val options = SettingsStore.profileFilterOptions(this)
        defaultProfileFilterKeys = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spDefaultProfileFilter.adapter = adapter

        val selectedIndex = defaultProfileFilterKeys.indexOf(SettingsStore.load(this).defaultProfileFilterId)
        binding.spDefaultProfileFilter.setSelection(if (selectedIndex >= 0) selectedIndex else 0)
    }

    private fun updatePermissionStatus() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED

        binding.tvPermissionStatus.text = getString(R.string.label_permission_sms_receive_granted)
        binding.tvPermissionStatus.visibility = if (granted) View.VISIBLE else View.GONE
        binding.btnRequestPermission.visibility = if (granted) View.GONE else View.VISIBLE
    }
}

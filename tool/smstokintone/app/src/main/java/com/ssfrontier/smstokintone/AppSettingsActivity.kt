package com.ssfrontier.smstokintone

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import com.ssfrontier.smstokintone.databinding.ActivityAppSettingsBinding

class AppSettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityAppSettingsBinding

    private val requestPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updatePermissionStatus()
            if (!granted) {
                Toast.makeText(
                    this,
                    "SMS受信の許可がないと、このアプリは動作しません",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityAppSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.swForwardingEnabled.isChecked = Prefs.load(this).forwardingEnabled
        binding.swForwardingEnabled.setOnCheckedChangeListener { _, isChecked ->
            Prefs.save(this, Prefs.load(this).copy(forwardingEnabled = isChecked))
        }

        binding.swLogEnabled.isChecked = Prefs.load(this).logEnabled
        binding.swLogEnabled.setOnCheckedChangeListener { _, isChecked ->
            Prefs.save(this, Prefs.load(this).copy(logEnabled = isChecked))
        }

        val config = Prefs.load(this)
        binding.swAutoRefreshEnabled.isChecked = config.autoRefreshEnabled
        binding.etAutoRefreshInterval.setText(config.autoRefreshIntervalSeconds.toString())

        binding.swAutoRefreshEnabled.setOnCheckedChangeListener { _, isChecked ->
            Prefs.save(this, Prefs.load(this).copy(autoRefreshEnabled = isChecked))
        }
        binding.btnSaveAutoRefreshInterval.setOnClickListener { onSaveAutoRefreshIntervalClicked() }

        when (config.themeMode) {
            Prefs.ThemeMode.SYSTEM -> binding.rbThemeSystem.isChecked = true
            Prefs.ThemeMode.LIGHT -> binding.rbThemeLight.isChecked = true
            Prefs.ThemeMode.DARK -> binding.rbThemeDark.isChecked = true
        }
        binding.rgThemeMode.setOnCheckedChangeListener { _, checkedId ->
            val themeMode = when (checkedId) {
                binding.rbThemeLight.id -> Prefs.ThemeMode.LIGHT
                binding.rbThemeDark.id -> Prefs.ThemeMode.DARK
                else -> Prefs.ThemeMode.SYSTEM
            }
            Prefs.save(this, Prefs.load(this).copy(themeMode = themeMode))
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }

        binding.btnRequestPermission.setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
        }
    }

    private fun onSaveAutoRefreshIntervalClicked() {
        val seconds = binding.etAutoRefreshInterval.text.toString().toIntOrNull()
        if (seconds == null || seconds < 1) {
            Toast.makeText(this, getString(R.string.auto_refresh_interval_error), Toast.LENGTH_LONG).show()
            return
        }

        Prefs.save(this, Prefs.load(this).copy(autoRefreshIntervalSeconds = seconds))
        Toast.makeText(this, "設定を保存しました", Toast.LENGTH_SHORT).show()
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStatus()
    }

    private fun updatePermissionStatus() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED

        binding.tvPermissionStatus.text = if (granted) {
            getString(R.string.permission_status_granted)
        } else {
            getString(R.string.permission_status_denied)
        }
    }
}

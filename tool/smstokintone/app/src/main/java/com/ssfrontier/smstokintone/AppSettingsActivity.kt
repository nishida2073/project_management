package com.ssfrontier.smstokintone

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import androidx.core.widget.addTextChangedListener
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

        val config = Prefs.load(this)
        binding.swAutoRefreshEnabled.isChecked = config.autoRefreshEnabled
        binding.etAutoRefreshInterval.setText(config.autoRefreshIntervalSeconds.toString())
        binding.tilAutoRefreshInterval.isEnabled = config.autoRefreshEnabled

        binding.swAutoRefreshEnabled.setOnCheckedChangeListener { _, isChecked ->
            Prefs.save(this, Prefs.load(this).copy(autoRefreshEnabled = isChecked))
            binding.tilAutoRefreshInterval.isEnabled = isChecked
        }
        binding.etAutoRefreshInterval.addTextChangedListener { text ->
            val seconds = text.toString().toIntOrNull() ?: return@addTextChangedListener
            if (seconds < 1) return@addTextChangedListener
            Prefs.save(this, Prefs.load(this).copy(autoRefreshIntervalSeconds = seconds))
        }

        applyThemeSelection(config.themeMode)

        binding.swThemeFollowSystem.setOnCheckedChangeListener { _, isChecked ->
            binding.rbThemeLight.isEnabled = !isChecked
            binding.rbThemeDark.isEnabled = !isChecked
            val themeMode = if (isChecked) {
                Prefs.ThemeMode.SYSTEM
            } else if (binding.rbThemeDark.isChecked) {
                Prefs.ThemeMode.DARK
            } else {
                Prefs.ThemeMode.LIGHT
            }
            Prefs.save(this, Prefs.load(this).copy(themeMode = themeMode))
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }
        binding.rgThemeLightDark.setOnCheckedChangeListener { _, checkedId ->
            if (binding.swThemeFollowSystem.isChecked) return@setOnCheckedChangeListener
            val themeMode = if (checkedId == binding.rbThemeDark.id) {
                Prefs.ThemeMode.DARK
            } else {
                Prefs.ThemeMode.LIGHT
            }
            Prefs.save(this, Prefs.load(this).copy(themeMode = themeMode))
            AppCompatDelegate.setDefaultNightMode(themeMode.toNightMode())
        }

        binding.btnRequestPermission.setOnClickListener {
            requestPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
        }
    }

    private fun applyThemeSelection(themeMode: Prefs.ThemeMode) {
        val followSystem = themeMode == Prefs.ThemeMode.SYSTEM
        binding.swThemeFollowSystem.isChecked = followSystem
        binding.rbThemeDark.isChecked = themeMode == Prefs.ThemeMode.DARK
        binding.rbThemeLight.isChecked = themeMode != Prefs.ThemeMode.DARK
        binding.rbThemeLight.isEnabled = !followSystem
        binding.rbThemeDark.isEnabled = !followSystem
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
        binding.btnRequestPermission.visibility = if (granted) View.GONE else View.VISIBLE
    }
}

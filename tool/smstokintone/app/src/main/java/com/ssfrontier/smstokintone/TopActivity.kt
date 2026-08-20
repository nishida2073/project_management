package com.ssfrontier.smstokintone

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.ssfrontier.smstokintone.databinding.ActivityTopBinding

class TopActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTopBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnOpenKintoneSettings.setOnClickListener {
            startActivity(Intent(this, KintoneSettingsActivity::class.java))
        }
        binding.btnOpenAppSettings.setOnClickListener {
            startActivity(Intent(this, AppSettingsActivity::class.java))
        }
        binding.btnOpenLog.setOnClickListener {
            startActivity(Intent(this, LogActivity::class.java))
        }
        binding.btnOpenSmsSearch.setOnClickListener {
            startActivity(Intent(this, SmsSearchActivity::class.java))
        }
    }

    override fun onResume() {
        super.onResume()
        updateModeStatus()
    }

    private fun updateModeStatus() {
        val forwardingEnabled = SettingsStore.load(this).forwardingEnabled
        binding.tvTopStatus.text = getString(
            if (forwardingEnabled) R.string.top_status_mode_auto else R.string.top_status_mode_manual
        )
        binding.tvTopStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (forwardingEnabled) R.color.status_running else R.color.status_manual
            )
        )
    }
}

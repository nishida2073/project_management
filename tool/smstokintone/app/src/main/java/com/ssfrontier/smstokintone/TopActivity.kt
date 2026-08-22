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
        val config = SettingsStore.load(this)

        binding.tvTopForwardingStatus.text = getString(
            if (config.forwardingEnabled) R.string.label_top_sms_forwarding_auto else R.string.label_top_sms_forwarding_manual
        )
        binding.tvTopForwardingStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (config.forwardingEnabled) R.color.status_running else R.color.status_manual
            )
        )

        binding.tvTopReplyStatus.text = getString(
            if (config.autoReplySplitFailedEnabled) R.string.label_top_sms_reply_auto else R.string.label_top_sms_reply_manual
        )
        binding.tvTopReplyStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (config.autoReplySplitFailedEnabled) R.color.status_running else R.color.status_manual
            )
        )
    }
}

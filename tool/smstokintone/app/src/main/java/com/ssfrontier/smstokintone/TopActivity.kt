package com.ssfrontier.smstokintone

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivityTopBinding

class TopActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTopBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnOpenKintoneSettings.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
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
}

package com.ssfrontier.smstokintone

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivitySettingsBinding

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val config = Prefs.load(this)
        binding.etSubdomain.setText(config.subdomain)
        binding.etAppId.setText(config.appId)
        binding.etApiToken.setText(config.apiToken)
        binding.etLoginName.setText(config.loginName)
        binding.etLoginPassword.setText(config.loginPassword)
        binding.etFieldPhone.setText(config.fieldPhone)
        binding.etFieldBody.setText(config.fieldBody)
        binding.etFieldDatetime.setText(config.fieldDatetime)

        when (config.authMethod) {
            Prefs.AuthMethod.API_TOKEN -> binding.rbAuthApiToken.isChecked = true
            Prefs.AuthMethod.PASSWORD -> binding.rbAuthPassword.isChecked = true
        }
        updateAuthMethodVisibility(config.authMethod)

        binding.rgAuthMethod.setOnCheckedChangeListener { _, checkedId ->
            val method = if (checkedId == binding.rbAuthPassword.id) {
                Prefs.AuthMethod.PASSWORD
            } else {
                Prefs.AuthMethod.API_TOKEN
            }
            updateAuthMethodVisibility(method)
        }

        binding.btnSave.setOnClickListener { onSaveClicked() }
    }

    private fun updateAuthMethodVisibility(method: Prefs.AuthMethod) {
        binding.tilApiToken.visibility = if (method == Prefs.AuthMethod.API_TOKEN) {
            android.view.View.VISIBLE
        } else {
            android.view.View.GONE
        }
        binding.layoutPasswordAuth.visibility = if (method == Prefs.AuthMethod.PASSWORD) {
            android.view.View.VISIBLE
        } else {
            android.view.View.GONE
        }
    }

    private fun onSaveClicked() {
        val authMethod = if (binding.rbAuthPassword.isChecked) {
            Prefs.AuthMethod.PASSWORD
        } else {
            Prefs.AuthMethod.API_TOKEN
        }

        val newConfig = Prefs.load(this).copy(
            subdomain = binding.etSubdomain.text.toString().trim(),
            appId = binding.etAppId.text.toString().trim(),
            authMethod = authMethod,
            apiToken = binding.etApiToken.text.toString().trim(),
            loginName = binding.etLoginName.text.toString().trim(),
            loginPassword = binding.etLoginPassword.text.toString(),
            fieldPhone = binding.etFieldPhone.text.toString().trim(),
            fieldBody = binding.etFieldBody.text.toString().trim(),
            fieldDatetime = binding.etFieldDatetime.text.toString().trim()
        )

        if (!newConfig.isValid) {
            Toast.makeText(this, getString(R.string.validation_error), Toast.LENGTH_LONG).show()
            return
        }

        Prefs.save(this, newConfig)
        Toast.makeText(this, "設定を保存しました", Toast.LENGTH_SHORT).show()
    }
}

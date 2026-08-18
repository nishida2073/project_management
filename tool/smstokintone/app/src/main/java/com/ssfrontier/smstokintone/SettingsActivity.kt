package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivitySettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemKintoneProfileBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding

    private class ProfileCard(val id: String, val binding: ItemKintoneProfileBinding)

    private val profileCards = mutableListOf<ProfileCard>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        Prefs.loadProfiles(this).forEach { addProfileCard(it) }

        binding.btnAddProfile.setOnClickListener {
            addProfileCard(Prefs.KintoneProfile.newEmpty())
        }
        binding.btnSave.setOnClickListener { onSaveClicked() }
    }

    private fun addProfileCard(profile: Prefs.KintoneProfile, insertAt: Int = -1) {
        val itemBinding = ItemKintoneProfileBinding.inflate(layoutInflater, binding.llProfilesContainer, false)
        val card = ProfileCard(profile.id, itemBinding)

        itemBinding.etProfileName.setText(profile.name)
        itemBinding.etKeywords.setText(profile.keywords)
        itemBinding.etSubdomain.setText(profile.subdomain)
        itemBinding.etAppId.setText(profile.appId)
        itemBinding.etApiToken.setText(profile.apiToken)
        itemBinding.etLoginName.setText(profile.loginName)
        itemBinding.etLoginPassword.setText(profile.loginPassword)
        itemBinding.etFieldSender.setText(profile.fieldSender)
        itemBinding.etFieldBody.setText(profile.fieldBody)
        itemBinding.etFieldDatetime.setText(profile.fieldDatetime)
        itemBinding.etFieldType.setText(profile.fieldType)
        itemBinding.etFieldCompanyName.setText(profile.fieldCompanyName)
        itemBinding.etFieldUserName.setText(profile.fieldUserName)
        itemBinding.etFieldContent.setText(profile.fieldContent)
        itemBinding.etUpdateWindowHours.setText(profile.updateWindowHours.toString())

        when (profile.authMethod) {
            Prefs.AuthMethod.API_TOKEN -> itemBinding.rbAuthApiToken.isChecked = true
            Prefs.AuthMethod.PASSWORD -> itemBinding.rbAuthPassword.isChecked = true
        }
        updateAuthMethodVisibility(itemBinding, profile.authMethod)

        itemBinding.rgAuthMethod.setOnCheckedChangeListener { _, checkedId ->
            val method = if (checkedId == itemBinding.rbAuthPassword.id) {
                Prefs.AuthMethod.PASSWORD
            } else {
                Prefs.AuthMethod.API_TOKEN
            }
            updateAuthMethodVisibility(itemBinding, method)
        }

        itemBinding.btnCopyProfile.setOnClickListener {
            val source = readProfileFromBinding(itemBinding, id = java.util.UUID.randomUUID().toString())
            val copyName = if (source.name.isBlank()) source.name else source.name + getString(R.string.profile_copy_suffix)
            addProfileCard(source.copy(name = copyName), insertAt = profileCards.indexOf(card) + 1)
        }

        itemBinding.btnDeleteProfile.setOnClickListener {
            binding.llProfilesContainer.removeView(itemBinding.root)
            profileCards.remove(card)
            renumberCards()
        }

        itemBinding.btnTestSend.setOnClickListener { onTestSendClicked(itemBinding, card) }

        if (insertAt < 0 || insertAt >= profileCards.size) {
            binding.llProfilesContainer.addView(itemBinding.root)
            profileCards.add(card)
        } else {
            binding.llProfilesContainer.addView(itemBinding.root, insertAt)
            profileCards.add(insertAt, card)
        }
        renumberCards()
    }

    private fun readProfileFromBinding(itemBinding: ItemKintoneProfileBinding, id: String): Prefs.KintoneProfile {
        val authMethod = if (itemBinding.rbAuthPassword.isChecked) {
            Prefs.AuthMethod.PASSWORD
        } else {
            Prefs.AuthMethod.API_TOKEN
        }

        return Prefs.KintoneProfile(
            id = id,
            name = itemBinding.etProfileName.text.toString().trim(),
            keywords = itemBinding.etKeywords.text.toString().trim(),
            subdomain = itemBinding.etSubdomain.text.toString().trim(),
            appId = itemBinding.etAppId.text.toString().trim(),
            authMethod = authMethod,
            apiToken = itemBinding.etApiToken.text.toString().trim(),
            loginName = itemBinding.etLoginName.text.toString().trim(),
            loginPassword = itemBinding.etLoginPassword.text.toString(),
            fieldSender = itemBinding.etFieldSender.text.toString().trim(),
            fieldBody = itemBinding.etFieldBody.text.toString().trim(),
            fieldDatetime = itemBinding.etFieldDatetime.text.toString().trim(),
            fieldType = itemBinding.etFieldType.text.toString().trim(),
            fieldCompanyName = itemBinding.etFieldCompanyName.text.toString().trim(),
            fieldUserName = itemBinding.etFieldUserName.text.toString().trim(),
            fieldContent = itemBinding.etFieldContent.text.toString().trim(),
            updateWindowHours = itemBinding.etUpdateWindowHours.text.toString().trim().toIntOrNull()
                ?: Defaults.NEW_PROFILE_UPDATE_WINDOW_HOURS
        )
    }

    private fun onTestSendClicked(itemBinding: ItemKintoneProfileBinding, card: ProfileCard) {
        val profile = readProfileFromBinding(itemBinding, id = card.id)
        if (!profile.isValid) {
            val index = profileCards.indexOf(card)
            val label = profile.name.ifBlank { getString(R.string.profile_index_format, index + 1) }
            AlertDialog.Builder(this)
                .setTitle(R.string.validation_error_title)
                .setMessage(getString(R.string.validation_error, label))
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }

        val datetimeIso = if (profile.fieldDatetime.isNotBlank()) {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())
        } else {
            null
        }

        val testBody = getString(R.string.test_send_body)
        val smsParts = SmsPartsGenerator.generateSmsParts(testBody)

        itemBinding.btnTestSend.isEnabled = false
        CoroutineScope(Dispatchers.Main).launch {
            val result = withContext(Dispatchers.IO) {
                KintoneApi.postRecord(
                    profile,
                    senderValue = Defaults.TEST_SEND_SENDER,
                    bodyValue = testBody,
                    datetimeIsoValue = datetimeIso,
                    companyNameValue = smsParts.companyName,
                    userNameValue = smsParts.userName,
                    contentValue = smsParts.content
                )
            }
            itemBinding.btnTestSend.isEnabled = true

            val message = when (result) {
                is KintoneApi.PostResult.Success -> result.message
                is KintoneApi.PostResult.Skipped -> result.message
                is KintoneApi.PostResult.HttpFailure -> "送信失敗: ${result.code} ${result.detail}"
                is KintoneApi.PostResult.NetworkError -> "通信エラー: ${result.message}"
            }
            AlertDialog.Builder(this@SettingsActivity)
                .setTitle(R.string.test_send_result_title)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }

    private fun renumberCards() {
        profileCards.forEachIndexed { index, card ->
            card.binding.tvProfileIndex.text = getString(R.string.profile_index_format, index + 1)
        }
    }

    private fun updateAuthMethodVisibility(itemBinding: ItemKintoneProfileBinding, method: Prefs.AuthMethod) {
        itemBinding.tilApiToken.visibility = if (method == Prefs.AuthMethod.API_TOKEN) {
            View.VISIBLE
        } else {
            View.GONE
        }
        itemBinding.layoutPasswordAuth.visibility = if (method == Prefs.AuthMethod.PASSWORD) {
            View.VISIBLE
        } else {
            View.GONE
        }
    }

    private fun onSaveClicked() {
        val newProfiles = mutableListOf<Prefs.KintoneProfile>()

        for ((index, card) in profileCards.withIndex()) {
            val profile = readProfileFromBinding(card.binding, id = card.id)

            if (!profile.isValid) {
                val label = profile.name.ifBlank { getString(R.string.profile_index_format, index + 1) }
                AlertDialog.Builder(this)
                    .setTitle(R.string.validation_error_title)
                    .setMessage(getString(R.string.validation_error, label))
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
                return
            }

            newProfiles.add(profile)
        }

        Prefs.saveProfiles(this, newProfiles)
        Toast.makeText(this, "設定を保存しました", Toast.LENGTH_SHORT).show()
        finish()
    }
}

package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivityKintoneSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemKintoneProfileBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class KintoneSettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityKintoneSettingsBinding

    private class ProfileCard(val id: String, val binding: ItemKintoneProfileBinding)

    private val profileCards = mutableListOf<ProfileCard>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityKintoneSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.tvKintoneSettingsDescription.visibility =
            if (getString(R.string.send_settings_description).isBlank()) View.GONE else View.VISIBLE

        SettingsStore.loadProfiles(this).forEach { addProfileCard(it) }

        binding.btnAddProfile.setOnClickListener {
            val newCardView = addProfileCard(SettingsStore.KintoneProfile.newEmpty())
            newCardView.post { binding.svKintoneSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svKintoneSettings)) }
        }
        binding.btnSave.setOnClickListener { onSaveClicked() }
    }

    private fun addProfileCard(profile: SettingsStore.KintoneProfile, insertAt: Int = -1): View {
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
        itemBinding.etUpdateToleranceHours.setText(profile.updateToleranceHours.toString())
        itemBinding.swCompanyNameWidthConversionEnabled.isChecked = profile.companyNameWidthConversionEnabled

        when (profile.authMethod) {
            SettingsStore.AuthMethod.API_TOKEN -> itemBinding.rbAuthApiToken.isChecked = true
            SettingsStore.AuthMethod.PASSWORD -> itemBinding.rbAuthPassword.isChecked = true
        }
        updateAuthMethodVisibility(itemBinding, profile.authMethod)

        itemBinding.rgAuthMethod.setOnCheckedChangeListener { _, checkedId ->
            val method = if (checkedId == itemBinding.rbAuthPassword.id) {
                SettingsStore.AuthMethod.PASSWORD
            } else {
                SettingsStore.AuthMethod.API_TOKEN
            }
            updateAuthMethodVisibility(itemBinding, method)
        }

        itemBinding.btnCopyProfile.setOnClickListener {
            val source = readProfileFromBinding(itemBinding, id = java.util.UUID.randomUUID().toString())
            val copyName = if (source.name.isBlank()) source.name else source.name + getString(R.string.suffix_profile_copy)
            val newCardView = addProfileCard(source.copy(name = copyName), insertAt = profileCards.indexOf(card) + 1)
            newCardView.post { binding.svKintoneSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svKintoneSettings)) }
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
        return itemBinding.root
    }

    /** [view]から[ancestor]までの祖先を遡り、[ancestor]の座標系における[view]の上端位置を求める */
    private fun topRelativeTo(view: View, ancestor: View): Int {
        var top = 0
        var current = view
        while (current !== ancestor) {
            top += current.top
            current = current.parent as View
        }
        return top
    }

    private fun readProfileFromBinding(itemBinding: ItemKintoneProfileBinding, id: String): SettingsStore.KintoneProfile {
        val authMethod = if (itemBinding.rbAuthPassword.isChecked) {
            SettingsStore.AuthMethod.PASSWORD
        } else {
            SettingsStore.AuthMethod.API_TOKEN
        }

        return SettingsStore.KintoneProfile(
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
            updateToleranceHours = itemBinding.etUpdateToleranceHours.text.toString().trim().toIntOrNull()
                ?: AppDefaults.UPDATE_TOLERANCE_HOURS,
            companyNameWidthConversionEnabled = itemBinding.swCompanyNameWidthConversionEnabled.isChecked
        )
    }

    private fun onTestSendClicked(itemBinding: ItemKintoneProfileBinding, card: ProfileCard) {
        val profile = readProfileFromBinding(itemBinding, id = card.id)
        if (!profile.isValid) {
            val index = profileCards.indexOf(card)
            val label = profile.name.ifBlank { getString(R.string.label_profile_index, index + 1) }
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_validation_error)
                .setMessage(getString(R.string.dialog_message_validation_error, label))
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
        val companyNameValue = if (profile.companyNameWidthConversionEnabled) {
            smsParts.companyNameNormalizedWidth
        } else {
            smsParts.companyName
        }

        itemBinding.btnTestSend.isEnabled = false
        CoroutineScope(Dispatchers.Main).launch {
            val result = withContext(Dispatchers.IO) {
                KintoneApi.postRecord(
                    applicationContext,
                    profile,
                    senderValue = AppConstants.TEST_SEND_SENDER,
                    bodyValue = testBody,
                    datetimeIsoValue = datetimeIso,
                    companyNameValue = companyNameValue,
                    userNameValue = smsParts.userName,
                    contentValue = smsParts.content
                )
            }
            itemBinding.btnTestSend.isEnabled = true

            val message = when (result) {
                is KintoneApi.PostResult.Success -> result.message
                is KintoneApi.PostResult.Skipped -> result.message
                is KintoneApi.PostResult.HttpFailure -> getString(R.string.dialog_message_test_send_result_failure, "${result.code} ${result.detail}")
                is KintoneApi.PostResult.NetworkError -> getString(R.string.dialog_message_test_send_result_network_error, result.message)
            }
            AlertDialog.Builder(this@KintoneSettingsActivity)
                .setTitle(R.string.dialog_title_test_send_result)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }

    private fun renumberCards() {
        profileCards.forEachIndexed { index, card ->
            card.binding.tvProfileIndex.text = getString(R.string.label_profile_index, index + 1)
        }
    }

    private fun updateAuthMethodVisibility(itemBinding: ItemKintoneProfileBinding, method: SettingsStore.AuthMethod) {
        itemBinding.tilApiToken.visibility = if (method == SettingsStore.AuthMethod.API_TOKEN) {
            View.VISIBLE
        } else {
            View.GONE
        }
        itemBinding.layoutPasswordAuth.visibility = if (method == SettingsStore.AuthMethod.PASSWORD) {
            View.VISIBLE
        } else {
            View.GONE
        }
    }

    private fun onSaveClicked() {
        val newProfiles = mutableListOf<SettingsStore.KintoneProfile>()

        for ((index, card) in profileCards.withIndex()) {
            val profile = readProfileFromBinding(card.binding, id = card.id)

            if (!profile.isValid) {
                val label = profile.name.ifBlank { getString(R.string.label_profile_index, index + 1) }
                AlertDialog.Builder(this)
                    .setTitle(R.string.dialog_title_validation_error)
                    .setMessage(getString(R.string.dialog_message_validation_error, label))
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
                return
            }

            newProfiles.add(profile)
        }

        SettingsStore.saveProfiles(this, newProfiles)
        Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}

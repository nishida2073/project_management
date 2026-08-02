package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivitySettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemKintoneProfileBinding

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
        itemBinding.etFieldPhone.setText(profile.fieldPhone)
        itemBinding.etFieldBody.setText(profile.fieldBody)
        itemBinding.etFieldDatetime.setText(profile.fieldDatetime)

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
            fieldPhone = itemBinding.etFieldPhone.text.toString().trim(),
            fieldBody = itemBinding.etFieldBody.text.toString().trim(),
            fieldDatetime = itemBinding.etFieldDatetime.text.toString().trim()
        )
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
                Toast.makeText(this, getString(R.string.validation_error, label), Toast.LENGTH_LONG).show()
                return
            }

            newProfiles.add(profile)
        }

        Prefs.saveProfiles(this, newProfiles)
        Toast.makeText(this, "設定を保存しました", Toast.LENGTH_SHORT).show()
    }
}

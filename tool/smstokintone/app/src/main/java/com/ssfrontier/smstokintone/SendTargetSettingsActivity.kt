package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivitySendTargetSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemSendTargetBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SendTargetSettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySendTargetSettingsBinding

    private class SendTargetCard(val id: String, val binding: ItemSendTargetBinding)

    private val sendTargetCards = mutableListOf<SendTargetCard>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySendTargetSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.tvSendTargetSettingsDescription.visibility =
            if (getString(R.string.send_target_settings_description).isBlank()) View.GONE else View.VISIBLE

        SettingsStore.loadSendTargets(this).forEach { addSendTargetCard(it) }

        binding.btnAddSendTarget.setOnClickListener {
            val newCardView = addSendTargetCard(SettingsStore.SendTarget.newEmpty())
            newCardView.post { binding.svSendTargetSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svSendTargetSettings)) }
        }
        binding.btnSave.setOnClickListener { onSaveClicked() }
    }

    private fun addSendTargetCard(sendTarget: SettingsStore.SendTarget, insertAt: Int = -1): View {
        val itemBinding = ItemSendTargetBinding.inflate(layoutInflater, binding.llSendTargetsContainer, false)
        val card = SendTargetCard(sendTarget.id, itemBinding)

        itemBinding.etSendTargetName.setText(sendTarget.name)
        itemBinding.etKeywords.setText(sendTarget.keywords)
        itemBinding.etSubdomain.setText(sendTarget.subdomain)
        itemBinding.etAppId.setText(sendTarget.appId)
        itemBinding.etApiToken.setText(sendTarget.apiToken)
        itemBinding.etLoginName.setText(sendTarget.loginName)
        itemBinding.etLoginPassword.setText(sendTarget.loginPassword)
        itemBinding.etFieldSender.setText(sendTarget.fieldSender)
        itemBinding.etFieldBody.setText(sendTarget.fieldBody)
        itemBinding.etFieldDatetime.setText(sendTarget.fieldDatetime)
        itemBinding.etFieldType.setText(sendTarget.fieldType)
        itemBinding.etFieldCompanyName.setText(sendTarget.fieldCompanyName)
        itemBinding.etFieldUserName.setText(sendTarget.fieldUserName)
        itemBinding.etFieldContent.setText(sendTarget.fieldContent)
        itemBinding.etUpdateToleranceHours.setText(sendTarget.updateToleranceHours.toString())
        itemBinding.swCompanyNameWidthConversionEnabled.isChecked = sendTarget.companyNameWidthConversionEnabled

        when (sendTarget.authMethod) {
            SettingsStore.AuthMethod.API_TOKEN -> itemBinding.rbAuthApiToken.isChecked = true
            SettingsStore.AuthMethod.PASSWORD -> itemBinding.rbAuthPassword.isChecked = true
        }
        updateAuthMethodVisibility(itemBinding, sendTarget.authMethod)

        itemBinding.rgAuthMethod.setOnCheckedChangeListener { _, checkedId ->
            val method = if (checkedId == itemBinding.rbAuthPassword.id) {
                SettingsStore.AuthMethod.PASSWORD
            } else {
                SettingsStore.AuthMethod.API_TOKEN
            }
            updateAuthMethodVisibility(itemBinding, method)
        }

        itemBinding.btnCopySendTarget.setOnClickListener {
            val source = readSendTargetFromBinding(itemBinding, id = java.util.UUID.randomUUID().toString())
            val copyName = if (source.name.isBlank()) source.name else source.name + getString(R.string.suffix_send_target_copy)
            val newCardView = addSendTargetCard(source.copy(name = copyName), insertAt = sendTargetCards.indexOf(card) + 1)
            newCardView.post { binding.svSendTargetSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svSendTargetSettings)) }
        }

        itemBinding.btnDeleteSendTarget.setOnClickListener {
            binding.llSendTargetsContainer.removeView(itemBinding.root)
            sendTargetCards.remove(card)
            renumberCards()
        }

        itemBinding.btnTestSend.setOnClickListener { onTestSendClicked(itemBinding, card) }

        if (insertAt < 0 || insertAt >= sendTargetCards.size) {
            binding.llSendTargetsContainer.addView(itemBinding.root)
            sendTargetCards.add(card)
        } else {
            binding.llSendTargetsContainer.addView(itemBinding.root, insertAt)
            sendTargetCards.add(insertAt, card)
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

    private fun readSendTargetFromBinding(itemBinding: ItemSendTargetBinding, id: String): SettingsStore.SendTarget {
        val authMethod = if (itemBinding.rbAuthPassword.isChecked) {
            SettingsStore.AuthMethod.PASSWORD
        } else {
            SettingsStore.AuthMethod.API_TOKEN
        }

        return SettingsStore.SendTarget(
            id = id,
            name = itemBinding.etSendTargetName.text.toString().trim(),
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

    private fun onTestSendClicked(itemBinding: ItemSendTargetBinding, card: SendTargetCard) {
        val sendTarget = readSendTargetFromBinding(itemBinding, id = card.id)
        if (!sendTarget.isValid) {
            val index = sendTargetCards.indexOf(card)
            val label = sendTarget.name.ifBlank { getString(R.string.label_send_target_index, index + 1) }
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_validation_error)
                .setMessage(getString(R.string.dialog_message_validation_error, label))
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }

        val datetimeIso = if (sendTarget.fieldDatetime.isNotBlank()) {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())
        } else {
            null
        }

        val testBody = getString(R.string.test_send_body)

        itemBinding.btnTestSend.isEnabled = false
        CoroutineScope(Dispatchers.Main).launch {
            val smsParts = SmsPartsGenerator.resolveSmsParts(testBody, SettingsStore.load(applicationContext).aiParsingEnabled)
            val companyNameValue = if (sendTarget.companyNameWidthConversionEnabled) {
                smsParts.companyNameNormalizedWidth
            } else {
                smsParts.companyName
            }
            val result = withContext(Dispatchers.IO) {
                KintoneApi.postRecord(
                    applicationContext,
                    sendTarget,
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
            AlertDialog.Builder(this@SendTargetSettingsActivity)
                .setTitle(R.string.dialog_title_test_send_result)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }

    private fun renumberCards() {
        sendTargetCards.forEachIndexed { index, card ->
            card.binding.tvSendTargetIndex.text = getString(R.string.label_send_target_index, index + 1)
        }
    }

    private fun updateAuthMethodVisibility(itemBinding: ItemSendTargetBinding, method: SettingsStore.AuthMethod) {
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
        val newSendTargets = mutableListOf<SettingsStore.SendTarget>()

        for ((index, card) in sendTargetCards.withIndex()) {
            val sendTarget = readSendTargetFromBinding(card.binding, id = card.id)

            if (!sendTarget.isValid) {
                val label = sendTarget.name.ifBlank { getString(R.string.label_send_target_index, index + 1) }
                AlertDialog.Builder(this)
                    .setTitle(R.string.dialog_title_validation_error)
                    .setMessage(getString(R.string.dialog_message_validation_error, label))
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
                return
            }

            newSendTargets.add(sendTarget)
        }

        SettingsStore.saveSendTargets(this, newSendTargets)
        Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}

package com.ssfrontier.smstokintone

import android.os.Bundle
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.lifecycle.lifecycleScope
import com.ssfrontier.smstokintone.databinding.ActivitySendTargetSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemSendTargetBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 送信先（Kintoneアプリ接続先）の一覧を追加・複製・削除・並べ替えしながら編集し、保存する画面 */
class SendTargetSettingsActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivitySendTargetSettingsBinding

    /**
     * idはカードの表示順が変わっても（複製・削除・並べ替え）当該送信先を追跡できるよう、
     * 画面上の並び位置とは別に保持しておく安定な識別子
     */
    private class SendTargetCard(val id: String, val binding: ItemSendTargetBinding)

    /**
     * 画面上のカードの並び順（=llSendTargetsContainerの子View順）を保持するリスト。この並び順のまま
     * 保存され、SettingsStore.resolveSendTargetでのキーワード一致判定も先頭から順に行われるため、
     * 複数の送信先が同じ本文にマッチし得る場合はここでの並び順が優先順位になる
     */
    private val sendTargetCards = mutableListOf<SendTargetCard>()

    /** 保存済みの送信先ごとにカードを1枚ずつ復元し、追加/保存ボタンの動作を配線する */
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

    /**
     * sendTargetの内容でカードを1枚生成し、insertAtの位置（省略時は末尾）にUIとsendTargetCardsの両方へ挿入する。
     * 戻り値のViewは追加直後にスクロール位置合わせで使うためのもの
     */
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

        when (sendTarget.matchTarget) {
            SettingsStore.MatchTarget.BODY -> itemBinding.rbMatchTargetBody.isChecked = true
            SettingsStore.MatchTarget.COMPANY_NAME -> itemBinding.rbMatchTargetCompanyName.isChecked = true
        }

        when (sendTarget.updateToleranceMode) {
            SettingsStore.UpdateToleranceMode.SAME_DATE -> itemBinding.rbUpdateToleranceModeSameDate.isChecked = true
            SettingsStore.UpdateToleranceMode.HOURS -> itemBinding.rbUpdateToleranceModeHours.isChecked = true
        }
        itemBinding.tilUpdateToleranceHours.isEnabled = sendTarget.updateToleranceMode == SettingsStore.UpdateToleranceMode.HOURS
        itemBinding.rgUpdateToleranceMode.setOnCheckedChangeListener { _, checkedId ->
            itemBinding.tilUpdateToleranceHours.isEnabled = checkedId == itemBinding.rbUpdateToleranceModeHours.id
        }

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

    /** ancestor（ScrollView）を基準にしたviewのY座標を、親を辿って足し上げて求める。smoothScrollToへ渡す用 */
    private fun topRelativeTo(view: View, ancestor: View): Int {
        var top = 0
        var current = view
        while (current !== ancestor) {
            top += current.top
            current = current.parent as View
        }
        return top
    }

    /**
     * カード内の入力項目一式をSendTargetへ変換する。idは引数で受け取る：既存カードの保存/テスト送信では
     * card.idをそのまま使い、複製ボタンでは複製先が別の送信先になるよう新しいUUIDを渡す
     */
    private fun readSendTargetFromBinding(itemBinding: ItemSendTargetBinding, id: String): SettingsStore.SendTarget {
        val authMethod = if (itemBinding.rbAuthPassword.isChecked) {
            SettingsStore.AuthMethod.PASSWORD
        } else {
            SettingsStore.AuthMethod.API_TOKEN
        }
        val matchTarget = if (itemBinding.rbMatchTargetBody.isChecked) {
            SettingsStore.MatchTarget.BODY
        } else {
            SettingsStore.MatchTarget.COMPANY_NAME
        }
        val updateToleranceMode = if (itemBinding.rbUpdateToleranceModeSameDate.isChecked) {
            SettingsStore.UpdateToleranceMode.SAME_DATE
        } else {
            SettingsStore.UpdateToleranceMode.HOURS
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
            updateToleranceMode = updateToleranceMode,
            companyNameWidthConversionEnabled = itemBinding.swCompanyNameWidthConversionEnabled.isChecked,
            matchTarget = matchTarget
        )
    }

    /** [index]は送信先名が未入力の場合のラベル表示用（何番目の設定か） */
    private fun showValidationErrorDialogIfInvalid(index: Int, sendTarget: SettingsStore.SendTarget): Boolean {
        if (sendTarget.isValid) return false

        val label = sendTarget.name.ifBlank { getString(R.string.label_send_target_index, index + 1) }
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_validation_error)
            .setMessage(getString(R.string.dialog_message_validation_error, label))
            .setPositiveButton(android.R.string.ok, null)
            .show()
        return true
    }

    /** カードの現在の入力内容で検証し、問題なければテスト本文を入力するダイアログを出す */
    private fun onTestSendClicked(itemBinding: ItemSendTargetBinding, card: SendTargetCard) {
        val sendTarget = readSendTargetFromBinding(itemBinding, id = card.id)
        if (showValidationErrorDialogIfInvalid(sendTargetCards.indexOf(card), sendTarget)) {
            return
        }

        val editText = EditText(this).apply {
            setText(getString(R.string.test_send_body))
            setSelection(text.length)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 3
            val padding = (16 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }

        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_test_send_body)
            .setView(editText)
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_send) { _, _ ->
                performTestSend(itemBinding, sendTarget, editText.text.toString())
            }
            .show()
    }

    /** [testBody]の振り分け条件を確認したうえでkintoneへテスト送信し、抽出結果と送信結果をダイアログで表示する */
    private fun performTestSend(itemBinding: ItemSendTargetBinding, sendTarget: SettingsStore.SendTarget, testBody: String) {
        val datetimeIso = if (sendTarget.fieldDatetime.isNotBlank()) {
            KintoneApi.formatIsoDateTime(System.currentTimeMillis())
        } else {
            null
        }

        itemBinding.btnTestSend.isEnabled = false
        lifecycleScope.launch {
            val smsParts = SmsPartsGenerator.resolveSmsParts(testBody, SettingsStore.load(applicationContext).aiParsingEnabled)

            // 本文（またはそこから抽出した会社名）が[sendTarget]自身の振り分け条件
            // （キーワード、またはデフォルト送信先）に一致しない場合は警告して送信を中断する。
            // 実際の登録処理（KintoneUploadWorker、SettingsStore.resolveSendTarget）と判定基準が
            // ずれないよう、routesToを使う（デフォルト送信先はここでは常にfalseになるので個別に許可する）
            if (!sendTarget.isDefault && !sendTarget.routesTo(testBody, smsParts.companyName)) {
                itemBinding.btnTestSend.isEnabled = true
                AlertDialog.Builder(this@SendTargetSettingsActivity)
                    .setTitle(R.string.dialog_title_test_send_result)
                    .setMessage(R.string.dialog_message_test_send_routing_unmatched)
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
                return@launch
            }

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

            val sendResultMessage = when (result) {
                is KintoneApi.PostResult.Success -> result.message
                is KintoneApi.PostResult.Skipped -> result.message
                is KintoneApi.PostResult.HttpFailure -> getString(R.string.dialog_message_test_send_result_failure, "${result.code} ${result.detail}")
                is KintoneApi.PostResult.NetworkError -> getString(R.string.dialog_message_test_send_result_network_error, result.message)
            }
            val message = buildSpannedString {
                append(sendResultMessage)
                append("\n\n")
                if (smsParts.isSplitFailed()) {
                    append(getString(R.string.dialog_message_split_failure))
                } else {
                    bold { append(getString(R.string.hint_field_company)) }
                    append("\n　$companyNameValue\n")
                    bold { append(getString(R.string.hint_field_user_name)) }
                    append("\n　${smsParts.userName}\n")
                    bold { append(getString(R.string.hint_field_content)) }
                    append("\n　${smsParts.content}")
                }
            }
            val icon = if (smsParts.parsedByAi) {
                getString(R.string.icon_split_ai)
            } else {
                getString(R.string.icon_split_rule)
            }
            val title = "${getString(R.string.dialog_title_test_send_result)} $icon"
            AlertDialog.Builder(this@SendTargetSettingsActivity)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }

    /** カード追加/削除/並べ替えのたびに呼び、各カードの表示上の番号ラベルを現在の並び順に合わせて振り直す */
    private fun renumberCards() {
        sendTargetCards.forEachIndexed { index, card ->
            card.binding.tvSendTargetIndex.text = getString(R.string.label_send_target_index, index + 1)
        }
    }

    /** 選択中の認証方式に応じて、APIトークン欄とID/パスワード欄のどちらか一方だけを表示する */
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

    /** 全カードを検証してからまとめて保存する。1件でも不正な入力があれば、その時点で中断しどこも保存しない */
    private fun onSaveClicked() {
        if (sendTargetCards.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_no_send_targets), Toast.LENGTH_SHORT).show()
            return
        }

        val newSendTargets = mutableListOf<SettingsStore.SendTarget>()

        for ((index, card) in sendTargetCards.withIndex()) {
            val sendTarget = readSendTargetFromBinding(card.binding, id = card.id)

            if (showValidationErrorDialogIfInvalid(index, sendTarget)) {
                return
            }

            newSendTargets.add(sendTarget)
        }

        SettingsStore.saveSendTargets(this, newSendTargets)
        Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}

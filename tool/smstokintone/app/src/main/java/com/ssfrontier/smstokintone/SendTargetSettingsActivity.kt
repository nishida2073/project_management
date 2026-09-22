package com.ssfrontier.smstokintone

import android.os.Bundle
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.lifecycle.lifecycleScope
import com.ssfrontier.smstokintone.databinding.ActivitySendTargetSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemSendTargetBinding
import com.ssfrontier.smstokintone.databinding.ItemSendTargetKeywordBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 送信先（Kintoneアプリ接続先）の一覧を追加・複製・削除・並べ替えしながら編集し、保存する画面 */
class SendTargetSettingsActivity : BaseActivity() {

    /**
     * この画面のViewBinding。
     */
    private lateinit var binding: ActivitySendTargetSettingsBinding

    /**
     * 送信先設定1件分のUIカード。[id]はカードの表示順が変わっても（複製・削除・並べ替え）
     * 当該送信先を安定に追跡できるよう、画面上の並び位置とは別に保持する一意な識別子。
     *
     * @property id UUID形式の一意な識別子
     * @property binding カード要素のViewBinding
     */
    private class SendTargetCard(val id: String, val binding: ItemSendTargetBinding)

    /**
     * 画面上のカードの並び順（=llSendTargetsContainerの子View順）を保持するリスト。
     * この並び順のまま保存される。[SettingsStore.resolveSendTargets]は一致した送信先をすべて返すため、
     * 複数の送信先が同じ本文にマッチした場合も、この並び順による優先順位は無く、一致した全件が振り分け対象になる。
     */
    private val sendTargetCards = mutableListOf<SendTargetCard>()

    /** 保存済みの送信先ごとにカードを1枚ずつ復元し、追加/保存ボタンの動作を配線する */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySendTargetSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.tvSendTargetSettingsDescription.visibility =
            if (getString(R.string.title_send_target_settings_description).isBlank()) View.GONE else View.VISIBLE

        SettingsStore.loadSendTargets(this).forEach { addSendTargetCard(it) }

        val addSendTargetListener = View.OnClickListener {
            val newCardView = addSendTargetCard(SettingsStore.SendTarget.newEmpty())
            newCardView.post { binding.svSendTargetSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svSendTargetSettings)) }
        }
        binding.btnAddSendTarget.setupManaged(addSendTargetListener)

        val saveListener = View.OnClickListener { onSaveClicked() }
        binding.btnSave.setupManaged(saveListener)
    }


    /**
     * sendTargetの内容でカードを1枚生成し、insertAtの位置（省略時は末尾）にUIとsendTargetCardsの両方へ挿入する。
     * 戻り値のViewは追加直後にスクロール位置合わせで使うためのもの
     */
    private fun addSendTargetCard(sendTarget: SettingsStore.SendTarget, insertAt: Int = -1): View {
        val itemBinding = ItemSendTargetBinding.inflate(layoutInflater, binding.llSendTargetsContainer, false)
        val card = SendTargetCard(sendTarget.id, itemBinding)

        itemBinding.etSendTargetName.setText(sendTarget.sendTargetName)
        itemBinding.etCompanyName.setText(sendTarget.companyName)
        val extractionCompanyNameEnabled = SettingsStore.load(applicationContext).extractionCompanyNameEnabled
        itemBinding.llCompanyNameSection.visibility =
            if (extractionCompanyNameEnabled) View.GONE else View.VISIBLE
        itemBinding.llKeywordsSection.visibility =
            if (extractionCompanyNameEnabled) View.VISIBLE else View.GONE
        sendTarget.keywords.forEach { addKeywordRow(itemBinding.llKeywordsContainer, it) }
        val addKeywordListener = View.OnClickListener { addKeywordRow(itemBinding.llKeywordsContainer, "") }
        itemBinding.btnAddKeyword.setupManaged(addKeywordListener)
        itemBinding.etSubdomain.setText(sendTarget.subdomain)
        itemBinding.etAppId.setText(sendTarget.appId)
        itemBinding.etLoginName.setText(sendTarget.loginName)
        itemBinding.etLoginPassword.setText(sendTarget.loginPassword)
        itemBinding.etFieldSender.setText(sendTarget.fieldSender)
        itemBinding.etFieldHistory.setText(sendTarget.fieldHistory)
        itemBinding.etFieldDatetime.setText(sendTarget.fieldDatetime)
        itemBinding.etFieldType.setText(sendTarget.fieldType)
        itemBinding.etFieldCompanyName.setText(sendTarget.fieldCompanyName)
        itemBinding.etFieldUserName.setText(sendTarget.fieldUserName)
        itemBinding.etFieldBody.setText(sendTarget.fieldBody)
        itemBinding.etUpdateToleranceHours.setText(sendTarget.updateToleranceHours.toString())

        when (sendTarget.updateToleranceMode) {
            SettingsStore.UpdateToleranceMode.SAME_DATE -> itemBinding.rbUpdateToleranceModeSameDate.isChecked = true
            SettingsStore.UpdateToleranceMode.HOURS -> itemBinding.rbUpdateToleranceModeHours.isChecked = true
        }
        itemBinding.tilUpdateToleranceHours.isEnabled = sendTarget.updateToleranceMode == SettingsStore.UpdateToleranceMode.HOURS
        val toleranceModeListener = android.widget.RadioGroup.OnCheckedChangeListener { _, checkedId ->
            itemBinding.tilUpdateToleranceHours.isEnabled = checkedId == itemBinding.rbUpdateToleranceModeHours.id
        }
        itemBinding.rgUpdateToleranceMode.setupManaged(toleranceModeListener)

        val copyListener = View.OnClickListener {
            val source = readSendTargetFromBinding(itemBinding, id = java.util.UUID.randomUUID().toString())
            val copyName = if (source.sendTargetName.isBlank()) source.sendTargetName else source.sendTargetName + getString(R.string.suffix_send_target_settings_copy)
            val newCardView = addSendTargetCard(source.copy(sendTargetName = copyName), insertAt = sendTargetCards.indexOf(card) + 1)
            newCardView.post { binding.svSendTargetSettings.smoothScrollTo(0, topRelativeTo(newCardView, binding.svSendTargetSettings)) }
        }
        itemBinding.btnCopySendTarget.setupManaged(copyListener)

        val deleteListener = View.OnClickListener {
            binding.llSendTargetsContainer.removeView(itemBinding.root)
            sendTargetCards.remove(card)
            renumberCards()
        }
        itemBinding.btnDeleteSendTarget.setupManaged(deleteListener)

        val testSendListener = View.OnClickListener { onTestSendClicked(itemBinding, card) }
        itemBinding.btnTestSend.setupManaged(testSendListener)

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

    /** キーワード行を1件containerへ追加する。削除ボタンで自身をUIから取り除けるようにする */
    private fun addKeywordRow(container: LinearLayout, keyword: String) {
        val rowBinding = ItemSendTargetKeywordBinding.inflate(layoutInflater, container, false)
        rowBinding.etKeyword.setText(keyword)
        val deleteListener = View.OnClickListener { container.removeView(rowBinding.root) }
        rowBinding.btnDeleteKeyword.setupManaged(deleteListener)
        container.addView(rowBinding.root)
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
        val updateToleranceMode = if (itemBinding.rbUpdateToleranceModeSameDate.isChecked) {
            SettingsStore.UpdateToleranceMode.SAME_DATE
        } else {
            SettingsStore.UpdateToleranceMode.HOURS
        }

        return SettingsStore.SendTarget(
            id = id,
            sendTargetName = itemBinding.etSendTargetName.text.toString().trim(),
            companyName = itemBinding.etCompanyName.text.toString().trim(),
            keywords = (0 until itemBinding.llKeywordsContainer.childCount).map { index ->
                itemBinding.llKeywordsContainer.getChildAt(index).findViewById<EditText>(R.id.etKeyword).text.toString().trim()
            }.filter { it.isNotEmpty() },
            subdomain = itemBinding.etSubdomain.text.toString().trim(),
            appId = itemBinding.etAppId.text.toString().trim(),
            loginName = itemBinding.etLoginName.text.toString().trim(),
            loginPassword = itemBinding.etLoginPassword.text.toString(),
            fieldSender = itemBinding.etFieldSender.text.toString().trim(),
            fieldHistory = itemBinding.etFieldHistory.text.toString().trim(),
            fieldDatetime = itemBinding.etFieldDatetime.text.toString().trim(),
            fieldType = itemBinding.etFieldType.text.toString().trim(),
            fieldCompanyName = itemBinding.etFieldCompanyName.text.toString().trim(),
            fieldUserName = itemBinding.etFieldUserName.text.toString().trim(),
            fieldBody = itemBinding.etFieldBody.text.toString().trim(),
            updateToleranceHours = itemBinding.etUpdateToleranceHours.text.toString().trim().toIntOrNull()
                ?: AppDefaults.UPDATE_TOLERANCE_HOURS,
            updateToleranceMode = updateToleranceMode
        )
    }

    /** [index]は送信先名が未入力の場合のラベル表示用（何番目の設定か） */
    private fun showValidationErrorDialogIfInvalid(index: Int, sendTarget: SettingsStore.SendTarget): Boolean {
        if (sendTarget.isValid) return false

        val label = sendTarget.sendTargetName.ifBlank { getString(R.string.label_send_target_settings_index, index + 1) }
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_send_target_settings_validation_error)
            .setMessage(getString(R.string.dialog_message_send_target_settings_validation_error, label))
            .setPositiveButton(android.R.string.ok, null)
            .show().setupManaged()
        return true
    }

    /** [duplicateNames]を「入力エラー」ダイアログで報告する（保存を中断するため呼び出し元でreturnする） */
    private fun showDuplicateNameErrorDialog(duplicateNames: List<String>) {
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_send_target_settings_validation_error)
            .setMessage(getString(R.string.dialog_message_send_target_settings_validation_error_duplicate_name, duplicateNames.joinToString("／")))
            .setPositiveButton(android.R.string.ok, null)
            .show().setupManaged()
    }

    /** カードの現在の入力内容で検証し、問題なければテスト本文を入力するダイアログを出す */
    private fun onTestSendClicked(itemBinding: ItemSendTargetBinding, card: SendTargetCard) {
        val sendTarget = readSendTargetFromBinding(itemBinding, id = card.id)
        if (showValidationErrorDialogIfInvalid(sendTargetCards.indexOf(card), sendTarget)) {
            return
        }

        val testSendBody = if (!SettingsStore.load(this).extractionCompanyNameEnabled) {
            getString(R.string.label_send_target_settings_test_send_body_template_company_name_extraction_disabled)
        } else if (sendTarget.keywords.isNotEmpty()) {
            getString(R.string.label_send_target_settings_test_send_body_template_exists_keywords, sendTarget.keywords.joinToString("、"))
        } else {
            getString(R.string.label_send_target_settings_test_send_body_template_no_keywords)
        }

        val editText = EditText(this).apply {
            setText(testSendBody)
            setSelection(text.length)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 3
            val padding = (16 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }

        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_send_target_settings_test_send_body)
            .setView(editText)
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_send) { _, _ ->
                performTestSend(itemBinding, sendTarget, editText.text.toString())
            }
            .show().setupManaged()
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
            val config = SettingsStore.load(applicationContext)
            val extracted = SmsPartsGenerator.resolveSmsParts(testBody, config.extractionAiEnabled, config.extractionCompanyNameEnabled)
            val smsParts = extracted.copy(
                companyName = SettingsStore.getConvertedCompanyName(
                    config,
                    if (config.extractionCompanyNameEnabled) extracted.companyName else sendTarget.companyName
                )
            )

            if (config.extractionCompanyNameEnabled && !sendTarget.isDefault && !sendTarget.routesTo(smsParts.companyName)) {
                itemBinding.btnTestSend.isEnabled = true
                AlertDialog.Builder(this@SendTargetSettingsActivity)
                    .setTitle(R.string.dialog_title_send_target_settings_test_send_result)
                    .setMessage(getString(R.string.dialog_message_send_target_settings_test_send_routing_unmatched, sendTarget.keywords.joinToString("、")))
                    .setPositiveButton(android.R.string.ok, null)
                    .show().setupManaged()
                return@launch
            }

            val result = withContext(Dispatchers.IO) {
                KintoneApi.postRecord(
                    applicationContext,
                    sendTarget,
                    senderValue = AppConstants.TEST_SEND_SENDER,
                    historyValue = testBody,
                    datetimeIsoValue = datetimeIso,
                    companyNameValue = smsParts.companyName,
                    userNameValue = smsParts.userName,
                    bodyValue = smsParts.body
                )
            }
            itemBinding.btnTestSend.isEnabled = true

            val sendResultMessage = when (result) {
                is KintoneApi.PostResult.Success -> result.message
                is KintoneApi.PostResult.Skipped -> result.message
                is KintoneApi.PostResult.HttpFailure -> getString(R.string.dialog_message_send_target_settings_test_send_result_failure, "${result.code} ${result.detail}")
                is KintoneApi.PostResult.NetworkError -> getString(R.string.dialog_message_send_target_settings_test_send_result_network_error, result.message)
            }
            val message = buildSpannedString {
                append(sendResultMessage)
                append("\n\n")
                if (smsParts.isExtractionFailed()) {
                    append(getString(R.string.dialog_message_log_extraction_failure))
                } else {
                    bold { append(getString(R.string.hint_send_target_settings_field_company)) }
                    append("：${smsParts.companyName}\n")
                    bold { append(getString(R.string.hint_send_target_settings_field_user_name)) }
                    append("：${smsParts.userName}\n\n")
                    append(smsParts.body)
                }
            }
            val icon = if (smsParts.extractedByAi) {
                getString(R.string.icon_extraction_ai)
            } else {
                getString(R.string.icon_extraction_rule)
            }
            val title = "${getString(R.string.dialog_title_send_target_settings_test_send_result)} $icon"
            AlertDialog.Builder(this@SendTargetSettingsActivity)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show().setupManaged()
        }
    }

    /** カード追加/削除/並べ替えのたびに呼び、各カードの表示上の番号ラベルを現在の並び順に合わせて振り直す */
    private fun renumberCards() {
        sendTargetCards.forEachIndexed { index, card ->
            card.binding.tvSendTargetIndex.text = getString(R.string.label_send_target_settings_index, index + 1)
        }
    }

    /** 全カードを検証してからまとめて保存する。1件でも不正な入力があれば、その時点で中断しどこも保存しない */
    private fun onSaveClicked() {
        // if (sendTargetCards.isEmpty()) {
        //     Toast.makeText(this, getString(R.string.toast_send_target_settings_no_send_targets), Toast.LENGTH_SHORT).show()
        //     return
        // }

        val newSendTargets = mutableListOf<SettingsStore.SendTarget>()

        for ((index, card) in sendTargetCards.withIndex()) {
            val sendTarget = readSendTargetFromBinding(card.binding, id = card.id)

            if (showValidationErrorDialogIfInvalid(index, sendTarget)) {
                return
            }

            newSendTargets.add(sendTarget)
        }

        val duplicateNames = newSendTargets.groupBy { it.sendTargetName }
            .filter { it.value.size > 1 }
            .map { it.key }
            .sorted()
        if (duplicateNames.isNotEmpty()) {
            showDuplicateNameErrorDialog(duplicateNames)
            return
        }

        SettingsStore.saveSendTargets(this, newSendTargets)
        Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
        finish()
    }
}

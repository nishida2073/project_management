package com.ssfrontier.smstokintone

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import com.ssfrontier.smstokintone.databinding.ActivityContinuationInfoSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemContinuationInfoBinding

/**
 * 送信元ごとの引継ぎ内容（[ContinuationStore]）を一覧表示し、会社名・氏名を個別に編集、
 * または送信元単位で削除できる画面。送信先は保持せず、会社名から
 * [SettingsStore.findSendTargets]で都度再判定した結果を読み取り専用のラベルとして
 * 表示するのみで、この画面での編集対象にはしない
 */
class ContinuationInfoSettingsActivity : BaseActivity() {

    /**
     * この画面のViewBinding。
     */
    private lateinit var binding: ActivityContinuationInfoSettingsBinding

    /**
     * 画面を開いた時点で読み込んだ内容のスナップショット。保存時に[ContinuationStore.applyIfUnchanged]へ渡し、
     * 編集中に他から更新されていないかの楽観的排他制御で判定に使う。
     */
    private lateinit var loadedSnapshot: Map<String, ContinuationStore.Entry>

    /**
     * 継続SMS引継ぎ内容1件分のUIカード。[senderKey]は正規化済みの送信元キー（[ContinuationStore]のマップのキー）。
     * この画面では元の電話番号は保持していないため編集対象にしない。
     *
     * @property senderKey 正規化済みの送信元キー
     * @property itemBinding カード要素のViewBinding
     */
    private class Card(
        val senderKey: String,
        val itemBinding: ItemContinuationInfoBinding
    )

    /**
     * UIに表示中のカード一覧。
     */
    private val cards = mutableListOf<Card>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityContinuationInfoSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loadedSnapshot = ContinuationStore.getAll(this)
        val entries = loadedSnapshot.entries.sortedBy { it.value.timestampMillis }

        binding.tvContinuationEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        entries.forEach { (senderKey, entry) -> addCard(senderKey, entry) }

        val searchTextWatcher = simpleTextWatcher { applySearchFilter(it) }
        binding.etContinuationSearch.setupManaged(searchTextWatcher)

        val deleteAllListener = View.OnClickListener {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_confirm_delete_all_continuation_info)
                .setMessage(R.string.dialog_message_delete_all_continuation_info)
                .setNegativeButton(R.string.btn_cancel, null)
                .setPositiveButton(R.string.btn_delete) { _, _ ->
                    binding.llContinuationContainer.removeAllViews()
                    cards.clear()
                    binding.tvContinuationEmpty.visibility = View.VISIBLE
                    binding.tvContinuationNoMatch.visibility = View.GONE
                }
                .show().setupManaged()
        }
        binding.btnDeleteAllContinuationInfo.setupManaged(deleteAllListener)

        val sortListener = android.widget.RadioGroup.OnCheckedChangeListener { _, checkedId ->
            val isAscending = checkedId == binding.rbContinuationSortAscending.id
            reloadCards(isAscending)
            applySearchFilter(binding.etContinuationSearch.text.toString())
        }
        binding.rgContinuationSort.setupManaged(sortListener)

        val saveListener = View.OnClickListener { onSaveClicked() }
        binding.btnSaveContinuationInfo.setupManaged(saveListener)
    }

    /** ソート順序に応じてカードを再読み込みする */
    private fun reloadCards(isAscending: Boolean) {
        binding.llContinuationContainer.removeAllViews()

        val sortedCards = if (isAscending) {
            cards.sortedBy { loadedSnapshot[it.senderKey]?.timestampMillis ?: 0 }
        } else {
            cards.sortedByDescending { loadedSnapshot[it.senderKey]?.timestampMillis ?: 0 }
        }

        sortedCards.forEach { card -> binding.llContinuationContainer.addView(card.itemBinding.root) }
    }

    /** [query]でカードを絞り込む（表示のみ、ストアは変更しない） */
    private fun applySearchFilter(query: String) {
        val q = query.trim()
        if (q.isEmpty()) {
            cards.forEach { it.itemBinding.root.visibility = View.VISIBLE }
            binding.tvContinuationNoMatch.visibility = View.GONE
            binding.tvContinuationEmpty.visibility = if (cards.isEmpty()) View.VISIBLE else View.GONE
            return
        }
        var matchCount = 0
        cards.forEach { card ->
            val entry = loadedSnapshot[card.senderKey]
            val matched = listOf(
                entry?.companyName.orEmpty(),
                entry?.userName.orEmpty(),
                entry?.senderAddress.orEmpty().ifBlank { card.senderKey }
            ).any { TextNormalization.matches(it, q) }
            card.itemBinding.root.visibility = if (matched) View.VISIBLE else View.GONE
            if (matched) matchCount++
        }
        binding.tvContinuationNoMatch.visibility = if (matchCount == 0) View.VISIBLE else View.GONE
        binding.tvContinuationEmpty.visibility = View.GONE
    }

    /** 1件分のカードをUIとcardsの両方へ追加する */
    private fun addCard(senderKey: String, entry: ContinuationStore.Entry) {
        val itemBinding = ItemContinuationInfoBinding.inflate(layoutInflater, binding.llContinuationContainer, false)
        itemBinding.tvSenderAddress.text = entry.senderAddress.ifBlank { senderKey }

        val config = SettingsStore.load(this)
        itemBinding.etContinuationCompanyName.setText(entry.companyName)
        itemBinding.llCompanyNameSection.visibility = if (config.companyNameExtractionEnabled) View.VISIBLE else View.GONE

        itemBinding.etContinuationUserName.setText(entry.userName)

        val sendTargets = SettingsStore.findSendTargets(this, entry.companyName)
        val name = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(this) }
        itemBinding.tvContinuationSendTargetName.text = name ?: getString(R.string.label_send_target_none)

        val card = Card(senderKey, itemBinding)

        val deleteCardListener = View.OnClickListener {
            binding.llContinuationContainer.removeView(itemBinding.root)
            cards.remove(card)
        }
        itemBinding.btnDeleteContinuationInfo.setupManaged(deleteCardListener)

        binding.llContinuationContainer.addView(itemBinding.root)
        cards.add(card)
    }


    /** 変更内容をストアへ適用。楽観的排他制御で競合を検出する */
    private fun onSaveClicked() {
        val config = SettingsStore.load(this)
        val invalidCard = cards.firstOrNull { card ->
            val companyNameBlank = card.itemBinding.etContinuationCompanyName.text.toString().isBlank()
            val userNameBlank = card.itemBinding.etContinuationUserName.text.toString().isBlank()
            if (config.companyNameExtractionEnabled) {
                companyNameBlank || userNameBlank
            } else {
                userNameBlank
            }
        }
        if (invalidCard != null) {
            val messageResId = if (config.companyNameExtractionEnabled) {
                R.string.dialog_message_continuation_validation_error_extraction_enabled
            } else {
                R.string.dialog_message_continuation_validation_error_extraction_disabled
            }
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_validation_error)
                .setMessage(getString(messageResId, invalidCard.senderKey))
                .setPositiveButton(android.R.string.ok, null)
                .show().setupManaged()
            return
        }

        val keptSenderKeys = cards.map { it.senderKey }.toSet()

        val success = ContinuationStore.applyIfUnchanged(this, loadedSnapshot) { entries ->
            entries.keys.toList().filter { it !in keptSenderKeys }.forEach { entries.remove(it) }
            cards.forEach { card ->
                val original = loadedSnapshot[card.senderKey]
                entries[card.senderKey] = ContinuationStore.Entry(
                    companyName = card.itemBinding.etContinuationCompanyName.text.toString().trim(),
                    userName = card.itemBinding.etContinuationUserName.text.toString().trim(),
                    timestampMillis = original?.timestampMillis ?: System.currentTimeMillis(),
                    senderAddress = original?.senderAddress ?: ""
                )
            }
        }

        if (success) {
            Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
            finish()
        } else {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_continuation_info_save_conflict)
                .setMessage(R.string.dialog_message_continuation_info_save_conflict)
                .setPositiveButton(android.R.string.ok, null)
                .show().setupManaged()
        }
    }
}
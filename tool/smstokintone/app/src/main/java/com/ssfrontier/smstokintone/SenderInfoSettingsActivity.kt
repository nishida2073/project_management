package com.ssfrontier.smstokintone

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivitySenderInfoSettingsBinding
import com.ssfrontier.smstokintone.databinding.ItemSenderInfoBinding

/**
 * 送信元ごとの送信元情報（[ContinuationStore]）を一覧表示し、会社名・氏名を個別に編集、
 * または送信元単位で削除できる画面。送信先は保持せず、会社名から
 * [SettingsStore.findSendTargets]で都度再判定した結果を読み取り専用のラベルとして
 * 表示するのみで、この画面での編集対象にはしない
 */
class SenderInfoSettingsActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivitySenderInfoSettingsBinding

    /**
     * 画面を開いた時点で読み込んだ内容のスナップショット。保存時に[ContinuationStore.applyIfUnchanged]
     * へ渡し、編集中に他から更新されていないかの判定に使う
     */
    private lateinit var loadedSnapshot: Map<String, ContinuationStore.Entry>

    /**
     * [senderKey]は正規化済みの送信元キー（[ContinuationStore]のマップのキー）。この画面では
     * 元の電話番号は保持していないため編集対象にしない
     */
    private class Card(
        val senderKey: String,
        val itemBinding: ItemSenderInfoBinding
    )

    private val cards = mutableListOf<Card>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySenderInfoSettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loadedSnapshot = ContinuationStore.getAll(this)
        val entries = loadedSnapshot.entries.sortedByDescending { it.value.timestampMillis }

        binding.tvSenderInfoEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        entries.forEach { (senderKey, entry) -> addCard(senderKey, entry) }

        binding.etSenderInfoSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit

            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit

            override fun afterTextChanged(s: Editable?) {
                applySearchFilter(s?.toString().orEmpty())
            }
        })

        binding.btnDeleteAllSenderInfo.setOnClickListener {
            // 個別の削除ボタンと同様、ここではUI上から一覧をまとめて外すだけでストアはまだ変更しない。
            // 実際にストアから削除されるのは「設定を保存」を押した時点（onSaveClicked）
            binding.llSenderInfoContainer.removeAllViews()
            cards.clear()
            binding.tvSenderInfoEmpty.visibility = View.VISIBLE
            binding.tvSenderInfoNoMatch.visibility = View.GONE
        }

        binding.btnSaveSenderInfo.setOnClickListener { onSaveClicked() }
    }

    /**
     * [query]でカードを絞り込む。会社名・氏名・電話番号（[ContinuationStore.Entry.senderAddress]、無ければ
     * 正規化済みの[senderKey]）のいずれかに部分一致したカードのみ表示する。検索は表示の絞り込みのみで
     * [cards]やストアは変更しないため、非表示のカードは保存時に通常どおり保持される
     */
    private fun applySearchFilter(query: String) {
        val q = query.trim()
        if (q.isEmpty()) {
            cards.forEach { it.itemBinding.root.visibility = View.VISIBLE }
            binding.tvSenderInfoNoMatch.visibility = View.GONE
            binding.tvSenderInfoEmpty.visibility = if (cards.isEmpty()) View.VISIBLE else View.GONE
            return
        }
        val lowered = q.lowercase()
        var matchCount = 0
        cards.forEach { card ->
            val entry = loadedSnapshot[card.senderKey]
            val matched = listOf(
                entry?.companyName.orEmpty(),
                entry?.userName.orEmpty(),
                entry?.senderAddress.orEmpty().ifBlank { card.senderKey }
            ).any { it.lowercase().contains(lowered) }
            card.itemBinding.root.visibility = if (matched) View.VISIBLE else View.GONE
            if (matched) matchCount++
        }
        binding.tvSenderInfoNoMatch.visibility = if (matchCount == 0) View.VISIBLE else View.GONE
        binding.tvSenderInfoEmpty.visibility = View.GONE
    }

    /** 1件分のカードをUIとcardsの両方へ追加する */
    private fun addCard(senderKey: String, entry: ContinuationStore.Entry) {
        val itemBinding = ItemSenderInfoBinding.inflate(layoutInflater, binding.llSenderInfoContainer, false)
        itemBinding.tvSenderAddress.text = entry.senderAddress.ifBlank { senderKey }
        itemBinding.etContinuationCompanyName.setText(entry.companyName)
        itemBinding.etContinuationUserName.setText(entry.userName)

        val sendTargets = SettingsStore.findSendTargets(this, entry.companyName)
        val name = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(this) }
        itemBinding.tvContinuationSendTargetName.text = name ?: getString(R.string.label_send_target_none)

        val card = Card(senderKey, itemBinding)

        itemBinding.btnDeleteSenderInfo.setOnClickListener {
            binding.llSenderInfoContainer.removeView(itemBinding.root)
            cards.remove(card)
        }

        binding.llSenderInfoContainer.addView(itemBinding.root)
        cards.add(card)
    }

    /**
     * 表示中の全カードの内容で[loadedSnapshot]からの差分をストアへ適用する。会社名・氏名の
     * どちらかが空のカードがあれば保存せずエラーダイアログを表示する（引き継ぎ先の会社名・氏名が
     * 空のまま次のSMSへ引き継がれてしまうことを防ぐため）。カードを削除した送信元はまとめて削除され、
     * 残っているカードは入力内容（会社名・氏名）で更新される。日時はこの画面では編集対象にしないため、
     * 元のデータの値をそのまま引き継ぐ。画面を開いてから保存するまでの間にSMS受信などでストアが
     * 更新されていた場合は何も保存せず、保存失敗のダイアログを表示する（[ContinuationStore.applyIfUnchanged]参照）
     */
    private fun onSaveClicked() {
        val invalidCard = cards.firstOrNull {
            it.itemBinding.etContinuationCompanyName.text.toString().isBlank() ||
                it.itemBinding.etContinuationUserName.text.toString().isBlank()
        }
        if (invalidCard != null) {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_validation_error)
                .setMessage(getString(R.string.dialog_message_continuation_validation_error, invalidCard.senderKey))
                .setPositiveButton(android.R.string.ok, null)
                .show()
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
                .setTitle(R.string.dialog_title_sender_info_save_conflict)
                .setMessage(R.string.dialog_message_sender_info_save_conflict)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }
}
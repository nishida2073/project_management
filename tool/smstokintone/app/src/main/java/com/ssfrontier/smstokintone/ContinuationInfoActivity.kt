package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivityContinuationInfoBinding
import com.ssfrontier.smstokintone.databinding.ItemContinuationInfoBinding

/**
 * 送信元ごとの引き継ぎ情報（[ContinuationStore]）を一覧表示し、会社名・氏名を個別に編集、
 * または送信元単位で削除できる画面。送信先は保持せず、会社名から
 * [SettingsStore.findSendTargetsForContinuation]で都度再判定した結果を読み取り専用のラベルとして
 * 表示するのみで、この画面での編集対象にはしない
 */
class ContinuationInfoActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivityContinuationInfoBinding

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
        val itemBinding: ItemContinuationInfoBinding
    )

    private val cards = mutableListOf<Card>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityContinuationInfoBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loadedSnapshot = ContinuationStore.getAll(this)
        val entries = loadedSnapshot.entries.sortedByDescending { it.value.timestampMillis }

        binding.tvContinuationInfoEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        entries.forEach { (senderKey, entry) -> addCard(senderKey, entry) }

        binding.btnDeleteAllContinuationInfo.setOnClickListener {
            // 個別の削除ボタンと同様、ここではUI上から一覧をまとめて外すだけでストアはまだ変更しない。
            // 実際にストアから削除されるのは「設定を保存」を押した時点（onSaveClicked）
            binding.llContinuationInfoContainer.removeAllViews()
            cards.clear()
            binding.tvContinuationInfoEmpty.visibility = View.VISIBLE
        }

        binding.btnSaveContinuationInfo.setOnClickListener { onSaveClicked() }
    }

    /** 1件分のカードをUIとcardsの両方へ追加する */
    private fun addCard(senderKey: String, entry: ContinuationStore.Entry) {
        val itemBinding = ItemContinuationInfoBinding.inflate(layoutInflater, binding.llContinuationInfoContainer, false)
        itemBinding.tvSenderKey.text = getString(R.string.label_continuation_sender, senderKey)
        itemBinding.etContinuationCompanyName.setText(entry.companyName)
        itemBinding.etContinuationUserName.setText(entry.userName)

        val sendTargets = SettingsStore.findSendTargetsForContinuation(this, entry.companyName)
        val name = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(this) }
        itemBinding.tvContinuationSendTargetName.text = name ?: getString(R.string.label_send_target_none)

        val card = Card(senderKey, itemBinding)

        itemBinding.btnDeleteContinuationInfo.setOnClickListener {
            binding.llContinuationInfoContainer.removeView(itemBinding.root)
            cards.remove(card)
        }

        binding.llContinuationInfoContainer.addView(itemBinding.root)
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
                    timestampMillis = original?.timestampMillis ?: System.currentTimeMillis()
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
                .show()
        }
    }
}

package com.ssfrontier.smstokintone

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.ssfrontier.smstokintone.databinding.ActivityContinuationDataBinding
import com.ssfrontier.smstokintone.databinding.ItemContinuationDataBinding

/**
 * 送信元ごとの引継ぎデータ（[ContinuationStore]）を一覧表示し、会社名・氏名を個別に編集、
 * または送信元単位で削除できる画面。送信先は複数一致し得り編集も複雑になるため、この画面では
 * 変更せず現在の値をラベル表示するのみとする
 */
class ContinuationDataActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivityContinuationDataBinding

    /**
     * 画面を開いた時点で読み込んだ内容のスナップショット。保存時に[ContinuationStore.applyIfUnchanged]
     * へ渡し、編集中に他から更新されていないかの判定に使う
     */
    private lateinit var loadedSnapshot: Map<String, ContinuationStore.Entry>

    /**
     * [senderKey]は正規化済みの送信元キー（[ContinuationStore]のマップのキー）。この画面では
     * 元の電話番号は保持していないため編集対象にしない
     */
    private class Card(val senderKey: String, val itemBinding: ItemContinuationDataBinding)

    private val cards = mutableListOf<Card>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityContinuationDataBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loadedSnapshot = ContinuationStore.getAll(this)
        val entries = loadedSnapshot.entries.sortedByDescending { it.value.timestampMillis }

        binding.tvContinuationDataEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        entries.forEach { (senderKey, entry) -> addCard(senderKey, entry) }

        binding.btnDeleteAllContinuationData.setOnClickListener {
            // 個別の削除ボタンと同様、ここではUI上から一覧をまとめて外すだけでストアはまだ変更しない。
            // 実際にストアから削除されるのは「設定を保存」を押した時点（onSaveClicked）
            binding.llContinuationDataContainer.removeAllViews()
            cards.clear()
            binding.tvContinuationDataEmpty.visibility = View.VISIBLE
        }

        binding.btnSaveContinuationData.setOnClickListener { onSaveClicked() }
    }

    /** 1件分のカードをUIとcardsの両方へ追加する */
    private fun addCard(senderKey: String, entry: ContinuationStore.Entry) {
        val itemBinding = ItemContinuationDataBinding.inflate(layoutInflater, binding.llContinuationDataContainer, false)
        itemBinding.tvSenderKey.text = getString(R.string.label_continuation_sender_key, senderKey)
        itemBinding.etContinuationCompanyName.setText(entry.companyName)
        itemBinding.etContinuationUserName.setText(entry.userName)
        // 複数の送信先に一致していた場合、entry.sendTargetNameは既に「、」区切りで連結済み
        itemBinding.tvContinuationSendTargetName.text = entry.sendTargetName ?: getString(R.string.label_send_target_none)

        val card = Card(senderKey, itemBinding)
        itemBinding.btnDeleteContinuationData.setOnClickListener {
            binding.llContinuationDataContainer.removeView(itemBinding.root)
            cards.remove(card)
        }

        binding.llContinuationDataContainer.addView(itemBinding.root)
        cards.add(card)
    }

    /**
     * 表示中の全カードの内容で[loadedSnapshot]からの差分をストアへ適用する。カードを削除した
     * 送信元はまとめて削除され、残っているカードは入力内容（会社名・氏名）で更新される。
     * 送信先・日時はこの画面では編集対象にしないため、元のデータの値をそのまま引き継ぐ。
     * 画面を開いてから保存するまでの間にSMS受信などでストアが更新されていた場合は何も保存せず、
     * 保存失敗のダイアログを表示する（[ContinuationStore.applyIfUnchanged]参照）
     */
    private fun onSaveClicked() {
        val keptSenderKeys = cards.map { it.senderKey }.toSet()

        val success = ContinuationStore.applyIfUnchanged(this, loadedSnapshot) { entries ->
            entries.keys.toList().filter { it !in keptSenderKeys }.forEach { entries.remove(it) }
            cards.forEach { card ->
                val original = loadedSnapshot[card.senderKey]
                entries[card.senderKey] = ContinuationStore.Entry(
                    companyName = card.itemBinding.etContinuationCompanyName.text.toString().trim(),
                    userName = card.itemBinding.etContinuationUserName.text.toString().trim(),
                    sendTargetIds = original?.sendTargetIds ?: emptyList(),
                    sendTargetName = original?.sendTargetName,
                    timestampMillis = original?.timestampMillis ?: System.currentTimeMillis()
                )
            }
        }

        if (success) {
            Toast.makeText(this, getString(R.string.toast_settings_saved), Toast.LENGTH_SHORT).show()
            finish()
        } else {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_continuation_data_save_conflict)
                .setMessage(R.string.dialog_message_continuation_data_save_conflict)
                .setPositiveButton(android.R.string.ok, null)
                .show()
        }
    }
}

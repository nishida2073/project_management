package com.ssfrontier.smstokintone

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import com.google.android.material.color.MaterialColors
import com.ssfrontier.smstokintone.databinding.ActivityLogBinding
import java.util.Date

/**
 * SmsLogStoreの全エントリを画面に表示するログ一覧。件数が少ない前提でRecyclerViewは使わず、
 * 都度LinearLayoutへViewを組み立て直す。設定で有効な間はHandlerで一定間隔ごとに自動再描画する。
 */
class LogActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivityLogBinding
    /** [autoRefreshRunnable]のスケジュールに使うHandler */
    private val autoRefreshHandler = Handler(Looper.getMainLooper())
    /** 再描画のたびに次回分を再スケジュールすることで自動更新を継続させる */
    private val autoRefreshRunnable = Runnable {
        renderLog()
        scheduleAutoRefresh()
    }

    /** ログ一覧の初期表示と、更新/クリアボタン・スワイプ更新の配線を行う */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLogBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnRefreshLog.setOnClickListener { renderLog() }
        binding.btnClearLog.setOnClickListener { onClearClicked() }
        binding.swipeRefreshLog.setOnRefreshListener {
            renderLog()
            binding.swipeRefreshLog.isRefreshing = false
        }
    }

    /** 他画面での変更を反映するため表示に戻るたびに再描画し、自動更新のスケジュールを再開する */
    override fun onResume() {
        super.onResume()
        renderLog()
        scheduleAutoRefresh()
    }

    /** 画面が表示されていない間は自動更新を止める */
    override fun onPause() {
        super.onPause()
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
    }

    /** 設定で自動更新が有効な場合、次回の[autoRefreshRunnable]実行を予約する */
    private fun scheduleAutoRefresh() {
        // 既存の予約をキャンセルしてから積み直す（onResumeとrunnable自身の両方から呼ばれるため多重登録を防ぐ）
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
        val config = SettingsStore.load(this)
        if (config.autoRefreshEnabled) {
            autoRefreshHandler.postDelayed(
                autoRefreshRunnable,
                config.autoRefreshIntervalSeconds * 1000L
            )
        }
    }

    /** 確認ダイアログを出し、OKならログを全削除して再描画する */
    private fun onClearClicked() {
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_confirm_clear_log)
            .setMessage(R.string.dialog_message_confirm_clear_log)
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_clear) { _, _ ->
                SmsLogStore.clear(this)
                renderLog()
            }
            .show()
    }

    /** SmsLogStoreの全エントリを読み込み、一覧のViewを組み立て直して表示する */
    private fun renderLog() {
        val entries = SmsLogStore.getAll(this)
        binding.llLogContainer.removeAllViews()
        binding.tvLogEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        val dateFormat = DateFormats.display()
        val itemTextColor = MaterialColors.getColor(
            binding.llLogContainer,
            com.google.android.material.R.attr.colorOnSurface
        )
        entries.forEach { entry ->
            val typeLabel = when (entry.type) {
                SmsLogStore.EntryType.RECEIVE -> getString(R.string.label_log_type_receive)
                SmsLogStore.EntryType.SEND_START -> getString(R.string.label_log_type_send_start)
                SmsLogStore.EntryType.SEND_COMPLETE -> getString(R.string.label_log_type_send_complete)
                SmsLogStore.EntryType.AUTO_REPLY -> getString(R.string.label_log_type_auto_reply)
            }

            // 送信系ログのみ末尾に自動=青(status_running)/手動=アンバー(status_manual)のアイコンを付ける
            val typeAndTimestampView = TextView(this).apply {
                text = buildSpannedString {
                    append(getString(R.string.label_log_type_bracketed, typeLabel))
                    append(" ${dateFormat.format(Date(entry.loggedAtMillis))}")
                    entry.smsParts?.let { smsParts ->
                        append(" ")
                        val splitIcon = when {
                            entry.isContinuation -> R.string.icon_split_excluded
                            smsParts.isSplitFailed() -> R.string.icon_split_failed
                            else -> R.string.icon_split_succeeded
                        }
                        append(getString(splitIcon))
                    }
                    if (entry.type == SmsLogStore.EntryType.SEND_START || entry.type == SmsLogStore.EntryType.SEND_COMPLETE) {
                        append("  ")
                        val modeColor = ContextCompat.getColor(
                            this@LogActivity,
                            if (entry.manual) R.color.status_manual else R.color.status_running
                        )
                        color(modeColor) {
                            append(getString(if (entry.manual) R.string.icon_send_manual else R.string.icon_send_auto))
                        }
                    }
                    if (entry.companyNameConverted) {
                        append(" ")
                        append(getString(R.string.icon_company_name_converted))
                    }
                    if (entry.type == SmsLogStore.EntryType.AUTO_REPLY) {
                        append(" ")
                        append(getString(R.string.icon_replied))
                    }
                }
                setTextColor(itemTextColor)
                textSize = 16f
                setPadding(0, 24, 0, 4)
            }

            val sendTargetNameView = TextView(this).apply {
                text = buildSpannedString {
                    val sendTargetIcon = when {
                        entry.isContinuation -> R.string.icon_send_target_inherited
                        entry.sendTargetName == null -> R.string.icon_send_target_unconfigured
                        else -> R.string.icon_send_target_exists
                    }
                    append(getString(sendTargetIcon))
                    append(" ")
                    color(ContextCompat.getColor(this@LogActivity, R.color.send_target_name)) {
                        bold { append(entry.sendTargetName ?: getString(R.string.label_send_target_none)) }
                    }
                }
                setPadding(0, 16, 0, 16)
            }
            val senderAndTimestampView = TextView(this).apply {
                text = "${dateFormat.format(Date(entry.timestampMillis))}　${entry.sender}"
                setTextColor(itemTextColor)
                setPadding(0, 0, 0, 4)
            }
            val bodyView = TextView(this).apply {
                text = entry.bodyPreview
                setTextColor(itemTextColor)
                setPadding(0, 0, 0, 4)
            }

            // 全エントリ共通: 成功=緑(log_success)・失敗=赤(log_failure)
            val resultLabel = if (entry.success) {
                getString(R.string.label_log_result_success)
            } else {
                getString(R.string.label_log_result_failure)
            }
            val resultColor = ContextCompat.getColor(
                this@LogActivity,
                if (entry.success) R.color.log_success else R.color.log_failure
            )
            val resultView: View = buildLabeledMessageRow(resultLabel, entry.message, resultColor, topPadding = 16)

            val divider = View(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@LogActivity, R.color.log_divider))
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    2
                )
            }

            val entryView = android.widget.LinearLayout(this).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                addView(typeAndTimestampView)
                addView(resultView)
                addView(sendTargetNameView)
                addView(senderAndTimestampView)
                addView(bodyView)
                // replyBodyとsmsPartsは両方設定され得る（AUTO_REPLY）ため、setOnLongClickListenerの
                // 上書きで片方が無効にならないよう、どちらを開くかをここで一つに決める
                val replyBody = entry.replyBody
                val smsParts = entry.smsParts
                if (replyBody != null) {
                    setOnLongClickListener {
                        showAutoReplyBodyDialog(replyBody)
                        true
                    }
                } else if (smsParts != null) {
                    setOnLongClickListener {
                        showSplitResultDialog(smsParts, entry.companyNameConverted)
                        true
                    }
                }
            }

            binding.llLogContainer.addView(entryView)
            binding.llLogContainer.addView(divider)
        }
    }

    /** 会社名はkintoneへ実際に登録した値（変換適用時は変換後の値）を表示する */
    private fun showSplitResultDialog(smsParts: SmsParts, companyNameConverted: Boolean) {
        val companyNameValue = if (companyNameConverted) {
            smsParts.companyNameNormalizedWidth
        } else {
            smsParts.companyName
        }
        val message = if (smsParts.isSplitFailed()) {
            getString(R.string.dialog_message_split_failure)
        } else {
            buildSpannedString {
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
        val title = "${getString(R.string.dialog_title_split_result)} $icon"
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    /** 自動返信ログの行を長押しした際に、実際に送信した返信本文をダイアログで表示する */
    private fun showAutoReplyBodyDialog(replyBody: String) {
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_auto_reply_body)
            .setMessage(replyBody)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    /** 結果行・分割結果行の両方で使う「[ラベル] メッセージ」形式の横並び行を組み立てる */
    private fun buildLabeledMessageRow(label: String, message: String, color: Int, topPadding: Int): View {
        return android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            setPadding(0, topPadding, 0, 4)
            addView(TextView(this@LogActivity).apply {
                text = getString(R.string.label_log_result_bracketed, label)
                setTextColor(color)
            })
            addView(TextView(this@LogActivity).apply {
                text = message
                setTextColor(color)
                setPadding(8, 0, 0, 0)
            })
        }
    }
}

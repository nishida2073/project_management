package com.ssfrontier.smstokintone

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import com.google.android.material.color.MaterialColors
import com.ssfrontier.smstokintone.databinding.ActivityLogBinding
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class LogActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLogBinding
    private val autoRefreshHandler = Handler(Looper.getMainLooper())
    private val autoRefreshRunnable = Runnable {
        renderLog()
        scheduleAutoRefresh()
    }

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

    override fun onResume() {
        super.onResume()
        renderLog()
        scheduleAutoRefresh()
    }

    override fun onPause() {
        super.onPause()
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
    }

    private fun scheduleAutoRefresh() {
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
        val config = SettingsStore.load(this)
        if (config.autoRefreshEnabled) {
            autoRefreshHandler.postDelayed(
                autoRefreshRunnable,
                config.autoRefreshIntervalSeconds * 1000L
            )
        }
    }

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

    private fun renderLog() {
        val entries = SmsLogStore.getAll(this)
        binding.llLogContainer.removeAllViews()
        binding.tvLogEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        val dateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
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

            val modeColor = ContextCompat.getColor(
                this@LogActivity,
                if (entry.manual) R.color.status_manual else R.color.status_running
            )

            // グループ1: ログ種別＋実行時のタイムスタンプ（種別は無彩色、送信系は自動＝青・手動＝アンバーで末尾に区別を付ける）
            val typeAndTimestampView = TextView(this).apply {
                text = buildSpannedString {
                    append(getString(R.string.label_log_type_bracketed, typeLabel))
                    append(" ${dateFormat.format(Date(entry.loggedAtMillis))}")
                    if (entry.type != SmsLogStore.EntryType.RECEIVE) {
                        append("  ")
                        color(modeColor) {
                            append(getString(if (entry.manual) R.string.label_log_type_suffix_manual else R.string.label_log_type_suffix_auto))
                        }
                    }
                }
                setTextColor(itemTextColor)
                setPadding(0, 24, 0, 4)
            }

            // グループ2: 設定名／送信元／SMS自体のタイムスタンプ／メッセージ（SMS本文）
            val profileView = TextView(this).apply {
                text = entry.profileName ?: getString(R.string.label_profile_none)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(ContextCompat.getColor(this@LogActivity, R.color.profile_name))
                setPadding(0, 16, 0, 4)
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

            // グループ3: 結果（受信・送信開始・送信完了共通で成功＝緑・失敗＝赤で色付け。
            // ラベルとメッセージは別列に分ける）
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

            // グループ4: 会社名・氏名・内容の分割結果（送信結果とは別の行で表示。結果の行と同じレイアウト）
            val splitResultView = entry.smsParts?.let { smsParts ->
                val succeeded = !smsParts.isSplitFailed()
                val splitLabel = if (succeeded) {
                    getString(R.string.label_log_result_success)
                } else {
                    getString(R.string.label_log_result_failure)
                }
                val splitColor = ContextCompat.getColor(
                    this@LogActivity,
                    if (succeeded) R.color.log_success else R.color.log_failure
                )
                val splitMessage = if (succeeded) {
                    getString(R.string.message_log_split)
                } else {
                    getString(R.string.message_log_split_failure)
                }
                buildLabeledMessageRow(splitLabel, splitMessage, splitColor, topPadding = 4)
            }

            val divider = View(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@LogActivity, R.color.log_divider))
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    2
                )
            }

            binding.llLogContainer.addView(typeAndTimestampView)
            binding.llLogContainer.addView(resultView)
            splitResultView?.let { binding.llLogContainer.addView(it) }
            binding.llLogContainer.addView(profileView)
            binding.llLogContainer.addView(senderAndTimestampView)
            binding.llLogContainer.addView(bodyView)
            binding.llLogContainer.addView(divider)
        }
    }

    /** 「[ラベル] メッセージ」を横並びの別列に分けた行を作る */
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

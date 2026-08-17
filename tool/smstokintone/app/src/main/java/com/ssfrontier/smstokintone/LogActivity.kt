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
        val config = Prefs.load(this)
        if (config.autoRefreshEnabled) {
            autoRefreshHandler.postDelayed(
                autoRefreshRunnable,
                config.autoRefreshIntervalSeconds * 1000L
            )
        }
    }

    private fun onClearClicked() {
        AlertDialog.Builder(this)
            .setTitle(R.string.confirm_clear_log_title)
            .setMessage(R.string.confirm_clear_log_message)
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_clear) { _, _ ->
                UploadLogStore.clear(this)
                renderLog()
            }
            .show()
    }

    private fun renderLog() {
        val entries = UploadLogStore.getAll(this)
        binding.llLogContainer.removeAllViews()
        binding.tvLogEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        val dateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
        entries.forEach { entry ->
            val typeLabel = when (entry.type) {
                UploadLogStore.EntryType.RECEIVE -> getString(R.string.log_type_receive)
                UploadLogStore.EntryType.SEND_START -> getString(R.string.log_type_send_start)
                UploadLogStore.EntryType.SEND_COMPLETE -> getString(R.string.log_type_send_complete)
            }

            val modeColor = ContextCompat.getColor(
                this@LogActivity,
                if (entry.manual) R.color.status_manual else R.color.status_running
            )

            // グループ1: ログ種別＋実行時のタイムスタンプ（種別は無彩色、送信系は自動＝青・手動＝アンバーで末尾に区別を付ける）
            val typeAndTimestampView = TextView(this).apply {
                text = buildSpannedString {
                    append("[$typeLabel")
                    if (entry.type != UploadLogStore.EntryType.RECEIVE) {
                        color(modeColor) { append(if (entry.manual) "・手動" else "・自動") }
                    }
                    append("] ${dateFormat.format(Date(entry.loggedAtMillis))}")
                }
                setPadding(0, 24, 0, 4)
            }

            // グループ2: 設定名／送信元／SMS自体のタイムスタンプ／メッセージ（SMS本文）
            val profileView = TextView(this).apply {
                text = entry.profileName ?: getString(R.string.label_profile_none)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setTextColor(ContextCompat.getColor(this@LogActivity, R.color.profile_name))
                setPadding(0, 16, 0, 4)
            }
            val senderView = TextView(this).apply {
                text = entry.sender
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setPadding(0, 0, 0, 4)
            }
            val smsTimestampView = TextView(this).apply {
                text = dateFormat.format(Date(entry.timestampMillis))
                setPadding(0, 0, 0, 4)
            }
            val bodyView = TextView(this).apply {
                text = entry.bodyPreview
                setPadding(0, 0, 0, 4)
            }

            // グループ3: 結果（送信完了のみ成功＝緑・失敗＝赤で色付け。ラベルとメッセージは別列に分ける）
            val resultView: View = if (entry.type == UploadLogStore.EntryType.SEND_COMPLETE) {
                val resultLabel = if (entry.success) {
                    getString(R.string.log_result_success)
                } else {
                    getString(R.string.log_result_failure)
                }
                val resultColor = ContextCompat.getColor(
                    this@LogActivity,
                    if (entry.success) R.color.log_success else R.color.log_failure
                )
                buildLabeledMessageRow(resultLabel, entry.message, resultColor, topPadding = 16)
            } else {
                TextView(this).apply {
                    text = entry.message
                    setPadding(0, 16, 0, 4)
                }
            }

            // グループ4: 会社名・氏名・内容の分割結果（送信結果とは別の行で表示。結果の行と同じレイアウト）
            val splitResultView = entry.parsedSms?.let { parsed ->
                val succeeded = parsed.companyName.isNotBlank() && parsed.userName.isNotBlank() && parsed.content.isNotBlank()
                val splitLabel = if (succeeded) {
                    getString(R.string.log_result_success)
                } else {
                    getString(R.string.log_result_failure)
                }
                val splitColor = ContextCompat.getColor(
                    this@LogActivity,
                    if (succeeded) R.color.log_success else R.color.log_failure
                )
                buildLabeledMessageRow(splitLabel, getString(R.string.log_split_label), splitColor, topPadding = 4)
            }

            val divider = View(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@LogActivity, R.color.log_divider))
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    2
                )
            }

            binding.llLogContainer.addView(typeAndTimestampView)
            binding.llLogContainer.addView(profileView)
            binding.llLogContainer.addView(senderView)
            binding.llLogContainer.addView(smsTimestampView)
            binding.llLogContainer.addView(bodyView)
            binding.llLogContainer.addView(resultView)
            splitResultView?.let { binding.llLogContainer.addView(it) }
            binding.llLogContainer.addView(divider)
        }
    }

    /** 「[ラベル] メッセージ」を横並びの別列に分けた行を作る */
    private fun buildLabeledMessageRow(label: String, message: String, color: Int, topPadding: Int): View {
        return android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            setPadding(0, topPadding, 0, 4)
            addView(TextView(this@LogActivity).apply {
                text = "[$label]"
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

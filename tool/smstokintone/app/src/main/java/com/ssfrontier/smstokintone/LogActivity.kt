package com.ssfrontier.smstokintone

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
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

            val resultColor = ContextCompat.getColor(
                this@LogActivity,
                when {
                    entry.type == UploadLogStore.EntryType.RECEIVE -> R.color.log_receive
                    entry.type == UploadLogStore.EntryType.SEND_START -> R.color.log_send_start
                    entry.success -> R.color.log_success
                    else -> R.color.log_failure
                }
            )

            // グループ1: ログ種別＋実行時のタイムスタンプ
            val typeAndTimestampView = TextView(this).apply {
                text = "[$typeLabel] ${dateFormat.format(Date(entry.loggedAtMillis))}"
                setTextColor(resultColor)
                setPadding(0, 24, 0, 4)
            }

            // グループ2: 電話番号／SMS自体のタイムスタンプ／メッセージ（SMS本文）
            val phoneView = TextView(this).apply {
                text = entry.sender
                setPadding(0, 16, 0, 4)
            }
            val smsTimestampView = TextView(this).apply {
                text = dateFormat.format(Date(entry.timestampMillis))
                setPadding(0, 0, 0, 4)
            }
            val bodyView = TextView(this).apply {
                text = entry.bodyPreview
                setPadding(0, 0, 0, 4)
            }

            // グループ3: 結果
            val resultView = TextView(this).apply {
                text = if (entry.type == UploadLogStore.EntryType.SEND_COMPLETE) {
                    val resultLabel = if (entry.success) {
                        getString(R.string.log_result_success)
                    } else {
                        getString(R.string.log_result_failure)
                    }
                    "[$resultLabel] ${entry.message}"
                } else {
                    entry.message
                }
                setPadding(0, 16, 0, 4)
            }

            val divider = View(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@LogActivity, R.color.log_divider))
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    2
                )
            }

            binding.llLogContainer.addView(typeAndTimestampView)
            binding.llLogContainer.addView(phoneView)
            binding.llLogContainer.addView(smsTimestampView)
            binding.llLogContainer.addView(bodyView)
            binding.llLogContainer.addView(resultView)
            binding.llLogContainer.addView(divider)
        }
    }
}

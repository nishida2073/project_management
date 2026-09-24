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

    /**
     * この画面のViewBinding。
     */
    private lateinit var binding: ActivityLogBinding

    companion object {
        private const val PADDING_RESULT_BOTTOM = 32
        private const val DIVIDER_HEIGHT = 2
    }

    /**
     * [autoRefreshRunnable]のスケジュール管理に使う[Handler]。メインスレッドで実行するため[Looper.getMainLooper]を使用。
     */
    private val autoRefreshHandler = Handler(Looper.getMainLooper())

    /**
     * 自動更新用Runnable。再描画のたびに次回実行を再スケジュールすることで、自動更新を継続させる。
     */
    private val autoRefreshRunnable = Runnable {
        renderLog()
        scheduleAutoRefresh()
    }

    /**
     * ログ一覧の初期表示と、更新/クリアボタン・スワイプ更新の配線を行う。
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLogBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnRefreshLog.setOnClickListener { renderLog() }
        binding.btnDeleteLog.setOnClickListener { onClearClicked() }
        binding.swipeRefreshLog.setOnRefreshListener {
            renderLog()
            binding.swipeRefreshLog.isRefreshing = false
        }
    }

    /**
     * 他画面での変更を反映するため、表示に戻るたびに再描画し、自動更新のスケジュールを再開する。
     */
    override fun onResume() {
        super.onResume()
        renderLog()
        scheduleAutoRefresh()
    }

    /**
     * 画面が表示されていない間は自動更新を停止する。
     */
    override fun onPause() {
        super.onPause()
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
    }

    /**
     * 設定で自動更新が有効な場合、次回の[autoRefreshRunnable]実行を予約する。
     * 既存予約をキャンセルしてから積み直すことで、[onResume]と[autoRefreshRunnable]の両方から呼ばれる際の多重登録を防ぐ。
     */
    private fun scheduleAutoRefresh() {
        autoRefreshHandler.removeCallbacks(autoRefreshRunnable)
        val config = SettingsStore.load(this)
        if (config.logRefreshEnabled) {
            autoRefreshHandler.postDelayed(
                autoRefreshRunnable,
                config.logRefreshIntervalSeconds * 1000L
            )
        }
    }

    /**
     * 確認ダイアログを表示し、ユーザーが了承したらログを全削除して再描画する。
     */
    private fun onClearClicked() {
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_log_confirm_delete_log)
            .setMessage(R.string.dialog_message_log_confirm_delete_log)
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_delete) { _, _ ->
                SmsLogStore.clear(this)
                renderLog()
            }
            .show()
    }

    /**
     * [SmsLogStore]の全エントリを読み込み、一覧のViewを組み立て直して表示する。
     */
    private fun renderLog() {
        val entries = SmsLogStore.getAll(this)
        binding.llLogContainer.removeAllViews()
        binding.tvLogEmpty.visibility = if (entries.isEmpty()) View.VISIBLE else View.GONE

        val config = SettingsStore.load(this)
        val dateFormat = DateFormats.display()
        val itemTextColor = MaterialColors.getColor(
            binding.llLogContainer,
            com.google.android.material.R.attr.colorOnSurface
        )
        entries.forEach { entry ->
            val entryView = buildEntryView(entry, config, dateFormat, itemTextColor)
            binding.llLogContainer.addView(entryView)
            binding.llLogContainer.addView(buildDivider())
        }
    }

    private fun buildEntryView(entry: SmsLogStore.Entry, config: SettingsStore.Config, dateFormat: java.text.SimpleDateFormat, itemTextColor: Int): View {
        return android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            addView(buildTypeAndTimestampView(entry, dateFormat, itemTextColor))
            addView(buildResultView(entry, itemTextColor))
            addView(buildStatusIconsView(entry, config, dateFormat, itemTextColor))
            setupLongClickListener(entry)
        }
    }

    private fun buildTypeAndTimestampView(entry: SmsLogStore.Entry, dateFormat: java.text.SimpleDateFormat, itemTextColor: Int): TextView {
        val typeLabel = when (entry.type) {
            SmsLogStore.EntryType.RECEIVE -> getString(R.string.label_log_type_receive)
            SmsLogStore.EntryType.SEND_START -> getString(R.string.label_log_type_send_start)
            SmsLogStore.EntryType.SEND_COMPLETE -> getString(R.string.label_log_type_send_complete)
            SmsLogStore.EntryType.AUTO_REPLY -> getString(R.string.label_log_type_auto_reply)
        }
        return TextView(this).apply {
            text = buildSpannedString {
                append(getString(R.string.label_log_type_bracketed, typeLabel))
                append(dateFormat.format(Date(entry.loggedAtMillis)))
            }
            setTextColor(itemTextColor)
        }
    }

    private fun buildStatusIconsView(entry: SmsLogStore.Entry, config: SettingsStore.Config, dateFormat: java.text.SimpleDateFormat, itemTextColor: Int): TextView {
        val extractionTargetIcon = entry.smsParts?.let { if (entry.isContinuation) getString(R.string.icon_extraction_target_storage) else getString(R.string.icon_extraction_target_sms) } ?: ""
        val isExtractionFailed = entry.smsParts?.isExtractionFailed() ?: false
        val sendStatus = when {
            entry.type == SmsLogStore.EntryType.SEND_START || entry.type == SmsLogStore.EntryType.SEND_COMPLETE -> getString(if (entry.manual) R.string.icon_send_manual else R.string.icon_send_auto)
            else -> null
        }
        val isAutoReplied = entry.type == SmsLogStore.EntryType.AUTO_REPLY
        val sendTargetIcon = getString(
            when {
                entry.sendTargetName == null -> R.string.icon_send_target_unconfigured
                else -> R.string.icon_send_target_exists
            }
        )
        val sendTargetName = entry.sendTargetName ?: getString(R.string.label_send_target_settings_none)
        val sendTargetColor = ContextCompat.getColor(this, R.color.send_target_name)
        val senderDisplay = if (entry.isContinuation && config.continuationShowUserNameEnabled && entry.smsParts?.userName?.isNotBlank() == true) {
            entry.smsParts.userName
        } else {
            entry.sender
        }
        val dateString = dateFormat.format(Date(entry.timestampMillis))

        return TextView(this).apply {
            text = buildSmsInfoString(extractionTargetIcon, isExtractionFailed, sendStatus, isAutoReplied, sendTargetIcon, sendTargetName, sendTargetColor, senderDisplay, dateString, entry.bodyExcerpt)
            setTextColor(itemTextColor)
        }
    }

    private fun buildResultView(entry: SmsLogStore.Entry, itemTextColor: Int): View {
        val resultLabel = if (entry.success) {
            getString(R.string.label_log_result_success)
        } else {
            getString(R.string.label_log_result_failure)
        }
        val resultColor = ContextCompat.getColor(
            this,
            if (entry.success) R.color.log_success else R.color.log_failure
        )
        return buildLabeledMessageRow(resultLabel, entry.message, resultColor)
    }

    private fun buildDivider(): View {
        return View(this).apply {
            setBackgroundColor(ContextCompat.getColor(this@LogActivity, R.color.log_divider))
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                DIVIDER_HEIGHT
            )
        }
    }

    private fun android.widget.LinearLayout.setupLongClickListener(entry: SmsLogStore.Entry) {
        val replyBody = entry.replyBody
        val smsParts = entry.smsParts
        if (replyBody != null) {
            setOnLongClickListener {
                showAutoReplyBodyDialog(replyBody)
                true
            }
        } else if (smsParts != null) {
            setOnLongClickListener {
                showExtractionResultDialog(smsParts, entry.companyNameConverted)
                true
            }
        }
    }

    /** 会社名は[SmsParts.companyName]（[SettingsStore.resolveSendTargets]で会社名変換が適用済み）をそのまま表示する */
    private fun showExtractionResultDialog(smsParts: SmsParts, companyNameConverted: Boolean) {
        val message = if (smsParts.isExtractionFailed()) {
            getString(R.string.dialog_message_log_extraction_failure)
        } else {
            buildSpannedString {
                bold { append(getString(R.string.hint_send_target_settings_field_company)) }
                append("：${smsParts.companyName}\n")
                bold { append(getString(R.string.hint_send_target_settings_field_user_name)) }
                append("：${smsParts.userName}\n\n")
                append(smsParts.body)
            }
        }
        val extractionMethodIcon = if (smsParts.extractedByAi) {
            getString(R.string.icon_extraction_ai)
        } else {
            getString(R.string.icon_extraction_rule)
        }
        val title = buildString {
            append(getString(R.string.dialog_title_log_extraction_result))
            append(" ")
            append(extractionMethodIcon)
            if (!smsParts.isExtractionFailed() && companyNameConverted) {
                append(" ")
                append(getString(R.string.icon_company_name_converted))
            }
        }
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    /** 自動返信ログの行を長押しした際に、実際に送信した返信本文をダイアログで表示する */
    private fun showAutoReplyBodyDialog(replyBody: String) {
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_log_auto_reply_body)
            .setMessage(replyBody)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun buildLabeledMessageRow(label: String, message: String, color: Int): TextView {
        return TextView(this).apply {
            text = buildSpannedString {
                append(getString(R.string.label_log_result_bracketed, label))
                append(message)
            }
            setTextColor(color)
            setPadding(0, 0, 0, PADDING_RESULT_BOTTOM)
        }
    }
}

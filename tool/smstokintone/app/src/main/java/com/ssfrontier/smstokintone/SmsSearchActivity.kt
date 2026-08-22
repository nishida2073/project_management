package com.ssfrontier.smstokintone

import android.Manifest
import android.app.DatePickerDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.CheckBox
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import androidx.lifecycle.Observer
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkContinuation
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.ssfrontier.smstokintone.databinding.ActivitySmsSearchBinding
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.math.abs

class SmsSearchActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySmsSearchBinding

    private var fromMillis: Long? = null
    private var toMillis: Long? = null
    private val records = mutableListOf<SmsRecord>()

    private var profileFilterKeys: List<String?> = emptyList()
    private var selectedProfileId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySmsSearchBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.etDateFrom.setOnClickListener { pickDate(isFrom = true) }
        binding.etDateTo.setOnClickListener { pickDate(isFrom = false) }
        binding.btnSearchSms.setOnClickListener { searchSms() }
        binding.btnSelectAll.setOnClickListener { setAllChecked(true) }
        binding.btnDeselectAll.setOnClickListener { setAllChecked(false) }
        binding.btnSendSelected.setOnClickListener { sendSelected() }
        binding.btnToggleSearchFilters.setOnClickListener { toggleSearchFilters() }
        binding.swipeRefreshSmsList.setOnRefreshListener {
            searchSms(showFoundToast = false)
            binding.swipeRefreshSmsList.isRefreshing = false
        }
        binding.spProfileFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                selectedProfileId = profileFilterKeys.getOrNull(position)
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        val config = SettingsStore.load(this)
        selectedProfileId = config.defaultProfileFilterId
        val today = Calendar.getInstance()
        val rangeStart = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, -(config.smsSearchDateRangeDays - 1)) }
        applyDateFilter(isFrom = true, calendar = rangeStart)
        applyDateFilter(isFrom = false, calendar = today)
    }

    override fun onResume() {
        super.onResume()
        updatePermissionUi()
        refreshProfileFilterOptions()
        searchSms(showFoundToast = false)
    }

    private fun refreshProfileFilterOptions() {
        val options = SettingsStore.profileFilterOptions(this)
        profileFilterKeys = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spProfileFilter.adapter = adapter

        val restoreIndex = profileFilterKeys.indexOf(selectedProfileId)
        binding.spProfileFilter.setSelection(if (restoreIndex >= 0) restoreIndex else 0)
    }

    private fun hasReadSmsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun updatePermissionUi() {
        val granted = hasReadSmsPermission()
        binding.layoutPermissionRequired.visibility = if (granted) View.GONE else View.VISIBLE
        binding.layoutSearchForm.visibility = if (granted) View.VISIBLE else View.GONE
    }

    /** 検索条件エリアの表示/非表示を切り替え、一覧により多くの領域を割けるようにする */
    private fun toggleSearchFilters() {
        val show = binding.llSearchFilters.visibility != View.VISIBLE
        binding.llSearchFilters.visibility = if (show) View.VISIBLE else View.GONE
        binding.btnToggleSearchFilters.text = getString(
            if (show) R.string.btn_hide_search_filters else R.string.btn_show_search_filters
        )
    }

    private fun pickDate(isFrom: Boolean) {
        val currentSelection = if (isFrom) fromMillis else toMillis
        val calendar = Calendar.getInstance().apply {
            currentSelection?.let { timeInMillis = it }
        }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply { set(year, month, dayOfMonth) }
                applyDateFilter(isFrom, picked)
            },
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH),
            calendar.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    private fun applyDateFilter(isFrom: Boolean, calendar: Calendar) {
        val display = SimpleDateFormat("yyyy/MM/dd", Locale.JAPAN).format(calendar.time)
        if (isFrom) {
            val startOfDay = (calendar.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            fromMillis = startOfDay.timeInMillis
            binding.etDateFrom.setText(display)
        } else {
            val endOfDay = (calendar.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 23)
                set(Calendar.MINUTE, 59)
                set(Calendar.SECOND, 59)
                set(Calendar.MILLISECOND, 999)
            }
            toMillis = endOfDay.timeInMillis
            binding.etDateTo.setText(display)
        }
    }

    private fun searchSms(showFoundToast: Boolean = true) {
        if (!hasReadSmsPermission()) return

        val bodyFilter = binding.etBodyFilter.text.toString().trim()
        val selectionParts = mutableListOf("${Telephony.Sms.TYPE} = ?")
        val selectionArgs = mutableListOf(Telephony.Sms.MESSAGE_TYPE_INBOX.toString())

        fromMillis?.let {
            selectionParts.add("${Telephony.Sms.DATE} >= ?")
            selectionArgs.add(it.toString())
        }
        toMillis?.let {
            selectionParts.add("${Telephony.Sms.DATE} <= ?")
            selectionArgs.add(it.toString())
        }
        if (bodyFilter.isNotBlank()) {
            selectionParts.add("${Telephony.Sms.BODY} LIKE ?")
            selectionArgs.add("%$bodyFilter%")
        }

        records.clear()
        try {
            contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms._ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE
                ),
                selectionParts.joinToString(" AND "),
                selectionArgs.toTypedArray(),
                "${Telephony.Sms.DATE} DESC"
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addressIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
                while (cursor.moveToNext()) {
                    records.add(
                        SmsRecord(
                            id = cursor.getLong(idIndex),
                            address = cursor.getString(addressIndex) ?: "",
                            body = cursor.getString(bodyIndex) ?: "",
                            dateMillis = cursor.getLong(dateIndex)
                        )
                    )
                }
            } ?: Toast.makeText(this, getString(R.string.toast_sms_search_error_null_cursor), Toast.LENGTH_LONG).show()
        } catch (e: SecurityException) {
            Toast.makeText(this, getString(R.string.toast_sms_search_permission_error, e.message ?: ""), Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, getString(R.string.toast_sms_search_error, e.message ?: ""), Toast.LENGTH_LONG).show()
        }

        if (binding.cbUnsentOnly.isChecked) {
            val sentEntries = matchSentEntries(records, loadCompletedEntries())
            records.removeAll { it.id in sentEntries }
        }

        if (binding.cbSplitFailedOnly.isChecked) {
            records.removeAll { !isSplitFailed(it.body) }
        }

        when (val profileId = selectedProfileId) {
            null -> Unit
            AppConstants.PROFILE_FILTER_KEY_UNSET -> records.removeAll { SettingsStore.findProfileForBody(this, it.body) != null }
            else -> records.removeAll { SettingsStore.findProfileForBody(this, it.body)?.id != profileId }
        }

        if (showFoundToast) {
            Toast.makeText(this, getString(R.string.toast_sms_search_found, records.size), Toast.LENGTH_SHORT).show()
        }
        renderSmsList()
    }

    private fun loadCompletedEntries(): List<SmsLogStore.Entry> =
        SmsLogStore.getAll(this)
            .filter { it.type == SmsLogStore.EntryType.SEND_COMPLETE && it.success }

    /**
     * ログのエントリとSMSレコードを1対1で対応付ける。手動送信のログはSMS検索画面で特定済みの
     * 確実なIDを持つため、そのID一致で対応付ける。自動送信のログはIDを持たないため、送信元・
     * タイムスタンプの近さで対応付ける（SmsMatching参照）が、同じ送信元から似た内容のSMSが
     * 許容範囲内（アプリ設定画面の「統合範囲」）に複数届いた場合に1件のログが複数のレコードへ
     * 同時にマッチしてしまうのを防ぐため、時刻が近いレコードから順に、1件のログにつき1件の
     * レコードだけを貪欲に割り当てる。
     */
    private fun matchSentEntries(
        records: List<SmsRecord>,
        completedEntries: List<SmsLogStore.Entry>
    ): Map<Long, SmsLogStore.Entry> {
        val result = mutableMapOf<Long, SmsLogStore.Entry>()

        val idMatchedEntries = completedEntries.filter { it.smsId != null }.associateBy { it.smsId }
        records.forEach { record ->
            idMatchedEntries[record.id]?.let { result[record.id] = it }
        }

        val toleranceMillis = SettingsStore.load(this).smsMatchToleranceSeconds * 1_000L
        val unclaimedEntries = completedEntries.filter { it.smsId == null }.toMutableList()
        records.filter { it.id !in result }
            .sortedBy { it.dateMillis }
            .forEach { record ->
                val bestIndex = unclaimedEntries.indices
                    .filter { i ->
                        val entry = unclaimedEntries[i]
                        SmsMatching.isLikelySameSms(entry.sender, entry.timestampMillis, record.address, record.dateMillis, toleranceMillis)
                    }
                    .minByOrNull { i -> abs(unclaimedEntries[i].timestampMillis - record.dateMillis) }
                if (bestIndex != null) {
                    result[record.id] = unclaimedEntries[bestIndex]
                    unclaimedEntries.removeAt(bestIndex)
                }
            }

        return result
    }

    private fun isSplitFailed(body: String): Boolean = SmsPartsGenerator.generateSmsParts(body).isSplitFailed()

    /** 標準のSMSアプリの返信（作成）画面を、指定した送信元宛てに開く */
    private fun openSmsReply(address: String, splitFailed: Boolean) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$address"))
        val config = SettingsStore.load(this)
        val body = if (splitFailed) config.splitFailedReplyAddition else config.defaultReplyBody
        if (body.isNotEmpty()) {
            intent.putExtra("sms_body", body)
        }
        try {
            startActivity(intent)
        } catch (e: android.content.ActivityNotFoundException) {
            Toast.makeText(this, getString(R.string.toast_sms_app_not_found), Toast.LENGTH_SHORT).show()
        }
    }

    private fun renderSmsList() {
        binding.llSmsListContainer.removeAllViews()
        binding.svSmsList.scrollTo(0, 0)
        binding.tvSmsListEmpty.visibility = if (records.isEmpty()) View.VISIBLE else View.GONE

        val sentEntries = matchSentEntries(records, loadCompletedEntries())
        val dateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
        records.forEach { record ->
            val checkBox = CheckBox(this).apply {
                tag = record.id
                val profile = SettingsStore.findProfileForBody(this@SmsSearchActivity, record.body)
                val profileName = profile?.displayName(this@SmsSearchActivity) ?: getString(R.string.label_profile_none)
                val isProfileUnconfigured = profile == null || !profile.isValid
                val profileColor = ContextCompat.getColor(this@SmsSearchActivity, R.color.profile_name)
                text = buildSpannedString {
                    if (isProfileUnconfigured) {
                        append(getString(R.string.label_profile_unconfigured_marker))
                    }
                    if (isSplitFailed(record.body)) {
                        append(getString(R.string.label_split_failed_marker))
                    }
                    if (isProfileUnconfigured || isSplitFailed(record.body)) {
                        append("\n")
                    }
                    color(profileColor) { bold { append(profileName) } }
                    append("\n${dateFormat.format(Date(record.dateMillis))}　${record.address}\n")
                    append(record.body.take(80))
                }
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                )
                setPadding(0, 16, 0, 16)
                val sentEntry = sentEntries[record.id]
                val backgroundColor = when {
                    sentEntry != null && sentEntry.manual -> R.color.sms_sent_manual_background
                    sentEntry != null -> R.color.sms_sent_auto_background
                    else -> null
                }
                backgroundColor?.let {
                    setBackgroundColor(ContextCompat.getColor(this@SmsSearchActivity, it))
                }
                setOnLongClickListener {
                    openSmsReply(record.address, isSplitFailed(record.body))
                    true
                }
            }

            val divider = View(this).apply {
                setBackgroundColor(ContextCompat.getColor(this@SmsSearchActivity, R.color.log_divider))
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    2
                )
            }

            binding.llSmsListContainer.addView(checkBox)
            binding.llSmsListContainer.addView(divider)
        }
    }

    private fun setAllChecked(checked: Boolean) {
        for (i in 0 until binding.llSmsListContainer.childCount) {
            (binding.llSmsListContainer.getChildAt(i) as? CheckBox)?.isChecked = checked
        }
    }

    private fun sendSelected() {
        val checkedIds = mutableSetOf<Long>()
        for (i in 0 until binding.llSmsListContainer.childCount) {
            val checkBox = binding.llSmsListContainer.getChildAt(i) as? CheckBox ?: continue
            if (checkBox.isChecked) checkedIds.add(checkBox.tag as Long)
        }

        val selectedRecords = records.filter { it.id in checkedIds }
        if (selectedRecords.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_sms_send_not_selection), Toast.LENGTH_SHORT).show()
            return
        }

        val workManager = WorkManager.getInstance(this)
        var continuation: WorkContinuation? = null
        var lastRequest: androidx.work.OneTimeWorkRequest? = null
        selectedRecords.forEach { record ->
            val data = workDataOf(
                KintoneUploadWorker.KEY_SENDER to record.address,
                KintoneUploadWorker.KEY_BODY to record.body,
                KintoneUploadWorker.KEY_TIMESTAMP to record.dateMillis,
                KintoneUploadWorker.KEY_MANUAL to true,
                KintoneUploadWorker.KEY_SMS_ID to record.id
            )
            val request = OneTimeWorkRequestBuilder<KintoneUploadWorker>()
                .setInputData(data)
                .setBackoffCriteria(
                    AppConstants.KINTONE_UPLOAD_RETRY_BACKOFF_POLICY,
                    AppConstants.KINTONE_UPLOAD_RETRY_BACKOFF_MILLIS,
                    TimeUnit.MILLISECONDS
                )
                .build()
            // 1件ずつ順番に処理させ、ログの送信開始/送信完了が入り乱れないようにする
            continuation = continuation?.then(request) ?: workManager.beginWith(request)
            lastRequest = request
        }
        continuation?.enqueue()

        val selectedIds = selectedRecords.map { it.id }.toSet()
        lastRequest?.let { request ->
            workManager.getWorkInfoByIdLiveData(request.id).observe(this, Observer { workInfo ->
                if (workInfo != null && workInfo.state.isFinished) {
                    onSendBatchFinished(selectedIds)
                }
            })
        }

        Toast.makeText(
            this,
            getString(R.string.toast_sms_send_queued, selectedRecords.size),
            Toast.LENGTH_LONG
        ).show()

        // メッセージの表示が終わってからチェックを解除して一覧を更新する。すぐ更新すると
        // チェックが消えるところがメッセージの表示と重なって見えてしまうため
        Handler(Looper.getMainLooper()).postDelayed({
            setAllChecked(false)
            searchSms(showFoundToast = false)
        }, TOAST_LONG_DURATION_MILLIS)
    }

    private fun onSendBatchFinished(selectedIds: Set<Long>) {
        // 送信先が未設定の場合は送信開始(SEND_START)のみが記録され送信完了(SEND_COMPLETE)は
        // 記録されないため、smsIdごとに最新の1件（開始・完了どちらか）を結果として扱う
        val latestCompleteEntryPerSms = SmsLogStore.getAll(this)
            .filter { it.type != SmsLogStore.EntryType.RECEIVE && it.smsId in selectedIds }
            .groupBy { it.smsId }
            .mapValues { it.value.first() }

        if (latestCompleteEntryPerSms.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_sms_send_finished_no_log), Toast.LENGTH_LONG).show()
        } else {
            val successCount = latestCompleteEntryPerSms.values.count { it.success }
            val failureCount = latestCompleteEntryPerSms.size - successCount
            Toast.makeText(
                this,
                getString(R.string.toast_sms_send_finished, successCount, failureCount),
                Toast.LENGTH_LONG
            ).show()
        }

        // Toast.LENGTH_LONGの表示が終わってから一覧を更新する。すぐ更新するとチェック状態が
        // 消えるところがメッセージの表示と重なって見えてしまうため
        Handler(Looper.getMainLooper()).postDelayed({ searchSms(showFoundToast = false) }, TOAST_LONG_DURATION_MILLIS)
    }

    private data class SmsRecord(
        val id: Long,
        val address: String,
        val body: String,
        val dateMillis: Long
    )

    companion object {
        private const val TOAST_LONG_DURATION_MILLIS = 3_500L
    }
}

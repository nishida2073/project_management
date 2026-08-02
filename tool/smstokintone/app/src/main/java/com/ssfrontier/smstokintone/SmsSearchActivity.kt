package com.ssfrontier.smstokintone

import android.Manifest
import android.app.DatePickerDialog
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Telephony
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.CheckBox
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import androidx.lifecycle.Observer
import androidx.work.BackoffPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkContinuation
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.workDataOf
import com.ssfrontier.smstokintone.databinding.ActivitySmsSearchBinding
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class SmsSearchActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySmsSearchBinding

    private var fromMillis: Long? = null
    private var toMillis: Long? = null
    private val records = mutableListOf<SmsRecord>()

    private var profileOptions: List<Prefs.KintoneProfile?> = emptyList()
    private var selectedProfileId: String? = null

    private val requestReadSmsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            updatePermissionUi()
            if (!granted) {
                Toast.makeText(
                    this,
                    "SMSの読み取りを許可しないと、受信済みのSMSは検索できません",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

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
        binding.btnRequestReadSmsPermission.setOnClickListener {
            requestReadSmsPermissionLauncher.launch(Manifest.permission.READ_SMS)
        }
        binding.spProfileFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                selectedProfileId = profileOptions.getOrNull(position)?.id
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        val today = Calendar.getInstance()
        val weekAgo = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, -7) }
        applyDateFilter(isFrom = true, calendar = weekAgo)
        applyDateFilter(isFrom = false, calendar = today)
    }

    override fun onResume() {
        super.onResume()
        updatePermissionUi()
        refreshProfileFilterOptions()
    }

    private fun refreshProfileFilterOptions() {
        val profiles = Prefs.loadProfiles(this)
        profileOptions = listOf(null) + profiles
        val labels = listOf(getString(R.string.filter_profile_all)) + profiles.map { it.displayName }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spProfileFilter.adapter = adapter

        val restoreIndex = profileOptions.indexOfFirst { it?.id == selectedProfileId }
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
            } ?: Toast.makeText(this, "SMSの検索でエラーが発生しました（クエリ結果がnull）", Toast.LENGTH_LONG).show()
        } catch (e: SecurityException) {
            Toast.makeText(this, "SMSの読み取り権限がないため検索できません: ${e.message}", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, "SMSの検索でエラーが発生しました: ${e.message}", Toast.LENGTH_LONG).show()
        }

        if (binding.cbUnsentOnly.isChecked) {
            val completedEntries = loadCompletedEntries()
            records.removeAll { findSentEntry(it, completedEntries) != null }
        }

        selectedProfileId?.let { profileId ->
            records.removeAll { Prefs.findProfileForBody(this, it.body)?.id != profileId }
        }

        if (showFoundToast) {
            Toast.makeText(this, "${records.size}件見つかりました", Toast.LENGTH_SHORT).show()
        }
        renderSmsList()
    }

    private fun loadCompletedEntries(): List<UploadLogStore.Entry> =
        UploadLogStore.getAll(this)
            .filter { it.type == UploadLogStore.EntryType.SEND_COMPLETE && it.success }

    /**
     * 手動送信のログはSMS検索画面で特定済みの確実なIDを持つため、そのID一致で判定する。
     * 自動転送のログはIDを持たないため、送信元とタイムスタンプの近さで判定する（SmsMatching参照）。
     */
    private fun findSentEntry(record: SmsRecord, completedEntries: List<UploadLogStore.Entry>): UploadLogStore.Entry? =
        completedEntries.firstOrNull { entry ->
            if (entry.smsId != null) {
                entry.smsId == record.id
            } else {
                SmsMatching.isLikelySameSms(entry.sender, entry.timestampMillis, record.address, record.dateMillis)
            }
        }

    private fun renderSmsList() {
        binding.llSmsListContainer.removeAllViews()
        binding.tvSmsListEmpty.visibility = if (records.isEmpty()) View.VISIBLE else View.GONE

        val completedEntries = loadCompletedEntries()
        val dateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
        records.forEach { record ->
            val checkBox = CheckBox(this).apply {
                tag = record.id
                val profileName = Prefs.findProfileForBody(this@SmsSearchActivity, record.body)?.displayName
                    ?: getString(R.string.label_profile_none)
                val profileColor = ContextCompat.getColor(this@SmsSearchActivity, R.color.profile_name)
                text = buildSpannedString {
                    color(profileColor) { bold { append(profileName) } }
                    append("\n${dateFormat.format(Date(record.dateMillis))}　${record.address}\n")
                    append(record.body.take(80))
                }
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                )
                setPadding(0, 16, 0, 16)
                val sentEntry = findSentEntry(record, completedEntries)
                if (sentEntry != null) {
                    val backgroundColor = if (sentEntry.manual) {
                        R.color.sms_sent_manual_background
                    } else {
                        R.color.sms_sent_auto_background
                    }
                    setBackgroundColor(ContextCompat.getColor(this@SmsSearchActivity, backgroundColor))
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
            Toast.makeText(this, getString(R.string.toast_no_selection), Toast.LENGTH_SHORT).show()
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
                    BackoffPolicy.LINEAR,
                    WorkRequest.MIN_BACKOFF_MILLIS,
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

        // キュー投入直後にチェックを解除して一覧を更新し、投入されたことを見た目でも分かるようにする
        setAllChecked(false)
        searchSms(showFoundToast = false)

        Toast.makeText(
            this,
            getString(R.string.toast_queued, selectedRecords.size),
            Toast.LENGTH_LONG
        ).show()
    }

    private fun onSendBatchFinished(selectedIds: Set<Long>) {
        val latestCompleteEntryPerSms = UploadLogStore.getAll(this)
            .filter { it.type == UploadLogStore.EntryType.SEND_COMPLETE && it.smsId in selectedIds }
            .groupBy { it.smsId }
            .mapValues { it.value.first() }

        if (latestCompleteEntryPerSms.isEmpty()) {
            Toast.makeText(this, getString(R.string.toast_send_finished_no_log), Toast.LENGTH_LONG).show()
        } else {
            val successCount = latestCompleteEntryPerSms.values.count { it.success }
            val failureCount = latestCompleteEntryPerSms.size - successCount
            Toast.makeText(
                this,
                getString(R.string.toast_send_finished, successCount, failureCount),
                Toast.LENGTH_LONG
            ).show()
        }

        searchSms(showFoundToast = false)
    }

    private data class SmsRecord(
        val id: Long,
        val address: String,
        val body: String,
        val dateMillis: Long
    )
}

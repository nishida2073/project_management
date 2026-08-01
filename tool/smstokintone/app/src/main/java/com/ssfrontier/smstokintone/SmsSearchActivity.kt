package com.ssfrontier.smstokintone

import android.Manifest
import android.app.DatePickerDialog
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Telephony
import android.view.View
import android.widget.CheckBox
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.OneTimeWorkRequestBuilder
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

        val today = Calendar.getInstance()
        val weekAgo = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, -7) }
        applyDateFilter(isFrom = true, calendar = weekAgo)
        applyDateFilter(isFrom = false, calendar = today)
    }

    override fun onResume() {
        super.onResume()
        updatePermissionUi()
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

    private fun searchSms() {
        if (!hasReadSmsPermission()) return

        val senderFilter = binding.etSenderFilter.text.toString().trim()
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
        if (senderFilter.isNotBlank()) {
            selectionParts.add("${Telephony.Sms.ADDRESS} LIKE ?")
            selectionArgs.add("%$senderFilter%")
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
            val sentSmsIds = loadSentSmsIds()
            records.removeAll { it.id in sentSmsIds }
        }

        Toast.makeText(this, "${records.size}件見つかりました", Toast.LENGTH_SHORT).show()
        renderSmsList()
    }

    private fun loadSentSmsIds(): Set<Long> =
        UploadLogStore.getAll(this)
            .filter { it.type == UploadLogStore.EntryType.SEND_START }
            .mapNotNull { it.smsId }
            .toSet()

    private fun renderSmsList() {
        binding.llSmsListContainer.removeAllViews()
        binding.tvSmsListEmpty.visibility = if (records.isEmpty()) View.VISIBLE else View.GONE

        val sentSmsIds = loadSentSmsIds()
        val dateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
        records.forEach { record ->
            val checkBox = CheckBox(this).apply {
                tag = record.id
                text = "${dateFormat.format(Date(record.dateMillis))}　${record.address}\n${record.body.take(80)}"
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                )
                setPadding(0, 16, 0, 16)
                if (record.id in sentSmsIds) {
                    setBackgroundColor(ContextCompat.getColor(this@SmsSearchActivity, R.color.sms_sent_background))
                }
            }
            binding.llSmsListContainer.addView(checkBox)
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
            workManager.enqueue(request)
        }

        Toast.makeText(
            this,
            getString(R.string.toast_queued, selectedRecords.size),
            Toast.LENGTH_LONG
        ).show()
    }

    private data class SmsRecord(
        val id: Long,
        val address: String,
        val body: String,
        val dateMillis: Long
    )
}

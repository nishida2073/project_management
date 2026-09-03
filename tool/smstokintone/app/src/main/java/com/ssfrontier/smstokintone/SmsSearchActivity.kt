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
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import androidx.lifecycle.Observer
import androidx.lifecycle.lifecycleScope
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkContinuation
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.ssfrontier.smstokintone.databinding.ActivitySmsSearchBinding
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/** 受信箱のSMSを日付・本文・送信状況・送信先で絞り込んで一覧表示し、選択した分をKintoneへ手動送信キューに載せる画面 */
class SmsSearchActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivitySmsSearchBinding

    /** 日付絞り込みの範囲（inclusive）。applyDateFilterで開始日は00:00:00.000、終了日は23:59:59.999に正規化される */
    private var fromMillis: Long? = null
    /** [fromMillis]と対をなす終了日時 */
    private var toMillis: Long? = null
    /** 直近のsearchSmsの結果。一覧描画・全選択/解除・送信対象の特定に共用するため、検索のたびにクリアして詰め直す */
    private val records = mutableListOf<SmsRecord>()

    /**
     * スピナーの表示位置に対応する送信先ID（sendTargetFilterOptionsと同じ並び）。null=すべて、
     * AppConstants.SEND_TARGET_FILTER_KEY_UNSET=未設定、それ以外は送信先ID
     */
    private var sendTargetFilterKeys: List<String?> = emptyList()
    /** 現在選択中の送信先フィルタのID。[sendTargetFilterKeys]の要素の一つ */
    private var selectedSendTargetId: String? = null

    /**
     * 直近のsearchSms呼び出し内でのSettingsStore.resolveSendTargets結果をrecord.idごとにキャッシュしたもの。
     * 送信先フィルタ・分割失敗フィルタ・一覧描画がいずれも同じrecordに対して抽出結果を必要とするため、
     * AI呼び出しを伴い得る抽出処理を1件のSMSにつき1回で済ませるためのもの。searchSmsのたびに作り直す
     */
    private var resolvedPartsCache = mutableMapOf<Long, Pair<SettingsStore.SmsResolution, List<SettingsStore.SendTarget>>>()

    /**
     * リスナー登録と、SettingsStoreに保存済みの初期条件（既定の日付範囲・送信先フィルタ・各チェックボックス）の反映のみ行う。
     * 実際の検索はonResumeで行われる
     */
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
        binding.spSendTargetFilter.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                selectedSendTargetId = sendTargetFilterKeys.getOrNull(position)
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        val config = SettingsStore.load(this)
        selectedSendTargetId = config.defaultSendTargetFilterId
        val today = Calendar.getInstance()
        val rangeStart = Calendar.getInstance().apply { add(Calendar.DAY_OF_MONTH, -(config.smsSearchDateRangeDays - 1)) }
        applyDateFilter(isFrom = true, calendar = rangeStart)
        applyDateFilter(isFrom = false, calendar = today)

        binding.llSearchFilters.visibility = if (config.searchFiltersVisibleByDefault) View.VISIBLE else View.GONE
        binding.btnToggleSearchFilters.text = getString(
            if (config.searchFiltersVisibleByDefault) R.string.btn_hide_search_filters else R.string.btn_show_search_filters
        )

        binding.cbSendNoneOnly.isChecked = config.defaultSendNoneOnlyEnabled
        binding.cbSentAutoOnly.isChecked = config.defaultSentAutoOnlyEnabled
        binding.cbSentManualOnly.isChecked = config.defaultSentManualOnlyEnabled
        binding.cbSplitFailedOnly.isChecked = config.defaultSplitFailedOnlyEnabled
        binding.cbSplitSucceededOnly.isChecked = config.defaultSplitSucceededOnlyEnabled
        binding.cbSplitExcludedOnly.isChecked = config.defaultSplitExcludedOnlyEnabled
    }

    /**
     * 権限が設定画面で後から許可された場合や、送信先設定・検索条件が他画面で変更された場合に
     * 反映させるため、表示に戻るたびに毎回作り直す
     */
    override fun onResume() {
        super.onResume()
        updatePermissionUi()
        refreshSendTargetFilterOptions()
        searchSms(showFoundToast = false)
    }

    /**
     * 送信先設定は他画面で変更され得るため、スピナーの選択肢を毎回作り直す。作り直した後も
     * 直前まで選ばれていたIDが選択肢に残っていればその位置を復元する
     */
    private fun refreshSendTargetFilterOptions() {
        // 送信先が1件しかない場合は「すべて」を選んでも絞り込み結果は変わらないため、
        // 項目名とリストボックスごと隠して値は「すべて」に固定する
        if (SettingsStore.loadSendTargets(this).size == 1) {
            binding.tvSendTargetFilterLabel.visibility = View.GONE
            binding.llSendTargetFilter.visibility = View.GONE
            selectedSendTargetId = null
            return
        }
        binding.tvSendTargetFilterLabel.visibility = View.VISIBLE
        binding.llSendTargetFilter.visibility = View.VISIBLE

        val options = SettingsStore.sendTargetFilterOptions(this)
        sendTargetFilterKeys = options.map { it.first }
        val labels = options.map { it.second }

        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, labels)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spSendTargetFilter.adapter = adapter

        val restoreIndex = sendTargetFilterKeys.indexOf(selectedSendTargetId)
        binding.spSendTargetFilter.setSelection(if (restoreIndex >= 0) restoreIndex else 0)
    }

    /** 受信箱をqueryできるのはREAD_SMSが許可されている場合のみ */
    private fun hasReadSmsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    /** 未許可の間は検索フォームの代わりに権限依頼レイアウトを表示する */
    private fun updatePermissionUi() {
        val granted = hasReadSmsPermission()
        binding.layoutPermissionRequired.visibility = if (granted) View.GONE else View.VISIBLE
        binding.layoutSearchForm.visibility = if (granted) View.VISIBLE else View.GONE
    }

    /** 閉じることで一覧の表示領域を広げられるようにする */
    private fun toggleSearchFilters() {
        val show = binding.llSearchFilters.visibility != View.VISIBLE
        binding.llSearchFilters.visibility = if (show) View.VISIBLE else View.GONE
        binding.btnToggleSearchFilters.text = getString(
            if (show) R.string.btn_hide_search_filters else R.string.btn_show_search_filters
        )
    }

    /** 開くたびに現在の選択日（無ければ今日）から初期表示するため、既存の選択値をカレンダーに反映してから開く */
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

    /** 選んだ日の00:00:00.000〜23:59:59.999に丸めることで、時刻を問わずその日一日分をDATE列の範囲条件として使えるようにする */
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

    /**
     * 絞り込みは (1) DBクエリでの日付・本文、(2) 送信状況（未送信/自動送信済/手動送信済）、
     * (3) 送信先、(4) 分割失敗、の順に段階的にrecordsを絞っていく。(3)(4)はAI呼び出しを伴い得るため
     * コルーチン内で行うが、(2)は同期処理のみなのでコルーチンに入る前に済ませている
     */
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

        if (binding.cbSendNoneOnly.isChecked || binding.cbSentAutoOnly.isChecked || binding.cbSentManualOnly.isChecked) {
            val sentEntries = matchSentEntries(records, loadCompletedEntries())
            records.removeAll { record ->
                val sentEntry = sentEntries[record.id]
                val matchesFilter = when {
                    sentEntry == null -> binding.cbSendNoneOnly.isChecked
                    sentEntry.manual -> binding.cbSentManualOnly.isChecked
                    else -> binding.cbSentAutoOnly.isChecked
                }
                !matchesFilter
            }
        }

        // AI解析（端末上のAI呼び出し）を伴う場合があるため、ここから先はコルーチンでUIをブロックしない
        lifecycleScope.launch {
            val config = SettingsStore.load(this@SmsSearchActivity)
            resolvedPartsCache = mutableMapOf()

            when (val sendTargetId = selectedSendTargetId) {
                null -> Unit
                AppConstants.SEND_TARGET_FILTER_KEY_UNSET -> {
                    val matched = mutableListOf<SmsRecord>()
                    for (record in records) {
                        val (_, sendTargets) = resolveSendTargetCached(record, config)
                        if (sendTargets.isEmpty()) matched.add(record)
                    }
                    records.clear()
                    records.addAll(matched)
                }
                else -> {
                    val matched = mutableListOf<SmsRecord>()
                    for (record in records) {
                        val (_, sendTargets) = resolveSendTargetCached(record, config)
                        if (sendTargets.any { it.id == sendTargetId }) matched.add(record)
                    }
                    records.clear()
                    records.addAll(matched)
                }
            }

            if (binding.cbSplitFailedOnly.isChecked || binding.cbSplitSucceededOnly.isChecked || binding.cbSplitExcludedOnly.isChecked) {
                val matchedSplitStatusRecords = mutableListOf<SmsRecord>()
                for (record in records) {
                    val (resolution, _) = resolveSendTargetCached(record, config)
                    val matchesFilter = when {
                        resolution.isContinuation -> binding.cbSplitExcludedOnly.isChecked
                        resolution.smsParts.isSplitFailed() -> binding.cbSplitFailedOnly.isChecked
                        else -> binding.cbSplitSucceededOnly.isChecked
                    }
                    if (matchesFilter) matchedSplitStatusRecords.add(record)
                }
                records.clear()
                records.addAll(matchedSplitStatusRecords)
            }

            if (showFoundToast) {
                Toast.makeText(this@SmsSearchActivity, getString(R.string.toast_sms_search_found, records.size), Toast.LENGTH_SHORT).show()
            }
            renderSmsList()
        }
    }

    /** [resolvedPartsCache]を経由してSettingsStore.resolveSendTargetsを呼ぶ。同一recordへの重複呼び出し（AI解析）を避ける */
    private suspend fun resolveSendTargetCached(record: SmsRecord, config: SettingsStore.Config): Pair<SettingsStore.SmsResolution, List<SettingsStore.SendTarget>> =
        resolvedPartsCache.getOrPut(record.id) {
            SettingsStore.resolveSendTargets(this, record.address, record.body, record.dateMillis, config.aiParsingEnabled, config.continuationEnabled, config.continuationScope)
        }

    /** 成功したKintone送信ログのみを対象にする（失敗ログは「未送信」として扱われるべきなので除外） */
    private fun loadCompletedEntries(): List<SmsLogStore.Entry> =
        SmsLogStore.getAll(this)
            .filter { it.type == SmsLogStore.EntryType.SEND_COMPLETE && it.success }

    /** 成功した自動返信ログのみを対象にする */
    private fun loadAutoReplyEntries(): List<SmsLogStore.Entry> =
        SmsLogStore.getAll(this)
            .filter { it.type == SmsLogStore.EntryType.AUTO_REPLY && it.success }

    /** ログとSMSレコードの1対1対応付け（アルゴリズム本体はSmsMatching.matchEntries参照） */
    private fun matchSentEntries(
        records: List<SmsRecord>,
        completedEntries: List<SmsLogStore.Entry>
    ): Map<Long, SmsLogStore.Entry> {
        val toleranceMillis = SettingsStore.load(this).smsMatchToleranceSeconds * 1_000L
        return SmsMatching.matchEntries(
            records = records,
            completedEntries = completedEntries,
            toleranceMillis = toleranceMillis,
            id = { it.id },
            sender = { it.address },
            timestampMillis = { it.dateMillis }
        )
    }

    /**
     * SMSアプリの返信画面を開く。分割失敗のメッセージには通常の定型文ではなく
     * splitFailedReplyAddition（分割失敗時専用の文面）を差し込む
     */
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

    /**
     * RecyclerViewは使わず、record1件ごとにチェックボックス+テキストの行をLinearLayoutへ直接addViewしていく。
     * 件数が多くないため簡易実装で足りる
     */
    private suspend fun renderSmsList() {
        binding.llSmsListContainer.removeAllViews()
        binding.svSmsList.scrollTo(0, 0)
        binding.tvSmsListEmpty.visibility = if (records.isEmpty()) View.VISIBLE else View.GONE

        val sentEntries = matchSentEntries(records, loadCompletedEntries())
        val autoRepliedEntries = matchSentEntries(records, loadAutoReplyEntries())
        val config = SettingsStore.load(this)
        val dateFormat = DateFormats.display()
        records.forEach { record ->
            val (resolution, sendTargets) = resolveSendTargetCached(record, config)
            val sendTargetName = sendTargets.takeIf { it.isNotEmpty() }?.joinToString("、") { it.displayName(this@SmsSearchActivity) }
                ?: resolution.inheritedSendTargetName
                ?: getString(R.string.label_send_target_none)
            val isSendTargetUnconfigured = sendTargets.none { it.isValid }
            val isAutoReplied = record.id in autoRepliedEntries
            val sentEntry = sentEntries[record.id]
            val isSplitFailedBody = resolution.smsParts.isSplitFailed()
            val isSelectable = (!isSendTargetUnconfigured || config.searchSendTargetUnconfiguredEnabled) &&
                (!isSplitFailedBody || config.searchSplitFailedEnabled) &&
                (!resolution.isContinuation || config.searchSplitExcludedEnabled)
            val sendTargetColor = ContextCompat.getColor(this@SmsSearchActivity, R.color.send_target_name)
            val sendTargetIcon = getString(
                when {
                    resolution.isContinuation -> R.string.icon_send_target_inherited
                    isSendTargetUnconfigured -> R.string.icon_send_target_unconfigured
                    else -> R.string.icon_send_target_exists
                }
            )

            val checkBox = CheckBox(this).apply {
                tag = record.id
                isEnabled = isSelectable
                isClickable = false
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                )
            }

            val textView = TextView(this).apply {
                text = buildSpannedString {
                    val splitIcon = when {
                        resolution.isContinuation -> R.string.icon_split_excluded
                        isSplitFailedBody -> R.string.icon_split_failed
                        else -> R.string.icon_split_succeeded
                    }
                    append(getString(splitIcon))
                    append(" ")
                    if (sentEntry == null) {
                        append(getString(R.string.icon_send_none))
                    } else {
                        append(
                            getString(
                                if (sentEntry.manual) R.string.icon_send_manual else R.string.icon_send_auto
                            )
                        )
                    }
                    if (isAutoReplied) {
                        append(" ")
                        append(getString(R.string.icon_replied))
                    }
                    append("\n")
                    if (isSelectable) {
                        color(sendTargetColor) { bold { append(sendTargetIcon); append(" "); append(sendTargetName) } }
                    } else {
                        bold { append(sendTargetIcon); append(" "); append(sendTargetName) }
                    }
                    val senderDisplay = if (resolution.isContinuation && config.continuationShowUserNameEnabled && resolution.smsParts.userName.isNotBlank()) {
                        resolution.smsParts.userName
                    } else {
                        record.address
                    }
                    append("\n\n${dateFormat.format(Date(record.dateMillis))}　$senderDisplay\n")
                    append(record.body.take(80))
                }
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    0,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f
                )
            }

            val row = android.widget.LinearLayout(this).apply {
                orientation = android.widget.LinearLayout.HORIZONTAL
                gravity = android.view.Gravity.CENTER_VERTICAL
                layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
                )
                setPadding(0, 16, 0, 16)
                addView(checkBox)
                addView(textView)
                val backgroundColor = when {
                    sentEntry != null && sentEntry.manual -> R.color.sms_sent_manual_background
                    sentEntry != null -> R.color.sms_sent_auto_background
                    else -> null
                }
                backgroundColor?.let {
                    setBackgroundColor(ContextCompat.getColor(this@SmsSearchActivity, it))
                }
                setOnClickListener {
                    if (isSelectable) {
                        checkBox.isChecked = !checkBox.isChecked
                    }
                }
                setOnLongClickListener {
                    openSmsReply(record.address, isSplitFailedBody)
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

            binding.llSmsListContainer.addView(row)
            binding.llSmsListContainer.addView(divider)
        }
    }

    /** 送信先未設定/分割失敗などで選択不可(isEnabled=false)にしてある行は対象から除く */
    private fun setAllChecked(checked: Boolean) {
        for (i in 0 until binding.llSmsListContainer.childCount) {
            val row = binding.llSmsListContainer.getChildAt(i) as? android.widget.LinearLayout ?: continue
            val checkBox = row.getChildAt(0) as? CheckBox ?: continue
            if (checkBox.isEnabled) checkBox.isChecked = checked
        }
    }

    /** チェック済みの行を受信日時の古い順にKintoneUploadWorkerへ手動送信キューとして投入する */
    private fun sendSelected() {
        val checkedIds = mutableSetOf<Long>()
        for (i in 0 until binding.llSmsListContainer.childCount) {
            val row = binding.llSmsListContainer.getChildAt(i) as? android.widget.LinearLayout ?: continue
            val checkBox = row.getChildAt(0) as? CheckBox ?: continue
            if (checkBox.isChecked) checkedIds.add(checkBox.tag as Long)
        }

        // 一覧の表示順（新しい順）とは関係なく、送信自体は受信日時の古い順に行う
        val selectedRecords = records.filter { it.id in checkedIds }.sortedBy { it.dateMillis }
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

    /** [selectedIds]の一括送信が完了した際に、結果をトーストで通知する */
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

    /** Telephony.Sms.CONTENT_URIから読み取った受信SMS1件分（_ID/ADDRESS/BODY/DATE） */
    private data class SmsRecord(
        val id: Long,
        val address: String,
        val body: String,
        val dateMillis: Long
    )

    /** [TOAST_LONG_DURATION_MILLIS]を保持するコンパニオンオブジェクト */
    companion object {
        /** Toast.LENGTH_LONGの実際の表示時間はAPIで取得できないため、体感の表示時間に合わせて固定値で待つ */
        private const val TOAST_LONG_DURATION_MILLIS = 3_500L
    }
}

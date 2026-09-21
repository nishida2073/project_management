package com.ssfrontier.smstokintone

import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.ssfrontier.smstokintone.databinding.ActivitySettingsImportExportBinding
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 外部のJSONファイルからアプリの設定（[SettingsStore.Config]）、送信先の設定
 * （[SettingsStore.SendTarget]）、引き継ぎ内容（[ContinuationStore.Entry]）をまとめて反映し、
 * 現在の設定を同じ形式のJSONファイルへまとめて書き出す画面。
 * インポートはファイルを選択して内容をプレビューで確認し、「この内容で設定する」で反映する。
 * ファイルに含まれるセクションだけが反映され、含まれないセクションは変更されない。
 * アプリ設定（[SettingsStore.Config]）、送信先（[SettingsStore.SendTarget]）、引き継ぎ内容（[ContinuationStore.Entry]）は
 * すべてマージされ、ファイルに含まれない属性・エントリは既存値が保持される。
 * エクスポートはインポートと互換のJSON（[buildExportJson]）を保存先に書き出す
 */
class SettingsImportExportActivity : AppCompatActivity() {

    /**
     * この画面のViewBinding。
     */
    private lateinit var binding: ActivitySettingsImportExportBinding

    /**
     * 選択中のインポートファイルの表示名。
     */
    private var selectedFileName: String? = null

    /**
     * ファイルから読み込んだインポート JSON。
     */
    private var importedJson: JSONObject? = null

    /**
     * 表示中のダイアログリスト。cleanup()で一括削除。
     */
    private val dialogs = mutableListOf<AlertDialog>()

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                cleanup()
            }
        })
    }

    /**
     * ファイル選択ダイアログの結果ハンドラ。選択されたURIのファイル内容を読み込んでプレビューへ反映する。
     */
    private val openDocumentLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) loadImportFile(uri)
        }

    /**
     * エクスポート先の保存ダイアログの結果ハンドラ。選択された保存先へJSONファイルを書き出す。
     */
    private val createDocumentLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
            if (uri != null) writeExportFile(uri)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsImportExportBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnSelectImportFile.setOnClickListener {
            openDocumentLauncher.launch(arrayOf("*/*"))
        }
        binding.btnImportSettings.isEnabled = false
        binding.btnImportSettings.setButtonStyleByEnabled(false)
        binding.btnImportSettings.setOnClickListener { onImportClicked() }
        binding.btnExportSettings.setOnClickListener {
            createDocumentLauncher.launch(suggestedExportFileName())
        }
    }

    /** エクスポート先のファイル名を生成（s2k_settings_時刻.json） */
    private fun suggestedExportFileName(): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return "s2k_settings_$timestamp.json"
    }

    /** 現在の設定をエクスポート用JSONにまとめる */
    private fun buildExportJson(): JSONObject {
        val sendTargets = JSONArray().apply {
            SettingsStore.loadSendTargets(this@SettingsImportExportActivity).forEach { sendTarget ->
                put(SettingsStore.sendTargetToJson(sendTarget))
            }
        }
        val continuationInfo = JSONArray().apply {
            ContinuationStore.getAll(this@SettingsImportExportActivity).forEach { (_, entry) ->
                put(
                    JSONObject()
                        .put("senderAddress", entry.senderAddress)
                        .put("companyName", entry.companyName)
                        .put("userName", entry.userName)
                        .put("timestampMillis", entry.timestampMillis)
                )
            }
        }
        return JSONObject()
            .put("appConfig", SettingsStore.configToJson(SettingsStore.load(this)))
            .put("sendTargetConfig", sendTargets)
            .put("continuationInfoConfig", continuationInfo)
    }

    /** [uri]の保存先へエクスポートJSONを書き出し、成功トーストまたは失敗ダイアログを表示する */
    private fun writeExportFile(uri: Uri) {
        val json = buildExportJson().toString(2)
        val written = try {
            contentResolver.openOutputStream(uri)?.use { out ->
                out.write(json.toByteArray(Charsets.UTF_8))
            } != null
        } catch (e: Exception) {
            false
        }
        if (written) {
            Toast.makeText(this, getString(R.string.toast_settings_exported), Toast.LENGTH_SHORT).show()
        } else {
            AlertDialog.Builder(this)
                .setTitle(R.string.dialog_title_export_error)
                .setMessage(R.string.dialog_message_export_failed)
                .setPositiveButton(android.R.string.ok, null)
                .show().addWithTracking()
        }
    }

    // ---- ファイルの選択と読み込み（インポート） ----

    /** [uri]のファイルを読み込み、JSONとして解析してプレビューを更新する */
    private fun loadImportFile(uri: Uri) {
        selectedFileName = queryDisplayName(uri)
        val text = try {
            contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        } catch (e: Exception) {
            null
        }
        if (text.isNullOrBlank()) {
            showError(getString(R.string.dialog_message_import_file_read_failed))
            return
        }
        try {
            parseImportFile(text)
        } catch (e: JSONException) {
            showError(getString(R.string.dialog_message_import_invalid_json, e.message.orEmpty()))
        }
    }

    /** ファイルの表示名を取得する。取得できない場合はURIのパス末尾を返す */
    private fun queryDisplayName(uri: Uri): String? =
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        } ?: uri.lastPathSegment

    /** インポートファイル（JSON）を検証して保持し、プレビューを更新する */
    private fun parseImportFile(text: String) {
        val root = JSONObject(text)
        root.optJSONArray("sendTargetConfig")?.let { checkSendTargetDuplicates(it) }
        root.optJSONArray("continuationInfoConfig")?.let {
            SettingsStore.parseContinuationInfoFromJson(it, ContinuationStore.getAll(this))
        }

        if (!hasAnySection(root)) {
            showError(getString(R.string.message_import_no_section))
            return
        }
        importedJson = root
        updatePreview()
    }

    /** JSON に1つ以上のセクションが含まれているか */
    private fun hasAnySection(json: JSONObject): Boolean =
        (json.optJSONObject("appConfig")?.length() ?: 0) > 0 ||
        (json.optJSONArray("sendTargetConfig")?.length() ?: 0) > 0 ||
        (json.optJSONArray("continuationInfoConfig")?.length() ?: 0) > 0

    /** 送信先の重複をチェック */
    private fun checkSendTargetDuplicates(array: JSONArray) {
        val duplicateNames = mutableSetOf<String>()
        val seenNames = mutableSetOf<String>()
        for (i in 0 until array.length()) {
            val name = array.getJSONObject(i).optString("name", "")
            if (!seenNames.add(name)) duplicateNames.add(name)
        }
        if (duplicateNames.isNotEmpty()) {
            throw JSONException(
                getString(R.string.message_import_send_target_duplicate_name, duplicateNames.sorted().joinToString("／"))
            )
        }
    }


    // ---- プレビュー表示と反映（インポート） ----

    /** 解析結果をプレビュー表示へ反映し、インポートボタンを有効化する */
    private fun updatePreview() {
        binding.tvImportPreview.text = buildPreviewText(includeFileName = true)
        binding.btnImportSettings.isEnabled = true
        binding.btnImportSettings.setButtonStyleByEnabled(true)
    }

    /** プレビュー表示と確認ダイアログで使う反映内容の一覧を組み立てる */
    private fun buildPreviewText(includeFileName: Boolean): String {
        val json = importedJson ?: return ""
        val lines = mutableListOf<String>()
        if (includeFileName) {
            selectedFileName?.let { lines += getString(R.string.label_import_file, it) }
        }
        lines += getString(R.string.preview_app_settings, getStateLabel(json.optJSONObject("appConfig")?.length() ?: 0 > 0))
        lines += getString(R.string.preview_send_targets, getCountLabel(json.optJSONArray("sendTargetConfig")?.length()))
        lines += getString(R.string.preview_continuation_info, getCountLabel(json.optJSONArray("continuationInfoConfig")?.length()))
        return lines.joinToString("\n")
    }

    /** セクションの状態文言を返す */
    private fun getStateLabel(included: Boolean): String =
        if (included) getString(R.string.value_import_applied) else getString(R.string.value_import_skip)

    /** セクションの件数文言を返す */
    private fun getCountLabel(count: Int?): String =
        if (count == null || count == 0) getString(R.string.value_import_skip)
        else getString(R.string.value_import_applied_count, count)

    /** 「この内容で設定する」ボタン。反映内容の確認ダイアログを表示し、確定時に適用する */
    private fun onImportClicked() {
        val json = importedJson ?: return
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_confirm_import)
            .setMessage(getString(R.string.dialog_message_confirm_import, buildPreviewText(includeFileName = true)))
            .setNegativeButton(R.string.btn_cancel, null)
            .setPositiveButton(R.string.btn_import_settings) { _, _ -> applyImport(json) }
            .show().addWithTracking()
    }

    /** JSON から設定をマージして反映し、完了トーストを表示して画面を閉じる */
    private fun applyImport(json: JSONObject) {
        SettingsStore.mergeFromJson(this, json)
        Toast.makeText(this, getString(R.string.toast_settings_imported), Toast.LENGTH_SHORT).show()
        json.optJSONObject("appConfig")?.takeIf { it.length() > 0 }?.let {
            val config = SettingsStore.configFromJson(it, SettingsStore.load(this))
            AppCompatDelegate.setDefaultNightMode(config.themeMode.toNightMode())
        }
        finish()
    }

    /** エラーダイアログを表示し、プレビューを未選択状態へ戻す */
    private fun showError(message: String) {
        importedJson = null
        binding.tvImportPreview.text = getString(R.string.message_import_no_file)
        binding.btnImportSettings.isEnabled = false
        binding.btnImportSettings.setButtonStyleByEnabled(false)
        AlertDialog.Builder(this)
            .setTitle(R.string.dialog_title_import_error)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
            .show().addWithTracking()
    }

    private fun AlertDialog.addWithTracking(): AlertDialog {
        dialogs.add(this)
        return this
    }

    private fun cleanup() {
        dialogs.forEach { it.dismiss() }
        dialogs.clear()
    }
}
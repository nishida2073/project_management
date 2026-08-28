package com.ssfrontier.smstokintone

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.ssfrontier.smstokintone.databinding.ActivityTopBinding

/**
 * アプリのホーム画面。送信/自動返信が自動・手動どちらのモードかを表示し、各種設定・ログ・
 * SMS検索画面への導線を提供する。他画面での設定変更を反映するためonResumeごとに表示を更新する。
 */
class TopActivity : AppCompatActivity() {

    /** この画面のViewBinding */
    private lateinit var binding: ActivityTopBinding

    /** 各設定・ログ・SMS検索画面への遷移ボタンを配線する */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTopBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.btnOpenSendTargetSettings.setOnClickListener {
            startActivity(Intent(this, SendTargetSettingsActivity::class.java))
        }
        binding.btnOpenAppSettings.setOnClickListener {
            startActivity(Intent(this, AppSettingsActivity::class.java))
        }
        binding.btnOpenLog.setOnClickListener {
            startActivity(Intent(this, LogActivity::class.java))
        }
        binding.btnOpenSmsSearch.setOnClickListener {
            startActivity(Intent(this, SmsSearchActivity::class.java))
        }
    }

    /** 他画面での設定変更を反映するため、表示に戻るたびにステータス表示を再読込する */
    override fun onResume() {
        super.onResume()
        // 設定画面から戻ってきた場合など、他画面での変更を毎回反映するために再読込する
        updateModeStatus()
    }

    /** SettingsStoreの現在値を送信/返信ステータス表示（文言・色）へ反映する */
    private fun updateModeStatus() {
        val config = SettingsStore.load(this)

        binding.tvTopSendStatus.text = getString(
            if (config.sendEnabled) R.string.label_top_sms_send_auto else R.string.label_top_sms_send_manual
        )
        binding.tvTopSendStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (config.sendEnabled) R.color.status_running else R.color.status_manual
            )
        )

        // autoReplySplitFailedEnabled: 項目分割に失敗したSMSにのみ自動返信する設定
        binding.tvTopReplyStatus.text = getString(
            if (config.autoReplySplitFailedEnabled) R.string.label_top_sms_reply_auto else R.string.label_top_sms_reply_manual
        )
        binding.tvTopReplyStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (config.autoReplySplitFailedEnabled) R.color.status_running else R.color.status_manual
            )
        )
    }
}

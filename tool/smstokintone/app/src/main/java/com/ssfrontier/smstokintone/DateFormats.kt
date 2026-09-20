package com.ssfrontier.smstokintone

import java.text.SimpleDateFormat
import java.util.Locale

/**
 * アプリ全体で共有する日時表示フォーマット。
 * kintone本文への書き込み（[KintoneApi]）とログ画面（[LogActivity]、[SmsSearchActivity]）の表示の両方で使われ、
 * 書式がずれると[KintoneApi.mergeBody]の日時再パース・並び順判定が壊れるため、必ずここを共有すること。
 */
object DateFormats {

    /**
     * 人が読める日時表示形式を返す。例：2026/08/28 12:34:56
     * 日本語ロケールを固定で使用することで、表示フォーマットの一貫性を保つ。
     *
     * @return 日本語フォーマットの[SimpleDateFormat]
     */
    fun display(): SimpleDateFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN)
}

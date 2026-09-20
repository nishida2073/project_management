package com.ssfrontier.smstokintone

import java.text.Normalizer

/**
 * 文字列の表記ゆれ吸収に使うNFKC正規化をまとめたユーティリティ。
 * 送信先マッチング・会社名変換で一貫性を保つため、ここを共有すること。
 */
object TextNormalization {

    /**
     * 文字列をNFKC正規化する。全角英数字を半角に、半角カナを全角カナに揃える。
     *
     * @param text 正規化対象の文字列
     * @return NFKC正規化済みの文字列
     */
    fun toNfkc(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFKC)

    /**
     * [text]が[keyword]を含むかを、半角/全角の表記ゆれ（英数字・カタカナ等）を無視して判定する。
     *
     * @param text 判定対象のテキスト
     * @param keyword 検索キーワード
     * @return 含む場合true
     */
    fun matches(text: String, keyword: String): Boolean =
        toNfkc(text).contains(toNfkc(keyword), ignoreCase = true)

    /**
     * 文字列を統一形式に正規化する。英字は半角大文字、数字は半角、それ以外（かな・記号・空白など）は全角に統一。
     * 会社名の統一変換に使用する（[SettingsStore.Config.companyNameAutoConversionEnabled]）。
     *
     * @param text 正規化対象の文字列
     * @return 統一形式に正規化済みの文字列
     */
    fun normalizeWidth(text: String): String {
        val nfkc = toNfkc(text)
        val builder = StringBuilder(nfkc.length)
        for (ch in nfkc) {
            when {
                ch in 'A'..'Z' || ch in '0'..'9' -> builder.append(ch)
                ch in 'a'..'z' -> builder.append(ch.uppercaseChar())
                ch == ' ' -> builder.append('　')
                ch.code in 0x21..0x7E -> builder.append((ch.code + 0xFEE0).toChar())
                else -> builder.append(ch)
            }
        }
        return builder.toString()
    }
}

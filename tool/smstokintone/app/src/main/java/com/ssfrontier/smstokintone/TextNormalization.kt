package com.ssfrontier.smstokintone

import java.text.Normalizer

/** 文字列の表記ゆれ吸収に使うNFKC正規化を1箇所にまとめたもの */
object TextNormalization {

    /** 全角英数字を半角に、半角カナを全角カナに揃える（NFKC正規化） */
    fun toNfkc(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFKC)

    /** [text]が[keyword]を含むかを、半角/全角の表記ゆれ（英数字・カタカナ等）を無視して判定する */
    fun matches(text: String, keyword: String): Boolean =
        toNfkc(text).contains(toNfkc(keyword), ignoreCase = true)

    /** 英字は半角大文字、数字は半角、それ以外（かな・記号・空白など）は全角に統一する */
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

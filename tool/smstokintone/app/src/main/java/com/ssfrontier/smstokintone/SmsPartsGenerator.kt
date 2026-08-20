package com.ssfrontier.smstokintone

/**
 * SMS本文から生成した部品（会社名・氏名・内容）
 */
data class SmsParts(
    val companyName: String = "",
    val userName: String = "",
    val content: String = ""
) {
    /** 何も抽出できなかったかどうか */
    fun isEmpty(): Boolean = companyName.isEmpty() && userName.isEmpty() && content.isEmpty()

    /** 会社名・氏名・内容のいずれかが空で、分割に失敗したとみなせるかどうか */
    fun isSplitFailed(): Boolean = !(companyName.isNotBlank() && userName.isNotBlank() && content.isNotBlank())
}

/**
 * SMS本文から部品（会社名・氏名・内容）を生成する（ラベルの表記ゆれ・記述順の違い・ラベル省略に対応）
 *
 * 「会社名：」「会社：」など、ラベルの表記ゆれがあっても、
 * また項目の記述順が入れ替わっていても、正しく項目を認識できるようにしています。
 * 内容のラベル（「内容：」）は省略可能で、氏名・会社名より後に続く自由記述はラベルが
 * 無くても内容として取り込みます。
 *
 * 対応例1（ラベルあり、内容ラベルは省略可）:
 * 会社名：XXX
 * 氏名：YYY
 * 内容：
 * XXX（複数行OK）
 *
 * 対応例2（ラベルなし、1行目:会社名 2行目:氏名 3行目以降:内容）:
 * XXX
 * YYY
 * XXX（複数行OK）
 */
object SmsPartsGenerator {

    /**
     * 会社名の表記ゆれを吸収し、「[AppConstants.SMS_COMPANY_NAME_CANONICAL_PREFIX]<地域名>」の形に強制する。
     *
     * 「NTTD四国」「NTTDATA四国」「四国」など、先頭のNTT表記の有無・書き方に関わらず、
     * 地域名部分（四国など）を残して正式な接頭辞を付け直す。既に正式な接頭辞で始まる場合はそのまま。
     * ※現在は呼び出し元（[generateSmsParts]内）がコメントアウトされており未使用。会社名は正規化されずそのまま返る。
     */
    private fun normalizeCompanyName(companyName: String): String {
        if (companyName.isEmpty() || companyName.startsWith(AppConstants.SMS_COMPANY_NAME_CANONICAL_PREFIX)) return companyName
        val rest = AppConstants.SMS_COMPANY_NAME_PREFIX_PATTERN.replaceFirst(companyName, "").trim()
        return "${AppConstants.SMS_COMPANY_NAME_CANONICAL_PREFIX}$rest"
    }

    private data class LabelMatch(val key: String, val value: String)

    /**
     * 1行が「ラベル：値」の形式かどうかを判定し、
     * マッチした場合は LabelMatch を返す。マッチしなければ null。
     */
    private fun matchLabelLine(line: String): LabelMatch? {
        for ((key, aliases) in AppConstants.SMS_BODY_FIELD_ALIASES) {
            for (alias in aliases) {
                // ラベルのみでコロンが無い行（値は次行以降に続く）にも対応
                if (line == alias) {
                    return LabelMatch(key, "")
                }
                // ラベルと値の区切りに対応。
                // ・記号区切り: ：: ＝= －-—― （前後の空白は全角含め許容）
                // ・記号が無く空白のみで区切られている場合（例:「会社名　XXX」）にも対応
                val pattern = Regex(
                    "^[\\s　]*${Regex.escape(alias)}(?:[\\s　]*[：:＝=－\\-—―][\\s　]*|[\\s　]+)(.*)$"
                )
                val match = pattern.find(line)
                if (match != null) {
                    return LabelMatch(key, match.groupValues[1].trim())
                }
            }
        }
        return null
    }

    /**
     * SMS本文から部品を生成する
     */
    fun generateSmsParts(body: String?): SmsParts {
        if (body.isNullOrBlank()) return SmsParts()

        val normalized = body.replace("\r\n", "\n").replace("\r", "\n").trim()
        val contentLines = normalized.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        // 行数が3行未満（会社名・氏名・内容をそれぞれ1行で書く想定に対して行数が足りない）
        // 場合は、氏名・会社名を1行でまとめて書く人がいるため抽出せず空のまま返す。
        // SMS本文自体は別途Bodyフィールドにそのまま登録されるため、ここで内容に詰め直す必要はない
        if (contentLines.size < 3) {
            return SmsParts()
        }

        var companyName = ""
        var userName = ""
        var content = ""
        // 内容は複数行の値を続けて追記できるようにする
        var currentKey: String? = null

        for (line in contentLines) {
            // ラベル行なら記述順に関係なく値だけを取り出す
            val labelMatch = matchLabelLine(line)
            if (labelMatch != null) {
                when (labelMatch.key) {
                    "companyName" -> companyName = labelMatch.value
                    "userName" -> userName = labelMatch.value
                    "content" -> content = labelMatch.value
                }
                currentKey = if (labelMatch.key == "content") "content" else null
                continue
            }

            when {
                // 内容の続き（複数行対応）
                currentKey == "content" -> content = if (content.isEmpty()) line else "$content\n$line"
                // ラベルが省略されている場合は行の位置で判定する（1つ目の未確定項目に会社名、2つ目に氏名を割り当てる）
                companyName.isEmpty() -> companyName = line
                userName.isEmpty() -> userName = line
                // 氏名・会社名が確定済みなら、以降はラベルが無くても内容として取り込む
                else -> {
                    content = line
                    currentKey = "content"
                }
            }
        }

        // 内容の先頭行が空行の場合は除去する
        val contentValueLines = content.split("\n")
        if (contentValueLines.first().isBlank()) {
            content = contentValueLines.drop(1).joinToString("\n")
        }

        // return SmsParts(companyName = normalizeCompanyName(companyName), userName = userName, content = content)
        return SmsParts(companyName = companyName, userName = userName, content = content)
    }
}

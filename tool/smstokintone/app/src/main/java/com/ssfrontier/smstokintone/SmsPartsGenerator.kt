package com.ssfrontier.smstokintone

import android.os.Build
import android.util.Log
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.generationConfig
import kotlinx.coroutines.flow.collect
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * SMS本文から生成した部品（会社名・氏名・内容）
 */
data class SmsParts(
    val companyName: String = "",
    val userName: String = "",
    val content: String = "",
    /** 端末上のAI（ML Kit GenAI）で抽出した結果かどうか。falseはルールベースでの抽出 */
    val parsedByAi: Boolean = false
) {
    /** 何も抽出できなかったかどうか */
    fun isEmpty(): Boolean = companyName.isEmpty() && userName.isEmpty() && content.isEmpty()

    /** 会社名・氏名・内容のいずれかが空で、分割に失敗したとみなせるかどうか */
    fun isSplitFailed(): Boolean = !(companyName.isNotBlank() && userName.isNotBlank() && content.isNotBlank())

    /**
     * [companyName]の英字（A-Z, a-z）・数字（0-9）を半角大文字に、それ以外の文字を全角に統一した文字列。
     * [companyName]が空白の場合は空文字を返す
     */
    val companyNameNormalizedWidth: String
        get() = if (companyName.isNotBlank()) TextNormalization.normalizeWidth(companyName) else ""
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

    private const val TAG = "SmsPartsGenerator"

    /** 本文をキーにしたAI解析結果のキャッシュ。同じ本文を何度も解析させない。
     * 受信・送信・検索など複数のスレッドから同時に呼ばれ得るためスレッドセーフなMapを使う */
    private val aiResultCache = ConcurrentHashMap<String, SmsParts>()

    @Volatile
    private var generativeModel: GenerativeModel? = null

    @Synchronized
    private fun getOrCreateModel(): GenerativeModel =
        generativeModel ?: Generation.getClient(generationConfig {}).also { generativeModel = it }

    /**
     * SMS本文から会社名・氏名・内容を解析する。[aiParsingEnabled]（アプリの設定「AIによる分割」）が
     * 有効な場合は端末上のAI（ML Kit GenAI / Gemini Nano）に解析させ、Android 12未満の端末、
     * AI解析が無効、非対応端末、またはAI呼び出しに失敗した場合は[generateSmsParts]（ルールベース）の
     * 結果を返す。同じ本文への問い合わせは[aiResultCache]から即座に返し、AIへの重複した問い合わせを避ける。
     */
    suspend fun resolveSmsParts(body: String, aiParsingEnabled: Boolean): SmsParts {
        if (!aiParsingEnabled || body.isBlank() || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return generateSmsParts(body)
        }

        aiResultCache[body]?.let { return it }

        val aiResult = requestAiSmsParts(body)
        val result = aiResult ?: generateSmsParts(body)
        aiResultCache[body] = result
        return result
    }

    /** 端末上のAI（ML Kit GenAI）へSMS本文を渡し、会社名・氏名・内容をJSONで抽出させる。失敗した場合はnullを返す */
    private suspend fun requestAiSmsParts(body: String): SmsParts? {
        return try {
            val model = getOrCreateModel()
            when (model.checkStatus()) {
                FeatureStatus.AVAILABLE -> {}
                FeatureStatus.DOWNLOADABLE -> {
                    var downloaded = false
                    model.download().collect { status ->
                        if (status is DownloadStatus.DownloadCompleted) downloaded = true
                        if (status is DownloadStatus.DownloadFailed) {
                            Log.w(TAG, "AIモデルのダウンロードに失敗しました: ${status.e.message}")
                        }
                    }
                    if (!downloaded) return null
                }
                else -> return null
            }

            val prompt = """
                以下のSMS本文から「会社名」「氏名」「内容」を抽出してください。
                該当する項目が本文に無い場合は空文字を返してください。
                出力は次の形式のJSONのみとし、それ以外の文章は含めないでください。
                {"companyName": "...", "userName": "...", "content": "..."}

                SMS本文:
                $body
            """.trimIndent()

            val response = model.generateContent(prompt)
            val text = response.candidates.firstOrNull()?.text?.trim() ?: return null
            val jsonText = text.substringAfter("{").substringBeforeLast("}").let { "{$it}" }
            val parsed = JSONObject(jsonText)
            SmsParts(
                companyName = parsed.optString("companyName", ""),
                userName = parsed.optString("userName", ""),
                content = parsed.optString("content", ""),
                parsedByAi = true
            )
        } catch (e: Exception) {
            Log.w(TAG, "ML Kit GenAIの呼び出しに失敗しました: ${e.message}")
            null
        }
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

        return SmsParts(companyName = companyName, userName = userName, content = content)
    }
}

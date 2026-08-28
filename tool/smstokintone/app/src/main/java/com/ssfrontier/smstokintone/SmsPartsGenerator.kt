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

data class SmsParts(
    val companyName: String = "",
    val userName: String = "",
    val content: String = "",
    /** 端末上のAI（ML Kit GenAI）で抽出した結果かどうか。falseはルールベースでの抽出 */
    val parsedByAi: Boolean = false
) {
    fun isEmpty(): Boolean = companyName.isEmpty() && userName.isEmpty() && content.isEmpty()

    /** [isEmpty]とは異なり、一部の項目だけ空でも分割失敗とみなす */
    fun isSplitFailed(): Boolean = !(companyName.isNotBlank() && userName.isNotBlank() && content.isNotBlank())

    /** [companyName]の英数字を半角大文字、それ以外を全角に統一した文字列（空白なら空文字） */
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

    /** 本文をキーにしたAI解析結果のキャッシュ（同じ本文を何度も解析させない）。複数スレッドから同時に呼ばれ得るためConcurrentHashMap */
    private val aiResultCache = ConcurrentHashMap<String, SmsParts>()

    @Volatile
    private var generativeModel: GenerativeModel? = null

    @Synchronized
    private fun getOrCreateModel(): GenerativeModel =
        generativeModel ?: Generation.getClient(generationConfig {}).also { generativeModel = it }

    /**
     * [aiParsingEnabled]が有効なら端末上のAI（ML Kit GenAI）に解析させ、Android 12未満・非対応端末・
     * AI呼び出し失敗時は[generateSmsParts]（ルールベース）にフォールバックする
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

    private fun matchLabelLine(line: String): LabelMatch? {
        for ((key, aliases) in AppConstants.SMS_BODY_FIELD_ALIASES) {
            for (alias in aliases) {
                // ラベルのみでコロンが無い行（値は次行以降に続く）にも対応
                if (line == alias) {
                    return LabelMatch(key, "")
                }
                // 区切り記号（：: ＝= －-—―、前後の全角空白も許容）だけでなく、
                // 記号が無く空白のみで区切られている場合（例:「会社名　XXX」）にも対応
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

    fun generateSmsParts(body: String?): SmsParts {
        if (body.isNullOrBlank()) return SmsParts()

        val normalized = body.replace("\r\n", "\n").replace("\r", "\n").trim()
        val contentLines = normalized.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        // 氏名・会社名を1行にまとめて書く人がいるため、3行未満では抽出せず空のまま返す
        // （本文自体は別途Bodyフィールドにそのまま登録されるので、ここで無理に詰め直す必要はない）
        if (contentLines.size < 3) {
            return SmsParts()
        }

        var companyName = ""
        var userName = ""
        var content = ""
        var currentKey: String? = null // "content"の間は続く行を内容として追記する

        for (line in contentLines) {
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
                currentKey == "content" -> content = if (content.isEmpty()) line else "$content\n$line"
                // ラベル省略時は行の位置で判定する（1つ目の未確定項目が会社名、2つ目が氏名）
                companyName.isEmpty() -> companyName = line
                userName.isEmpty() -> userName = line
                // 氏名・会社名が確定済みなら、以降はラベルが無くても内容として取り込む
                else -> {
                    content = line
                    currentKey = "content"
                }
            }
        }

        val contentValueLines = content.split("\n")
        if (contentValueLines.first().isBlank()) {
            content = contentValueLines.drop(1).joinToString("\n")
        }

        return SmsParts(companyName = companyName, userName = userName, content = content)
    }
}

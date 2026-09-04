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

/** SMS本文から抽出した会社名・氏名と、本文全体（原文）・抽出方法（AI/ルールベース）の結果を保持する */
data class SmsParts(
    /** 抽出した会社名 */
    val companyName: String = "",
    /** 抽出した氏名 */
    val userName: String = "",
    /** SMS本文全体（原文のまま。会社名・氏名の抽出に成功したかどうかに関わらず常に本文全体が入る） */
    val body: String = "",
    /** 端末上のAI（ML Kit GenAI）で抽出した結果かどうか。falseはルールベースでの抽出 */
    val extractedByAi: Boolean = false
) {
    /** [companyName]・[userName]・[body]がすべて空かどうか */
    fun isEmpty(): Boolean = companyName.isEmpty() && userName.isEmpty() && body.isEmpty()

    /** [isEmpty]とは異なり、一部の項目だけ空でも抽出失敗とみなす */
    fun isExtractionFailed(): Boolean = !(companyName.isNotBlank() && userName.isNotBlank() && body.isNotBlank())

    /** [companyName]の英数字を半角大文字、それ以外を全角に統一した文字列（空白なら空文字） */
    val companyNameNormalizedWidth: String
        get() = if (companyName.isNotBlank()) TextNormalization.normalizeWidth(companyName) else ""
}

/**
 * SMS本文から部品（会社名・氏名）を生成する（1行目:会社名 2行目:氏名の固定位置で判定）。
 * 本文（[SmsParts.body]）は抽出の成否に関わらず常に本文全体（原文）をそのまま保持する
 *
 * 対応例:
 * XXX
 * YYY
 * XXX（複数行OK）
 */
object SmsPartsGenerator {

    /** [Log]出力に使うタグ */
    private const val TAG = "SmsPartsGenerator"

    /** 本文をキーにしたAI解析結果のキャッシュ（同じ本文を何度も解析させない）。複数スレッドから同時に呼ばれ得るためConcurrentHashMap */
    private val aiResultCache = ConcurrentHashMap<String, SmsParts>()

    /** 生成コストを避けるため一度作ったモデルを使い回す。@Volatile+@Synchronizedは複数スレッドからの遅延初期化を安全にするため */
    @Volatile
    private var generativeModel: GenerativeModel? = null

    /** [generativeModel]を遅延生成して返す。既に生成済みならそれを再利用する */
    @Synchronized
    private fun getOrCreateModel(): GenerativeModel =
        generativeModel ?: Generation.getClient(generationConfig {}).also { generativeModel = it }

    /**
     * [aiExtractionEnabled]が有効なら端末上のAI（ML Kit GenAI）に解析させ、Android 12未満・非対応端末・
     * AI呼び出し失敗時は[generateSmsParts]（ルールベース）にフォールバックする
     */
    suspend fun resolveSmsParts(body: String, aiExtractionEnabled: Boolean): SmsParts {
        if (!aiExtractionEnabled || body.isBlank() || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return generateSmsParts(body)
        }

        aiResultCache[body]?.let { return it }

        val aiResult = requestAiSmsParts(body)
        val result = aiResult ?: generateSmsParts(body)
        aiResultCache[body] = result
        return result
    }

    /** 端末上のAIモデルを呼び出して会社名・氏名を抽出する。モデルが利用不可・ダウンロード失敗・呼び出し失敗の場合はnullを返す */
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
                以下のSMS本文から「会社名」「氏名」を抽出してください。
                該当する項目が本文に無い場合は空文字を返してください。
                出力は次の形式のJSONのみとし、それ以外の文章は含めないでください。
                {"companyName": "...", "userName": "..."}

                SMS本文:
                $body
            """.trimIndent()

            val response = model.generateContent(prompt)
            val text = response.candidates.firstOrNull()?.text?.trim() ?: return null
            // プロンプトで指示してもモデルが前後に余計な文章やコードフェンスを付けることがあるため、
            // 外側の中括弧の範囲だけを取り出してから改めて{}で包み直す
            val jsonText = text.substringAfter("{").substringBeforeLast("}").let { "{$it}" }
            val parsed = JSONObject(jsonText)
            SmsParts(
                companyName = parsed.optString("companyName", ""),
                userName = parsed.optString("userName", ""),
                body = body,
                extractedByAi = true
            )
        } catch (e: Exception) {
            Log.w(TAG, "ML Kit GenAIの呼び出しに失敗しました: ${e.message}")
            null
        }
    }

    /** 1行目を会社名、2行目を氏名として固定位置で切り出す（ラベル文字列は見ない）。本文は常に全体をそのまま保持する */
    fun generateSmsParts(body: String?): SmsParts {
        if (body.isNullOrBlank()) return SmsParts()

        val normalized = body.replace("\r\n", "\n").replace("\r", "\n").trim()
        val contentLines = normalized.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        // 氏名・会社名を1行にまとめて書く人がいるため、3行未満では会社名・氏名は抽出せず空のまま返す
        if (contentLines.size < 3) {
            return SmsParts(body = normalized)
        }

        val companyName = contentLines[0]
        val userName = contentLines[1]

        return SmsParts(companyName = companyName, userName = userName, body = normalized)
    }
}

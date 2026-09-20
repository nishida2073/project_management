package com.ssfrontier.smstokintone

import android.os.Build
import android.util.Log
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.generationConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
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
    val extractedByAi: Boolean = false,
    /** SMS本文から会社名・氏名の抽出を試みたかどうか。falseの場合は固定値を使用 */
    val extractionPerformed: Boolean = true
) {
    /** [companyName]・[userName]・[body]がすべて空かどうか */
    fun isEmpty(): Boolean = companyName.isEmpty() && userName.isEmpty() && body.isEmpty()

    /** [extractionPerformed]が true の場合のみ、一部の項目だけ空でも抽出失敗とみなす */
    fun isExtractionFailed(): Boolean = extractionPerformed && !(companyName.isNotBlank() && userName.isNotBlank() && body.isNotBlank())
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

    /** [Log]出力用のタグ。 */
    private const val TAG = "SmsPartsGenerator"

    /**
     * 本文をキーにしたAI解析結果のキャッシュ（同じ本文を何度も解析させない）。値を結果そのものではなく
     * Deferredで持つことで、同じ本文に対する呼び出しが同時に来た場合（SmsReceiverとKintoneUploadWorkerが
     * 同じSMSを並行して解決する場合など）も2回目以降はAIを呼ばず1回目の完了を待つだけになる
     * （computeIfAbsentがキーごとに1回しかマッピング関数を実行しないことを利用）
     */
    private val aiResultCache = ConcurrentHashMap<String, Deferred<SmsParts>>()

    /**
     * AI呼び出し用のコルーチンスコープ。呼び出し元（[SmsReceiver]・[KintoneUploadWorker]など）の
     * ライフサイクルに関わらず、進行中のAI呼び出しを複数の呼び出し元が共有できるようにするため、
     * [SmsPartsGenerator]自身の寿命の長いスコープを使用。
     */
    private val aiScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * AI生成モデルの遅延初期化キャッシュ。初期化コストが高いため、一度作成したモデルを再利用。
     * @Volatile と @Synchronized で複数スレッドからの同時初期化を安全に制御。
     */
    @Volatile
    private var generativeModel: GenerativeModel? = null

    /** [generativeModel]を遅延生成して返す。既に生成済みならそれを再利用する */
    @Synchronized
    private fun getOrCreateModel(): GenerativeModel =
        generativeModel ?: Generation.getClient(generationConfig {}).also { generativeModel = it }

    /**
     * SMS本文から会社名・氏名を抽出する（AI/ルールベース）。
     *
     * AI抽出が有効で端末が対応していれば [ML Kit GenAI](Gemini Nano) を使用し、
     * 無効・非対応・呼び出し失敗時は [generateSmsParts]（ルールベース抽出）にフォールバック。
     * 同一本文への重複呼び出しはキャッシュから即座に返される。
     *
     * @param body SMS本文（改行はいずれの形式にも対応）
     * @param aiExtractionEnabled AI抽出機能の有効フラグ
     * @param companyNameExtractionEnabled 会社名抽出の有効フラグ（無効時は空文字返却）
     * @return 抽出結果を含む [SmsParts]。失敗時も本文は常に返される
     */
    suspend fun resolveSmsParts(body: String, aiExtractionEnabled: Boolean, companyNameExtractionEnabled: Boolean = true): SmsParts {
        if (!aiExtractionEnabled || body.isBlank() || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return generateSmsParts(body, companyNameExtractionEnabled)
        }

        val deferred = aiResultCache.computeIfAbsent(body) {
            aiScope.async { requestAiSmsParts(body) ?: generateSmsParts(body, companyNameExtractionEnabled) }
        }
        return deferred.await()
    }

    /**
     * 端末上のAIモデル（ML Kit GenAI）を呼び出して会社名・氏名を抽出。
     * モデルの初期化・ダウンロード・呼び出しが失敗した場合は null を返し、
     * 呼び出し元で [generateSmsParts]（ルールベース）にフォールバック。
     *
     * @param body SMS本文
     * @return 抽出成功時は [SmsParts]、失敗時は null
     */
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
            // モデルの応答は指示に従わずコードフェンスなどを含むことがあるため、
            // 中括弧の範囲だけを抽出してから改めて{}で包み直す。
            val jsonText = text.substringAfter("{").substringBeforeLast("}").let { "{$it}" }
            val parsed = JSONObject(jsonText)
            SmsParts(
                companyName = parsed.optString("companyName", ""),
                userName = parsed.optString("userName", ""),
                body = body,
                extractedByAi = true,
                extractionPerformed = true
            )
        } catch (e: Exception) {
            Log.w(TAG, "ML Kit GenAIの呼び出しに失敗しました: ${e.message}")
            null
        }
    }

    /**
     * SMS本文から会社名・氏名をルールベースで抽出。
     *
     * [companyNameExtractionEnabled] が有効: 1行目=会社名、2行目=氏名（3行以上必須）。
     * [companyNameExtractionEnabled] が無効: 1行目=氏名、会社名=空（2行以上必須）。
     * 行数不足時は抽出フラグを立てた上で、本文と空文字を返す。
     *
     * @param body SMS本文（null/空白時は空の [SmsParts] を返す）
     * @param companyNameExtractionEnabled 会社名抽出の有効フラグ
     * @return 本文と抽出結果（または空文字）を含む [SmsParts]
     */
    fun generateSmsParts(body: String?, companyNameExtractionEnabled: Boolean = true): SmsParts {
        if (body.isNullOrBlank()) return SmsParts()

        val normalized = body.replace("\r\n", "\n").replace("\r", "\n").trim()
        val contentLines = normalized.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

        if (companyNameExtractionEnabled) {
            // 氏名・会社名を1行にまとめて書く人がいるため、3行未満では抽出せず空で返す。
            if (contentLines.size < 3) {
                return SmsParts(body = normalized, extractionPerformed = true)
            }
            return SmsParts(companyName = contentLines[0], userName = contentLines[1], body = normalized, extractionPerformed = true)
        }

        if (contentLines.size < 2) {
            return SmsParts(body = normalized, extractionPerformed = false)
        }
        return SmsParts(
            companyName = "",
            userName = contentLines[0],
            body = normalized,
            extractionPerformed = false
        )
    }
}

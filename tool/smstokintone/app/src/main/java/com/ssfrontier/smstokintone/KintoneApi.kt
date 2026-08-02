package com.ssfrontier.smstokintone

import android.util.Base64
import android.util.Log
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

/** kintoneへのレコード登録・更新リクエストを組み立てて送信する共通処理 */
object KintoneApi {

    private const val TAG = "KintoneApi"

    sealed class PostResult {
        data class Success(val message: String = "登録成功") : PostResult()
        data class HttpFailure(val code: Int, val detail: String) : PostResult()
        data class NetworkError(val message: String) : PostResult()
    }

    /**
     * レコードを登録する。ただし送信元（[profile].fieldPhone）と受信日時（[profile].fieldDatetime）
     * が一致する既存レコードが見つかった場合は、新規登録ではなくそのレコードを更新する。
     */
    fun postRecord(profile: Prefs.KintoneProfile, phoneValue: String, bodyValue: String, datetimeIsoValue: String?): PostResult {
        val record = buildRecord(profile, phoneValue, bodyValue, datetimeIsoValue)

        val existingId = if (profile.fieldPhone.isNotBlank() && profile.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            findExistingRecordId(profile, phoneValue, datetimeIsoValue)
        } else {
            null
        }

        return if (existingId != null) {
            updateRecord(profile, existingId, record)
        } else {
            insertRecord(profile, record)
        }
    }

    private fun buildRecord(profile: Prefs.KintoneProfile, phoneValue: String, bodyValue: String, datetimeIsoValue: String?): JSONObject {
        val record = JSONObject()
        if (profile.fieldPhone.isNotBlank()) {
            record.put(profile.fieldPhone, JSONObject().put("value", phoneValue))
        }
        record.put(profile.fieldBody, JSONObject().put("value", bodyValue))
        if (profile.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            record.put(profile.fieldDatetime, JSONObject().put("value", datetimeIsoValue))
        }
        return record
    }

    /** 送信元と受信日時が一致する既存レコードのIDを探す。見つからない・検索に失敗した場合はnull */
    private fun findExistingRecordId(profile: Prefs.KintoneProfile, phoneValue: String, datetimeIsoValue: String): String? {
        val query = "${profile.fieldPhone} = \"${escapeForQuery(phoneValue)}\" and " +
            "${profile.fieldDatetime} = \"${escapeForQuery(datetimeIsoValue)}\""

        val url = HttpUrl.Builder()
            .scheme("https")
            .host("${profile.subdomain}.cybozu.com")
            .addPathSegments("k/v1/records.json")
            .addQueryParameter("app", profile.appId)
            .addQueryParameter("query", query)
            .addQueryParameter("fields[0]", "\$id")
            .build()

        val requestBuilder = Request.Builder().url(url).get()
        addAuthHeader(requestBuilder, profile)

        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "既存レコードの検索に失敗しました: ${response.code} ${response.body?.string() ?: ""}")
                    return null
                }
                val records = JSONObject(response.body?.string() ?: "{}").optJSONArray("records")
                val first = records?.optJSONObject(0) ?: return null
                first.getJSONObject("\$id").getString("value")
            }
        } catch (e: IOException) {
            Log.w(TAG, "既存レコードの検索で通信エラーが発生しました: ${e.message}")
            null
        }
    }

    private fun escapeForQuery(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")

    private fun insertRecord(profile: Prefs.KintoneProfile, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", profile.appId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${profile.subdomain}.cybozu.com/k/v1/record.json")
            .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, profile)

        return execute(requestBuilder, successMessage = "登録成功")
    }

    private fun updateRecord(profile: Prefs.KintoneProfile, recordId: String, record: JSONObject): PostResult {
        val payload = JSONObject()
            .put("app", profile.appId)
            .put("id", recordId)
            .put("record", record)

        val requestBuilder = Request.Builder()
            .url("https://${profile.subdomain}.cybozu.com/k/v1/record.json")
            .put(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
        addAuthHeader(requestBuilder, profile)

        return execute(requestBuilder, successMessage = "更新成功")
    }

    private fun addAuthHeader(requestBuilder: Request.Builder, profile: Prefs.KintoneProfile) {
        when (profile.authMethod) {
            Prefs.AuthMethod.API_TOKEN ->
                requestBuilder.addHeader("X-Cybozu-API-Token", profile.apiToken)
            Prefs.AuthMethod.PASSWORD -> {
                val credentials = "${profile.loginName}:${profile.loginPassword}"
                val encoded = Base64.encodeToString(
                    credentials.toByteArray(Charsets.UTF_8),
                    Base64.NO_WRAP
                )
                requestBuilder.addHeader("X-Cybozu-Authorization", encoded)
            }
        }
    }

    private fun execute(requestBuilder: Request.Builder, successMessage: String): PostResult {
        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (response.isSuccessful) {
                    PostResult.Success(successMessage)
                } else {
                    PostResult.HttpFailure(response.code, response.body?.string() ?: "")
                }
            }
        } catch (e: IOException) {
            PostResult.NetworkError(e.message ?: "")
        }
    }
}

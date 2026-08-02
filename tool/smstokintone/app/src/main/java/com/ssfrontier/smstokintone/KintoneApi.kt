package com.ssfrontier.smstokintone

import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

/** kintoneへのレコード登録リクエストを組み立てて送信する共通処理 */
object KintoneApi {

    sealed class PostResult {
        data class Success(val message: String = "登録成功") : PostResult()
        data class HttpFailure(val code: Int, val detail: String) : PostResult()
        data class NetworkError(val message: String) : PostResult()
    }

    fun postRecord(profile: Prefs.KintoneProfile, phoneValue: String, bodyValue: String, datetimeIsoValue: String?): PostResult {
        val record = JSONObject()
        if (profile.fieldPhone.isNotBlank()) {
            record.put(profile.fieldPhone, JSONObject().put("value", phoneValue))
        }
        record.put(profile.fieldBody, JSONObject().put("value", bodyValue))
        if (profile.fieldDatetime.isNotBlank() && datetimeIsoValue != null) {
            record.put(profile.fieldDatetime, JSONObject().put("value", datetimeIsoValue))
        }

        val payload = JSONObject()
            .put("app", profile.appId)
            .put("record", record)

        val requestBody = payload.toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())

        val requestBuilder = Request.Builder()
            .url("https://${profile.subdomain}.cybozu.com/k/v1/record.json")
            .post(requestBody)

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

        return try {
            OkHttpClient().newCall(requestBuilder.build()).execute().use { response ->
                if (response.isSuccessful) {
                    PostResult.Success()
                } else {
                    PostResult.HttpFailure(response.code, response.body?.string() ?: "")
                }
            }
        } catch (e: IOException) {
            PostResult.NetworkError(e.message ?: "")
        }
    }
}

package com.ssfrontier.smstokintone

import android.content.res.ColorStateList
import android.util.TypedValue
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.text.bold
import androidx.core.text.buildSpannedString
import androidx.core.text.color
import com.google.android.material.button.MaterialButton

fun MaterialButton.setButtonStyleByEnabled(enabled: Boolean) {
    if (enabled) {
        setStrokeWidth(0)
        setBackgroundColor(getThemeColor(com.google.android.material.R.attr.colorPrimary))
        setTextColor(getThemeColor(com.google.android.material.R.attr.colorOnPrimary))
    } else {
        setStrokeWidth(1)
        setBackgroundColor(context.getColor(android.R.color.transparent))
        setTextColor(context.getColor(android.R.color.darker_gray))
        setStrokeColor(ColorStateList.valueOf(context.getColor(android.R.color.darker_gray)))
    }
}

private fun MaterialButton.getThemeColor(attrId: Int): Int {
    val typedValue = TypedValue()
    context.theme.resolveAttribute(attrId, typedValue, true)
    return typedValue.data
}

fun AppCompatActivity.buildSmsInfoString(
    extractionTargetIcon: String,
    isExtractionFailed: Boolean,
    sendStatus: String?,
    isAutoReplied: Boolean,
    sendTargetIcon: String,
    sendTargetName: String? = null,
    sendTargetColor: Int? = null,
    senderDisplay: String? = null,
    dateString: String? = null,
    body: String? = null
): CharSequence {
    return buildSpannedString {
        append(extractionTargetIcon)
        append(" ")
        val extractionIcon = if (isExtractionFailed) getString(R.string.icon_extraction_failed) else getString(R.string.icon_extraction_succeeded)
        append(extractionIcon)
        append(" ")
        if (sendStatus != null) {
            append(sendStatus)
        }
        if (isAutoReplied) {
            append(" ")
            append(getString(R.string.icon_replied))
        }
        append(" ")
        append(sendTargetIcon)
        if (sendTargetName != null) {
            append("\n")
            if (sendTargetColor != null) {
                color(sendTargetColor) {
                    bold { append(sendTargetName) }
                }
            } else {
                bold { append(sendTargetName) }
            }
        }
        if (senderDisplay != null && dateString != null) {
            append("\n\n$dateString　$senderDisplay")
        }
        if (body != null) {
            append("\n$body")
        }
    }
}


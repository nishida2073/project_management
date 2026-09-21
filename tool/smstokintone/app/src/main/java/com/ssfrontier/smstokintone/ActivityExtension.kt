package com.ssfrontier.smstokintone

import android.util.TypedValue
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
    }
}

private fun MaterialButton.getThemeColor(attrId: Int): Int {
    val typedValue = TypedValue()
    context.theme.resolveAttribute(attrId, typedValue, true)
    return typedValue.data
}

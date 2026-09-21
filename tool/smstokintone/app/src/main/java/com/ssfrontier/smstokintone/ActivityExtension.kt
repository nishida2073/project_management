package com.ssfrontier.smstokintone

import android.app.Dialog
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.View
import android.widget.AdapterView
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.RadioGroup
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
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

fun simpleTextWatcher(onAfter: (String) -> Unit): TextWatcher = object : TextWatcher {
    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
    override fun afterTextChanged(s: Editable?) {
        onAfter(s?.toString().orEmpty())
    }
}

class ActivityLifecycleResourceManager {
    private val textWatchers = mutableListOf<Pair<EditText, TextWatcher>>()
    private val dialogs = mutableListOf<Dialog>()
    private val radioGroupListeners = mutableListOf<Pair<RadioGroup, RadioGroup.OnCheckedChangeListener>>()
    private val compoundButtonListeners = mutableListOf<Pair<CompoundButton, CompoundButton.OnCheckedChangeListener>>()
    private val clickListeners = mutableListOf<Pair<View, View.OnClickListener>>()
    private val spinnerListeners = mutableListOf<Pair<AdapterView<*>, AdapterView.OnItemSelectedListener>>()
    private val refreshListeners = mutableListOf<Pair<SwipeRefreshLayout, SwipeRefreshLayout.OnRefreshListener>>()
    private val liveDataObservers = mutableListOf<Triple<LiveData<*>, Observer<*>, Any?>>()

    @Synchronized
    fun addTextWatcher(editText: EditText, listener: TextWatcher) {
        editText.addTextChangedListener(listener)
        textWatchers.add(editText to listener)
    }

    @Synchronized
    fun addRadioGroupListener(radioGroup: RadioGroup, listener: RadioGroup.OnCheckedChangeListener) {
        radioGroup.setOnCheckedChangeListener(listener)
        radioGroupListeners.add(radioGroup to listener)
    }

    @Synchronized
    fun addCompoundButtonListener(compoundButton: CompoundButton, listener: CompoundButton.OnCheckedChangeListener) {
        compoundButton.setOnCheckedChangeListener(listener)
        compoundButtonListeners.add(compoundButton to listener)
    }

    @Synchronized
    fun addClickListener(view: View, listener: View.OnClickListener) {
        view.setOnClickListener(listener)
        clickListeners.add(view to listener)
    }

    @Synchronized
    fun addSpinnerListener(spinner: AdapterView<*>, listener: AdapterView.OnItemSelectedListener) {
        spinner.onItemSelectedListener = listener
        spinnerListeners.add(spinner to listener)
    }

    @Synchronized
    fun addRefreshListener(refreshLayout: SwipeRefreshLayout, listener: SwipeRefreshLayout.OnRefreshListener) {
        refreshLayout.setOnRefreshListener(listener)
        refreshListeners.add(refreshLayout to listener)
    }

    @Synchronized
    fun addDialog(dialog: Dialog) {
        dialogs.add(dialog)
    }

    @Synchronized
    fun <T> addLiveDataObserver(liveData: LiveData<T>, observer: Observer<T>) {
        liveData.observeForever(observer)
        @Suppress("UNCHECKED_CAST")
        liveDataObservers.add(Triple(liveData, observer as Observer<*>, null))
    }

    @Synchronized
    fun cleanup() {
        try {
            textWatchers.forEach { (editText, watcher) ->
                try {
                    editText.removeTextChangedListener(watcher)
                } catch (e: Exception) {
                }
            }
        } finally {
            textWatchers.clear()
        }

        try {
            radioGroupListeners.forEach { (radioGroup, listener) ->
                try {
                    radioGroup.setOnCheckedChangeListener(null)
                } catch (e: Exception) {
                }
            }
        } finally {
            radioGroupListeners.clear()
        }

        try {
            compoundButtonListeners.forEach { (compoundButton, listener) ->
                try {
                    compoundButton.setOnCheckedChangeListener(null)
                } catch (e: Exception) {
                }
            }
        } finally {
            compoundButtonListeners.clear()
        }

        try {
            clickListeners.forEach { (view, _) ->
                try {
                    view.setOnClickListener(null)
                } catch (e: Exception) {
                }
            }
        } finally {
            clickListeners.clear()
        }

        try {
            spinnerListeners.forEach { (spinner, _) ->
                try {
                    spinner.onItemSelectedListener = null
                } catch (e: Exception) {
                }
            }
        } finally {
            spinnerListeners.clear()
        }

        try {
            refreshListeners.forEach { (refreshLayout, _) ->
                try {
                    refreshLayout.setOnRefreshListener(null)
                } catch (e: Exception) {
                }
            }
        } finally {
            refreshListeners.clear()
        }

        try {
            dialogs.forEach { dialog ->
                try {
                    dialog.cancel()
                    dialog.dismiss()
                } catch (e: Exception) {
                }
            }
        } finally {
            dialogs.clear()
        }

        try {
            liveDataObservers.forEach { (liveData, observer, _) ->
                try {
                    @Suppress("UNCHECKED_CAST")
                    (liveData as LiveData<Any?>).removeObserver(observer as Observer<Any?>)
                } catch (e: Exception) {
                }
            }
        } finally {
            liveDataObservers.clear()
        }
    }
}

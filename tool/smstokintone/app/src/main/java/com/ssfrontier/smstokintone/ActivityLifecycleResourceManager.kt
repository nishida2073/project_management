package com.ssfrontier.smstokintone

import android.app.Dialog
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.AdapterView
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.RadioGroup
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

fun simpleTextWatcher(onAfter: (String) -> Unit): TextWatcher = object : TextWatcher {
    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
    override fun afterTextChanged(s: Editable?) {
        onAfter(s?.toString().orEmpty())
    }
}

class ActivityLifecycleResourceManager {
    internal val textWatchers = mutableListOf<Pair<EditText, TextWatcher>>()
    internal val dialogs = mutableListOf<Dialog>()
    internal val radioGroupListeners = mutableListOf<Pair<RadioGroup, RadioGroup.OnCheckedChangeListener>>()
    internal val compoundButtonListeners = mutableListOf<Pair<CompoundButton, CompoundButton.OnCheckedChangeListener>>()
    internal val clickListeners = mutableListOf<Pair<View, View.OnClickListener>>()
    internal val spinnerListeners = mutableListOf<Pair<AdapterView<*>, AdapterView.OnItemSelectedListener>>()
    internal val refreshListeners = mutableListOf<Pair<SwipeRefreshLayout, SwipeRefreshLayout.OnRefreshListener>>()
    internal val liveDataObservers = mutableListOf<Triple<LiveData<*>, Observer<*>, Any?>>()

    @Synchronized
    fun cleanup() {
        cleanupTextWatchers()
        cleanupRadioGroupListeners()
        cleanupCompoundButtonListeners()
        cleanupClickListeners()
        cleanupSpinnerListeners()
        cleanupRefreshListeners()
        cleanupDialogs()
        cleanupLiveDataObservers()
    }

    private fun cleanupTextWatchers() {
        try {
            textWatchers.forEach { (editText, watcher) ->
                try { editText.removeTextChangedListener(watcher) } catch (e: Exception) {}
            }
        } finally {
            textWatchers.clear()
        }
    }

    private fun cleanupRadioGroupListeners() {
        try {
            radioGroupListeners.forEach { (radioGroup, _) ->
                try { radioGroup.setOnCheckedChangeListener(null) } catch (e: Exception) {}
            }
        } finally {
            radioGroupListeners.clear()
        }
    }

    private fun cleanupCompoundButtonListeners() {
        try {
            compoundButtonListeners.forEach { (compoundButton, _) ->
                try { compoundButton.setOnCheckedChangeListener(null) } catch (e: Exception) {}
            }
        } finally {
            compoundButtonListeners.clear()
        }
    }

    private fun cleanupClickListeners() {
        try {
            clickListeners.forEach { (view, _) ->
                try { view.setOnClickListener(null) } catch (e: Exception) {}
            }
        } finally {
            clickListeners.clear()
        }
    }

    private fun cleanupSpinnerListeners() {
        try {
            spinnerListeners.forEach { (spinner, _) ->
                try { spinner.onItemSelectedListener = null } catch (e: Exception) {}
            }
        } finally {
            spinnerListeners.clear()
        }
    }

    private fun cleanupRefreshListeners() {
        try {
            refreshListeners.forEach { (refreshLayout, _) ->
                try { refreshLayout.setOnRefreshListener(null) } catch (e: Exception) {}
            }
        } finally {
            refreshListeners.clear()
        }
    }

    private fun cleanupDialogs() {
        try {
            dialogs.forEach { dialog ->
                try {
                    dialog.cancel()
                    dialog.dismiss()
                } catch (e: Exception) {}
            }
        } finally {
            dialogs.clear()
        }
    }

    private fun cleanupLiveDataObservers() {
        try {
            liveDataObservers.forEach { (liveData, observer, _) ->
                try {
                    @Suppress("UNCHECKED_CAST")
                    (liveData as LiveData<Any?>).removeObserver(observer as Observer<Any?>)
                } catch (e: Exception) {}
            }
        } finally {
            liveDataObservers.clear()
        }
    }
}

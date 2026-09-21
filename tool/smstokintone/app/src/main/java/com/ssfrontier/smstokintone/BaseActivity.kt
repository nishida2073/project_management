package com.ssfrontier.smstokintone

import android.app.Dialog
import android.text.TextWatcher
import android.view.View
import android.widget.AdapterView
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.RadioGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

abstract class BaseActivity : AppCompatActivity() {
    protected val lifecycleResources = ActivityLifecycleResourceManager()

    override fun onDestroy() {
        super.onDestroy()
        lifecycleResources.cleanup()
    }

    protected fun EditText.setupManaged(listener: TextWatcher) {
        addTextChangedListener(listener)
        lifecycleResources.textWatchers.add(this to listener)
    }

    protected fun RadioGroup.setupManaged(listener: RadioGroup.OnCheckedChangeListener) {
        setOnCheckedChangeListener(listener)
        lifecycleResources.radioGroupListeners.add(this to listener)
    }

    protected fun CompoundButton.setupManaged(listener: CompoundButton.OnCheckedChangeListener) {
        setOnCheckedChangeListener(listener)
        lifecycleResources.compoundButtonListeners.add(this to listener)
    }

    protected fun View.setupManaged(listener: View.OnClickListener) {
        setOnClickListener(listener)
        lifecycleResources.clickListeners.add(this to listener)
    }

    protected fun AdapterView<*>.setupManaged(listener: AdapterView.OnItemSelectedListener) {
        onItemSelectedListener = listener
        lifecycleResources.spinnerListeners.add(this to listener)
    }

    protected fun SwipeRefreshLayout.setupManaged(listener: SwipeRefreshLayout.OnRefreshListener) {
        setOnRefreshListener(listener)
        lifecycleResources.refreshListeners.add(this to listener)
    }

    protected fun Dialog.setupManaged(): Dialog {
        lifecycleResources.dialogs.add(this)
        return this
    }

    protected fun <T> LiveData<T>.setupManaged(observer: Observer<T>) {
        observeForever(observer)
        @Suppress("UNCHECKED_CAST")
        lifecycleResources.liveDataObservers.add(Triple(this, observer as Observer<*>, null))
    }
}

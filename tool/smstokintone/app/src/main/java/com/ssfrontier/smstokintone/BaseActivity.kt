package com.ssfrontier.smstokintone

import androidx.appcompat.app.AppCompatActivity

abstract class BaseActivity : AppCompatActivity() {
    protected val lifecycleResources = ActivityLifecycleResourceManager()

    override fun onDestroy() {
        super.onDestroy()
        lifecycleResources.cleanup()
    }
}

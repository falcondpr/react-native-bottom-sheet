package com.swmansion.reactnativebottomsheet

import android.os.Bundle
import android.view.KeyEvent
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import java.util.concurrent.atomic.AtomicInteger

class RecordingReactActivity : ReactActivity() {
  override fun createReactActivityDelegate(): ReactActivityDelegate =
    RecordingReactActivityDelegate(this)
}

class RecordingReactActivityDelegate(activity: ReactActivity) :
  ReactActivityDelegate(activity, null) {
  override fun onCreate(savedInstanceState: Bundle?) = Unit

  override fun onPause() = Unit

  override fun onResume() = Unit

  override fun onDestroy() = Unit

  override fun onWindowFocusChanged(hasFocus: Boolean) = Unit

  override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = false

  override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean = false

  override fun onKeyLongPress(keyCode: Int, event: KeyEvent): Boolean = false

  override fun onUserLeaveHint() = Unit

  override fun onBackPressed(): Boolean {
    backEntryCount.incrementAndGet()
    return true
  }

  companion object {
    val backEntryCount = AtomicInteger()
  }
}

@file:OptIn(com.facebook.react.common.annotations.UnstableReactNativeAPI::class)

package com.swmansion.reactnativebottomsheet.accessibility

import androidx.annotation.UiThread
import com.facebook.jni.HybridData
import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.fabric.FabricUIManager
import com.facebook.soloader.SoLoader

/** One source resource per observed UIManager; all access is deferred to the UI queue. */
@UiThread
@DoNotStrip
internal class FabricPortalPublication
private constructor(@field:DoNotStrip private val mHybridData: HybridData) :
  FabricPublicationLease {
  private var active = true

  override fun bootstrap() {
    if (active) bootstrapNative()
  }

  override fun release() {
    if (!active) return
    active = false
    mHybridData.resetNative()
  }

  @DoNotStrip private external fun bootstrapNative()

  companion object {
    fun acquire(identity: Any): FabricPublicationLease? {
      val manager = identity as? FabricUIManager ?: return null
      SoLoader.loadLibrary("react_codegen_ReactNativeBottomSheetSpec")
      return initHybrid(manager)?.let(::FabricPortalPublication)
    }

    @JvmStatic @DoNotStrip private external fun initHybrid(manager: FabricUIManager): HybridData?
  }
}

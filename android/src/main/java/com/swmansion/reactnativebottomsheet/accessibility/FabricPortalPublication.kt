@file:OptIn(com.facebook.react.common.annotations.UnstableReactNativeAPI::class)

package com.swmansion.reactnativebottomsheet.accessibility

import androidx.annotation.UiThread
import com.facebook.jni.HybridData
import com.facebook.proguard.annotations.DoNotStrip
import com.facebook.react.fabric.FabricUIManager
import com.facebook.react.uimanager.StateWrapper
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

  override fun receipt(
    surfaceId: Int,
    tag: Int,
    states: Map<Int, StateWrapper?>,
  ): FabricPortalReceipt? {
    if (!active || tag !in states) return null
    val delivered = states.toList()
    return receiptNative(
      surfaceId,
      tag,
      delivered.map { it.first }.toIntArray(),
      delivered.map { it.second }.toTypedArray(),
    )
  }

  override fun release() {
    if (!active) return
    active = false
    mHybridData.resetNative()
  }

  @DoNotStrip private external fun bootstrapNative()

  @DoNotStrip
  private external fun receiptNative(
    surfaceId: Int,
    tag: Int,
    tags: IntArray,
    states: Array<StateWrapper?>,
  ): FabricPortalReceipt?

  companion object {
    fun acquire(identity: Any): FabricPublicationLease? {
      val manager = identity as? FabricUIManager ?: return null
      SoLoader.loadLibrary("react_codegen_ReactNativeBottomSheetSpec")
      return initHybrid(manager)?.let(::FabricPortalPublication)
    }

    @JvmStatic @DoNotStrip private external fun initHybrid(manager: FabricUIManager): HybridData?
  }
}

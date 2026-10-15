package com.swmansion.reactnativebottomsheet.accessibility

import android.view.View
import androidx.annotation.UiThread
import com.facebook.react.bridge.UIManager
import com.facebook.react.uimanager.IllegalViewOperationException
import com.facebook.react.uimanager.StateWrapper
import com.swmansion.reactnativebottomsheet.BottomSheetView

/**
 * Reads exact delivered States from the SDK registry, including sheets outside this native branch.
 * Every delivered State needs a completed observed execution batch; source native edges and queried
 * ancestry must agree. This does not establish full applied-family or attachment/window membership.
 */
@UiThread
internal fun FabricPublicationLease.receiptFromRegistry(
  manager: UIManager,
  surfaceId: Int,
  presentation: BottomSheetView,
): FabricPortalReceipt? {
  val tags = sheetTags(surfaceId, presentation.id, presentation.stateWrapper) ?: return null
  val states = mutableMapOf<Int, StateWrapper?>()
  for (tag in tags) {
    val view =
      try {
        manager.resolveView(tag)
      } catch (_: IllegalViewOperationException) {
        return null
      }
    if (view !is BottomSheetView || view.id != tag) return null
    if (tag == presentation.id && view !== presentation) return null
    val state = view.stateWrapper
    if (!view.isMountCompleteFor(state)) return null
    states[tag] = state
  }
  val receipt = receipt(surfaceId, presentation.id, states) ?: return null
  return receipt.takeIf {
    it.nativeMembers(manager::resolveView) != null &&
      it.nativePath(manager::resolveView, presentation) != null
  }
}

/**
 * Requires every supplied owner in one surface/window or rejects the group. Ownership comes from
 * the caller; source discovery still includes all sheets. Empty input returns an empty release
 * result. This adds current owner attachment/window checks, not full applied-root/family
 * acceptance.
 */
@UiThread
internal fun FabricPublicationLease.attachedReceiptsFromRegistry(
  manager: UIManager,
  surfaceId: Int,
  presentations: Collection<BottomSheetView>,
  windowRoot: View,
): Map<BottomSheetView, FabricPortalReceipt>? {
  val receipts = mutableMapOf<BottomSheetView, FabricPortalReceipt>()
  for (presentation in presentations) {
    val receipt = receiptFromRegistry(manager, surfaceId, presentation) ?: return null
    if (receipt.attachedNativePath(manager::resolveView, presentation, windowRoot) == null)
      return null
    receipts[presentation] = receipt
  }
  return receipts
}

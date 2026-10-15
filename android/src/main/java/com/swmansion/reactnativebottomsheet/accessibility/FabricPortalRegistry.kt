package com.swmansion.reactnativebottomsheet.accessibility

import androidx.annotation.UiThread
import com.facebook.react.bridge.UIManager
import com.facebook.react.uimanager.IllegalViewOperationException
import com.facebook.react.uimanager.StateWrapper
import com.swmansion.reactnativebottomsheet.BottomSheetView

/**
 * Reads exact delivered States from the SDK registry, including sheets outside this native branch.
 * The queried native ancestry must agree. This does not establish full native branch/family
 * membership, completed mounting, attachment or window membership.
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
    states[tag] = view.stateWrapper
  }
  val receipt = receipt(surfaceId, presentation.id, states) ?: return null
  return receipt.takeIf { it.nativePath(manager::resolveView, presentation) != null }
}

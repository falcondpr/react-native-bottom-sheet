package com.swmansion.reactnativebottomsheet.accessibility

import androidx.annotation.UiThread
import com.facebook.react.bridge.UIManager
import com.facebook.react.uimanager.IllegalViewOperationException
import com.facebook.react.uimanager.StateWrapper
import com.swmansion.reactnativebottomsheet.BottomSheetView

/**
 * Reads exact delivered States from the SDK registry, including sheets outside this native branch.
 * A source receipt does not establish native attachment, parent edges or window membership.
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
  return receipt(surfaceId, presentation.id, states)
}

package com.swmansion.reactnativebottomsheet.accessibility

import android.view.View
import androidx.annotation.UiThread
import com.facebook.react.bridge.UIManager
import com.facebook.react.uimanager.IllegalViewOperationException
import com.facebook.react.uimanager.StateWrapper
import com.facebook.react.uimanager.UIManagerHelper
import com.swmansion.reactnativebottomsheet.BottomSheetView

/**
 * Reads exact delivered States from the SDK registry, including sheets outside this native branch.
 * Source native edges and queried ancestry must agree. Callers reconcile from queued
 * mount/lifecycle work, not inline during State delivery. This validates the available source and
 * structure, not successful execution of every RN mount instruction or attachment/window
 * membership.
 */
@UiThread
internal fun FabricPublicationLease.receiptFromRegistry(
  manager: UIManager,
  surfaceId: Int,
  presentation: BottomSheetView,
): FabricPortalReceipt? {
  val states = deliveredStatesFromRegistry(manager, surfaceId, presentation) ?: return null
  val receipt = receipt(surfaceId, presentation.id, states) ?: return null
  return receipt.takeIf {
    it.nativeMembers(manager::resolveView) != null &&
      it.nativePath(manager::resolveView, presentation) != null
  }
}

@UiThread
private fun FabricPublicationLease.deliveredStatesFromRegistry(
  manager: UIManager,
  surfaceId: Int,
  presentation: BottomSheetView,
): Map<Int, StateWrapper?>? {
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
    states[tag] = state
  }
  return states
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

/**
 * Reads source projections after validating every supplied owner's source structure and window.
 * Retained paths are caller-owned. Results are consumed in the current UI work, not cached as
 * accepted native cuts; native-only sibling composition and final mask validation remain separate.
 */
@UiThread
internal fun FabricPublicationLease.attachedIsolationFromRegistry(
  manager: UIManager,
  presentations: Collection<BottomSheetView>,
  retainedPresentations: Collection<BottomSheetView>,
  windowRoot: View,
): Map<Int, FabricPortalIsolationProjection>? {
  if (!presentations.toSet().containsAll(retainedPresentations)) return null
  val projections = mutableMapOf<Int, FabricPortalIsolationProjection>()
  for ((surface, owners) in presentations.groupBy(UIManagerHelper::getSurfaceId)) {
    if (surface <= 0) return null
    val states = deliveredStatesFromRegistry(manager, surface, owners.first()) ?: return null
    val receipts = mutableMapOf<BottomSheetView, FabricPortalReceipt>()
    for (owner in owners) {
      val receipt = receipt(surface, owner.id, states) ?: return null
      if (receipt.attachedNativePath(manager::resolveView, owner, windowRoot) == null) return null
      receipts[owner] = receipt
    }
    val source = receipts.getValue(owners.first())
    if (source.nativeMembers(manager::resolveView) == null) return null
    val retainedByHost =
      retainedPresentations
        .filter(receipts::containsKey)
        .groupBy { receipts.getValue(it).hostTag }
        .mapValues { (_, retained) -> retained.map { it.id } }
    projections[surface] =
      isolation(surface, states, source.nativeParents, retainedByHost) ?: return null
  }
  return projections
}

/** Reads every supplied owner across this manager's surfaces, or rejects the complete group. */
@UiThread
internal fun FabricPublicationLease.attachedReceiptsFromRegistry(
  manager: UIManager,
  presentations: Collection<BottomSheetView>,
  windowRoot: View,
): Map<BottomSheetView, FabricPortalReceipt>? {
  val receipts = mutableMapOf<BottomSheetView, FabricPortalReceipt>()
  for ((surface, owners) in presentations.groupBy(UIManagerHelper::getSurfaceId)) {
    if (surface <= 0) return null
    val group = attachedReceiptsFromRegistry(manager, surface, owners, windowRoot) ?: return null
    receipts.putAll(group)
  }
  return receipts
}

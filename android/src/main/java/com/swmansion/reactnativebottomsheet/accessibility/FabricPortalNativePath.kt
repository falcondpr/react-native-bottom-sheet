package com.swmansion.reactnativebottomsheet.accessibility

import android.view.View
import android.view.ViewGroup
import androidx.annotation.UiThread
import com.facebook.react.uimanager.IllegalViewOperationException
import com.facebook.react.views.modal.ReactModalHostView
import java.util.Collections
import java.util.IdentityHashMap

private fun cachedNativeLookup(resolveView: (Int) -> View?): (Int) -> View? {
  val registry = mutableMapOf<Int, View?>()
  return { tag ->
    if (tag !in registry) {
      registry[tag] =
        try {
          resolveView(tag)
        } catch (_: IllegalViewOperationException) {
          null
        }
    }
    registry[tag]
  }
}

private fun View.isModalContainer(owner: View?, child: View): Boolean {
  if (owner !is ReactModalHostView || this !is ViewGroup) return false
  val index = indexOfChild(child)
  return index >= 0 && owner.childCount == childCount && owner.getChildAt(index) === child
}

/** Validates expected source materialization/edges, not family bindings or completed mounting. */
@UiThread
internal fun FabricPortalReceipt.nativeMembers(resolveView: (Int) -> View?): Map<Int, View>? {
  val rootTag = nativeParents.entries.singleOrNull { it.value == 0 }?.key ?: return null
  if (!logicalTags.toSet().containsAll(nativeParents.keys)) return null
  val registered = cachedNativeLookup(resolveView)
  val members = mutableMapOf<Int, View>()
  for (tag in logicalTags) {
    val view = registered(tag)
    if ((tag in nativeParents) != (view != null)) return null
    if (view != null) {
      if (view.id != tag) return null
      members[tag] = view
    }
  }
  val root = members[rootTag] as? ViewGroup ?: return null
  for ((tag, expectedParent) in nativeParents) {
    if (tag == rootTag) continue
    var child = members[tag] ?: return null
    val seen = Collections.newSetFromMap(IdentityHashMap<View, Boolean>())
    while (true) {
      val parent = child.parent as? ViewGroup ?: return null
      if (!seen.add(parent)) return null
      val index = parent.indexOfChild(child)
      if (index < 0 || parent.getChildAt(index) !== child) return null
      val owner = registered(parent.id)
      if (owner === parent || parent.isModalContainer(owner, child)) {
        if (owner !== members[expectedParent]) return null
        break
      }
      child = parent
    }
  }
  val pending = mutableListOf<View>(root)
  val seen = Collections.newSetFromMap(IdentityHashMap<View, Boolean>())
  while (pending.isNotEmpty()) {
    val view = pending.removeAt(pending.lastIndex)
    if (!seen.add(view)) return null
    if (registered(view.id) === view && members[view.id] !== view) return null
    if (view is ViewGroup) {
      for (index in 0 until view.childCount) pending.add(view.getChildAt(index))
    }
  }
  return members
}

/**
 * Checks queried ancestry, not full native branch/family membership or completed mounting. Missing
 * intermediate registry views may be flattened logical nodes. The returned physical path does not
 * replace a logical context with its nearest materialized ancestor.
 */
@UiThread
internal fun FabricPortalReceipt.nativePath(
  resolveView: (Int) -> View?,
  presentation: View,
): List<View>? {
  if (ancestors.firstOrNull() != presentation.id || hostTag !in ancestors) return null
  val registered = cachedNativeLookup(resolveView)
  val expected = mutableListOf<View>()
  for (tag in ancestors) {
    val view = registered(tag) ?: continue
    if (view.id != tag) return null
    expected.add(view)
  }
  if (expected.firstOrNull() !== presentation || registered(ancestors.last()) == null) return null
  val host = registered(hostTag) as? ViewGroup ?: return null
  if (
    host.getTag(com.facebook.react.R.id.view_tag_native_id) !=
      "__react_native_bottom_sheet_portal_host"
  )
    return null
  val path = mutableListOf<View>()
  var current = presentation
  var next = 0
  while (true) {
    if (path.any { it === current }) return null
    path.add(current)
    val owner = registered(current.id)
    if (owner === current) {
      if (expected.getOrNull(next) !== current) return null
      next++
      if (next == expected.size) return path
    } else if (
      owner is ReactModalHostView &&
        expected.getOrNull(next) === owner &&
        next == expected.lastIndex
    ) {
      // Stock RN Modal redirects its public child API to the dialog container.
      // A copied tag alone cannot establish this physical owner relationship.
      val child = path.getOrNull(path.lastIndex - 1) ?: return null
      if (!current.isModalContainer(owner, child)) return null
      return path
    }
    val parent = current.parent as? ViewGroup ?: return null
    val index = parent.indexOfChild(current)
    if (index < 0 || parent.getChildAt(index) !== current) return null
    current = parent
  }
}

/** Adds current attachment/window checks; it does not establish full applied native membership. */
@UiThread
internal fun FabricPortalReceipt.attachedNativePath(
  resolveView: (Int) -> View?,
  presentation: View,
  windowRoot: View,
): List<View>? {
  val path = nativePath(resolveView, presentation) ?: return null
  val token = windowRoot.windowToken ?: return null
  if (!windowRoot.isAttachedToWindow || windowRoot.rootView !== windowRoot) return null
  if (
    path.any {
      !it.isAttachedToWindow || it.windowToken !== token || it.rootView !== windowRoot
    }
  )
    return null
  return path
}

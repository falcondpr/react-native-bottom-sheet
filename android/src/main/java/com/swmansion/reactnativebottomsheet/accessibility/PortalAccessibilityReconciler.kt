package com.swmansion.reactnativebottomsheet.accessibility

import android.view.View
import android.view.ViewGroup
import java.lang.ref.WeakReference
import java.util.Collections
import java.util.IdentityHashMap

/** Applies the accessibility path cut for one nearest React Native root. */
internal class PortalAccessibilityReconciler(root: ViewGroup) {
  private val root = WeakReference(root)
  private val maskLedger = PortalAccessibilityMaskLedger()

  fun reconcile(retainedAnchors: Collection<View>): Boolean {
    val root = root.get()
    val retainedChildren = IdentityHashMap<ViewGroup, MutableSet<View>>()
    retainedAnchors.forEach { anchor ->
      val path = root?.let { pathFromRoot(anchor, it) } ?: return@forEach
      path.zipWithNext().forEach { (parent, child) ->
        val group = parent as? ViewGroup ?: return@forEach
        retainedChildren.getOrPut(group) { identitySet() }.add(child)
      }
    }
    val desiredMasks = identitySet()

    retainedChildren.forEach { (parent, retained) ->
      for (index in 0 until parent.childCount) {
        parent.getChildAt(index).takeIf { it !in retained }?.let(desiredMasks::add)
      }
    }
    maskLedger.reconcile(desiredMasks)
    return retainedChildren.isNotEmpty()
  }

  private fun pathFromRoot(anchor: View, root: ViewGroup): List<View>? {
    val reversed = mutableListOf<View>()
    var current = anchor
    while (true) {
      reversed.add(current)
      if (current === root) return reversed.asReversed()
      val parent = current.parent as? ViewGroup ?: return null
      if (parent.indexOfChild(current) < 0) return null
      current = parent
    }
  }

  private fun identitySet(): MutableSet<View> =
    Collections.newSetFromMap(IdentityHashMap<View, Boolean>())
}

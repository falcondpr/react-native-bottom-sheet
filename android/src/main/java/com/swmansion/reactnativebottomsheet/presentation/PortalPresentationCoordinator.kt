package com.swmansion.reactnativebottomsheet.presentation

import android.view.View
import android.view.ViewTreeObserver
import androidx.annotation.UiThread
import java.lang.ref.WeakReference
import java.util.WeakHashMap

internal enum class PortalPresentationAssignment {
  NONE,
  TOP,
  CLOSE_FALLBACK,
}

/** One neutral membership and native-order authority, with weak anchors, roots and observers. */
@UiThread
internal object PortalPresentationCoordinator {
  internal interface Registration {
    /** False means the hierarchy or observer expired; the controller must resolve it again. */
    fun update(isActive: Boolean): Boolean

    fun remove()
  }

  private class Entry(
    anchor: View,
    context: PortalPresentationContext,
    var isActive: Boolean,
    observer: (PortalPresentationAssignment) -> Unit,
  ) {
    val anchor = WeakReference(anchor)
    val reactRoot = WeakReference(context.reactRoot)
    val windowRoot = WeakReference(context.windowRoot)
    val windowToken = WeakReference(context.windowToken)
    val observer = WeakReference(observer)
    var isRegistered = true
    var assignment = PortalPresentationAssignment.NONE

    fun assign(value: PortalPresentationAssignment) {
      if (assignment == value) return
      assignment = value
      observer.get()?.invoke(value)
    }
  }

  private class RegistrationImpl(private val entry: Entry, root: View) : Registration {
    private val root = WeakReference(root)

    override fun update(isActive: Boolean): Boolean {
      if (!entry.isRegistered) return false
      entry.isActive = isActive
      root.get()?.let(::reconcile)
      return entry.isRegistered
    }

    override fun remove() {
      if (!entry.isRegistered) return
      entry.isRegistered = false
      entry.assign(PortalPresentationAssignment.NONE)
      root.get()?.let(::reconcile)
    }
  }

  private class WindowState(root: View) : ViewTreeObserver.OnPreDrawListener {
    val entries = mutableListOf<Entry>()
    private val root = WeakReference(root)
    private var observer: WeakReference<ViewTreeObserver>? = null

    fun observeDrawing(view: View) {
      val current = view.viewTreeObserver
      if (observer?.get() === current) return
      stopObserving()
      if (current.isAlive) {
        current.addOnPreDrawListener(this)
        observer = WeakReference(current)
      }
    }

    override fun onPreDraw(): Boolean {
      // This runs before every draw while registrations exist, so keep reconciliation cheap.
      // Z and native child order may change without layout, requiring this refresh before the
      // new order is displayed; do not derive Active from drawing.
      val view = root.get()
      if (view != null) reconcile(view) else stopObserving()
      return true
    }

    fun stopObserving() {
      observer?.get()?.takeIf { it.isAlive }?.removeOnPreDrawListener(this)
      observer = null
    }
  }

  private val windows = WeakHashMap<View, WindowState>()

  fun register(
    anchor: View,
    isActive: Boolean,
    observer: (PortalPresentationAssignment) -> Unit,
  ): Registration? {
    val context = anchor.resolvePortalPresentationContext() ?: return null
    val entry = Entry(anchor, context, isActive, observer)
    windows.getOrPut(context.windowRoot) { WindowState(context.windowRoot) }.entries.add(entry)
    reconcile(context.windowRoot)
    return RegistrationImpl(entry, context.windowRoot)
  }

  fun reconcile(root: View) {
    val window = windows[root] ?: return
    val entries = window.entries
    val contexts = mutableMapOf<Entry, PortalPresentationContext>()
    entries.toList().forEach { entry ->
      val context = entry.anchor.get()?.resolvePortalPresentationContext()
      if (
        !entry.isRegistered ||
          entry.observer.get() == null ||
          context == null ||
          context.reactRoot !== entry.reactRoot.get() ||
          context.windowRoot !== root ||
          context.windowRoot !== entry.windowRoot.get() ||
          context.windowToken !== entry.windowToken.get()
      ) {
        entry.isRegistered = false
        entry.assign(PortalPresentationAssignment.NONE)
        entries.remove(entry)
      } else if (entry.isActive) {
        contexts[entry] = context
      }
    }
    if (entries.isEmpty()) {
      window.stopObserving()
      windows.remove(root)
      return
    }
    window.observeDrawing(root)
    val top =
      contexts.keys.singleOrNull { candidate ->
        contexts.all { (other, context) ->
          candidate === other ||
            NativePortalOrderResolver.compare(contexts.getValue(candidate), context) ==
              NativePortalOrder.ABOVE
        }
      }
    val closeOwner = top ?: entries.lastOrNull { it in contexts }
    // Registration order is only a Close fallback, never evidence for Top.
    // Withdraw the previous assignment synchronously before enabling its successor.
    entries.filter { it !== closeOwner }.forEach { it.assign(PortalPresentationAssignment.NONE) }
    closeOwner?.assign(
      if (top != null) PortalPresentationAssignment.TOP
      else PortalPresentationAssignment.CLOSE_FALLBACK
    )
  }
}

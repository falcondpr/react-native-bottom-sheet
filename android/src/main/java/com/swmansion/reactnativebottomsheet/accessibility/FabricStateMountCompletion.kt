package com.swmansion.reactnativebottomsheet.accessibility

import android.os.Handler
import android.os.Looper
import androidx.annotation.UiThread
import com.facebook.react.bridge.ReactMarker
import com.facebook.react.bridge.ReactMarkerConstants
import com.facebook.react.uimanager.StateWrapper
import java.lang.ref.WeakReference

/** Exact delivery identity, independent of source IDs, surfaces and presentation ownership. */
internal class FabricStateMountCompletion {
  internal class Delivery(
    state: StateWrapper,
    private val completed: () -> Boolean,
  ) {
    private val state = WeakReference(state)

    fun accepts(current: StateWrapper?): Boolean =
      current != null && state.get() === current && completed()
  }

  private class Batch(val number: Int, var unambiguous: Boolean) {
    var completed = false
  }

  private var active = true
  private val batches = mutableListOf<Batch>()

  fun begin(number: Int) {
    if (!active) return
    // Keep outer scopes until they unwind: later nested batches remain ambiguous
    // even after an earlier nested batch ends. Dispatch cleanup abandons failures.
    batches.forEach { it.unambiguous = false }
    batches.add(Batch(number, batches.isEmpty()))
  }

  fun end(number: Int) {
    val current = batches.lastOrNull() ?: return
    if (current.number != number) {
      batches.forEach { it.unambiguous = false }
      return
    }
    batches.removeAt(batches.lastIndex)
    if (active && current.unambiguous) current.completed = true
  }

  fun capture(state: StateWrapper?): Delivery? {
    val current = batches.lastOrNull() ?: return null
    if (!active || state == null) return null
    return Delivery(state) { active && current.completed }
  }

  fun beginDispatch(): () -> Unit {
    val inheritedDepth = batches.size
    var pending = true
    return {
      if (pending) {
        pending = false
        // A nested manager may finish while an outer manager is still executing.
        while (batches.size > inheritedDepth) batches.removeAt(batches.lastIndex)
      }
    }
  }

  fun stop() {
    active = false
    batches.clear()
  }
}

/**
 * Missing execution markers (including older RN) leave State unavailable, never assumed applied.
 */
@UiThread
internal object FabricStateMountObserver {
  internal interface Observation {
    fun willMountItems()

    fun didMountItems()

    fun remove()
  }

  private var observations = 0
  private var completion: FabricStateMountCompletion? = null
  private var ready = false
  private val listener =
    object : ReactMarker.FabricMarkerListener {
      override fun logFabricMarker(
        name: ReactMarkerConstants,
        tag: String?,
        instanceKey: Int,
        timestamp: Long,
      ) {
        if (!ready || Looper.myLooper() !== Looper.getMainLooper()) return
        // Older RN defines these markers without emitting them. Missing evidence
        // stays unavailable; a callback or source ID is never a substitute.
        when (name) {
          ReactMarkerConstants.FABRIC_BATCH_EXECUTION_START -> completion?.begin(instanceKey)
          ReactMarkerConstants.FABRIC_BATCH_EXECUTION_END -> completion?.end(instanceKey)
          else -> Unit
        }
      }
    }

  fun observe(): Observation {
    if (observations++ == 0) {
      val session = FabricStateMountCompletion()
      completion = session
      ReactMarker.addFabricListener(listener)
      // Installation can happen inside a batch whose START we never saw. Begin
      // accepting evidence only after that synchronous UI execution has returned.
      Handler(Looper.getMainLooper()).post {
        if (completion === session) ready = true
      }
    }
    return object : Observation {
      private var active = true
      private var finishDispatch: (() -> Unit)? = null

      override fun willMountItems() {
        if (active && ready) finishDispatch = completion?.beginDispatch()
      }

      override fun didMountItems() {
        finishDispatch?.invoke()
        finishDispatch = null
      }

      override fun remove() {
        if (!active) return
        active = false
        finishDispatch = null
        if (--observations == 0) {
          ready = false
          ReactMarker.removeFabricListener(listener)
          completion?.stop()
          completion = null
        }
      }
    }
  }

  fun capture(state: StateWrapper?): FabricStateMountCompletion.Delivery? =
    if (ready && Looper.myLooper() === Looper.getMainLooper()) completion?.capture(state) else null
}

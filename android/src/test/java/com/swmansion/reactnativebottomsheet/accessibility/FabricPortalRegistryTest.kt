@file:OptIn(com.facebook.react.common.annotations.UnstableReactNativeAPI::class)
@file:Suppress("DEPRECATION")

package com.swmansion.reactnativebottomsheet.accessibility

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.facebook.react.bridge.BridgeReactContext
import com.facebook.react.bridge.ReactMarker
import com.facebook.react.bridge.ReactMarkerConstants
import com.facebook.react.bridge.UIManager
import com.facebook.react.bridge.UIManagerListener
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsForTests
import com.facebook.react.uimanager.StateWrapper
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.views.modal.ReactModalHostView
import com.swmansion.reactnativebottomsheet.BottomSheetView
import com.swmansion.reactnativebottomsheet.TestArgumentsShadow
import com.swmansion.reactnativebottomsheet.presentation.TestReactRoot
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], shadows = [TestArgumentsShadow::class])
class FabricPortalRegistryTest {
  @Before fun useLocalReactNativeFeatureFlags() = ReactNativeFeatureFlagsForTests.setUp()

  @Test
  fun `every supplied owner must be attached before any window receipt is accepted`() {
    Fixture().use { f ->
      val window = f.a.rootView
      assertEquals(setOf(f.a, f.b), f.read(window)?.keys)
      f.root.removeView(f.modalContent)
      assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      assertNull(f.read(window))
      f.root.addView(f.modalContent)
      assertEquals(setOf(f.a, f.b), f.read(window)?.keys)
    }
  }

  @Test
  fun `all source states need their own completed mount before a receipt is accepted`() {
    Fixture().use { f ->
      f.beginBatch(72)
      val next = f.newState()
      f.a.stateWrapper = next
      f.b.stateWrapper = next
      assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      f.endBatch(72)
      assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
    }
  }

  @Test
  fun `nested manager cleanup cannot complete a state while an outer batch remains open`() {
    Fixture().use { f ->
      var listener: UIManagerListener? = null
      val otherBoundary =
        object : ReactNativeMountCallbacks {
          override val identity = Any()
          override val isFabric = true

          override fun addListener(value: UIManagerListener) {
            listener = value
          }

          override fun removeListener(value: UIManagerListener) = Unit

          override fun enqueueAfterPaperMount(block: () -> Unit) = Unit
        }
      val otherObservation = f.adapter.observe(otherBoundary) {}
      try {
        val outer = requireNotNull(f.mountListener)
        val inner = requireNotNull(listener)
        outer.willMountItems(f.manager)
        f.beginBatch(81)
        inner.willMountItems(f.manager)
        f.beginBatch(82)
        f.endBatch(82)
        inner.didMountItems(f.manager)
        inner.willMountItems(f.manager)
        f.beginBatch(83)
        val next = f.newState()
        f.a.stateWrapper = next
        f.b.stateWrapper = next
        f.endBatch(83)
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        inner.didMountItems(f.manager)
        f.endBatch(81)
        outer.didMountItems(f.manager)
        outer.willMountItems(f.manager)
        f.beginBatch(84)
        f.a.stateWrapper = next
        f.b.stateWrapper = next
        f.endBatch(84)
        outer.didMountItems(f.manager)
        assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      } finally {
        otherObservation.remove()
      }
    }
  }

  @Test
  fun `observation installed during execution cannot borrow an unseen outer batch end`() {
    Fixture(attachToWindow = false).use { f ->
      f.observation.remove()
      f.beginBatch(71)
      val nextObservation = f.adapter.observe(f.boundary) {}
      try {
        f.beginBatch(71)
        val next = f.newState()
        f.a.stateWrapper = next
        f.b.stateWrapper = next
        // The nested batch aborts without END or dispatch cleanup; only outer A ends.
        f.endBatch(71)
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        f.beginBatch(72)
        val completed = f.newState()
        f.a.stateWrapper = completed
        f.b.stateWrapper = completed
        f.endBatch(72)
        assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      } finally {
        nextObservation.remove()
      }
    }
  }

  @Test
  fun `queued activation from a removed observation cannot arm its replacement`() {
    Fixture(attachToWindow = false).use { f ->
      f.observation.remove()
      f.adapter.observe(f.boundary) {}.remove()
      val replacement = f.adapter.observe(f.boundary) {}
      try {
        // Run the old session's task, leaving the replacement's task queued.
        shadowOf(Looper.getMainLooper()).runOneTask()
        f.beginBatch(71)
        val early = f.newState()
        f.a.stateWrapper = early
        f.b.stateWrapper = early
        f.endBatch(71)
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        f.beginBatch(72)
        val completed = f.newState()
        f.a.stateWrapper = completed
        f.b.stateWrapper = completed
        f.endBatch(72)
        assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      } finally {
        replacement.remove()
      }
    }
  }

  @Test
  fun `ending the last observation requires a fresh completed state on reobservation`() {
    Fixture(attachToWindow = false).use { f ->
      assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      f.observation.remove()
      assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      val nextObservation = f.adapter.observe(f.boundary) {}
      try {
        assertNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
        shadowOf(Looper.getMainLooper()).idle()
        f.beginBatch(71)
        val next = f.newState()
        f.a.stateWrapper = next
        f.b.stateWrapper = next
        f.endBatch(71)
        assertNotNull(f.source.receiptFromRegistry(f.manager, 2, f.a))
      } finally {
        nextObservation.remove()
      }
    }
  }

  private class Fixture(attachToWindow: Boolean = true) : AutoCloseable {
    val activity = Robolectric.buildActivity(Activity::class.java).setup()
    val context = BridgeReactContext(activity.get().applicationContext)
    val themed = ThemedReactContext(context, activity.get(), "test", 2)
    val root = TestReactRoot(activity.get()).apply { id = 2 }
    val areaA = FrameLayout(activity.get()).apply { id = 11 }
    val areaB = FrameLayout(activity.get()).apply { id = 21 }
    val hostA = host(13)
    val hostB = host(23)
    val a = BottomSheetView(themed).apply { id = 14 }
    val b = BottomSheetView(themed).apply { id = 24 }
    val modal = ReactModalHostView(themed).apply { id = 30 }
    val modalContent: ViewGroup
    val registry =
      mutableMapOf<Int, View>(
        2 to root,
        11 to areaA,
        13 to hostA,
        14 to a,
        21 to areaB,
        23 to hostB,
        24 to b,
        30 to modal,
      )
    val manager =
      Proxy.newProxyInstance(
        UIManager::class.java.classLoader,
        arrayOf(UIManager::class.java),
      ) { _, method, args ->
        if (method.name == "resolveView") registry[args!![0] as Int] else null
      } as UIManager
    val source =
      object : FabricPublicationLease {
        override fun bootstrap() = Unit

        override fun release() = Unit

        override fun sheetTags(surfaceId: Int, tag: Int, state: StateWrapper?) = intArrayOf(14, 24)

        override fun receipt(
          surfaceId: Int,
          tag: Int,
          states: Map<Int, StateWrapper?>,
        ): FabricPortalReceipt? {
          if (states.keys != setOf(14, 24) || states.values.any { it == null }) return null
          return FabricPortalReceipt(
            "source:1",
            if (tag == 14) 13 else 23,
            intArrayOf(if (tag == 14) 11 else 21),
            if (tag == 14) intArrayOf(14, 13, 11, 2) else intArrayOf(24, 23, 21, 30),
            intArrayOf(2, 11, 13, 14, 21, 23, 24, 30),
            intArrayOf(2, 0, 11, 2, 13, 11, 14, 13, 30, 2, 21, 30, 23, 21, 24, 23),
          )
        }
      }
    var mountListener: UIManagerListener? = null
    val boundary =
      object : ReactNativeMountCallbacks {
        override val identity: Any = manager
        override val isFabric = true

        override fun addListener(listener: UIManagerListener) {
          mountListener = listener
        }

        override fun removeListener(listener: UIManagerListener) {
          mountListener = null
        }

        override fun enqueueAfterPaperMount(block: () -> Unit) = Unit
      }
    val adapter =
      ReactNativeMountReconciliationAdapter(
        postToUiThread = { it.run() },
        acquirePublicationSource = { source },
      )
    val observation = adapter.observe(boundary) {}

    init {
      shadowOf(Looper.getMainLooper()).idle()
      val state = newState()
      beginBatch(71)
      a.stateWrapper = state
      b.stateWrapper = state
      endBatch(71)
      hostA.addView(a)
      areaA.addView(hostA)
      hostB.addView(b)
      areaB.addView(hostB)
      modal.addView(areaB, 0)
      modalContent = areaB.parent as ViewGroup
      root.addView(areaA)
      root.addView(modal)
      root.addView(modalContent)
      if (attachToWindow) activity.get().setContentView(root)
    }

    fun read(window: View, owners: Collection<BottomSheetView> = listOf(a, b)) =
      source.attachedReceiptsFromRegistry(manager, 2, owners, window)

    fun newState() =
      Proxy.newProxyInstance(
        StateWrapper::class.java.classLoader,
        arrayOf(StateWrapper::class.java),
      ) { _, _, _ ->
        null
      } as StateWrapper

    fun beginBatch(number: Int) =
      ReactMarker.logFabricMarker(
        ReactMarkerConstants.FABRIC_BATCH_EXECUTION_START,
        null,
        number,
      )

    fun endBatch(number: Int) =
      ReactMarker.logFabricMarker(
        ReactMarkerConstants.FABRIC_BATCH_EXECUTION_END,
        null,
        number,
      )

    private fun host(tag: Int) =
      FrameLayout(activity.get()).apply {
        id = tag
        setTag(
          com.facebook.react.R.id.view_tag_native_id,
          "__react_native_bottom_sheet_portal_host",
        )
      }

    override fun close() {
      observation.remove()
      a.destroy()
      b.destroy()
      modal.onDropInstance()
      activity.close()
    }
  }
}

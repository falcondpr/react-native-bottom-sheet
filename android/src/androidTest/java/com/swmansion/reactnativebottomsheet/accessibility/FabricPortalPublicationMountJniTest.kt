@file:OptIn(com.facebook.react.common.annotations.UnstableReactNativeAPI::class)

package com.swmansion.reactnativebottomsheet.accessibility

import android.view.View
import android.view.ViewGroup
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint
import com.facebook.react.defaults.DefaultReactHost
import com.facebook.react.fabric.FabricUIManager
import com.facebook.react.interfaces.TaskInterface
import com.facebook.react.shell.MainReactPackage
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.react.uimanager.StateWrapper
import com.facebook.soloader.SoLoader
import com.swmansion.reactnativebottomsheet.BottomSheetPackage
import com.swmansion.reactnativebottomsheet.BottomSheetView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith

/** Runs alone with the app's actual codegen registration; no Activity or window is created. */
@RunWith(AndroidJUnit4::class)
class FabricPortalPublicationMountJniTest {
  @Test
  fun reobservingMountedSheetBootstrapsNewPublicationUntilItsSurfaceStops() {
    val context = InstrumentationRegistry.getInstrumentation().context
    val mounted = CountDownLatch(1)
    val refreshed = CountDownLatch(1)
    var awaitedPublication = mounted
    val failure = AtomicReference<Throwable?>()
    val host =
      DefaultReactHost.getDefaultReactHost(
        context,
        listOf(MainReactPackage(), BottomSheetPackage()),
        jsBundleAssetPath = "publication-mount.bundle",
        useDevSupport = false,
        exceptionHandler = {
          failure.set(it)
          mounted.countDown()
          refreshed.countDown()
        },
      )
    val surface = host.createSurface(context, "MountedPublication", null)
    val root = requireNotNull(surface.view)
    var lease: FabricPublicationLease? = null
    val adapter =
      ReactNativeMountReconciliationAdapter(
        acquirePublicationSource = { FabricPortalPublication.acquire(it).also { lease = it } }
      )
    var observation: ReactNativeMountReconciliationAdapter.Observation? = null
    var deliveredState: StateWrapper? = null
    var sheetTag = View.NO_ID
    var mountedSheet: BottomSheetView? = null
    var publicationId: String? = null
    lateinit var verifyMountedState: () -> Unit
    var started = false
    try {
      await(host.start())
      onMain {
        val size = View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY)
        root.measure(size, size)
        root.layout(0, 0, 640, 640)
        val boundary = requireNotNull(ReactNativeMountReconciliationAdapter.resolve(root))
        val manager = boundary.identity as FabricUIManager
        verifyMountedState = verify@{
          if (awaitedPublication.count == 0L) return@verify
          try {
            val views = descendants(root)
            val sheet = views.filterIsInstance<BottomSheetView>().singleOrNull() ?: return@verify
            val area = views.single { it.tag == "local-area" }
            val portalHost = views.single {
              it.getTag(com.facebook.react.R.id.view_tag_native_id) ==
                "__react_native_bottom_sheet_portal_host"
            }
            assertSame(sheet, manager.resolveView(sheet.id))
            assertFalse(root.isAttachedToWindow)
            assertFalse(sheet.isAttachedToWindow)
            if (mountedSheet != null) assertSame(mountedSheet, sheet)
            mountedSheet = sheet
            deliveredState = requireNotNull(sheet.stateWrapper)
            sheetTag = sheet.id
            val receipt =
              requireNotNull(lease).receipt(surface.surfaceID, sheetTag, deliveredState)
                ?: return@verify
            assertTrue(receipt.publicationId.isNotEmpty())
            assertEquals(portalHost.id, receipt.hostTag)
            assertEquals(listOf(area.id), receipt.contexts)
            publicationId = receipt.publicationId
            awaitedPublication.countDown()
          } catch (caught: Throwable) {
            failure.set(caught)
            awaitedPublication.countDown()
          }
        }
        observation = adapter.observe(boundary, verifyMountedState)
        host.onHostResume(null)
      }
      // Drain acquisition/bootstrap before React starts its first render.
      onMain { assertNotNull(lease) }
      await(surface.start())
      started = true
      assertTrue("Production State delivery timed out", mounted.await(20, TimeUnit.SECONDS))
      failure.get()?.let { throw it }
      val firstPublicationId = requireNotNull(publicationId)
      val firstState = requireNotNull(deliveredState)
      val firstSource = requireNotNull(lease)
      onMain {
        observation?.remove()
        observation = null
      }
      onMain {
        // The queued release ran first. Keep the mounted surface and its JS tree unchanged.
        assertNull(firstSource.receipt(surface.surfaceID, sheetTag, firstState))
        awaitedPublication = refreshed
        observation =
          adapter.observe(
            requireNotNull(ReactNativeMountReconciliationAdapter.resolve(root)),
            verifyMountedState,
          )
      }
      onMain {
        assertNotSame(firstSource, lease)
        assertNull(requireNotNull(lease).receipt(surface.surfaceID, sheetTag, firstState))
      }
      assertTrue(
        "Reobserved mounted State delivery timed out",
        refreshed.await(20, TimeUnit.SECONDS),
      )
      failure.get()?.let { throw it }
      assertNotEquals(firstPublicationId, publicationId)
      await(surface.stop())
      started = false
      onMain {
        assertNull(requireNotNull(lease).receipt(surface.surfaceID, sheetTag, deliveredState))
      }
    } finally {
      try {
        onMain {
          observation?.remove()
          host.onHostPause()
        }
        onMain {} // Drain the final native release before SDK teardown.
        if (started) await(surface.stop())
      } finally {
        await(host.destroy("Publication mount test", null))
      }
    }
  }

  private fun descendants(view: View): List<View> =
    listOf(view) +
      if (view is ViewGroup) {
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
      } else emptyList()

  private fun await(task: TaskInterface<Void>) {
    assertTrue("ReactHost lifecycle timed out", task.waitForCompletion(20, TimeUnit.SECONDS))
    task.getError()?.let { throw it }
    assertFalse(task.isCancelled())
  }

  private fun onMain(block: () -> Unit) {
    var failure: Throwable? = null
    InstrumentationRegistry.getInstrumentation().runOnMainSync {
      try {
        block()
      } catch (caught: Throwable) {
        failure = caught
      }
    }
    failure?.let { throw it }
  }

  companion object {
    @BeforeClass
    @JvmStatic
    fun initializeSdk() {
      assumeTrue(
        InstrumentationRegistry.getArguments().getString("bottomSheetPublicationMountJni") == "true"
      )
      SoLoader.init(InstrumentationRegistry.getInstrumentation().context, OpenSourceMergedSoMapping)
      DefaultNewArchitectureEntryPoint.load()
    }
  }
}

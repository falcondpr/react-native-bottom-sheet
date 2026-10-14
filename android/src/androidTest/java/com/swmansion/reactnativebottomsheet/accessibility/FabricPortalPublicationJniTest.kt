package com.swmansion.reactnativebottomsheet.accessibility

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.facebook.jni.HybridData
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.react.uimanager.StateWrapper
import com.facebook.soloader.SoLoader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith

/** No Activity or React app is launched: this tests the actual Kotlin/JNI boundary. */
@RunWith(AndroidJUnit4::class)
class FabricPortalPublicationJniTest {
  @Test
  fun bootstrappedDeliveredStateCrossesJniAndReleasedResourceStopsServingReceipts() = onMain {
    FabricPublicationJniFixture.create().use { fixture ->
      val lease = fixture.lease()
      try {
        assertNull(fixture.takeDeliveredState())
        lease.bootstrap()
        val state = requireNotNull(fixture.takeDeliveredState())
        try {
          val receipt = requireNotNull(lease.receipt(1, 14, state))
          assertTrue(receipt.publicationId.isNotEmpty())
          assertEquals(13, receipt.hostTag)
          assertEquals(listOf(11), receipt.contexts)
          assertNull(lease.receipt(2, 14, state))
          assertNull(lease.receipt(1, 99, state))
          state.destroyState()
          assertNull(lease.receipt(1, 14, state))
          lease.release()
          lease.release()
          lease.bootstrap()
          fixture.moveHost(31)
          assertNull(fixture.takeDeliveredState())
          assertNull(lease.receipt(1, 14, state))
        } finally {
          state.destroyState()
        }
      } finally {
        lease.release()
      }
    }
  }

  @Test
  fun delayedWrapperKeepsItsDeliveredContextAfterNewerFabricState() = onMain {
    FabricPublicationJniFixture.create().use { fixture ->
      val lease = fixture.lease()
      var delayed: StateWrapper? = null
      var current: StateWrapper? = null
      try {
        lease.bootstrap()
        delayed = requireNotNull(fixture.takeDeliveredState())
        fixture.moveHost(31)
        current = requireNotNull(fixture.takeDeliveredState())
        val oldReceipt = requireNotNull(lease.receipt(1, 14, delayed))
        val newReceipt = requireNotNull(lease.receipt(1, 14, current))
        assertNotEquals(oldReceipt.publicationId, newReceipt.publicationId)
        assertEquals(listOf(11), oldReceipt.contexts)
        assertEquals(listOf(31), newReceipt.contexts)
        lease.release()
        assertNull(lease.receipt(1, 14, current))
      } finally {
        delayed?.destroyState()
        current?.destroyState()
        lease.release()
      }
    }
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
    fun loadNativeBoundary() {
      assumeTrue(
        InstrumentationRegistry.getArguments().getString("bottomSheetPublicationJni") == "true"
      )
      SoLoader.init(InstrumentationRegistry.getInstrumentation().context, OpenSourceMergedSoMapping)
      SoLoader.loadLibrary("fabricjni")
      System.loadLibrary("bottomsheet_publication_jni_test")
    }
  }
}

internal class FabricPublicationJniFixture
private constructor(private val mHybridData: HybridData) : AutoCloseable {
  external fun lease(): FabricPublicationLease

  external fun takeDeliveredState(): StateWrapper?

  external fun moveHost(context: Int)

  override fun close() = mHybridData.resetNative()

  companion object {
    @JvmStatic external fun create(): FabricPublicationJniFixture
  }
}

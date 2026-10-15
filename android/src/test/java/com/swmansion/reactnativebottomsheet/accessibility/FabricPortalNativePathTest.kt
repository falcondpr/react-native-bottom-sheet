@file:Suppress("DEPRECATION")

package com.swmansion.reactnativebottomsheet.accessibility

import android.app.Activity
import android.view.View
import android.widget.FrameLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.facebook.react.bridge.BridgeReactContext
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsForTests
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.views.modal.ReactModalHostView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class FabricPortalNativePathTest {
  @Before fun useLocalReactNativeFeatureFlags() = ReactNativeFeatureFlagsForTests.setUp()

  @Test
  fun `flattened source ancestors stay logical while native wrappers preserve the physical path`() {
    Fixture().use { f ->
      assertEquals(
        listOf(f.sheet, f.wrapper, f.host, f.area, f.root),
        f.receipt.nativePath(f.registry::get, f.sheet),
      )
    }
  }

  @Test
  fun `a registered view cannot substitute a different source tag`() {
    Fixture().use { f ->
      f.area.id = 99
      f.registry[99] = f.area
      assertNull(f.receipt.nativePath(f.registry::get, f.sheet))
    }
  }

  @Test
  fun `RN Modal redirected children identify the physical container without its off-window JSX parent`() {
    Fixture().use { f ->
      val reactContext = BridgeReactContext(f.activity.get().applicationContext)
      val themedContext = ThemedReactContext(reactContext, f.activity.get(), "test", 1)
      val modal = ReactModalHostView(themedContext).apply { id = 30 }
      (f.root.parent as android.view.ViewGroup).removeView(f.root)
      modal.addView(f.root, 0)
      val container = f.root.parent as android.view.ViewGroup
      f.activity.get().setContentView(container)
      f.registry[30] = modal
      val receipt =
        FabricPortalReceipt("source:1", 13, intArrayOf(11), intArrayOf(14, 13, 31, 11, 2, 30))

      assertEquals(
        listOf(f.sheet, f.wrapper, f.host, f.area, f.root, container),
        receipt.nativePath(f.registry::get, f.sheet),
      )
      container.removeView(f.root)
      val impostor = FrameLayout(f.activity.get()).apply { id = 30 }
      impostor.addView(f.root)
      f.activity.get().setContentView(impostor)
      assertNull(receipt.nativePath(f.registry::get, f.sheet))
    }
  }

  @Test
  fun `a materialized logical ancestor cannot be skipped as a flattened wrapper`() {
    Fixture().use { f ->
      f.registry[31] = FrameLayout(f.activity.get()).apply { id = 31 }
      assertNull(f.receipt.nativePath(f.registry::get, f.sheet))
    }
  }

  @Test
  fun `the registered host must be the actual marked native instance`() {
    Fixture().use { f ->
      f.host.setTag(com.facebook.react.R.id.view_tag_native_id, null)
      assertNull(f.receipt.nativePath(f.registry::get, f.sheet))
      f.host.setTag(
        com.facebook.react.R.id.view_tag_native_id,
        "__react_native_bottom_sheet_portal_host",
      )
      f.registry[13] = FrameLayout(f.activity.get()).apply { id = 13 }
      assertNull(f.receipt.nativePath(f.registry::get, f.sheet))
    }
  }

  @Test
  fun `attachment and the expected window remain separate from source ancestry after migration`() {
    Fixture().use { f ->
      val expected = listOf(f.sheet, f.wrapper, f.host, f.area, f.root)
      val firstWindow = f.sheet.rootView
      assertEquals(expected, f.receipt.attachedNativePath(f.registry::get, f.sheet, firstWindow))
      (f.root.parent as android.view.ViewGroup).removeView(f.root)
      assertEquals(expected, f.receipt.nativePath(f.registry::get, f.sheet))
      assertNull(f.receipt.attachedNativePath(f.registry::get, f.sheet, firstWindow))
      val second = Robolectric.buildActivity(Activity::class.java).setup()
      try {
        second.get().setContentView(f.root)
        assertNull(f.receipt.attachedNativePath(f.registry::get, f.sheet, firstWindow))
        assertEquals(
          expected,
          f.receipt.attachedNativePath(f.registry::get, f.sheet, f.sheet.rootView),
        )
      } finally {
        second.close()
      }
    }
  }

  private class Fixture : AutoCloseable {
    val activity = Robolectric.buildActivity(Activity::class.java).setup()
    val root = FrameLayout(activity.get()).apply { id = 2 }
    val area = FrameLayout(activity.get()).apply { id = 11 }
    val host =
      FrameLayout(activity.get()).apply {
        id = 13
        setTag(
          com.facebook.react.R.id.view_tag_native_id,
          "__react_native_bottom_sheet_portal_host",
        )
      }
    val wrapper = FrameLayout(activity.get())
    val sheet = View(activity.get()).apply { id = 14 }
    val registry = mutableMapOf<Int, View>(2 to root, 11 to area, 13 to host, 14 to sheet)
    val receipt = FabricPortalReceipt("source:1", 13, intArrayOf(11), intArrayOf(14, 13, 31, 11, 2))

    init {
      wrapper.addView(sheet)
      host.addView(wrapper)
      area.addView(host)
      root.addView(area)
      activity.get().setContentView(root)
    }

    override fun close() = activity.close()
  }
}

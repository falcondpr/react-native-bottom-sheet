package com.swmansion.reactnativebottomsheet

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsForTests
import com.swmansion.reactnativebottomsheet.presentation.TestReactRoot
import java.util.Collections
import java.util.IdentityHashMap
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class BottomSheetViewPortalAccessibilityTest {
  @Before
  fun useLocalReactNativeFeatureFlags() {
    ReactNativeFeatureFlagsForTests.setUp()
  }

  @Test
  fun `Active portal excludes background while sheet content and real Dismiss remain reachable`() {
    val activity = Robolectric.buildActivity(Activity::class.java).setup()
    val sheet = BottomSheetView(activity.get())
    try {
      val root = TestReactRoot(activity.get())
      val background =
        View(activity.get()).apply {
          importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
          contentDescription = "Application control"
        }
      val portalWrapper = FrameLayout(activity.get())
      val sheetContent =
        View(activity.get()).apply {
          importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
          contentDescription = "Sheet content"
        }
      sheet.apply {
        animateIn = false
        modal = true
        setDetents(
          listOf(
            mapOf("value" to 0.0, "kind" to "points", "programmatic" to false),
            mapOf("value" to 300.0, "kind" to "points", "programmatic" to false),
          )
        )
        setIndex(1)
        addSheetChild(sheetContent, 0)
      }
      portalWrapper.addView(sheet, matchParent())
      root.addView(background, matchParent())
      root.addView(portalWrapper, matchParent())
      activity.get().setContentView(root)
      layout(root)
      val host = sheet.getChildAt(0) as ViewGroup
      val dismiss = host.getChildAt(0)

      val activeTree = accessibleTree(root)
      assertFalse(activeTree.contains(background))
      assertTrue(activeTree.contains(sheetContent))
      assertTrue(activeTree.contains(dismiss))

      sheet.modal = false

      assertTrue(accessibleTree(root).contains(background))
    } finally {
      sheet.destroy()
      activity.close()
    }
  }

  private fun accessibleTree(root: ViewGroup): Set<View> {
    val result = Collections.newSetFromMap(IdentityHashMap<View, Boolean>())
    fun visit(parent: ViewGroup) {
      val children = arrayListOf<View>()
      parent.addChildrenForAccessibility(children)
      children.forEach { child ->
        if (result.add(child) && child is ViewGroup) visit(child)
      }
    }
    visit(root)
    return result
  }

  private fun layout(view: View) {
    view.measure(
      View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY),
    )
    view.layout(0, 0, 1080, 1920)
    shadowOf(Looper.getMainLooper()).idle()
  }

  private fun matchParent() =
    ViewGroup.LayoutParams(
      ViewGroup.LayoutParams.MATCH_PARENT,
      ViewGroup.LayoutParams.MATCH_PARENT,
    )
}

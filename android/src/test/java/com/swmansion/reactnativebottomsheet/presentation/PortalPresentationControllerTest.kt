package com.swmansion.reactnativebottomsheet.presentation

import android.app.Activity
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class PortalPresentationControllerTest {
  @Test
  fun `hierarchy sync refreshes the path and withdraws old root before joining another`() {
    val activity = Robolectric.buildActivity(Activity::class.java).setup()
    try {
      val container = FrameLayout(activity.get())
      val firstRoot = TestReactRoot(activity.get())
      val secondRoot = TestReactRoot(activity.get())
      val branch = FrameLayout(activity.get())
      val anchor = View(activity.get())
      firstRoot.addView(anchor)
      firstRoot.addView(branch)
      container.addView(firstRoot)
      container.addView(secondRoot)
      activity.get().setContentView(container)
      var current: PortalPresentationContext? = null
      val assignments = mutableListOf<Pair<ViewGroup?, PortalPresentationAssignment>>()
      val controller =
        PortalPresentationController(anchor) { context, assignment ->
          current = context
          assignments.add(context?.reactRoot to assignment)
        }
      controller.update(isPortal = true, isActive = true)
      firstRoot.removeView(anchor)
      branch.addView(anchor)
      controller.syncHierarchy()
      assertEquals(listOf(firstRoot, branch, anchor), current?.path)

      assignments.clear()
      branch.removeView(anchor)
      secondRoot.addView(anchor)
      controller.scheduleHierarchySync()
      shadowOf(Looper.getMainLooper()).idle()
      assertSame(secondRoot, current?.reactRoot)
      val oldRelease = assignments.indexOf(firstRoot to PortalPresentationAssignment.NONE)
      val newClaim = assignments.indexOf(secondRoot to PortalPresentationAssignment.TOP)
      assertTrue(oldRelease >= 0 && newClaim > oldRelease)

      controller.scheduleHierarchySync()
      controller.clear()
      shadowOf(Looper.getMainLooper()).idle()
      assertNull(current)
      controller.dispose()
    } finally {
      activity.close()
    }
  }

  @Test
  fun `only an attached portal registers and clear and dispose withdraw synchronously`() {
    val activity = Robolectric.buildActivity(Activity::class.java).setup()
    try {
      val root = TestReactRoot(activity.get())
      val anchor = View(activity.get())
      var context: PortalPresentationContext? = null
      var assignment = PortalPresentationAssignment.NONE
      val controller =
        PortalPresentationController(anchor) { resolved, selected ->
          context = resolved
          assignment = selected
        }
      controller.update(isPortal = true, isActive = true)
      assertNull(context)
      root.addView(anchor)
      activity.get().setContentView(root)
      controller.syncHierarchy()
      assertEquals(PortalPresentationAssignment.TOP, assignment)
      controller.update(isPortal = false, isActive = true)
      assertNull(context)
      assertEquals(PortalPresentationAssignment.NONE, assignment)
      controller.update(isPortal = true, isActive = true)
      controller.clear()
      assertNull(context)
      controller.update(isPortal = true, isActive = true)
      controller.dispose()
      controller.update(isPortal = true, isActive = true)
      assertNull(context)
      assertEquals(PortalPresentationAssignment.NONE, assignment)
    } finally {
      activity.close()
    }
  }
}

package com.swmansion.reactnativebottomsheet

import android.app.Activity
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ColorDrawable
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsForTests
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35], qualifiers = "w600dp-h1000dp-mdpi")
class BottomSheetHostViewScrimTest {
  @Before
  fun useLocalReactNativeFeatureFlags() {
    ReactNativeFeatureFlagsForTests.setUp()
  }

  @Test
  fun `host keeps full size visual and dismiss layers below sheet content`() {
    withActivity { activity ->
      val host = configuredHost(activity)
      val sheetChild = View(activity)
      host.addSheetChild(sheetChild, 0)
      val color = Color.argb(128, 12, 34, 56)
      host.setScrimColor(color)
      host.setScrimOpacities(listOf(0f, 0.4f))
      activity.setContentView(host)
      layout(host)

      val visualScrim = visualScrim(host)
      val dismiss = dismissAccessibilityView(host)
      val sheetContainer = sheetContainer(host)
      assertEquals(3, host.childCount)
      assertSame(visualScrim, host.getChildAt(0))
      assertSame(dismiss, host.getChildAt(1))
      assertSame(sheetContainer, host.getChildAt(2))
      assertSame(sheetChild, host.getSheetChildAt(0))
      assertEquals(1, host.sheetChildCount)
      assertEquals(HOST_WIDTH, visualScrim.width)
      assertEquals(HOST_HEIGHT, visualScrim.height)
      assertEquals(HOST_WIDTH, dismiss.width)
      assertEquals(HOST_HEIGHT, dismiss.height)
      assertEquals(color, (visualScrim.background as ColorDrawable).color)
      assertEquals(0.4f, visualScrim.alpha, 0.001f)
      assertEquals(View.VISIBLE, visualScrim.visibility)
      assertEquals(null, dismiss.background)
      assertEquals(1f, dismiss.alpha, 0f)
      assertEquals(0f, dismiss.pivotY, 0f)

      host.setScrimOpacities(listOf(0f, 0.7f))
      assertEquals(0.7f, visualScrim.alpha, 0.001f)
      assertEquals(1f, dismiss.alpha, 0f)
      assertFalse(visualScrim.isLayoutRequested)
      assertFalse(dismiss.isLayoutRequested)
    }
  }

  @Test
  fun `accessibility tree excludes visual scrim and contains sheet content then Dismiss`() {
    withActivity { activity ->
      val host = configuredHost(activity)
      val sheetChild =
        View(activity).apply {
          importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
          contentDescription = "Sheet content"
        }
      host.addSheetChild(sheetChild, 0)
      activity.setContentView(host)
      layout(host)

      val hostAccessibleChildren = arrayListOf<View>()
      host.addChildrenForAccessibility(hostAccessibleChildren)
      val sheetAccessibleChildren = arrayListOf<View>()
      sheetContainer(host).addChildrenForAccessibility(sheetAccessibleChildren)

      assertEquals(2, hostAccessibleChildren.size)
      assertFalse(hostAccessibleChildren.contains(visualScrim(host)))
      assertTrue(hostAccessibleChildren.contains(dismissAccessibilityView(host)))
      assertTrue(hostAccessibleChildren.contains(sheetContainer(host)))
      assertTrue(sheetAccessibleChildren.contains(sheetChild))
      assertEquals(
        sheetContainer(host).createAccessibilityNodeInfo(),
        dismissAccessibilityView(host).createAccessibilityNodeInfo().traversalAfter,
      )
      assertEquals(
        sheetContainer(host).id,
        dismissAccessibilityView(host).accessibilityTraversalAfter,
      )
    }
  }

  @Test
  fun `Dismiss default node and transformed view end at stable sheet top`() {
    withActivity { activity ->
      val host = configuredHost(activity)
      activity.setContentView(host)
      layout(host)
      val visualScrim = visualScrim(host)
      val dismiss = dismissAccessibilityView(host)
      val node = dismiss.createAccessibilityNodeInfo()
      val nodeBounds = Rect()
      val viewBounds = Rect()
      node.getBoundsInScreen(nodeBounds)
      dismiss.getGlobalVisibleRect(viewBounds)
      val expectedBottom =
        HOST_HEIGHT - (OPEN_DETENT_DP * activity.resources.displayMetrics.density).roundToInt()
      val expectedBounds = Rect(0, 0, HOST_WIDTH, expectedBottom)

      assertEquals("android.widget.Button", node.className)
      assertEquals("Dismiss", node.contentDescription)
      assertTrue(node.isClickable)
      assertTrue(node.isDismissable)
      assertTrue(node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_CLICK })
      assertTrue(node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_DISMISS })
      assertEquals(expectedBounds, nodeBounds)
      assertEquals(expectedBounds, viewBounds)
      assertEquals(expectedBottom.toFloat() / HOST_HEIGHT, dismiss.scaleY, 0.001f)
      assertEquals(sheetContainer(host).id, dismiss.accessibilityTraversalAfter)
      assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, dismiss.importantForAccessibility)
      assertTrue(dismiss.isFocusable)
      assertTrue(dismiss.isClickable)

      assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, visualScrim.importantForAccessibility)
      assertEquals(null, visualScrim.contentDescription)
      assertFalse(visualScrim.isFocusable)
      assertFalse(visualScrim.isClickable)
      assertFalse(visualScrim.createAccessibilityNodeInfo().isDismissable)
    }
  }

  @Test
  fun `accessibility click and dismiss each snap closed without a close request`() {
    val accessibilityActions =
      listOf(AccessibilityNodeInfo.ACTION_CLICK, AccessibilityNodeInfo.ACTION_DISMISS)
    accessibilityActions.forEach { action ->
      withActivity { activity ->
        val listener = RecordingListener()
        val host = configuredHost(activity, listener = listener)
        activity.setContentView(host)
        layout(host)

        val dismiss = dismissAccessibilityView(host)
        assertTrue(dismiss.performAccessibilityAction(action, null))
        assertEquals(listOf(0), listener.indexChanges)
        assertEquals(0, listener.closeRequestCount)
        assertFalse(dismiss.isClickable)
      }
    }
  }

  @Test
  fun `confirm keys on focused Dismiss control each snap closed exactly once`() {
    val confirmKeys =
      listOf(KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_DPAD_CENTER)
    confirmKeys.forEach { keyCode ->
      withActivity { activity ->
        val listener = RecordingListener()
        val host = configuredHost(activity, listener = listener)
        activity.setContentView(host)
        layout(host)
        val dismiss = dismissAccessibilityView(host)
        assertTrue(dismiss.requestFocus())

        assertTrue(host.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode)))
        assertTrue(host.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode)))

        assertEquals(listOf(0), listener.indexChanges)
        assertEquals(0, listener.closeRequestCount)
      }
    }
  }

  @Test
  fun `focused sheet content receives confirm keys regardless of Dismiss control availability`() {
    listOf(false, true).forEach { modal ->
      withActivity { activity ->
        val host = configuredHost(activity, modal = modal)
        var downCount = 0
        val sheetChild =
          object : View(activity) {
              override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
                downCount++
                return true
              }
            }
            .apply { isFocusableInTouchMode = true }
        host.addSheetChild(sheetChild, 0)
        activity.setContentView(host)
        sheetChild.measure(
          View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.EXACTLY),
          View.MeasureSpec.makeMeasureSpec(100, View.MeasureSpec.EXACTLY),
        )
        layout(host)
        assertTrue(sheetChild.requestFocus())

        host.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A))
        assertEquals("Control: A reaches content when modal=$modal", 1, downCount)
        listOf(KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_DPAD_CENTER)
          .forEachIndexed { index, keyCode ->
            host.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            assertEquals("Confirm key must reach content when modal=$modal", index + 2, downCount)
          }
      }
    }
  }

  @Test
  fun `host dismisses a scrim tap while sheet content keeps its own touch`() {
    withActivity { activity ->
      val listener = RecordingListener()
      val host = configuredHost(activity, listener = listener)
      activity.setContentView(host)
      layout(host)

      dispatchTap(host, y = 100f)

      assertEquals(listOf(0), listener.indexChanges)
      assertEquals(0, listener.closeRequestCount)
    }

    withActivity { activity ->
      val listener = RecordingListener()
      var contentTouchCount = 0
      val content =
        object : View(activity) {
          override fun onTouchEvent(event: MotionEvent): Boolean {
            contentTouchCount++
            return true
          }
        }
      val host = configuredHost(activity, listener = listener)
      host.addSheetChild(content, 0)
      val openDetentPx = (OPEN_DETENT_DP * activity.resources.displayMetrics.density).roundToInt()
      content.measure(
        View.MeasureSpec.makeMeasureSpec(HOST_WIDTH, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(openDetentPx, View.MeasureSpec.EXACTLY),
      )
      activity.setContentView(host)
      layout(host)

      dispatchTap(host, y = HOST_HEIGHT - openDetentPx / 2f)

      assertEquals(2, contentTouchCount)
      assertTrue(listener.indexChanges.isEmpty())
      assertFalse(visualScrim(host).onTouchEvent(motionEvent(MotionEvent.ACTION_DOWN, 100f)))
      assertFalse(
        dismissAccessibilityView(host).onTouchEvent(motionEvent(MotionEvent.ACTION_DOWN, 100f))
      )
    }
  }

  @Test
  fun `Dismiss requires positive stable geometry and direct dismissal`() {
    listOf(
        HostState(modal = false),
        HostState(index = 0),
        HostState(openDetent = 1.0, openDetentKind = "percentage"),
        HostState(openDetent = 2_000.0),
        HostState(closedDetentProgrammatic = true),
        HostState(scrimOpacity = 0f),
        HostState(includeClosedDetent = false, index = 0),
      )
      .forEach { state ->
        withActivity { activity ->
          val listener = RecordingListener()
          val host =
            configuredHost(
              activity,
              listener = listener,
              modal = state.modal,
              index = state.index,
              openDetent = state.openDetent,
              openDetentKind = state.openDetentKind,
              closedDetentProgrammatic = state.closedDetentProgrammatic,
              scrimOpacity = state.scrimOpacity,
              includeClosedDetent = state.includeClosedDetent,
            )
          val dismissBeforeLayout = dismissAccessibilityView(host)
          assertEquals(0f, dismissBeforeLayout.scaleY, 0f)
          assertEquals(View.INVISIBLE, dismissBeforeLayout.visibility)
          assertEquals(
            View.IMPORTANT_FOR_ACCESSIBILITY_NO,
            dismissBeforeLayout.importantForAccessibility,
          )
          activity.setContentView(host)
          layout(host)
          val dismiss = dismissAccessibilityView(host)

          assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, dismiss.importantForAccessibility)
          assertFalse(dismiss.isFocusable)
          assertFalse(dismiss.isClickable)
          assertFalse(dismiss.performClick())
          assertTrue(listener.indexChanges.isEmpty())
          assertEquals(0, listener.closeRequestCount)
          assertEquals(View.INVISIBLE, dismiss.visibility)
        }
      }
  }

  @Test
  fun `Dismiss becomes unavailable when host layout reaches zero size`() {
    withActivity { activity ->
      val host = configuredHost(activity)
      activity.setContentView(host)
      layout(host)
      val dismiss = dismissAccessibilityView(host)
      assertTrue(dismiss.isClickable)

      layout(host, width = 0, height = 0)

      assertEquals(0f, dismiss.scaleY, 0f)
      assertEquals(View.INVISIBLE, dismiss.visibility)
      assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, dismiss.importantForAccessibility)
      assertFalse(dismiss.isFocusable)
      assertFalse(dismiss.isClickable)
    }
  }

  @Test
  fun `disabling Dismiss clears focus and pressed state without removing private children`() {
    withActivity { activity ->
      val host = configuredHost(activity)
      activity.setContentView(host)
      layout(host)
      val dismiss = dismissAccessibilityView(host)
      assertTrue(dismiss.requestFocus())
      dismiss.isPressed = true

      host.modal = false

      assertFalse(dismiss.hasFocus())
      assertFalse(dismiss.isPressed)
      assertFalse(dismiss.isFocusable)
      assertFalse(dismiss.isClickable)
      assertEquals(View.INVISIBLE, dismiss.visibility)
      assertEquals(3, host.childCount)
    }
  }

  private fun configuredHost(
    activity: Activity,
    listener: RecordingListener? = null,
    modal: Boolean = true,
    index: Int = 1,
    openDetent: Double = OPEN_DETENT_DP.toDouble(),
    openDetentKind: String = "points",
    closedDetentProgrammatic: Boolean = false,
    scrimOpacity: Float = 1f,
    includeClosedDetent: Boolean = true,
  ) =
    BottomSheetHostView(activity).apply {
      this.listener = listener
      animateIn = false
      this.modal = modal
      setScrimOpacities(listOf(0f, scrimOpacity))
      val closedDetents =
        if (includeClosedDetent) {
          listOf(
            mapOf<String, Any>(
              "value" to 0.0,
              "kind" to "points",
              "programmatic" to closedDetentProgrammatic,
            )
          )
        } else {
          emptyList()
        }
      setDetents(
        closedDetents +
          mapOf<String, Any>(
            "value" to openDetent,
            "kind" to openDetentKind,
            "programmatic" to false,
          )
      )
      setIndex(index)
    }

  private fun layout(
    host: ViewGroup,
    width: Int = HOST_WIDTH,
    height: Int = HOST_HEIGHT,
  ) {
    host.measure(
      View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
    )
    host.layout(0, 0, width, height)
  }

  private fun dispatchTap(host: View, y: Float) {
    host.dispatchTouchEvent(motionEvent(MotionEvent.ACTION_DOWN, y))
    host.dispatchTouchEvent(motionEvent(MotionEvent.ACTION_UP, y))
  }

  private fun motionEvent(action: Int, y: Float): MotionEvent =
    MotionEvent.obtain(1L, 2L, action, 100f, y, 0)

  private fun visualScrim(host: BottomSheetHostView): View = host.getChildAt(0)

  private fun dismissAccessibilityView(host: BottomSheetHostView): View = host.getChildAt(1)

  private fun sheetContainer(host: BottomSheetHostView): ViewGroup = host.getChildAt(2) as ViewGroup

  private inline fun withActivity(block: (Activity) -> Unit) {
    Robolectric.buildActivity(Activity::class.java).setup().use { controller ->
      val activity = controller.get()
      try {
        block(activity)
      } finally {
        (activity.findViewById<View>(android.R.id.content) as? ViewGroup)?.let { content ->
          (content.getChildAt(0) as? BottomSheetHostView)?.destroy()
        }
      }
    }
  }

  private data class HostState(
    val modal: Boolean = true,
    val index: Int = 1,
    val openDetent: Double = OPEN_DETENT_DP.toDouble(),
    val openDetentKind: String = "points",
    val closedDetentProgrammatic: Boolean = false,
    val scrimOpacity: Float = 1f,
    val includeClosedDetent: Boolean = true,
  )

  private class RecordingListener : BottomSheetViewListener {
    val indexChanges = mutableListOf<Int>()
    var closeRequestCount = 0

    override fun onIndexChange(index: Int) {
      indexChanges.add(index)
    }

    override fun onSettle(index: Int) = Unit

    override fun onPositionChange(position: Double, index: Double) = Unit

    override fun onCloseRequest() {
      closeRequestCount++
    }
  }

  private companion object {
    const val HOST_WIDTH = 600
    const val HOST_HEIGHT = 1000
    const val OPEN_DETENT_DP = 100
  }
}

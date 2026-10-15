package com.swmansion.reactnativebottomsheet.accessibility

import com.facebook.react.uimanager.StateWrapper
import java.lang.reflect.Proxy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FabricStateMountCompletionTest {
  @Test
  fun `later nested delivery stays unavailable until the outer batch unwinds`() {
    val completion = FabricStateMountCompletion()
    val state = state()
    completion.begin(7)
    completion.begin(7)
    completion.end(7)
    completion.begin(7)
    val nested = requireNotNull(completion.capture(state))
    completion.end(7)
    assertFalse(nested.accepts(state))
    completion.end(7)
    assertFalse(nested.accepts(state))
    completion.begin(8)
    val recovery = requireNotNull(completion.capture(state))
    completion.end(8)
    assertTrue(recovery.accepts(state))
  }

  @Test
  fun `overlapping batches cannot borrow an end even when their numbers match`() {
    val completion = FabricStateMountCompletion()
    val outerState = state()
    val innerState = state()
    completion.begin(7)
    val outer = requireNotNull(completion.capture(outerState))
    completion.begin(7)
    val inner = requireNotNull(completion.capture(innerState))
    completion.end(7)
    assertFalse(outer.accepts(outerState))
    assertFalse(inner.accepts(innerState))
    completion.end(7)
    assertFalse(outer.accepts(outerState))
    completion.begin(8)
    val recovery = requireNotNull(completion.capture(innerState))
    completion.end(8)
    assertTrue(recovery.accepts(innerState))
  }

  @Test
  fun `only the exact delivered state becomes available after its matching end`() {
    val completion = FabricStateMountCompletion()
    val firstState = state()
    val anotherState = state()
    assertNull(completion.capture(firstState))
    completion.begin(4)
    val delivery = requireNotNull(completion.capture(firstState))
    assertFalse(delivery.accepts(firstState))
    completion.end(4)
    assertTrue(delivery.accepts(firstState))
    assertFalse(delivery.accepts(anotherState))
    assertFalse(delivery.accepts(null))
    completion.begin(5)
    val mismatched = requireNotNull(completion.capture(anotherState))
    completion.end(6)
    completion.end(5)
    assertFalse(mismatched.accepts(anotherState))
  }

  @Test
  fun `another delivery with a reused batch number cannot complete an abandoned state`() {
    val completion = FabricStateMountCompletion()
    val firstState = state()
    val nextState = state()
    val finishDispatch = completion.beginDispatch()
    completion.begin(1)
    val abandoned = requireNotNull(completion.capture(firstState))
    finishDispatch()
    completion.begin(1)
    val next = requireNotNull(completion.capture(nextState))
    completion.end(1)
    assertFalse(abandoned.accepts(firstState))
    assertTrue(next.accepts(nextState))
  }

  @Test
  fun `ending observation invalidates completed deliveries and rejects late events`() {
    val completion = FabricStateMountCompletion()
    val state = state()
    completion.begin(1)
    val delivery = requireNotNull(completion.capture(state))
    completion.end(1)
    assertTrue(delivery.accepts(state))
    completion.stop()
    completion.begin(2)
    completion.end(2)
    assertFalse(delivery.accepts(state))
    assertNull(completion.capture(state))
  }

  private fun state() =
    Proxy.newProxyInstance(
      StateWrapper::class.java.classLoader,
      arrayOf(StateWrapper::class.java),
    ) { _, _, _ ->
      null
    } as StateWrapper
}

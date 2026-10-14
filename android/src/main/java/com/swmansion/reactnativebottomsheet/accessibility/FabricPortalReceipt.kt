package com.swmansion.reactnativebottomsheet.accessibility

import com.facebook.proguard.annotations.DoNotStrip

/** Exact source metadata; this does not establish attached native membership. */
@DoNotStrip
internal class FabricPortalReceipt
@DoNotStrip
constructor(val publicationId: String, val hostTag: Int, contextPath: IntArray) {
  val contexts: List<Int> = contextPath.toList()
}

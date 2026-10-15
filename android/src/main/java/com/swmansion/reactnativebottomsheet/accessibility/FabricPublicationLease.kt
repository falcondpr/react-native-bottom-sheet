package com.swmansion.reactnativebottomsheet.accessibility

import com.facebook.react.uimanager.StateWrapper

/** Native source resource, independent of presentation ownership and isolation. */
internal interface FabricPublicationLease {
  fun bootstrap()

  /** Inventory of one exact source revision, independent of native ancestry or Active state. */
  fun sheetTags(surfaceId: Int, tag: Int, state: StateWrapper?): IntArray?

  /** Requires every sheet's delivered State from one source revision, including inactive sheets. */
  fun receipt(surfaceId: Int, tag: Int, states: Map<Int, StateWrapper?>): FabricPortalReceipt?

  fun release()
}

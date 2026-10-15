package com.swmansion.reactnativebottomsheet.accessibility

import com.facebook.react.uimanager.StateWrapper

/** Native source resource, independent of presentation ownership and isolation. */
internal interface FabricPublicationLease {
  fun bootstrap()

  /** Requires every sheet's delivered State from one source revision, including inactive sheets. */
  fun receipt(surfaceId: Int, tag: Int, states: Map<Int, StateWrapper?>): FabricPortalReceipt?

  fun release()
}

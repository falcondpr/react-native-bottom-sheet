package com.swmansion.reactnativebottomsheet.accessibility

import com.facebook.react.uimanager.StateWrapper

/** Native source resource, independent of presentation ownership and isolation. */
internal interface FabricPublicationLease {
  fun bootstrap()

  fun receipt(surfaceId: Int, tag: Int, state: StateWrapper?): FabricPortalReceipt?

  fun release()
}

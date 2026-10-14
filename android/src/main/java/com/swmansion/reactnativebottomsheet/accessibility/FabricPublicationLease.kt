package com.swmansion.reactnativebottomsheet.accessibility

/** Native source resource, independent of presentation ownership and isolation. */
internal interface FabricPublicationLease {
  fun bootstrap()

  fun release()
}

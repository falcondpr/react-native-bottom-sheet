import React from 'react';
import { AppRegistry, View } from 'react-native';
import NativeSheet from '../../src/BottomSheetNativeComponent';
import { renderPortalHost } from '../../src/PortalHost';

function MountedPublication() {
  const sheet = React.createElement(NativeSheet, {
    testID: 'mounted-sheet',
    style: { flex: 1 },
    detents: [
      { value: 0, kind: 'points', programmatic: false },
      { value: 200, kind: 'points', programmatic: false },
    ],
    index: 1,
    modal: true,
    animateIn: false,
    hasCloseRequestHandler: false,
    scrollableExpandNegotiation: 0,
    scrollableCollapseNegotiation: 0,
  });
  return React.createElement(
    View,
    {
      testID: 'local-area',
      collapsable: false,
      style: { width: 320, height: 640, position: 'relative' },
    },
    renderPortalHost([['one', sheet]])
  );
}

AppRegistry.registerComponent('MountedPublication', () => MountedPublication);

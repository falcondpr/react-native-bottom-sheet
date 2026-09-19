import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';

export type PortalSnapshot = Array<[string, ReactNode]>;

export const renderPortalHost = (portals: PortalSnapshot) => {
  if (portals.length === 0) return null;

  return (
    // Keep portal wrappers under one non-flattened native parent. Android uses
    // their native sibling order to select the unique accessible Top portal.
    <View
      collapsable={false}
      style={StyleSheet.absoluteFill}
      pointerEvents="box-none"
    >
      {portals.map(([key, element]) => (
        <View
          key={key}
          style={StyleSheet.absoluteFill}
          pointerEvents="box-none"
        >
          {element}
        </View>
      ))}
    </View>
  );
};

import { useRef, useState } from 'react';
import { Button, Pressable, StyleSheet, Text, View } from 'react-native';
import { ModalBottomSheet } from '@swmansion/react-native-bottom-sheet';

import {
  DemoScreen,
  MODAL_SCRIM_COLOR,
  SheetBackground,
  SheetHeader,
  useSheetBottomPadding,
} from '../demoShared';

type PortalName = 'lower' | 'upper';
type PortalPhase = 'open' | 'closing' | 'settle';
type PortalEvent = {
  id: number;
  portal: PortalName;
  phase: PortalPhase;
  index: number;
};

const PortalFocusTarget = ({ label }: { label: string }) => (
  <Pressable
    accessibilityLabel={label}
    accessibilityRole="button"
    onPress={() => undefined}
    style={styles.focusTarget}
  >
    <Text style={styles.focusTargetText}>{label}</Text>
  </Pressable>
);

export const PortalAccessibilityStackScreen = () => {
  const [lowerIndex, setLowerIndex] = useState(0);
  const [upperIndex, setUpperIndex] = useState(0);
  const [events, setEvents] = useState<PortalEvent[]>([]);
  const nextEventId = useRef(0);
  const pendingSettle = useRef<Record<PortalName, boolean>>({
    lower: false,
    upper: false,
  });
  const bottomPadding = useSheetBottomPadding();

  const logEvent = (portal: PortalName, phase: PortalPhase, index: number) => {
    const message = `[two-portals] ${portal} ${phase} index=${index}`;
    console.log(message);
    setEvents((current) =>
      [{ id: nextEventId.current++, portal, phase, index }, ...current].slice(
        0,
        8
      )
    );
  };

  const beginTransition = (
    portal: PortalName,
    phase: Exclude<PortalPhase, 'settle'>,
    index: number,
    setIndex: (index: number) => void
  ) => {
    pendingSettle.current[portal] = true;
    logEvent(portal, phase, index);
    setIndex(index);
  };

  const openLower = () => beginTransition('lower', 'open', 1, setLowerIndex);

  const closeLower = () => {
    if (lowerIndex === 0) return;
    beginTransition('lower', 'closing', 0, setLowerIndex);
  };

  const openUpper = () => beginTransition('upper', 'open', 1, setUpperIndex);

  const closeUpper = () => {
    if (upperIndex === 0) return;
    beginTransition('upper', 'closing', 0, setUpperIndex);
  };

  const handleIndexChange = (
    portal: PortalName,
    nextIndex: number,
    setIndex: (index: number) => void
  ) => {
    beginTransition(
      portal,
      nextIndex === 0 ? 'closing' : 'open',
      nextIndex,
      setIndex
    );
  };

  const handleSettle = (portal: PortalName, index: number) => {
    if (!pendingSettle.current[portal]) return;
    pendingSettle.current[portal] = false;
    logEvent(portal, 'settle', index);
  };

  return (
    <DemoScreen
      title="Portal accessibility stack"
      sheet={
        <>
          <ModalBottomSheet
            detents={[0, 440]}
            index={lowerIndex}
            onIndexChange={(nextIndex) =>
              handleIndexChange('lower', nextIndex, setLowerIndex)
            }
            onSettle={(index) => handleSettle('lower', index)}
            onCloseRequest={closeLower}
            scrimColor={MODAL_SCRIM_COLOR}
            surface={<SheetBackground style={StyleSheet.absoluteFill} />}
          >
            <SheetHeader title="Lower portal" onClose={closeLower} />
            <View
              style={[styles.sheetContent, { paddingBottom: bottomPadding }]}
            >
              <PortalFocusTarget label="Lower focus target" />
              <Button title="Open upper portal" onPress={openUpper} />
              <Text style={styles.hint}>
                TalkBack should not reach the application screen while this
                portal is active.
              </Text>
            </View>
          </ModalBottomSheet>

          <ModalBottomSheet
            detents={[0, 360]}
            index={upperIndex}
            onIndexChange={(nextIndex) =>
              handleIndexChange('upper', nextIndex, setUpperIndex)
            }
            onSettle={(index) => handleSettle('upper', index)}
            onCloseRequest={closeUpper}
            scrimColor={MODAL_SCRIM_COLOR}
            surface={
              <SheetBackground
                style={[StyleSheet.absoluteFill, styles.upperSurface]}
              />
            }
          >
            <SheetHeader title="Upper portal" onClose={closeUpper} />
            <View
              style={[styles.sheetContent, { paddingBottom: bottomPadding }]}
            >
              <PortalFocusTarget label="Upper focus target" />
              <Button
                title="Close upper; keep lower open"
                onPress={closeUpper}
              />
              <Text style={styles.hint}>
                Lower focus target must remain unreachable through closing and
                return only after upper settle.
              </Text>
            </View>
          </ModalBottomSheet>
        </>
      }
    >
      <Text style={styles.instructions}>
        Open lower, move TalkBack to Lower focus target, open upper, then close
        upper. During upper closing only Upper focus target should remain in the
        modal accessibility scope.
      </Text>
      <Button title="Open lower portal" onPress={openLower} />
      <View style={styles.eventLog}>
        <Text style={styles.eventLogTitle}>Lifecycle log (newest first)</Text>
        {events.length === 0 ? (
          <Text style={styles.muted}>No events yet.</Text>
        ) : (
          events.map((event) => (
            <Text key={event.id} style={styles.eventLine}>
              {event.portal} {event.phase} index={event.index}
            </Text>
          ))
        )}
      </View>
    </DemoScreen>
  );
};

const styles = StyleSheet.create({
  instructions: {
    color: '#444',
    fontSize: 15,
    lineHeight: 22,
  },
  sheetContent: {
    paddingHorizontal: 20,
    paddingTop: 20,
    gap: 16,
  },
  focusTarget: {
    minHeight: 56,
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#295ea7',
    backgroundColor: '#eaf2ff',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  focusTargetText: {
    color: '#143b70',
    fontSize: 18,
    fontWeight: '700',
  },
  hint: {
    color: '#555',
    lineHeight: 20,
  },
  upperSurface: {
    backgroundColor: '#fff9e8',
  },
  eventLog: {
    borderRadius: 12,
    backgroundColor: '#f3f3f3',
    padding: 12,
    gap: 4,
  },
  eventLogTitle: {
    fontWeight: '700',
    marginBottom: 4,
  },
  eventLine: {
    fontFamily: 'monospace',
    fontVariant: ['tabular-nums'],
  },
  muted: {
    color: '#777',
  },
});

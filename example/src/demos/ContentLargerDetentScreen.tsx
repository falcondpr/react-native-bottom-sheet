import { useState } from 'react';
import { Button, StyleSheet, Text, View } from 'react-native';
import { BottomSheet, type Detent } from '@swmansion/react-native-bottom-sheet';

import { DemoScreen, SheetBackground, SheetHeader } from '../demoShared';

const EXPANDED_DETENT = 560;
const TALLER_DETENTS = [600, 700];
const CONTENT_BODY_HEIGHT = 132;

export const ContentLargerDetentScreen = () => {
  const [index, setIndex] = useState(1);
  // Swapping the taller detents in and targeting the new last one in the same
  // update: the index must survive the content re-measuring against the new
  // tallest detent.
  const [hasTallerDetents, setHasTallerDetents] = useState(false);
  const detents: Detent[] = hasTallerDetents
    ? [0, 'content', ...TALLER_DETENTS]
    : [0, 'content', EXPANDED_DETENT];
  const detentsLabel = detents
    .map((detent) => (typeof detent === 'string' ? `'${detent}'` : detent))
    .join(', ');

  const expandWithTallerDetents = () => {
    setHasTallerDetents(true);
    setIndex(3);
  };

  const restoreDetents = () => {
    setHasTallerDetents(false);
    setIndex(1);
  };

  return (
    <DemoScreen
      title="Content plus larger detent"
      sheet={
        <BottomSheet
          detents={detents}
          index={index}
          onIndexChange={setIndex}
          surface={<SheetBackground style={StyleSheet.absoluteFill} />}
        >
          <SheetHeader
            title="Content plus larger detent"
            onClose={() => setIndex(0)}
          />
          <View
            style={{
              height: CONTENT_BODY_HEIGHT,
              justifyContent: 'center',
              paddingHorizontal: 20,
              gap: 12,
            }}
          >
            <Text style={{ fontSize: 18, fontWeight: '600' }}>
              Short content, taller expansion.
            </Text>
            <Text style={{ fontSize: 15, lineHeight: 22, color: '#555' }}>
              The content detent fits this block, while the 560pt detent expands
              the sheet beyond the measured content height.
            </Text>
          </View>
        </BottomSheet>
      }
    >
      <Button title="Open at content height" onPress={() => setIndex(1)} />
      {hasTallerDetents ? (
        <Button
          title="Restore 560pt detents at content"
          onPress={restoreDetents}
        />
      ) : (
        <>
          <Button title="Expand to 560pt" onPress={() => setIndex(2)} />
          <Button
            title="Add 600pt and 700pt, expand to 700pt"
            onPress={expandWithTallerDetents}
          />
        </>
      )}
      <Text>index: {index}</Text>
      <Text>detents: [{detentsLabel}]</Text>
    </DemoScreen>
  );
};

import { useState } from 'react';
import { Button, Pressable, StyleSheet, Text, View } from 'react-native';
import {
  GestureHandlerRootView,
  Pressable as GesturePressable,
} from 'react-native-gesture-handler';
import {
  BottomSheetProvider,
  ModalBottomSheet,
} from '@swmansion/react-native-bottom-sheet';

import {
  DemoScreen,
  MODAL_SCRIM_COLOR,
  SheetBackground,
  SheetHeader,
} from '../demoShared';

export const ScrimPressablesScreen = () => {
  const [index, setIndex] = useState(0);
  const [nestedIndex, setNestedIndex] = useState(0);
  const [backgroundPresses, setBackgroundPresses] = useState(0);
  const [nativePresses, setNativePresses] = useState(0);
  const [sheetPresses, setSheetPresses] = useState(0);

  return (
    <GestureHandlerRootView style={styles.root}>
      <BottomSheetProvider>
        <DemoScreen title="Scrim press isolation">
          <GesturePressable
            style={styles.button}
            onPress={() => setBackgroundPresses((count) => count + 1)}
          >
            <Text>Background RNGH presses: {backgroundPresses}</Text>
          </GesturePressable>
          <Pressable
            style={styles.button}
            onPress={() => setNativePresses((count) => count + 1)}
          >
            <Text>Background RN presses: {nativePresses}</Text>
          </Pressable>
          <Button title="Open sheet" onPress={() => setIndex(1)} />
          <Text>
            Sheet index: {index}; nested index: {nestedIndex}
          </Text>
        </DemoScreen>
        <ModalBottomSheet
          index={index}
          onIndexChange={setIndex}
          detents={[0, 420]}
          scrimColor={MODAL_SCRIM_COLOR}
          surface={<SheetBackground style={StyleSheet.absoluteFill} />}
        >
          <SheetHeader title="Lower sheet" onClose={() => setIndex(0)} />
          <View style={styles.content}>
            <GesturePressable
              style={styles.button}
              onPress={() => setSheetPresses((count) => count + 1)}
            >
              <Text>Sheet RNGH presses: {sheetPresses}</Text>
            </GesturePressable>
            <Button
              title="Open nested sheet"
              onPress={() => setNestedIndex(1)}
            />
          </View>
        </ModalBottomSheet>
        <ModalBottomSheet
          index={nestedIndex}
          onIndexChange={setNestedIndex}
          detents={[0, 160]}
          scrimColor={MODAL_SCRIM_COLOR}
          surface={<SheetBackground style={StyleSheet.absoluteFill} />}
        >
          <SheetHeader title="Nested sheet" onClose={() => setNestedIndex(0)} />
        </ModalBottomSheet>
      </BottomSheetProvider>
    </GestureHandlerRootView>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: 'white' },
  content: { padding: 16, gap: 16 },
  button: { alignItems: 'center', padding: 16, backgroundColor: 'lightgray' },
});

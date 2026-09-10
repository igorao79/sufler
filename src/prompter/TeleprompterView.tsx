import React, { useCallback, useMemo, useRef, useState } from 'react';
import { LayoutChangeEvent, StyleSheet, View } from 'react-native';
import Animated, {
  Easing,
  useAnimatedReaction,
  useAnimatedStyle,
  useDerivedValue,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import { scheduleOnRN } from 'react-native-worklets';

import { theme } from '../ui/theme';
import { ActiveLine } from './ActiveLine';
import type { PositionValues } from './usePositionBridge';

type Props = {
  lines: string[];
  position: PositionValues;
  fontSize: number;
  lineHeight: number;
  mirrored: boolean;
};

/** Where the active line sits vertically — the "eye line" a presenter reads from. */
const EYE_LINE = 0.38;

/**
 * The in-app teleprompter.
 *
 * Scrolling is a `translateY` on one content view inside a clipped container, rather than a
 * `ScrollView` driven by `scrollTo`. Three reasons: it is a single transform node on the UI thread
 * instead of a scroll-offset write; there is no momentum or bounce fighting the aligner for control
 * of the position; and it composes cleanly with the `scaleX: -1` mirror for beam-splitter rigs.
 *
 * Every line is mounted rather than windowed. Windowing needs measured offsets for lines that are
 * not on screen, which means either estimating heights (wrong as soon as a line wraps) or a
 * two-pass measure. A few hundred static `Text` rows cost one slow first render and nothing
 * afterwards, which is the better trade for scripts of realistic length.
 */
export function TeleprompterView({ lines, position, fontSize, lineHeight, mirrored }: Props) {
  const containerHeight = useSharedValue(0);
  const lineOffsets = useSharedValue<number[]>([]);
  const offsetsRef = useRef<number[]>([]);
  const measuredCount = useRef(0);

  // Mirrored into React state so the active line can render word spans. A line changes every few
  // seconds, so this re-render is cheap — unlike the token index, which must never get here.
  const [activeLine, setActiveLine] = useState(0);

  useAnimatedReaction(
    () => position.lineIndex.value,
    (current, previous) => {
      if (current !== previous) {
        // `runOnJS` no longer exists in Reanimated 4.
        scheduleOnRN(setActiveLine, current);
      }
    },
  );

  const onContainerLayout = useCallback(
    (event: LayoutChangeEvent) => {
      containerHeight.value = event.nativeEvent.layout.height;
    },
    [containerHeight],
  );

  const onLineLayout = useCallback(
    (index: number, y: number) => {
      offsetsRef.current[index] = y;
      measuredCount.current += 1;
      if (measuredCount.current >= lines.length) {
        lineOffsets.value = [...offsetsRef.current];
      }
    },
    [lineOffsets, lines.length],
  );

  // Reset measurement bookkeeping whenever the layout inputs change.
  useMemo(() => {
    offsetsRef.current = new Array(lines.length).fill(0);
    measuredCount.current = 0;
    lineOffsets.value = [];
  }, [lines, fontSize, lineHeight, lineOffsets]);

  const targetY = useDerivedValue(() => {
    const offsets = lineOffsets.value;
    if (offsets.length === 0) return 0;
    const index = Math.min(Math.max(position.lineIndex.value, 0), offsets.length - 1);
    return Math.max(0, offsets[index] - containerHeight.value * EYE_LINE);
  });

  const scrollY = useDerivedValue(() =>
    withTiming(targetY.value, { duration: 320, easing: Easing.out(Easing.cubic) }),
  );

  const contentStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: -scrollY.value }],
  }));

  const rowStyle = useMemo(
    () => ({ fontSize, lineHeight: fontSize * lineHeight }),
    [fontSize, lineHeight],
  );

  return (
    <View style={styles.container} onLayout={onContainerLayout}>
      <Animated.View style={[styles.content, mirrored && styles.mirrored, contentStyle]}>
        {lines.map((line, index) => (
          <ActiveLine
            key={index}
            index={index}
            text={line}
            isActive={index === activeLine}
            activeWordIndex={position.indexInLine}
            style={rowStyle}
            onLayout={onLineLayout}
          />
        ))}
        {/* Trailing space so the last line can still reach the eye line. */}
        <View style={{ height: 400 }} />
      </Animated.View>

      <View pointerEvents="none" style={styles.eyeLine} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    overflow: 'hidden',
    backgroundColor: theme.color.background,
  },
  content: {
    paddingHorizontal: theme.space(5),
    paddingTop: theme.space(4),
  },
  mirrored: {
    transform: [{ scaleX: -1 }],
  },
  eyeLine: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: `${EYE_LINE * 100}%`,
    height: 1,
    backgroundColor: theme.color.accent,
    opacity: 0.22,
  },
});

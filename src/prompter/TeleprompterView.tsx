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
  const measuredRef = useRef<Set<number>>(new Set());

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
      if (offsetsRef.current[index] === y && measuredRef.current.has(index)) return;
      offsetsRef.current[index] = y;
      measuredRef.current.add(index);
      // Publish every time rather than waiting for a full set. Lines re-lay out whenever one
      // becomes active, so a plain counter over-counts, and gating on it risks the opposite —
      // offsets that are never published at all, which reads to the user as a teleprompter that
      // highlights words but refuses to scroll.
      lineOffsets.value = [...offsetsRef.current];
    },
    [lineOffsets],
  );

  // Reset measurement bookkeeping whenever the layout inputs change.
  useMemo(() => {
    offsetsRef.current = new Array(lines.length).fill(0);
    measuredRef.current = new Set();
    lineOffsets.value = [];
  }, [lines, fontSize, lineHeight, lineOffsets]);

  // Word counts per line, so the worklet can turn a word index into a fraction of a line.
  const wordsPerLine = useSharedValue<number[]>([]);
  useMemo(() => {
    wordsPerLine.value = lines.map((line) => line.split(/\s+/).filter(Boolean).length);
  }, [lines, wordsPerLine]);

  // Interpolate *within* the line using how far through it the speaker is.
  //
  // Targeting the line's own offset means the view sits still for every word of a line and then
  // jumps a whole line at once — which is exactly the lurching the eye notices most. Blending
  // toward the next line's offset in proportion to the word index turns the same information into
  // continuous motion, without needing per-word measurement.
  const targetY = useDerivedValue(() => {
    const offsets = lineOffsets.value;
    if (offsets.length === 0) return 0;

    const index = Math.min(Math.max(position.lineIndex.value, 0), offsets.length - 1);
    const current = offsets[index];
    const next = index + 1 < offsets.length ? offsets[index + 1] : current;

    const words = Math.max(wordsPerLine.value[index] ?? 1, 1);
    const progress = Math.min(Math.max(position.indexInLine.value, 0), words) / words;

    return Math.max(0, current + (next - current) * progress - containerHeight.value * EYE_LINE);
  });

  const scrollY = useDerivedValue(() =>
    withTiming(targetY.value, { duration: 260, easing: Easing.out(Easing.cubic) }),
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

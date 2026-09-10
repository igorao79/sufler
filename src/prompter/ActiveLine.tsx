import React, { useCallback, useMemo } from 'react';
import { LayoutChangeEvent, StyleSheet, Text, TextStyle, View } from 'react-native';
import Animated, { useAnimatedStyle, type SharedValue } from 'react-native-reanimated';

import { theme } from '../ui/theme';

type Props = {
  index: number;
  text: string;
  isActive: boolean;
  activeWordIndex: SharedValue<number>;
  style: Pick<TextStyle, 'fontSize' | 'lineHeight'>;
  onLayout: (index: number, y: number) => void;
};

/**
 * One line of the script.
 *
 * Inactive lines are a single memoised `Text` — the cheapest thing that can be on screen, which
 * matters because every line of the script is mounted at once. Only the active line is split into
 * per-word spans, and those spans read the word index straight off a shared value, so the highlight
 * moves on the UI thread without a single React render.
 */
function LineComponent({ index, text, isActive, activeWordIndex, style, onLayout }: Props) {
  const handleLayout = useCallback(
    (event: LayoutChangeEvent) => onLayout(index, event.nativeEvent.layout.y),
    [index, onLayout],
  );

  const words = useMemo(() => (isActive ? text.split(/(\s+)/) : []), [isActive, text]);

  // Both branches wrap in the same View so that the measured `y` of a line does not shift the
  // moment it becomes active — which would drag the whole scroll offset with it.
  if (!isActive) {
    return (
      <View onLayout={handleLayout} style={styles.row}>
        <Text style={[styles.line, style, styles.inactive]} allowFontScaling={false}>
          {text || ' '}
        </Text>
      </View>
    );
  }

  // `split` with a capturing group keeps the separators, so word positions stay aligned with what
  // the native tokeniser counted.
  let wordCursor = -1;

  return (
    <View onLayout={handleLayout} style={styles.row}>
      <Text style={[styles.line, style, styles.active]} allowFontScaling={false}>
        {words.map((chunk, chunkIndex) => {
          if (/^\s+$/.test(chunk) || chunk.length === 0) {
            return <Text key={chunkIndex}>{chunk}</Text>;
          }
          wordCursor += 1;
          return (
            <Word key={chunkIndex} text={chunk} position={wordCursor} activeWordIndex={activeWordIndex} />
          );
        })}
      </Text>
    </View>
  );
}

function Word({
  text,
  position,
  activeWordIndex,
}: {
  text: string;
  position: number;
  activeWordIndex: SharedValue<number>;
}) {
  const animatedStyle = useAnimatedStyle(() => {
    const isCurrent = activeWordIndex.value === position;
    return {
      color: isCurrent ? theme.color.accent : theme.color.text,
    };
  });

  return <Animated.Text style={animatedStyle}>{text}</Animated.Text>;
}

export const ActiveLine = React.memo(LineComponent);

const styles = StyleSheet.create({
  line: {
    color: theme.color.text,
    fontWeight: '500',
  },
  inactive: {
    color: theme.color.textMuted,
  },
  active: {
    color: theme.color.text,
    fontWeight: '700',
  },
  row: {
    alignSelf: 'stretch',
  },
});

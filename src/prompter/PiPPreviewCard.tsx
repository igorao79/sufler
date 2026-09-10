import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { SuflerPiP, SuflerPiPView, isPiPAvailable } from '../../modules/sufler-core';
import { theme } from '../ui/theme';

type Props = {
  active: boolean;
  /** Rendered beside the card so the header stays one compact row. */
  children?: React.ReactNode;
};

/**
 * The 16:9 card that hosts the Picture in Picture source layer.
 *
 * It has to be genuinely on screen and genuinely visible: automatic PiP will not engage from a
 * hidden, transparent, zero-sized, or modal-hosted layer. Rather than hiding a 1×1 view somewhere
 * and hoping, this shows the user exactly the frames that will float over their other apps.
 *
 * The card is rendered even when `AVPictureInPictureController` is unavailable — which is the case
 * on every iPhone simulator. The display layer and the whole frame pipeline still work there, so
 * this stays the fastest way to see what the renderer is producing without a device. Only the
 * caption changes.
 */
export function PiPPreviewCard({ active, children }: Props) {
  const moduleMissing = SuflerPiP == null;
  const pipSupported = isPiPAvailable();

  if (moduleMissing) {
    return (
      <View style={[styles.card, styles.unavailable]}>
        <Text style={styles.unavailableText}>
          Нативный модуль не подключён.{'\n'}Соберите приложение через expo run:ios.
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.wrapper}>
      <SuflerPiPView style={styles.card} />
      <View style={styles.column}>
        <View style={styles.caption}>
          <View style={[styles.dot, active && styles.dotActive]} />
          <Text style={styles.captionText}>
            {!pipSupported
              ? 'Кадр окна поверх приложений. Само окно на симуляторе недоступно — нужен iPhone.'
              : active
                ? 'Окно поверх других приложений активно'
                : 'Так будет выглядеть окно поверх других приложений'}
          </Text>
        </View>
        {children}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: theme.space(3),
  },
  column: {
    flex: 1,
    gap: theme.space(2),
  },
  card: {
    aspectRatio: 16 / 9,
    // Roughly the proportion of the screen a real PiP window occupies, which keeps the preview
    // honest and leaves the teleprompter the room it needs.
    width: 176,
    backgroundColor: '#000',
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.color.border,
  },
  caption: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: theme.space(2),
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: theme.color.textFaint,
    marginTop: 2,
  },
  dotActive: {
    backgroundColor: theme.color.success,
  },
  captionText: {
    color: theme.color.textMuted,
    fontSize: theme.font.small,
    flex: 1,
    lineHeight: 18,
  },
  unavailable: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    padding: theme.space(4),
  },
  unavailableText: {
    color: theme.color.textMuted,
    fontSize: theme.font.small,
    textAlign: 'center',
    lineHeight: 19,
  },
});

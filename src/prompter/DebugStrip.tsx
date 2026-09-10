import React, { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import {
  SuflerPiP,
  SuflerSpeech,
  type PiPDiagnostics,
  type TranscriptEvent,
} from '../../modules/sufler-core';
import { theme } from '../ui/theme';

/**
 * Raw hypothesis and alignment scores.
 *
 * Speech-following is the product, and when it drifts the only useful question is "what did it hear
 * and what did it score". Guessing at that from the outside is hopeless, so this exists from the
 * first build rather than being added after the first confusing bug report.
 *
 * Subscribing here is what turns the native `onTranscript` stream on at all — nothing is emitted
 * while nothing is listening.
 */
export function DebugStrip() {
  const [event, setEvent] = useState<TranscriptEvent | null>(null);
  const [pip, setPip] = useState<PiPDiagnostics | null>(null);

  useEffect(() => {
    if (!SuflerSpeech) return;
    const subscription = SuflerSpeech.addListener('onTranscript', setEvent);
    return () => subscription.remove();
  }, []);

  // Polled rather than pushed: the interesting question is "is the frame counter still moving",
  // which only a periodic sample can answer. Once a second is enough and costs nothing.
  useEffect(() => {
    const pipModule = SuflerPiP;
    if (!pipModule) return;
    const tick = () => setPip(pipModule.getDiagnostics());
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.text} numberOfLines={1}>
        {event ? event.words.join(' ') : 'отладка: ждём речь…'}
      </Text>
      {event && (
        <Text style={styles.scores}>
          t{event.cursor} · best {event.best.toFixed(2)} · run {event.runnerUp.toFixed(2)}
          {event.moved ? ' · →' : ' · hold'}
        </Text>
      )}
      {pip && (
        <Text style={styles.scores} numberOfLines={2}>
          pip {pip.active ? 'on' : 'off'}/{pip.possible ? 'possible' : 'not-possible'} · frames{' '}
          {pip.framesEnqueued} @{pip.clockHz}Hz · {pip.renderWidth}×{pip.renderHeight} ·{' '}
          src {pip.sourceSize} {pip.sourceInWindow ? 'in-window' : 'DETACHED'}
          {pip.rendererError ? ` · ${pip.rendererError}` : ''}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingHorizontal: theme.space(4),
    paddingVertical: theme.space(2),
    backgroundColor: '#000',
    borderTopWidth: 1,
    borderTopColor: theme.color.border,
    gap: 2,
  },
  text: {
    color: theme.color.success,
    fontFamily: 'Menlo',
    fontSize: 11,
  },
  scores: {
    color: theme.color.textFaint,
    fontFamily: 'Menlo',
    fontSize: 10,
  },
});

import { useEffect } from 'react';
import { useSharedValue, type SharedValue } from 'react-native-reanimated';

import { SuflerSpeech } from '../../modules/sufler-core';
import { useSufler } from '../store';

export type PositionValues = {
  tokenIndex: SharedValue<number>;
  lineIndex: SharedValue<number>;
  indexInLine: SharedValue<number>;
};

/**
 * Routes native position events into Reanimated shared values — and nowhere else.
 *
 * This is the single most important performance decision in the app. `onPosition` fires up to
 * twelve times a second. Writing it into React state (or into Zustand, which amounts to the same
 * thing) would re-render the teleprompter on every event, and a teleprompter that re-renders twelve
 * times a second is a slideshow. Writing a shared value from the JS thread triggers no render at
 * all; the scroll then runs entirely on the UI thread at display rate.
 *
 * Status and error events are the exception: they fire a handful of times per session, so they are
 * allowed to touch the store.
 */
export function usePositionBridge(): PositionValues {
  const tokenIndex = useSharedValue(0);
  const lineIndex = useSharedValue(0);
  const indexInLine = useSharedValue(0);

  const setStatusFromSpeech = useSufler((state) => state.setStatusFromSpeech);
  const setError = useSufler((state) => state.setError);

  useEffect(() => {
    if (!SuflerSpeech) return;

    SuflerSpeech.setPositionEventHz(12);

    const position = SuflerSpeech.addListener('onPosition', (event) => {
      tokenIndex.value = event.tokenIndex;
      lineIndex.value = event.lineIndex;
      indexInLine.value = event.indexInLine;
    });

    const state = SuflerSpeech.addListener('onSpeechState', ({ state }) => {
      setStatusFromSpeech(state);
    });

    const error = SuflerSpeech.addListener('onSpeechError', (event) => {
      setError(event);
    });

    return () => {
      position.remove();
      state.remove();
      error.remove();
    };
  }, [indexInLine, lineIndex, setError, setStatusFromSpeech, tokenIndex]);

  return { tokenIndex, lineIndex, indexInLine };
}

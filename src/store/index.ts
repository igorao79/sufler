import AsyncStorage from '@react-native-async-storage/async-storage';
import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

import { createPlaybackSlice } from './playbackSlice';
import { createScriptSlice } from './scriptSlice';
import { createSettingsSlice } from './settingsSlice';
import type { SuflerStore } from './types';

/**
 * One store, three slices.
 *
 * `persist` wraps the *combined* store rather than any individual slice — applying middleware
 * inside a slice and again at the top produces surprising behaviour, and only the combined store
 * knows the full shape to serialise.
 *
 * `partialize` is doing real work here: playback status, permissions and errors are all things that
 * must be re-derived at launch. Persisting `status: 'following'` would restore a UI claiming the
 * microphone is live when it is not.
 */
export const useSufler = create<SuflerStore>()(
  persist(
    (...args) => ({
      ...createScriptSlice(...args),
      ...createPlaybackSlice(...args),
      ...createSettingsSlice(...args),
    }),
    {
      name: 'sufler',
      version: 1,
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({
        scripts: state.scripts,
        order: state.order,
        locale: state.locale,
        preferOnDevice: state.preferOnDevice,
        fontSize: state.fontSize,
        lineHeight: state.lineHeight,
        mirrored: state.mirrored,
        showDebug: state.showDebug,
        tuning: state.tuning,
      }),
    },
  ),
);

export type { PlaybackStatus, ScriptDoc, ScriptSource, SuflerStore } from './types';

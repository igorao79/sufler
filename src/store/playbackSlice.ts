import type { StateCreator } from 'zustand';

import type { PlaybackSlice, SuflerStore } from './types';

export const createPlaybackSlice: StateCreator<SuflerStore, [], [], PlaybackSlice> = (set) => ({
  status: 'idle',
  pipActive: false,
  pipPossible: false,
  lastError: null,
  perms: { speech: 'undetermined', mic: 'undetermined' },

  setStatus: (status) => set({ status }),

  /**
   * Native speech states map onto playback status one-to-one except that `idle` from native must
   * not clobber a local `error` the user has not acknowledged yet.
   */
  setStatusFromSpeech: (state) =>
    set((current) => {
      if (state === 'idle' && current.status === 'error') return current;
      return { status: state };
    }),

  setPip: (patch) =>
    set((current) => ({
      pipActive: patch.active ?? current.pipActive,
      pipPossible: patch.possible ?? current.pipPossible,
    })),

  setPerms: (perms) => set({ perms }),

  setError: (lastError) =>
    set(lastError ? { lastError, status: 'error' } : { lastError: null }),
});

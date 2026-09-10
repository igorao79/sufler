import type { StateCreator } from 'zustand';

import { DEFAULT_TUNING } from '../../modules/sufler-core';
import type { SettingsSlice, SuflerStore } from './types';

export const createSettingsSlice: StateCreator<SuflerStore, [], [], SettingsSlice> = (set) => ({
  locale: 'ru-RU',
  preferOnDevice: true,
  fontSize: 30,
  lineHeight: 1.35,
  mirrored: false,
  showDebug: __DEV__,
  tuning: DEFAULT_TUNING,

  setSetting: (key, value) => set({ [key]: value } as Partial<SuflerStore>),

  setTuning: (patch) => set((state) => ({ tuning: { ...state.tuning, ...patch } })),

  resetTuning: () => set({ tuning: DEFAULT_TUNING }),
});

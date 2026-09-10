import type { AlignerTuning, PermissionStatus, SpeechState } from '../../modules/sufler-core';

export type ScriptSource = 'typed' | 'file' | 'shared';

export type ScriptDoc = {
  id: string;
  title: string;
  text: string;
  /** Derived from `text` at write time so the prompter never re-splits on every render. */
  lines: string[];
  source: ScriptSource;
  createdAt: number;
  updatedAt: number;
};

export type PlaybackStatus =
  | 'idle'
  | 'starting'
  | 'following'
  | 'stalled'
  | 'interrupted'
  | 'error';

export type ScriptSlice = {
  scripts: Record<string, ScriptDoc>;
  order: string[];
  upsertScript: (doc: ScriptDoc) => void;
  createScript: (input: { title?: string; text: string; source: ScriptSource }) => ScriptDoc;
  updateScript: (id: string, patch: { title?: string; text?: string }) => void;
  removeScript: (id: string) => void;
};

export type PlaybackSlice = {
  status: PlaybackStatus;
  pipActive: boolean;
  pipPossible: boolean;
  lastError: { code: string; message: string } | null;
  perms: { speech: PermissionStatus; mic: PermissionStatus };
  // Deliberately absent: the cursor. It updates ~12 times a second, and putting it here would
  // re-render every subscriber at that rate. It lives in native state and in Reanimated shared
  // values instead.
  setStatus: (status: PlaybackStatus) => void;
  setStatusFromSpeech: (state: SpeechState) => void;
  setPip: (patch: { active?: boolean; possible?: boolean }) => void;
  setPerms: (perms: { speech: PermissionStatus; mic: PermissionStatus }) => void;
  setError: (error: { code: string; message: string } | null) => void;
};

export type SettingsSlice = {
  locale: string;
  preferOnDevice: boolean;
  fontSize: number;
  lineHeight: number;
  mirrored: boolean;
  showDebug: boolean;
  tuning: AlignerTuning;
  setSetting: <K extends keyof SettingsValues>(key: K, value: SettingsValues[K]) => void;
  setTuning: (patch: Partial<AlignerTuning>) => void;
  resetTuning: () => void;
};

export type SettingsValues = {
  locale: string;
  preferOnDevice: boolean;
  fontSize: number;
  lineHeight: number;
  mirrored: boolean;
  showDebug: boolean;
};

export type SuflerStore = ScriptSlice & PlaybackSlice & SettingsSlice;

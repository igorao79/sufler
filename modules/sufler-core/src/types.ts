export type PermissionStatus = 'granted' | 'denied' | 'restricted' | 'undetermined';

export type Permissions = {
  speech: PermissionStatus;
  mic: PermissionStatus;
};

/** Where in the script the speaker is, as the native aligner sees it. */
export type SuflerPosition = {
  tokenIndex: number;
  lineIndex: number;
  /** Index of the word within its line — used for the in-app word highlight. */
  indexInLine: number;
  confidence: number;
};

export type SpeechState =
  | 'idle'
  | 'following'
  /** The speaker has gone quiet. The cursor holds — this app never advances on a timer. */
  | 'stalled'
  /** Another app took the microphone. See the README on why this cannot be worked around. */
  | 'interrupted';

export type StartOptions = {
  locale?: string;
  preferOnDevice?: boolean;
  /** `-1` keeps the current cursor. */
  startTokenIndex?: number;
};

/** Knobs for the alignment algorithm, exposed in Settings because no fixed heuristic suits every speaker. */
export type AlignerTuning = {
  hypothesisWindow: number;
  lookahead: number;
  backtrack: number;
  acceptThreshold: number;
  backtrackThreshold: number;
  maxJump: number;
  stallTimeoutMs: number;
};

export const DEFAULT_TUNING: AlignerTuning = {
  hypothesisWindow: 7,
  lookahead: 60,
  backtrack: 8,
  acceptThreshold: 0.55,
  backtrackThreshold: 0.8,
  maxJump: 25,
  stallTimeoutMs: 2500,
};

export type PiPStyle = {
  fontSize?: number;
  mirrored?: boolean;
  debugOverlay?: boolean;
};

export type PiPState = { active: boolean; possible: boolean };

export type PiPDiagnostics = {
  supported: boolean;
  possible: boolean;
  active: boolean;
  hasController: boolean;
  hasLayer: boolean;
  sourceInWindow: boolean;
  sourceSize: string;
  following: boolean;
  /** Total frames handed to the display layer since launch. Flat means nothing is being drawn. */
  framesEnqueued: number;
  renderWidth: number;
  renderHeight: number;
  /** Current pump rate: 30 while moving, 1 while idle, 0 when stopped. */
  clockHz: number;
  rendererError: string;
};
export type PiPPlaybackToggled = { playing: boolean };
export type SuflerError = { code: string; message: string };

export type TranscriptEvent = {
  words: string[];
  cursor: number;
  moved: boolean;
  best: number;
  runnerUp: number;
};

export type SharedItem = {
  id: string;
  title: string;
  text: string;
  createdAt: number;
};

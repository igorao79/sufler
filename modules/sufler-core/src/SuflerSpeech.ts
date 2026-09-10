import { requireOptionalNativeModule, type NativeModule } from 'expo';

import type {
  AlignerTuning,
  Permissions,
  SpeechState,
  StartOptions,
  SuflerError,
  SuflerPosition,
  TranscriptEvent,
} from './types';

type SuflerSpeechEvents = {
  /**
   * Fires at up to `setPositionEventHz` (12 Hz by default). Handlers must write to Reanimated
   * shared values only — putting this into React state re-renders the teleprompter twelve times a
   * second and turns it into a slideshow.
   */
  onPosition: (event: SuflerPosition) => void;
  /** Only produced while something is subscribed; used by the debug strip. */
  onTranscript: (event: TranscriptEvent) => void;
  onSpeechState: (event: { state: SpeechState }) => void;
  onSpeechError: (event: SuflerError) => void;
};

declare class SuflerSpeechNativeModule extends NativeModule<SuflerSpeechEvents> {
  requestPermissions(): Promise<Permissions>;
  getPermissions(): Permissions;
  supportedLocales(): string[];
  isOnDeviceAvailable(locale: string): boolean;
  start(options: StartOptions): Promise<void>;
  stop(): Promise<void>;
  setTuning(tuning: AlignerTuning): void;
  setPositionEventHz(hz: number): void;
}

export const SuflerSpeech =
  requireOptionalNativeModule<SuflerSpeechNativeModule>('SuflerSpeech');

export const isSpeechAvailable = () => SuflerSpeech != null;

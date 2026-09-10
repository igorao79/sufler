import { requireOptionalNativeModule, type NativeModule } from 'expo';

import type {
  PiPDiagnostics,
  PiPPlaybackToggled,
  PiPState,
  PiPStyle,
  SuflerError,
} from './types';

type SuflerPiPEvents = {
  onPiPStateChanged: (event: PiPState) => void;
  onPiPPlaybackToggled: (event: PiPPlaybackToggled) => void;
  onPiPError: (event: SuflerError) => void;
};

declare class SuflerPiPNativeModule extends NativeModule<SuflerPiPEvents> {
  /** False on iPhone simulators, where sample-buffer PiP does not exist. */
  isSupported: boolean;
  /** Pushed once per script, never per frame. */
  setScript(lines: string[], startTokenIndex: number): Promise<void>;
  setStyle(style: PiPStyle): Promise<void>;
  /** Must be called from a user gesture, or iOS silently ignores it. */
  startPictureInPicture(): Promise<boolean>;
  stopPictureInPicture(): Promise<void>;
  isActive(): boolean;
  /** False until the preview layer has been in a window for a run loop turn or two. */
  isPossible(): boolean;
  /**
   * Live state of the overlay pipeline. PiP fails silently — an empty floating window and no
   * error anywhere — and none of it exists in the Simulator, so this is the only practical way to
   * see whether frames are actually being produced on a device.
   */
  getDiagnostics(): PiPDiagnostics;
  setCursor(tokenIndex: number): void;
}

/**
 * Optional rather than required so the JS layer still runs on Android and web, where this module
 * does not exist. Every call site has to tolerate `null` — see `isAvailable`.
 */
export const SuflerPiP = requireOptionalNativeModule<SuflerPiPNativeModule>('SuflerPiP');

export const isPiPAvailable = () => SuflerPiP != null && SuflerPiP.isSupported;

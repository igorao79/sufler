import { requireOptionalNativeModule, type NativeModule } from 'expo';

import type { SharedItem } from './types';

type SuflerInboxEvents = {
  /** The share extension just wrote something while the app was already running. */
  onSharedItem: () => void;
};

declare class SuflerInboxNativeModule extends NativeModule<SuflerInboxEvents> {
  /** Reads and deletes — draining twice returns nothing the second time. */
  drain(): Promise<SharedItem[]>;
  /** False when the App Group is misconfigured, which otherwise makes shares vanish silently. */
  isAppGroupAvailable(): boolean;
}

export const SuflerInbox = requireOptionalNativeModule<SuflerInboxNativeModule>('SuflerInbox');

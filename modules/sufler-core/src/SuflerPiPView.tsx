import { requireNativeView } from 'expo';
import * as React from 'react';
import { View, type ViewProps } from 'react-native';

import { SuflerPiP } from './SuflerPiP';

export type SuflerPiPViewProps = ViewProps & {
  onReady?: (event: { nativeEvent: { ready: boolean } }) => void;
};

const NativeView: React.ComponentType<SuflerPiPViewProps> | null = SuflerPiP
  ? requireNativeView('SuflerPiP')
  : null;

/**
 * The visible home of the Picture in Picture source layer.
 *
 * This has to be a real, laid-out, visible view: automatic PiP refuses to engage when its source
 * layer is hidden, transparent, zero-sized, or inside a modal (a separate window is not the key
 * window). Rendering it as a genuine preview card satisfies that honestly and doubles as the only
 * way to see the rendered frames in the Simulator, where PiP itself is unavailable.
 */
export function SuflerPiPView(props: SuflerPiPViewProps) {
  if (!NativeView) return <View {...props} />;
  return <NativeView {...props} />;
}

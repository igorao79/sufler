import { useCallback, useEffect, useState } from 'react';
import { Linking } from 'react-native';

import { SuflerSpeech, type Permissions } from '../../modules/sufler-core';
import { useSufler } from '../store';

const UNAVAILABLE: Permissions = { speech: 'denied', mic: 'denied' };

/**
 * Speech recognition and microphone access are requested together, before the audio session is
 * activated, because starting the engine without both produces an opaque CoreAudio error rather
 * than anything a user could act on.
 */
export function usePermissions() {
  const perms = useSufler((state) => state.perms);
  const setPerms = useSufler((state) => state.setPerms);
  const [requesting, setRequesting] = useState(false);

  const refresh = useCallback(() => {
    setPerms(SuflerSpeech ? SuflerSpeech.getPermissions() : UNAVAILABLE);
  }, [setPerms]);

  useEffect(refresh, [refresh]);

  const request = useCallback(async () => {
    if (!SuflerSpeech) {
      setPerms(UNAVAILABLE);
      return UNAVAILABLE;
    }
    setRequesting(true);
    try {
      const result = await SuflerSpeech.requestPermissions();
      setPerms(result);
      return result;
    } finally {
      setRequesting(false);
    }
  }, [setPerms]);

  const granted = perms.speech === 'granted' && perms.mic === 'granted';
  // Once denied, iOS never shows the prompt again — the only path forward is Settings.
  const permanentlyDenied =
    perms.speech === 'denied' || perms.mic === 'denied' || perms.speech === 'restricted';

  return {
    perms,
    granted,
    permanentlyDenied,
    requesting,
    request,
    refresh,
    openSettings: () => Linking.openSettings(),
  };
}

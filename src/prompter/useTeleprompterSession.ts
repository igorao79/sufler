import { useCallback, useEffect, useRef, useState } from 'react';

import { SuflerPiP, SuflerSpeech, isPiPAvailable } from '../../modules/sufler-core';
import { usePermissions } from '../permissions/usePermissions';
import { useSufler, type ScriptDoc } from '../store';

/**
 * Wires one script to the native session: pushes the text down, keeps the render style in sync,
 * and owns start/stop.
 *
 * Note what crosses the bridge here and what does not. The script goes down once. The style goes
 * down when the user changes it. The cursor never comes back through this hook at all — it reaches
 * the overlay renderer natively and the in-app view through Reanimated shared values.
 */
export function useTeleprompterSession(script: ScriptDoc | undefined) {
  const status = useSufler((state) => state.status);
  const setStatus = useSufler((state) => state.setStatus);
  const setError = useSufler((state) => state.setError);
  const setPip = useSufler((state) => state.setPip);

  const locale = useSufler((state) => state.locale);
  const preferOnDevice = useSufler((state) => state.preferOnDevice);
  const fontSize = useSufler((state) => state.fontSize);
  const mirrored = useSufler((state) => state.mirrored);
  const showDebug = useSufler((state) => state.showDebug);
  const tuning = useSufler((state) => state.tuning);

  const permissions = usePermissions();
  const [busy, setBusy] = useState(false);
  const startedRef = useRef(false);

  // Push the script down once per script.
  useEffect(() => {
    if (!SuflerPiP || !script) return;
    SuflerPiP.setScript(script.lines, 0).catch((error: Error) =>
      setError({ code: 'set_script_failed', message: error.message }),
    );
  }, [script, setError]);

  useEffect(() => {
    SuflerPiP?.setStyle({ fontSize, mirrored, debugOverlay: showDebug }).catch(() => {});
  }, [fontSize, mirrored, showDebug]);

  useEffect(() => {
    SuflerSpeech?.setTuning(tuning);
  }, [tuning]);

  // PiP lifecycle events, including the window's own play/pause button — which is the only control
  // the user has once they are in another app.
  useEffect(() => {
    if (!SuflerPiP) return;

    const state = SuflerPiP.addListener('onPiPStateChanged', (event) => {
      setPip({ active: event.active, possible: event.possible });
    });
    const toggled = SuflerPiP.addListener('onPiPPlaybackToggled', (event) => {
      setStatus(event.playing ? 'following' : 'idle');
    });
    const failed = SuflerPiP.addListener('onPiPError', (event) => setError(event));

    return () => {
      state.remove();
      toggled.remove();
      failed.remove();
    };
  }, [setError, setPip, setStatus]);

  // Leaving the screen must not leave the microphone open.
  useEffect(
    () => () => {
      if (startedRef.current) {
        SuflerSpeech?.stop().catch(() => {});
        startedRef.current = false;
      }
    },
    [],
  );

  const start = useCallback(async () => {
    if (!SuflerSpeech) {
      setError({
        code: 'unavailable',
        message: 'Нативный модуль недоступен. Соберите приложение через expo run:ios.',
      });
      return;
    }

    setBusy(true);
    setStatus('starting');
    setError(null);
    try {
      const granted = permissions.granted ? permissions.perms : await permissions.request();
      if (granted.speech !== 'granted' || granted.mic !== 'granted') {
        setError({
          code: 'permission_denied',
          message: 'Нужен доступ к микрофону и распознаванию речи — без них суфлёр не сможет следить за текстом.',
        });
        return;
      }

      await SuflerSpeech.start({ locale, preferOnDevice, startTokenIndex: -1 });
      startedRef.current = true;
    } catch (error) {
      setError({ code: 'start_failed', message: (error as Error).message });
    } finally {
      setBusy(false);
    }
  }, [locale, permissions, preferOnDevice, setError, setStatus]);

  const stop = useCallback(async () => {
    setBusy(true);
    try {
      await SuflerSpeech?.stop();
      startedRef.current = false;
    } finally {
      setBusy(false);
    }
  }, []);

  /**
   * Must run inside the touch handler: `startPictureInPicture()` outside a user gesture is a silent
   * no-op, which is exactly the kind of failure that costs an afternoon to diagnose.
   */
  const openOverlay = useCallback(async () => {
    if (!isPiPAvailable()) {
      setError({
        code: 'pip_unsupported',
        message:
          'Picture in Picture недоступен. На симуляторах iPhone его нет — проверьте на реальном устройстве.',
      });
      return;
    }
    try {
      await SuflerPiP!.startPictureInPicture();
    } catch (error) {
      setError({ code: 'pip_start_failed', message: (error as Error).message });
    }
  }, [setError]);

  const closeOverlay = useCallback(async () => {
    await SuflerPiP?.stopPictureInPicture();
  }, []);

  const restart = useCallback(() => {
    SuflerPiP?.setCursor(0);
  }, []);

  const isFollowing = status === 'following' || status === 'stalled' || status === 'interrupted';

  return { busy, isFollowing, start, stop, openOverlay, closeOverlay, restart, permissions };
}

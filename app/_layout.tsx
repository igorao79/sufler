import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef } from 'react';
import { Alert, AppState, type AppStateStatus } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { SuflerInbox } from '../modules/sufler-core';
import { useSufler } from '../src/store';
import { theme } from '../src/ui/theme';

export default function RootLayout() {
  const createScript = useSufler((state) => state.createScript);

  /**
   * Pulls anything the share extension left in the App Group container.
   *
   * The extension deliberately does not launch the app — the responder-chain trick that makes that
   * possible is not a public path and is a recurring rejection reason. So items wait in the
   * container and get collected here, on launch and on every return to the foreground.
   */
  const drainInbox = useCallback(async () => {
    if (!SuflerInbox) return;

    if (!SuflerInbox.isAppGroupAvailable()) {
      // Nil container means the App Group is not enabled for both bundle identifiers in the
      // developer portal. Shares vanish silently in that state, so say so loudly instead.
      console.warn('[Sufler] App Group unavailable — shared scripts cannot be received.');
      return;
    }

    try {
      const items = await SuflerInbox.drain();
      if (items.length === 0) return;

      for (const item of items) {
        createScript({ title: item.title, text: item.text, source: 'shared' });
      }
      Alert.alert(
        'Добавлено',
        items.length === 1
          ? `Скрипт «${items[0].title}» сохранён.`
          : `Сохранено скриптов: ${items.length}.`,
      );
    } catch (error) {
      console.warn('[Sufler] Failed to drain the share inbox', error);
    }
  }, [createScript]);

  const appState = useRef(AppState.currentState);

  useEffect(() => {
    drainInbox();

    const subscription = AppState.addEventListener('change', (next: AppStateStatus) => {
      if (appState.current.match(/inactive|background/) && next === 'active') {
        drainInbox();
      }
      appState.current = next;
    });

    // Immediate pickup when the app is already running and the user shares from another app.
    const shared = SuflerInbox?.addListener('onSharedItem', () => {
      drainInbox();
    });

    return () => {
      subscription.remove();
      shared?.remove();
    };
  }, [drainInbox]);

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: theme.color.background }}>
      <SafeAreaProvider>
        <StatusBar style="light" />
        <Stack
          screenOptions={{
            headerStyle: { backgroundColor: theme.color.background },
            headerTintColor: theme.color.text,
            headerTitleStyle: { color: theme.color.text },
            contentStyle: { backgroundColor: theme.color.background },
          }}>
          <Stack.Screen name="index" options={{ title: 'Sufler' }} />
          <Stack.Screen name="editor/[id]" options={{ title: 'Текст' }} />
          <Stack.Screen
            name="prompter/[id]"
            options={{ title: 'Суфлёр', headerBackTitle: 'Назад' }}
          />
          <Stack.Screen name="settings" options={{ title: 'Настройки' }} />
        </Stack>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

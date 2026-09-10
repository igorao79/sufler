import { useKeepAwake } from 'expo-keep-awake';
import { useLocalSearchParams } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { DebugStrip } from '../../src/prompter/DebugStrip';
import { PiPPreviewCard } from '../../src/prompter/PiPPreviewCard';
import { TeleprompterView } from '../../src/prompter/TeleprompterView';
import { usePositionBridge } from '../../src/prompter/usePositionBridge';
import { useTeleprompterSession } from '../../src/prompter/useTeleprompterSession';
import { useSufler } from '../../src/store';
import { Button } from '../../src/ui/Button';
import { theme } from '../../src/ui/theme';

export default function PrompterScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const insets = useSafeAreaInsets();
  useKeepAwake();

  const doc = useSufler((state) => (id ? state.scripts[id] : undefined));
  const status = useSufler((state) => state.status);
  const pipActive = useSufler((state) => state.pipActive);
  const lastError = useSufler((state) => state.lastError);
  const setError = useSufler((state) => state.setError);
  const fontSize = useSufler((state) => state.fontSize);
  const lineHeight = useSufler((state) => state.lineHeight);
  const mirrored = useSufler((state) => state.mirrored);
  const showDebug = useSufler((state) => state.showDebug);

  const position = usePositionBridge();
  const session = useTeleprompterSession(doc);

  if (!doc) {
    return (
      <View style={styles.missing}>
        <Text style={styles.missingText}>Скрипт не найден.</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <PiPPreviewCard active={pipActive}>
          <StatusLine status={status} />
        </PiPPreviewCard>
      </View>

      <TeleprompterView
        lines={doc.lines}
        position={position}
        fontSize={fontSize}
        lineHeight={lineHeight}
        mirrored={mirrored}
      />

      {lastError && (
        <Pressable style={styles.error} onPress={() => setError(null)}>
          <Text style={styles.errorText}>{lastError.message}</Text>
          <Text style={styles.errorDismiss}>Нажмите, чтобы скрыть</Text>
        </Pressable>
      )}

      {showDebug && <DebugStrip />}

      <View style={[styles.controls, { paddingBottom: insets.bottom + theme.space(3) }]}>
        <View style={styles.primaryRow}>
          <Button
            title={session.isFollowing ? 'Стоп' : 'Старт'}
            variant={session.isFollowing ? 'danger' : 'primary'}
            loading={session.busy}
            onPress={session.isFollowing ? session.stop : session.start}
            style={styles.grow}
          />
          <Button title="В начало" variant="secondary" onPress={session.restart} />
        </View>

        <Button
          title={pipActive ? 'Закрыть окно поверх приложений' : 'Показать поверх других приложений'}
          variant="secondary"
          onPress={pipActive ? session.closeOverlay : session.openOverlay}
        />

        <Text style={styles.hint}>
          Окно также открывается само, когда вы уходите из Sufler в другое приложение — если карточка
          предпросмотра была видна на экране.
        </Text>
      </View>
    </View>
  );
}

function StatusLine({ status }: { status: string }) {
  const map: Record<string, { text: string; color: string }> = {
    idle: { text: 'Готов к старту', color: theme.color.textMuted },
    starting: { text: 'Запускаем распознавание…', color: theme.color.textMuted },
    following: { text: 'Слушаю и веду текст за вами', color: theme.color.success },
    stalled: { text: 'Пауза — жду, когда вы продолжите', color: theme.color.accent },
    interrupted: {
      text: 'Микрофон занят другим приложением — прокрутка остановлена',
      color: theme.color.danger,
    },
    error: { text: 'Ошибка', color: theme.color.danger },
  };
  const entry = map[status] ?? map.idle;

  return (
    <View style={styles.statusRow}>
      <View style={[styles.statusDot, { backgroundColor: entry.color }]} />
      <Text style={[styles.statusText, { color: entry.color }]}>{entry.text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.color.background },
  header: { padding: theme.space(4) },
  statusRow: { flexDirection: 'row', alignItems: 'flex-start', gap: theme.space(2) },
  statusDot: { width: 8, height: 8, borderRadius: 4, marginTop: 5 },
  statusText: { fontSize: theme.font.small, flex: 1, lineHeight: 18 },
  controls: {
    padding: theme.space(4),
    gap: theme.space(3),
    borderTopWidth: 1,
    borderTopColor: theme.color.border,
    backgroundColor: theme.color.background,
  },
  primaryRow: { flexDirection: 'row', gap: theme.space(3) },
  grow: { flex: 1 },
  hint: {
    color: theme.color.textFaint,
    fontSize: 12,
    lineHeight: 17,
    textAlign: 'center',
  },
  error: {
    backgroundColor: 'rgba(255, 90, 90, 0.14)',
    borderTopWidth: 1,
    borderTopColor: theme.color.danger,
    padding: theme.space(3),
    gap: 2,
  },
  errorText: { color: theme.color.danger, fontSize: theme.font.small, lineHeight: 19 },
  errorDismiss: { color: theme.color.textFaint, fontSize: 11 },
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  missingText: { color: theme.color.textMuted },
});

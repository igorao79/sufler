import { Link, router, useNavigation } from 'expo-router';
import { useLayoutEffect, useState } from 'react';
import {
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { pickTextDocument } from '../src/import/pickDocument';
import { estimateDurationSeconds, formatDuration } from '../src/lib/tokenize';
import { useSufler, type ScriptDoc } from '../src/store';
import { Button } from '../src/ui/Button';
import { theme } from '../src/ui/theme';

export default function LibraryScreen() {
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();

  const order = useSufler((state) => state.order);
  const scripts = useSufler((state) => state.scripts);
  const createScript = useSufler((state) => state.createScript);
  const removeScript = useSufler((state) => state.removeScript);

  const [importing, setImporting] = useState(false);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Link href="/settings" asChild>
          <TouchableOpacity hitSlop={12}>
            <Text style={styles.headerAction}>Настройки</Text>
          </TouchableOpacity>
        </Link>
      ),
    });
  }, [navigation]);

  const documents = order.map((id) => scripts[id]).filter(Boolean) as ScriptDoc[];

  const onCreate = () => {
    const doc = createScript({ text: '', source: 'typed', title: 'Новый скрипт' });
    router.push(`/editor/${doc.id}`);
  };

  const onImport = async () => {
    setImporting(true);
    try {
      const picked = await pickTextDocument();
      if (!picked) return;
      const doc = createScript({ title: picked.title, text: picked.text, source: 'file' });
      router.push(`/editor/${doc.id}`);
    } catch (error) {
      Alert.alert('Не удалось открыть файл', (error as Error).message);
    } finally {
      setImporting(false);
    }
  };

  const onDelete = (doc: ScriptDoc) => {
    Alert.alert('Удалить скрипт?', doc.title, [
      { text: 'Отмена', style: 'cancel' },
      { text: 'Удалить', style: 'destructive', onPress: () => removeScript(doc.id) },
    ]);
  };

  return (
    <View style={styles.container}>
      <FlatList
        data={documents}
        keyExtractor={(item) => item.id}
        contentContainerStyle={[styles.list, documents.length === 0 && styles.listEmpty]}
        ListEmptyComponent={<EmptyState />}
        renderItem={({ item }) => (
          <Pressable
            style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
            onPress={() => router.push(`/prompter/${item.id}`)}
            onLongPress={() => onDelete(item)}>
            <View style={styles.rowText}>
              <Text style={styles.rowTitle} numberOfLines={1}>
                {item.title}
              </Text>
              <Text style={styles.rowMeta}>
                {item.lines.length} строк · ≈{formatDuration(estimateDurationSeconds(item.text))}
                {item.source === 'shared' ? ' · из общего доступа' : ''}
                {item.source === 'file' ? ' · из файла' : ''}
              </Text>
            </View>
            <Pressable
              hitSlop={12}
              onPress={() => router.push(`/editor/${item.id}`)}
              style={styles.editButton}>
              <Text style={styles.editLabel}>Правка</Text>
            </Pressable>
          </Pressable>
        )}
      />

      <View style={[styles.actions, { paddingBottom: insets.bottom + theme.space(4) }]}>
        <Button title="Новый скрипт" onPress={onCreate} />
        <Button
          title="Импорт .txt / .md"
          variant="secondary"
          loading={importing}
          onPress={onImport}
        />
      </View>
    </View>
  );
}

function EmptyState() {
  return (
    <View style={styles.empty}>
      <Text style={styles.emptyTitle}>Пока пусто</Text>
      <Text style={styles.emptyText}>
        Создайте скрипт, импортируйте .txt или .md, либо отправьте текст в Sufler через «Поделиться»
        из любого приложения.
      </Text>
      <Text style={styles.emptyNote}>
        Суфлёр показывается поверх других приложений в окне Picture in Picture и прокручивается
        сам — за вашей речью.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.color.background },
  headerAction: { color: theme.color.accent, fontSize: 16 },
  list: { padding: theme.space(4), gap: theme.space(3) },
  listEmpty: { flexGrow: 1, justifyContent: 'center' },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: theme.color.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.color.border,
    padding: theme.space(4),
    gap: theme.space(3),
  },
  rowPressed: { opacity: 0.75 },
  rowText: { flex: 1, gap: 4 },
  rowTitle: { color: theme.color.text, fontSize: 17, fontWeight: '600' },
  rowMeta: { color: theme.color.textMuted, fontSize: theme.font.small },
  editButton: {
    paddingHorizontal: theme.space(3),
    paddingVertical: theme.space(2),
    borderRadius: theme.radius.sm,
    backgroundColor: theme.color.surfaceRaised,
  },
  editLabel: { color: theme.color.textMuted, fontSize: theme.font.small },
  actions: {
    padding: theme.space(4),
    gap: theme.space(3),
    borderTopWidth: 1,
    borderTopColor: theme.color.border,
  },
  empty: { padding: theme.space(6), gap: theme.space(3), alignItems: 'center' },
  emptyTitle: { color: theme.color.text, fontSize: theme.font.section, fontWeight: '700' },
  emptyText: {
    color: theme.color.textMuted,
    fontSize: theme.font.body,
    textAlign: 'center',
    lineHeight: 23,
  },
  emptyNote: {
    color: theme.color.textFaint,
    fontSize: theme.font.small,
    textAlign: 'center',
    lineHeight: 19,
  },
});

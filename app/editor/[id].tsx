import { router, useLocalSearchParams, useNavigation } from 'expo-router';
import { useCallback, useLayoutEffect, useMemo, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { countWords, estimateDurationSeconds, formatDuration, splitIntoLines } from '../../src/lib/tokenize';
import { useSufler } from '../../src/store';
import { Button } from '../../src/ui/Button';
import { theme } from '../../src/ui/theme';

export default function EditorScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();

  const doc = useSufler((state) => (id ? state.scripts[id] : undefined));
  const updateScript = useSufler((state) => state.updateScript);

  const [title, setTitle] = useState(doc?.title ?? '');
  const [text, setText] = useState(doc?.text ?? '');

  const save = useCallback(() => {
    if (!id) return;
    updateScript(id, { title, text });
  }, [id, text, title, updateScript]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <TouchableOpacity
          hitSlop={12}
          onPress={() => {
            save();
            router.back();
          }}>
          <Text style={styles.headerAction}>Готово</Text>
        </TouchableOpacity>
      ),
    });
  }, [navigation, save]);

  const stats = useMemo(() => {
    const words = countWords(text);
    const lines = splitIntoLines(text).length;
    return { words, lines, duration: formatDuration(estimateDurationSeconds(text)) };
  }, [text]);

  if (!doc) {
    return (
      <View style={styles.missing}>
        <Text style={styles.missingText}>Скрипт не найден.</Text>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={90}>
      <ScrollView contentContainerStyle={styles.scroll} keyboardDismissMode="interactive">
        <TextInput
          value={title}
          onChangeText={setTitle}
          onBlur={save}
          placeholder="Название"
          placeholderTextColor={theme.color.textFaint}
          style={styles.title}
        />
        <TextInput
          value={text}
          onChangeText={setText}
          onBlur={save}
          placeholder="Вставьте или наберите текст выступления…"
          placeholderTextColor={theme.color.textFaint}
          multiline
          textAlignVertical="top"
          style={styles.body}
        />
        <Text style={styles.stats}>
          {stats.words} слов · {stats.lines} строк · ≈{stats.duration} при обычном темпе
        </Text>
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + theme.space(4) }]}>
        <Button
          title="Открыть суфлёр"
          disabled={text.trim().length === 0}
          onPress={() => {
            save();
            router.replace(`/prompter/${doc.id}`);
          }}
        />
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.color.background },
  scroll: { padding: theme.space(4), gap: theme.space(3) },
  headerAction: { color: theme.color.accent, fontSize: 16, fontWeight: '600' },
  title: {
    color: theme.color.text,
    fontSize: theme.font.section,
    fontWeight: '700',
    backgroundColor: theme.color.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.color.border,
    paddingHorizontal: theme.space(4),
    paddingVertical: theme.space(3),
  },
  body: {
    color: theme.color.text,
    fontSize: 17,
    lineHeight: 25,
    minHeight: 320,
    backgroundColor: theme.color.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.color.border,
    padding: theme.space(4),
  },
  stats: { color: theme.color.textMuted, fontSize: theme.font.small },
  footer: {
    padding: theme.space(4),
    borderTopWidth: 1,
    borderTopColor: theme.color.border,
  },
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  missingText: { color: theme.color.textMuted },
});

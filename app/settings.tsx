import Slider from '@react-native-community/slider';
import { useMemo } from 'react';
import { ScrollView, StyleSheet, Switch, Text, View } from 'react-native';

import { SuflerSpeech } from '../modules/sufler-core';
import { useSufler } from '../src/store';
import { Button } from '../src/ui/Button';
import { theme } from '../src/ui/theme';

export default function SettingsScreen() {
  const locale = useSufler((state) => state.locale);
  const preferOnDevice = useSufler((state) => state.preferOnDevice);
  const fontSize = useSufler((state) => state.fontSize);
  const lineHeight = useSufler((state) => state.lineHeight);
  const mirrored = useSufler((state) => state.mirrored);
  const showDebug = useSufler((state) => state.showDebug);
  const tuning = useSufler((state) => state.tuning);
  const setSetting = useSufler((state) => state.setSetting);
  const setTuning = useSufler((state) => state.setTuning);
  const resetTuning = useSufler((state) => state.resetTuning);

  const onDeviceAvailable = useMemo(
    () => SuflerSpeech?.isOnDeviceAvailable(locale) ?? false,
    [locale],
  );

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Section title="Распознавание речи">
        <Row label="Язык">
          <Text style={styles.value}>{locale}</Text>
        </Row>
        <ToggleRow
          label="Распознавание на устройстве"
          value={preferOnDevice}
          onChange={(value) => setSetting('preferOnDevice', value)}
        />
        <Text style={styles.note}>
          {onDeviceAvailable
            ? 'Доступно для этого языка: работает без интернета, звук не покидает устройство и нет ограничения на длину запроса.'
            : 'Для этого языка на устройстве недоступно — будет использовано облачное распознавание Apple. Требуется интернет, аудио отправляется на серверы Apple.'}
        </Text>
      </Section>

      <Section title="Внешний вид">
        <SliderRow
          label="Размер шрифта"
          value={fontSize}
          min={18}
          max={54}
          step={1}
          format={(v) => `${Math.round(v)} pt`}
          onChange={(value) => setSetting('fontSize', Math.round(value))}
        />
        <SliderRow
          label="Межстрочный интервал"
          value={lineHeight}
          min={1.1}
          max={2}
          step={0.05}
          format={(v) => v.toFixed(2)}
          onChange={(value) => setSetting('lineHeight', Number(value.toFixed(2)))}
        />
        <ToggleRow
          label="Зеркальное отражение"
          value={mirrored}
          onChange={(value) => setSetting('mirrored', value)}
        />
        <Text style={styles.note}>
          Зеркало нужно для съёмки через светоделительное стекло — текст читается правильно в
          отражении.
        </Text>
      </Section>

      <Section title="Точность следования">
        <Text style={styles.note}>
          Алгоритм сопоставляет услышанные слова с текстом. Универсальных настроек тут нет: темп
          речи, акцент и то, читаете вы дословно или пересказываете, меняют оптимальные значения —
          поэтому ручки вынесены сюда.
        </Text>
        <SliderRow
          label="Окно гипотезы"
          hint="Сколько последних распознанных слов сопоставлять. Больше — устойчивее, но с задержкой."
          value={tuning.hypothesisWindow}
          min={3}
          max={14}
          step={1}
          format={(v) => `${Math.round(v)} слов`}
          onChange={(value) => setTuning({ hypothesisWindow: Math.round(value) })}
        />
        <SliderRow
          label="Поиск вперёд"
          hint="Насколько далеко вперёд искать. Больше — легче поймать пропущенный абзац."
          value={tuning.lookahead}
          min={20}
          max={300}
          step={10}
          format={(v) => `${Math.round(v)} слов`}
          onChange={(value) => setTuning({ lookahead: Math.round(value) })}
        />
        <SliderRow
          label="Порог принятия"
          hint="Ниже — курсор двигается охотнее, но чаще ошибается."
          value={tuning.acceptThreshold}
          min={0.3}
          max={0.9}
          step={0.05}
          format={(v) => v.toFixed(2)}
          onChange={(value) => setTuning({ acceptThreshold: Number(value.toFixed(2)) })}
        />
        <SliderRow
          label="Пауза до «жду»"
          hint="Через сколько тишины считать, что вы остановились. Текст при этом не едет дальше сам."
          value={tuning.stallTimeoutMs}
          min={800}
          max={8000}
          step={100}
          format={(v) => `${(v / 1000).toFixed(1)} с`}
          onChange={(value) => setTuning({ stallTimeoutMs: Math.round(value) })}
        />
        <Button title="Сбросить к значениям по умолчанию" variant="secondary" onPress={resetTuning} />
      </Section>

      <Section title="Отладка">
        <ToggleRow
          label="Показывать распознанное и оценки"
          value={showDebug}
          onChange={(value) => setSetting('showDebug', value)}
        />
        <Text style={styles.note}>
          Полоска под текстом показывает, что именно услышал распознаватель и как алгоритм оценил
          позицию. Это же выводится поверх окна Picture in Picture.
        </Text>
      </Section>

      <Section title="Про ограничения iOS">
        <Text style={styles.note}>
          iOS не разрешает обычным приложениям рисовать поверх других — единственный легальный
          способ это Picture in Picture, его Sufler и использует.{'\n\n'}
          Микрофон на iPhone эксклюзивен: пока другое приложение записывает звук (Камера в режиме
          видеозаписи, звонок в Zoom или Meet), Sufler не слышит вас и прокрутка останавливается.
          Обойти это нельзя — окно при этом покажет, что микрофон занят.
        </Text>
      </Section>
    </ScrollView>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <View style={styles.card}>{children}</View>
    </View>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      {children}
    </View>
  );
}

function ToggleRow({
  label,
  value,
  onChange,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <Row label={label}>
      <Switch
        value={value}
        onValueChange={onChange}
        trackColor={{ true: theme.color.accent, false: theme.color.border }}
        thumbColor={theme.color.text}
      />
    </Row>
  );
}

function SliderRow({
  label,
  hint,
  value,
  min,
  max,
  step,
  format,
  onChange,
}: {
  label: string;
  hint?: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format: (value: number) => string;
  onChange: (value: number) => void;
}) {
  return (
    <View style={styles.sliderRow}>
      <View style={styles.row}>
        <Text style={styles.label}>{label}</Text>
        <Text style={styles.value}>{format(value)}</Text>
      </View>
      {hint && <Text style={styles.hint}>{hint}</Text>}
      <Slider
        value={value}
        minimumValue={min}
        maximumValue={max}
        step={step}
        onValueChange={onChange}
        minimumTrackTintColor={theme.color.accent}
        maximumTrackTintColor={theme.color.border}
        thumbTintColor={theme.color.accent}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: theme.color.background },
  content: { padding: theme.space(4), gap: theme.space(6), paddingBottom: theme.space(12) },
  section: { gap: theme.space(2) },
  sectionTitle: {
    color: theme.color.textMuted,
    fontSize: theme.font.small,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  card: {
    backgroundColor: theme.color.surface,
    borderRadius: theme.radius.md,
    borderWidth: 1,
    borderColor: theme.color.border,
    padding: theme.space(4),
    gap: theme.space(3),
  },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: theme.space(3) },
  sliderRow: { gap: theme.space(1) },
  label: { color: theme.color.text, fontSize: theme.font.body, flexShrink: 1 },
  value: { color: theme.color.accent, fontSize: theme.font.body, fontVariant: ['tabular-nums'] },
  hint: { color: theme.color.textFaint, fontSize: 12, lineHeight: 17 },
  note: { color: theme.color.textMuted, fontSize: theme.font.small, lineHeight: 20 },
});

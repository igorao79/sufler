/**
 * Splits raw script text into display lines.
 *
 * Lines are the unit everything else works in: the aligner reports a line index, the teleprompter
 * measures line offsets, and the PiP renderer draws three of them. Paragraphs from a pasted
 * document are far too long to be any of those, so they are broken at sentence boundaries and then,
 * if still long, at word boundaries.
 */
export function splitIntoLines(text: string, maxChars = 64): string[] {
  const paragraphs = text.replace(/\r\n/g, '\n').split('\n');
  const lines: string[] = [];

  for (const paragraph of paragraphs) {
    const trimmed = paragraph.trim();
    if (!trimmed) {
      // Keep blank lines: they are the visual paragraph break the reader relies on.
      if (lines.length > 0 && lines[lines.length - 1] !== '') lines.push('');
      continue;
    }
    if (trimmed.length <= maxChars) {
      lines.push(trimmed);
      continue;
    }
    for (const sentence of splitSentences(trimmed)) {
      lines.push(...wrapWords(sentence, maxChars));
    }
  }

  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

function splitSentences(text: string): string[] {
  // Split after ., !, ? or … when followed by whitespace. Deliberately naive: abbreviations produce
  // a slightly short line, which costs nothing, whereas a proper sentence tokeniser costs a
  // dependency and a lot of locale-specific rules.
  return text
    .split(/(?<=[.!?…])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function wrapWords(text: string, maxChars: number): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let current = '';

  for (const word of words) {
    if (!current) {
      current = word;
    } else if (current.length + 1 + word.length <= maxChars) {
      current += ` ${word}`;
    } else {
      lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines;
}

/** Word count, used for the reading-time estimate. */
export function countWords(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

/** Rough spoken duration at a typical presentation pace of ~130 words per minute. */
export function estimateDurationSeconds(text: string): number {
  return Math.round((countWords(text) / 130) * 60);
}

export function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds} с`;
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return rest === 0 ? `${minutes} мин` : `${minutes} мин ${rest} с`;
}

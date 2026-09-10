import type { StateCreator } from 'zustand';

import { splitIntoLines } from '../lib/tokenize';
import type { ScriptDoc, ScriptSlice, ScriptSource, SuflerStore } from './types';

function makeId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

/** First non-empty line, trimmed to something that fits a list row. */
function deriveTitle(text: string): string {
  const firstLine = text.split('\n').find((line) => line.trim().length > 0) ?? '';
  const trimmed = firstLine.trim();
  if (!trimmed) return 'Без названия';
  return trimmed.length > 48 ? `${trimmed.slice(0, 45)}…` : trimmed;
}

export const createScriptSlice: StateCreator<SuflerStore, [], [], ScriptSlice> = (set, get) => ({
  scripts: {},
  order: [],

  upsertScript: (doc) =>
    set((state) => ({
      scripts: { ...state.scripts, [doc.id]: doc },
      order: state.order.includes(doc.id) ? state.order : [doc.id, ...state.order],
    })),

  createScript: ({ title, text, source }) => {
    const now = Date.now();
    const doc: ScriptDoc = {
      id: makeId(),
      title: title?.trim() || deriveTitle(text),
      text,
      // Split once, here, rather than on every prompter render.
      lines: splitIntoLines(text),
      source,
      createdAt: now,
      updatedAt: now,
    };
    get().upsertScript(doc);
    return doc;
  },

  updateScript: (id, patch) =>
    set((state) => {
      const existing = state.scripts[id];
      if (!existing) return state;

      const text = patch.text ?? existing.text;
      const updated: ScriptDoc = {
        ...existing,
        text,
        lines: patch.text !== undefined ? splitIntoLines(text) : existing.lines,
        title: patch.title !== undefined ? patch.title.trim() || deriveTitle(text) : existing.title,
        updatedAt: Date.now(),
      };
      return { scripts: { ...state.scripts, [id]: updated } };
    }),

  removeScript: (id) =>
    set((state) => {
      const { [id]: _removed, ...rest } = state.scripts;
      return { scripts: rest, order: state.order.filter((entry) => entry !== id) };
    }),
});

export type { ScriptSource };

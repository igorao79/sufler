/**
 * A teleprompter is read at a glance, in a hurry, often at arm's length. Everything here is
 * dark-first and high-contrast for that reason — this is not a preference, it is the use case.
 */
export const theme = {
  color: {
    background: '#0B0B0F',
    surface: '#16161D',
    surfaceRaised: '#1E1E27',
    border: '#2A2A36',
    text: '#F5F5F7',
    textMuted: '#9A9AA8',
    textFaint: '#5C5C6B',
    accent: '#FFB833',
    accentText: '#1A1200',
    danger: '#FF5A5A',
    success: '#4ADE80',
  },
  radius: { sm: 8, md: 14, lg: 20 },
  space: (n: number) => n * 4,
  font: {
    body: 16,
    small: 13,
    title: 28,
    section: 20,
  },
} as const;

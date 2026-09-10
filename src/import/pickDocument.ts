import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system';

export type PickedDocument = {
  title: string;
  text: string;
};

/**
 * Imports a plain-text or Markdown script from Files/iCloud.
 *
 * `copyToCacheDirectory` matters: without it the picked URL is a security-scoped reference that
 * may not still be readable by the time we get to it.
 */
export async function pickTextDocument(): Promise<PickedDocument | null> {
  const result = await DocumentPicker.getDocumentAsync({
    type: ['text/plain', 'text/markdown', 'public.plain-text', 'net.daringfireball.markdown'],
    copyToCacheDirectory: true,
    multiple: false,
  });

  if (result.canceled) return null;

  const asset = result.assets?.[0];
  if (!asset) return null;

  const file = new FileSystem.File(asset.uri);
  const text = await file.text();

  const title = asset.name?.replace(/\.(txt|md|markdown)$/i, '') ?? 'Импортированный текст';
  return { title, text };
}

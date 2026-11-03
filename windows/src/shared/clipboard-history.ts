export const CLIPBOARD_HISTORY_LIMITS = { entries: 100, itemBytes: 64 * 1024, totalBytes: 2 * 1024 * 1024 } as const;
export interface ClipboardHistoryEntry { id: string; text: string; copiedAt: number }
export interface ClipboardHistoryState { isEnabled: boolean; entries: ClipboardHistoryEntry[]; totalBytes: number; images?: ClipboardImageEntry[]; totalImageBytes?: number; imageNotice?: string }
export interface ClipboardHistoryBridge {
    showClipboardHistory(): Promise<void>;
    getClipboardHistory(): Promise<ClipboardHistoryState>;
    setClipboardHistoryEnabled(enabled: boolean): Promise<void>;
    deleteClipboardHistoryEntry(id: string): Promise<void>;
    clearClipboardHistory(): Promise<void>;
    useClipboardHistoryEntry(request: { id: string; paste: boolean }): Promise<{ status: string }>;
    getClipboardHistoryImage(id: string): Promise<string | null>;
    previewClipboardHistoryMerge(request: ClipboardMergeRequest): Promise<string>;
    useClipboardHistoryMerge(request: ClipboardMergeRequest & {paste: boolean}): Promise<{status: string}>;
    onClipboardHistoryChanged(callback: (state: ClipboardHistoryState) => void): () => void;
    onShowClipboardHistory(callback: () => void): () => void;
}
export const CLIPBOARD_IMAGE_LIMITS = {entries: 10, itemBytes: 8 * 1024 * 1024, totalBytes: 32 * 1024 * 1024, pixels: 16_000_000, thumbnailSide: 128, previewSide: 960} as const;
export interface ClipboardImageEntry {id: string; copiedAt: number; width: number; height: number; thumbnail: string}
export interface ClipboardMergeRequest {ids: string[]; trimLines: boolean; collapseBlankLines: boolean}
/** Browser and host share cleanup so the preview matches the authoritative host result. */
export function mergeHistoryText(texts: string[], options: Pick<ClipboardMergeRequest, 'trimLines' | 'collapseBlankLines'>): string {
    let lines = texts.join('\n').replace(/\r\n?/g, '\n').split('\n');
    if (options.trimLines) lines = lines.map(line => line.trim());
    if (options.collapseBlankLines) lines = lines.filter((line, index) => line.trim() || index === 0 || lines[index - 1].trim());
    const merged = lines.join('\n');
    if (!merged.trim() || new TextEncoder().encode(merged).length > 64 * 1024) throw new Error('合并文字为空或超过 64 KiB，请减少选择。');
    return merged;
}

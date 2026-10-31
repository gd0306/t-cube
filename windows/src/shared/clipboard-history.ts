export const CLIPBOARD_HISTORY_LIMITS = { entries: 100, itemBytes: 64 * 1024, totalBytes: 2 * 1024 * 1024 } as const;
export interface ClipboardHistoryEntry { id: string; text: string; copiedAt: number }
export interface ClipboardHistoryState { isEnabled: boolean; entries: ClipboardHistoryEntry[]; totalBytes: number }
export interface ClipboardHistoryBridge {
    showClipboardHistory(): Promise<void>;
    getClipboardHistory(): Promise<ClipboardHistoryState>;
    setClipboardHistoryEnabled(enabled: boolean): Promise<void>;
    deleteClipboardHistoryEntry(id: string): Promise<void>;
    clearClipboardHistory(): Promise<void>;
    useClipboardHistoryEntry(request: { id: string; paste: boolean }): Promise<{ status: string }>;
    onClipboardHistoryChanged(callback: (state: ClipboardHistoryState) => void): () => void;
    onShowClipboardHistory(callback: () => void): () => void;
}

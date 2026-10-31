import { randomUUID } from 'node:crypto';
import { CLIPBOARD_HISTORY_LIMITS as LIMITS, type ClipboardHistoryEntry } from '../shared/clipboard-history';

/** Session-only text ownership. No persistence or clipboard access belongs in this model. */
export class ClipboardHistory {
    private entries: Array<ClipboardHistoryEntry & { bytes: number }> = [];
    private bytes = 0;
    get totalBytes(): number { return this.bytes; }
    snapshot(): ClipboardHistoryEntry[] { return this.entries.map(({ id, text, copiedAt }) => ({ id, text, copiedAt })); }
    add(text: string): boolean {
        if (!text.trim() || text.includes('\0')) return false;
        const bytes = Buffer.byteLength(text, 'utf8');
        if (bytes > LIMITS.itemBytes) return false;
        const existing = this.entries.find(entry => entry.text === text);
        if (existing) this.delete(existing.id);
        this.entries.unshift({ id: existing?.id ?? randomUUID(), text, copiedAt: Date.now(), bytes });
        this.bytes += bytes;
        while (this.entries.length > LIMITS.entries || this.bytes > LIMITS.totalBytes) this.bytes -= this.entries.pop()!.bytes;
        return true;
    }
    delete(id: string): void {
        const index = this.entries.findIndex(entry => entry.id === id);
        if (index >= 0) this.bytes -= this.entries.splice(index, 1)[0].bytes;
    }
    clear(): void { this.entries = []; this.bytes = 0; }
}

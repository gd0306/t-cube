import { createHash, randomUUID } from 'node:crypto';
import { CLIPBOARD_HISTORY_LIMITS as LIMITS, CLIPBOARD_IMAGE_LIMITS as IMAGES, type ClipboardImageEntry, type ClipboardHistoryEntry } from '../shared/clipboard-history';

/** Session-only clipboard ownership. No persistence or clipboard access belongs in this model. */
export class ClipboardHistory {
    private entries: Array<ClipboardHistoryEntry & { bytes: number }> = [];
    private bytes = 0;
    private images: Array<ClipboardImageEntry & {png: Buffer; digest: string}> = [];
    get totalImageBytes(): number { return this.images.reduce((total, image) => total + image.png.length, 0); }
    imageSnapshot(): ClipboardImageEntry[] { return this.images.map(({id, copiedAt, width, height, thumbnail}) => ({id, copiedAt, width, height, thumbnail})); }
    hasImage(id: string): boolean { return this.images.some(image => image.id === id); }
    image(id: string): HistoryImage | undefined { const image = this.images.find(entry => entry.id === id); return image ? {...image, png: Buffer.from(image.png)} : undefined; }
    addImage(image: HistoryImage): boolean {
        if (!image.png.length || image.png.length > IMAGES.itemBytes || !Number.isInteger(image.width) || !Number.isInteger(image.height)
            || image.width < 1 || image.height < 1 || image.width * image.height > IMAGES.pixels || image.thumbnail.length > 128 * 1024) return false;
        const digest = createHash('sha256').update(image.png).digest('hex');
        const existing = this.images.find(entry => entry.digest === digest);
        if (existing) this.delete(existing.id);
        this.images.unshift({...image, png: Buffer.from(image.png), digest, id: existing?.id ?? randomUUID(), copiedAt: Date.now()});
        while (this.images.length > IMAGES.entries || this.totalImageBytes > IMAGES.totalBytes) this.images.pop();
        return true;
    }
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
    edit(id: string, text: string): void {
        const entry = this.entries.find(entry => entry.id === id);
        if (!entry) throw new Error('此历史记录已删除或过期。');
        const bytes = Buffer.byteLength(text, 'utf8');
        if (!text.trim() || text.includes('\0') || bytes > LIMITS.itemBytes) throw new Error('文字不能为空，不能包含空字符，且最多 64 KiB。');
        if (this.bytes - entry.bytes + bytes > LIMITS.totalBytes) throw new Error('历史文字合计不能超过 2 MiB，请缩短文字或删除其他记录。');
        this.bytes += bytes - entry.bytes;
        entry.text = text; entry.bytes = bytes;
    }
    delete(id: string): void {
        this.images = this.images.filter(image => image.id !== id);
        const index = this.entries.findIndex(entry => entry.id === id);
        if (index >= 0) this.bytes -= this.entries.splice(index, 1)[0].bytes;
    }
    clear(): void { this.entries = []; this.bytes = 0; this.images = []; }
}

export interface HistoryImage {png: Buffer; width: number; height: number; thumbnail: string}

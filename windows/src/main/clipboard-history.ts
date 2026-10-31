import { ClipboardHistory } from '../core/clipboard-history';
import type { ClipboardHistoryState } from '../shared/clipboard-history';
export interface ClipboardHistoryReader { sequence(): number | null; read(isCurrent: () => boolean): Promise<string | null> }
export type HistoryScheduler = (callback: () => void, milliseconds: number) => () => void;
const schedule: HistoryScheduler = (callback, milliseconds) => {
    const timer = setInterval(callback, milliseconds); timer.unref(); return () => clearInterval(timer);
};

/** Sequence-first opt-in recorder. Epochs invalidate reads spanning privacy/lifecycle changes. */
export class ClipboardHistoryRecorder {
    private readonly history = new ClipboardHistory();
    private enabled = false;
    private disposed = false;
    private generation = 0;
    private lastSequence: number | null = null;
    private reading = false;
    private ownWrites = 0;
    private stopTimer: (() => void) | undefined;
    constructor(private readonly reader: ClipboardHistoryReader, private readonly changed: (state: ClipboardHistoryState) => void,
                private readonly schedule: HistoryScheduler = schedule) {}
    get state(): ClipboardHistoryState { return { isEnabled: this.enabled, entries: this.history.snapshot(), totalBytes: this.history.totalBytes }; }
    setEnabled(enabled: boolean): void {
        if (this.disposed || this.enabled === enabled) return;
        this.generation++; this.enabled = enabled;
        this.stopTimer?.(); this.stopTimer = undefined;
        this.lastSequence = this.sequence();
        if (enabled) this.stopTimer = this.schedule(() => { void this.poll(); }, 500);
        this.publish();
    }
    private sequence(): number | null { try { return this.reader.sequence(); } catch { return null; } }
    async poll(): Promise<void> {
        if (!this.enabled || this.disposed || this.reading || this.ownWrites) return;
        const sequence = this.sequence();
        if (sequence === null || sequence === this.lastSequence) return;
        const first = this.lastSequence === null;
        this.lastSequence = sequence;
        if (first) return;
        const generation = this.generation;
        this.reading = true;
        try {
            const isCurrent = () => this.enabled && !this.disposed && generation === this.generation && this.ownWrites === 0 && this.sequence() === sequence;
            const text = await this.reader.read(isCurrent);
            if (!isCurrent()) return;
            if (text !== null && this.history.add(text)) this.publish();
        } catch { /* A busy/unavailable clipboard is skipped without logging its content. */ }
        finally { this.reading = false; }
    }
    async performOwnWrite<T>(write: () => Promise<T>): Promise<T> {
        this.generation++; this.ownWrites++;
        try { return await write(); }
        finally { this.ownWrites--; this.lastSequence = this.sequence(); }
    }
    delete(id: string): void { this.history.delete(id); this.publish(); }
    clear(): void { this.generation++; this.lastSequence = this.sequence(); this.history.clear(); this.publish(); }
    text(id: string): string {
        const entry = this.history.snapshot().find(entry => entry.id === id);
        if (!entry) throw new Error('此历史记录已删除或过期。');
        return entry.text;
    }
    dispose(): void {
        this.generation++; this.enabled = false; this.disposed = true;
        this.stopTimer?.(); this.stopTimer = undefined; this.history.clear();
    }
    private publish(): void { if (!this.disposed) this.changed(this.state); }
}

/** Renderer requests name a history ID; the host owns the text and existing paste authority. */
export function clipboardHistoryOperations(recorder: ClipboardHistoryRecorder,
    use: (request: { text: string; paste: boolean }) => Promise<{ status: string }>): Record<string, (value?: unknown) => unknown> {
    function empty(value: unknown): void { if (value !== undefined) throw new Error('Invalid history request'); }
    function id(value: unknown): string {
        if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new Error('Invalid history ID');
        return value;
    }
    return {
        getClipboardHistory: value => { empty(value); return recorder.state; },
        setClipboardHistoryEnabled: value => { if (typeof value !== 'boolean') throw new Error('Invalid history preference'); recorder.setEnabled(value); },
        deleteClipboardHistoryEntry: value => recorder.delete(id(value)),
        clearClipboardHistory: value => { empty(value); recorder.clear(); },
        useClipboardHistoryEntry: value => {
            if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid history request');
            const request = value as Record<string, unknown>;
            if (Object.keys(request).some(key => !['id', 'paste'].includes(key)) || typeof request.paste !== 'boolean') throw new Error('Invalid history request');
            return use({ text: recorder.text(id(request.id)), paste: request.paste });
        },
    };
}

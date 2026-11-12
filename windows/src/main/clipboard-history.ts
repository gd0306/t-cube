import { CLIPBOARD_TEXT_ACTIONS, processClipboardText, type ClipboardTextAction } from '../shared/clipboard-text-processing';
import { ClipboardHistory, type HistoryImage } from '../core/clipboard-history';
import { mergeHistoryText, type ClipboardMergeRequest, type ClipboardHistoryState } from '../shared/clipboard-history';
export interface ClipboardHistoryReader { sequence(): number | null; read(isCurrent: () => boolean): Promise<string | HistoryImage | {skippedImage:string} | null> }
export type HistoryScheduler = (callback: () => void, milliseconds: number) => () => void;
const schedulePolling: HistoryScheduler = (callback, milliseconds) => {
    const timer = setInterval(callback, milliseconds); timer.unref(); return () => clearInterval(timer);
};

/** Sequence-first opt-in recorder. Epochs invalidate reads spanning privacy/lifecycle changes. */
export class ClipboardHistoryRecorder {
    private readonly history = new ClipboardHistory();
    private enabled = false;
    private imageNotice: string | undefined;
    private disposed = false;
    private generation = 0;
    private lastSequence: number | null = null;
    private reading = false;
    private ownWrites = 0;
    private stopTimer: (() => void) | undefined;
    constructor(private readonly reader: ClipboardHistoryReader, private readonly changed: (state: ClipboardHistoryState) => void,
                private readonly schedule: HistoryScheduler = schedulePolling) {}
    get state(): ClipboardHistoryState { return { isEnabled: this.enabled, entries: this.history.snapshot(), totalBytes: this.history.totalBytes, images: this.history.imageSnapshot(), totalImageBytes: this.history.totalImageBytes, imageNotice: this.imageNotice }; }
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
            if (text && typeof text === 'object' && 'skippedImage' in text) { this.imageNotice = text.skippedImage.slice(0,160); this.publish(); }
            else if (text !== null && (typeof text === 'string' ? this.history.add(text) : this.history.addImage(text))) { this.imageNotice = undefined; this.publish(); }
        } catch { /* A busy/unavailable clipboard is skipped without logging its content. */ }
        finally { this.reading = false; }
    }
    async performOwnWrite<T>(write: () => Promise<T>): Promise<T> {
        this.generation++; this.ownWrites++;
        try { return await write(); }
        finally { this.ownWrites--; this.lastSequence = this.sequence(); }
    }
    edit(id: string, text: string): void { this.history.edit(id, text); this.publish(); }
    delete(id: string): void { this.history.delete(id); this.publish(); }
    clear(): void { this.generation++; this.lastSequence = this.sequence(); this.history.clear(); this.imageNotice = undefined; this.publish(); }
    text(id: string): string {
        const entry = this.history.snapshot().find(entry => entry.id === id);
        if (!entry) throw new Error('此历史记录已删除或过期。');
        return entry.text;
    }
    hasImage(id: string): boolean { return this.history.hasImage(id); }
    image(id: string): HistoryImage | undefined { return this.history.image(id); }
    merge(request: ClipboardMergeRequest): string {
        const ids = new Set(request.ids);
        if (!ids.size || ids.size !== request.ids.length || ids.size > 100) throw new Error('Invalid merge selection');
        const entries = this.history.snapshot().filter(entry => ids.has(entry.id));
        if (entries.length !== ids.size) throw new Error('此历史记录已删除或过期。');
        return mergeHistoryText(entries.map(entry => entry.text), request);
    }
    dispose(): void {
        this.generation++; this.enabled = false; this.disposed = true;
        this.stopTimer?.(); this.stopTimer = undefined; this.history.clear();
    }
    private publish(): void { if (!this.disposed) this.changed(this.state); }
}

/** Renderer requests name a history ID; the host owns the text and existing paste authority. */
export function clipboardHistoryOperations(recorder: ClipboardHistoryRecorder,
    use: (request: { text: string; paste: boolean }) => Promise<{ status: string }>,
    imageUse?: (image: HistoryImage, paste: boolean) => Promise<{status: string}>, imagePreview?: (image: HistoryImage, current: () => boolean) => string | null | Promise<string | null>): Record<string, (value?: unknown) => unknown> {
    function empty(value: unknown): void { if (value !== undefined) throw new Error('Invalid history request'); }
    function id(value: unknown): string {
        if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new Error('Invalid history ID');
        return value;
    }
    function merge(value: unknown, withPaste = false): ClipboardMergeRequest & {paste?: boolean} {
        if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid merge request');
        const request = value as Record<string, unknown>;
        if (Object.keys(request).some(key => !['ids', 'trimLines', 'collapseBlankLines', ...(withPaste ? ['paste'] : [])].includes(key))
            || !Array.isArray(request.ids) || request.ids.length > 100 || typeof request.trimLines !== 'boolean' || typeof request.collapseBlankLines !== 'boolean'
            || (withPaste && typeof request.paste !== 'boolean')) throw new Error('Invalid merge request');
        return {ids: request.ids.map(id), trimLines: request.trimLines, collapseBlankLines: request.collapseBlankLines, paste: request.paste as boolean | undefined};
    }
    function validAction(action: unknown): action is ClipboardTextAction {
        return typeof action === 'string' && Object.hasOwn(CLIPBOARD_TEXT_ACTIONS, action);
    }
    return {
        useClipboardHistoryText: value => {
            if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid text processing request');
            const request = value as Record<string, unknown>;
            if (Object.keys(request).some(key => !['id', 'action', 'paste', 'sourceText', 'editedText'].includes(key)) || !validAction(request.action) || typeof request.paste !== 'boolean') throw new Error('Invalid text processing request');
            const source = recorder.text(id(request.id));
            if (request.sourceText !== undefined && (typeof request.sourceText !== 'string' || request.sourceText !== source)) throw new Error('原记录已修改，请重新生成预览。');
            if (request.editedText !== undefined && (typeof request.editedText !== 'string' || typeof request.sourceText !== 'string')) throw new Error('Invalid edited processing preview');
            const output = request.editedText === undefined ? processClipboardText(source, request.action) : processClipboardText(request.editedText as string, 'original');
            return use({text: output, paste: request.paste});
        },
        previewClipboardHistoryMerge: value => recorder.merge(merge(value)),
        useClipboardHistoryMerge: value => { const request = merge(value, true); return use({text: recorder.merge(request), paste: request.paste!}); },
        getClipboardHistoryImage: value => { const selectedId=id(value),image=recorder.image(selectedId); if (!image || !imagePreview) throw new Error('Image unavailable'); const preview=imagePreview(image,()=>recorder.hasImage(selectedId)); return preview instanceof Promise ? preview.then(value=>recorder.hasImage(selectedId)?value:null) : preview; },
        editClipboardHistoryEntry: value => {
            if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid history edit');
            const request = value as Record<string, unknown>;
            if (Object.keys(request).some(key => !['id', 'text', 'expectedText'].includes(key)) || typeof request.text !== 'string') throw new Error('Invalid history edit');
            const selectedId = id(request.id);
            if (request.expectedText !== undefined && (typeof request.expectedText !== 'string' || recorder.text(selectedId) !== request.expectedText)) throw new Error('原记录已修改，请重新生成预览。');
            recorder.edit(selectedId, request.text);
        },
        getClipboardHistory: value => { empty(value); return recorder.state; },
        setClipboardHistoryEnabled: value => { if (typeof value !== 'boolean') throw new Error('Invalid history preference'); recorder.setEnabled(value); },
        deleteClipboardHistoryEntry: value => recorder.delete(id(value)),
        clearClipboardHistory: value => { empty(value); recorder.clear(); },
        useClipboardHistoryEntry: value => {
            if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid history request');
            const request = value as Record<string, unknown>;
            if (Object.keys(request).some(key => !['id', 'paste'].includes(key)) || typeof request.paste !== 'boolean') throw new Error('Invalid history request');
            const selectedId = id(request.id), image = recorder.image(selectedId);
            if (image) { if (!imageUse) throw new Error('Image unavailable'); return imageUse(image, request.paste); }
            return use({ text: recorder.text(selectedId), paste: request.paste });
        },
    };
}

import type { Configuration, Face, Hit } from '../shared/contracts';

export function gestureHit(type: string, pick: () => Hit | null): Hit | null {
    return type === 'pointerup' ? pick() : null;
}

export function shouldDeferSettingsRender(page: string, focusedId: string | null, focusedTag?: string): boolean {
    return focusedTag === 'SELECT' || (page === 'groups' && focusedId === 'group-name');
}

type Edit = (config: Configuration) => void;
interface PendingEdit {
    edit: Edit;
    resolve: () => void;
    reject: (reason: unknown) => void;
}

/** Serializes writes and reapplies outstanding edits to every fresh host snapshot. */
export class PreferenceQueue {
    private base: Configuration;
    private pending: PendingEdit[] = [];
    private running = false;
    constructor(
        initial: Configuration,
        private apply: (config: Configuration) => Promise<void>,
        private read: () => Promise<Configuration>,
        private changed: () => void = () => {},
    ) {
        this.base = structuredClone(initial);
    }
    get draft(): Configuration {
        const config = structuredClone(this.base);
        for (const pending of this.pending) pending.edit(config);
        return config;
    }
    update(config: Configuration): void {
        this.base = structuredClone(config);
    }
    edit(edit: Edit): Promise<void> {
        const promise = new Promise<void>((resolve, reject) => {
            this.pending.push({ edit, resolve, reject });
        });
        this.changed();
        void this.drain();
        return promise;
    }
    private async drain(): Promise<void> {
        if (this.running) return;
        this.running = true;
        while (this.pending.length) {
            const current = this.pending[0];
            try {
                const config = structuredClone(this.base);
                current.edit(config);
                await this.apply(config);
                this.base = structuredClone(await this.read());
                this.pending.shift();
                current.resolve();
            } catch (error) {
                this.pending.shift();
                current.reject(error);
            }
            this.changed();
        }
        this.running = false;
    }
}

export class NameDraft {
    private values = new Map<Face, { value: string; committed: boolean }>();
    change(face: Face, value: string): void {
        this.values.set(face, { value, committed: false });
    }
    commit(face: Face, value: string): void {
        this.values.set(face, { value, committed: true });
    }
    observe(face: Face, name: string): void {
        const draft = this.values.get(face);
        if (draft?.committed && draft.value.trim() === name) this.values.delete(face);
    }
    value(face: Face, name: string): string {
        return this.values.get(face)?.value ?? name;
    }
    clear(face: Face): void {
        this.values.delete(face);
    }
}

import { runDisplayInputProcess } from './display-input-process';
import path from 'node:path';
import { DisplayInputStore } from './display-input-store';
import { normalizeIdentity, type DisplayInputMapping } from '../shared/display-input';
import type { InputJob, InputResult } from '../native/display-input';
export class DisplayInputService {
    private generation = 0;
    private cancellation: Int32Array | null = null;
    private cancelProcess: (() => void) | null = null;
    private queue: Promise<unknown> = Promise.resolve();
    private busy = false;
    constructor(private readonly directory: string, private readonly store: DisplayInputStore, private readonly workerExecutor?: (job: InputJob, cancellation: Int32Array) => Promise<InputResult>) {}
    whenIdle(): Promise<unknown> { return this.queue; }
    cancel(): void { this.generation++; if (this.cancellation) Atomics.store(this.cancellation, 0, 1); this.cancelProcess?.(); }
    private serialize<T>(operation: () => Promise<T>): Promise<T> {
        const generation = this.generation;
        const run = this.queue.then(() => { if (generation !== this.generation) throw new Error('Display operation cancelled'); return operation(); });
        this.queue = run.catch(() => {}); return run;
    }
    private worker(job: InputJob): Promise<InputResult> {
        const cancellation = new SharedArrayBuffer(4); this.cancellation = new Int32Array(cancellation);
        if (this.workerExecutor) return this.workerExecutor(job, this.cancellation).finally(() => { this.cancellation = null; });
        const operation = runDisplayInputProcess(path.join(this.directory, 'display-input-worker.cjs'), job);
        this.cancelProcess = operation.cancel;
        return operation.result.finally(() => { this.cancellation = null; this.cancelProcess = null; });
    }
    list() {
        const generation = this.generation;
        return this.serialize(async () => {
            const result = await this.worker({ kind: 'list' }); const mappings = (await this.store.load()).mappings;
            if (generation !== this.generation) throw new Error('Display operation cancelled');
            return { result, mappings };
        });
    }
    save(identity: string, mapping: DisplayInputMapping) {
        const generation = this.generation;
        return this.serialize(async () => { await this.store.save(identity, mapping, () => generation !== this.generation); if (generation !== this.generation) throw new Error('Display operation cancelled'); });
    }
    switch(identity: string, target: 'typeC' | 'hdmi') {
        if (this.busy) return Promise.reject(new Error('Display input operation already in progress'));
        this.busy = true;
        const generation = this.generation;
        return this.serialize(async () => {
            const mapping = (await this.store.load()).mappings[normalizeIdentity(identity)];
            if (generation !== this.generation) throw new Error('Display operation cancelled');
            const result = await this.worker({ kind: 'switch', identity, mapping, target });
            if (generation !== this.generation) throw new Error('Display changed or panel closed; the command may have been sent. Check the monitor.');
            return result;
        }).finally(() => { this.busy = false; });
    }
}

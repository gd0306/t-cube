import { mkdir, open, readFile, rename, unlink } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { emptyDisplayPositionMemory, normalizeDisplayPositionMemory, type DisplayPositionMemory } from '../core/display-placement';

export interface DisplayPositionPersistence {
    load(): Promise<DisplayPositionMemory>;
    save(memory: DisplayPositionMemory): Promise<void>;
}
/** Separate from configuration; corrupt data is never silently replaced by a position save. */
export class DisplayPositionStore implements DisplayPositionPersistence {
    private blocked = false;
    private queue: Promise<unknown> = Promise.resolve();
    constructor(readonly filePath: string) {}
    private serialize<T>(operation: () => Promise<T>): Promise<T> {
        const result = this.queue.then(operation); this.queue = result.catch(() => undefined); return result;
    }
    private async read(): Promise<DisplayPositionMemory> {
        if (this.blocked) throw new Error('Display positions require explicit repair after corruption');
        try { return normalizeDisplayPositionMemory(JSON.parse(await readFile(this.filePath, 'utf8'))); }
        catch (error) {
            if ((error as NodeJS.ErrnoException).code === 'ENOENT') return emptyDisplayPositionMemory();
            this.blocked = true; throw error;
        }
    }
    load(): Promise<DisplayPositionMemory> { return this.serialize(() => this.read()); }
    save(memory: DisplayPositionMemory): Promise<void> {
        const next = normalizeDisplayPositionMemory(memory);
        return this.serialize(async () => {
            await this.read();
            await mkdir(dirname(this.filePath), { recursive: true });
            const temporary = `${this.filePath}.${randomUUID()}.tmp`;
            try {
                const handle = await open(temporary, 'wx', 0o600);
                try { await handle.writeFile(`${JSON.stringify(next, null, 4)}\n`, 'utf8'); await handle.sync(); }
                finally { await handle.close(); }
                await rename(temporary, this.filePath);
            } finally { await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
        });
    }
}

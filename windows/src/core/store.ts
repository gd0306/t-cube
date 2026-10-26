import { mkdir, open, readFile, rename, unlink } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { Configuration } from '../shared/contracts';
import { defaultConfiguration, normalizeConfiguration } from './configuration';

export class ConfigurationStore {
    private current: Configuration | null = null;
    private blocked = false;
    private queue: Promise<unknown> = Promise.resolve();
    constructor(readonly filePath: string) {}
    get snapshot(): Configuration {
        if (!this.current) throw new Error('Configuration has not loaded');
        return structuredClone(this.current);
    }
    private serialize<T>(operation: () => Promise<T>): Promise<T> {
        const result = this.queue.then(operation); this.queue = result.catch(() => undefined); return result;
    }
    private async read(): Promise<Configuration> {
        try { return normalizeConfiguration(JSON.parse(await readFile(this.filePath, 'utf8'))); }
        catch (error) {
            if ((error as NodeJS.ErrnoException).code === 'ENOENT') return defaultConfiguration();
            this.blocked = true; throw error;
        }
    }
    load(): Promise<Configuration> {
        return this.serialize(async () => {
            const configuration = await this.read();
            if (this.blocked) throw new Error('Configuration requires explicit backup and reset');
            this.current = configuration; return this.snapshot;
        });
    }
    update(edit: (configuration: Configuration) => Configuration | void): Promise<Configuration> {
        return this.serialize(async () => {
            if (this.blocked) throw new Error('Configuration requires explicit backup and reset');
            const disk = await this.read(); // A file corrupted externally must never be overwritten.
            const candidate = structuredClone(this.current ?? disk);
            const next = normalizeConfiguration(edit(candidate) ?? candidate);
            await this.write(next); this.current = next; return this.snapshot;
        });
    }
    backupAndReset(): Promise<Configuration> {
        return this.serialize(async () => {
            try { await rename(this.filePath, `${this.filePath}.${Date.now()}.${randomUUID()}.backup`); }
            catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
            const next = defaultConfiguration();
            await this.write(next); this.blocked = false; this.current = next; return this.snapshot;
        });
    }
    private async write(configuration: Configuration): Promise<void> {
        await mkdir(dirname(this.filePath), { recursive: true });
        const temporary = `${this.filePath}.${randomUUID()}.tmp`;
        try {
            const handle = await open(temporary, 'wx', 0o600);
            try { await handle.writeFile(`${JSON.stringify(configuration, null, 4)}\n`, 'utf8'); await handle.sync(); }
            finally { await handle.close(); }
            await rename(temporary, this.filePath);
        } finally {
            await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
        }
    }
}

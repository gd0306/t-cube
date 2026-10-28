import { mkdir, open, readFile, rename, unlink, readdir, realpath, stat } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { Configuration } from '../shared/contracts';
import type { SnippetLibrary } from '../shared/productivity';
import { defaultConfiguration, normalizeConfiguration } from './configuration';
import { validateSnippetLibrary } from './snippet-library';

const locks = new Map<string, Promise<unknown>>();
/** Shared with ordinary stores: reserve every path before awaiting to avoid lock inversion. */
export function serializeFileOperations<T>(paths: string[], operation: () => Promise<T>): Promise<T> {
    const keys = [...new Set(paths.map(path => resolve(path).toLowerCase()))].sort();
    const waiting = keys.map(key => locks.get(key) ?? Promise.resolve());
    const result = Promise.all(waiting).then(operation);
    const settled = result.catch(() => undefined);
    for (const key of keys) locks.set(key, settled);
    void settled.then(() => { for (const key of keys) if (locks.get(key) === settled) locks.delete(key); });
    return result;
}
export interface ConfigurationArchive { version: 1; createdAt: string; configuration: Configuration; contentLibrary: SnippetLibrary }
export function validateArchive(value: unknown): ConfigurationArchive {
    if (!value || typeof value !== 'object') throw new Error('Invalid archive');
    const source = value as Record<string, unknown>;
    if (source.version !== 1 || typeof source.createdAt !== 'string' || !Number.isFinite(Date.parse(source.createdAt))) throw new Error('Unsupported or invalid archive');
    return { version: 1, createdAt: source.createdAt, configuration: normalizeConfiguration(source.configuration), contentLibrary: validateSnippetLibrary(source.contentLibrary) };
}
export async function atomicWrite(path: string, bytes: Uint8Array | string): Promise<void> {
    await mkdir(dirname(path), { recursive: true });
    const temporary = `${path}.${randomUUID()}.tmp`;
    try {
        const handle = await open(temporary, 'wx', 0o600);
        try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
        await rename(temporary, path);
    } finally { await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
}
async function bytes(path: string): Promise<Buffer | null> {
    try { return await readFile(path); } catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error; }
}
function encode(value: unknown): string { return `${JSON.stringify(value, null, 4)}\n`; }
async function identity(path: string): Promise<string> {
    try { return (await realpath(path)).toLowerCase(); }
    catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
        const parent = dirname(path);
        return parent === path ? resolve(path).toLowerCase() : join(await identity(parent), basename(path).toLowerCase());
    }
}
async function aliases(first: string, second: string): Promise<boolean> {
    if (await identity(first) === await identity(second)) return true;
    try { const [a, b] = await Promise.all([stat(first), stat(second)]); return a.dev === b.dev && a.ino === b.ino; }
    catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return false; throw error; }
}
export class ConfigurationArchiveStore {
    readonly backupsPath: string;
    constructor(readonly configurationPath: string, readonly libraryPath: string, private readonly options: { beforeWrite?: (path: string) => Promise<void>; backupsPath?: string } = {}) {
        this.backupsPath = options.backupsPath ?? join(dirname(configurationPath), 'Backups');
    }
    private paths() { return [this.configurationPath, this.libraryPath]; }
    private async readCurrent(): Promise<ConfigurationArchive> {
        const [configuration, library] = await Promise.all([bytes(this.configurationPath), bytes(this.libraryPath)]);
        return { version: 1, createdAt: new Date().toISOString(), configuration: configuration ? normalizeConfiguration(JSON.parse(configuration.toString('utf8'))) : defaultConfiguration(), contentLibrary: library ? validateSnippetLibrary(JSON.parse(library.toString('utf8'))) : { version: 1, items: [] } };
    }
    currentArchive(): Promise<ConfigurationArchive> { return serializeFileOperations(this.paths(), () => this.readCurrent()); }
    async export(destination: string): Promise<void> {
        await serializeFileOperations([...this.paths(), destination], async () => {
            const archive = await this.readCurrent();
            for (const live of this.paths()) if (await aliases(destination, live)) throw new Error('Cannot overwrite live data with an archive');
            await atomicWrite(destination, encode(archive));
        });
    }
    private async saveBackup(archive: ConfigurationArchive): Promise<string> {
        await mkdir(this.backupsPath, { recursive: true });
        const path = join(this.backupsPath, `T-Cube-${new Date().toISOString().replaceAll(':', '-')}-${randomUUID().slice(0, 8)}.json`);
        for (const live of this.paths()) if (await aliases(path, live)) throw new Error('Backup path aliases live data');
        await atomicWrite(path, encode(archive)); return path;
    }
    makeBackup(): Promise<string> { return serializeFileOperations(this.paths(), async () => this.saveBackup(await this.readCurrent())); }
    async backups(): Promise<string[]> {
        try {
            const entries = await readdir(this.backupsPath, { withFileTypes: true });
            return entries.filter(entry => entry.isFile() && entry.name.toLowerCase().endsWith('.json')).map(entry => join(this.backupsPath, entry.name)).sort().reverse();
        } catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return []; throw error; }
    }
    restore(value: ConfigurationArchive): Promise<string> {
        const archive = validateArchive(value);
        return serializeFileOperations(this.paths(), async () => {
            const current = await this.readCurrent();
            const originals = await Promise.all(this.paths().map(path => bytes(path)));
            const backup = await this.saveBackup(current);
            try {
                for (const [path, data] of [[this.configurationPath, archive.configuration], [this.libraryPath, archive.contentLibrary]] as const) {
                    await this.options.beforeWrite?.(path); await atomicWrite(path, encode(data));
                }
            } catch (original) {
                const failures: unknown[] = [];
                for (let index = 0; index < this.paths().length; index++) {
                    try { const path = this.paths()[index], data = originals[index]; if (data) await atomicWrite(path, data); else await unlink(path).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
                    catch (error) { failures.push(error); }
                }
                if (failures.length) throw new AggregateError([original, ...failures], `Restore and rollback failed; pre-import backup retained at ${backup}`);
                throw original;
            }
            return backup;
        });
    }
}

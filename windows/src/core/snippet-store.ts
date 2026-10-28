import { mkdir, open, readFile, rename, stat, unlink } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { SnippetLibrary } from '../shared/productivity';
import { SNIPPET_LIMITS, validateSnippetLibrary } from './snippet-library';
import { serializeFileOperations } from './configuration-archive';
export interface SnippetPersistence {
    load(): Promise<SnippetLibrary>;
    reload(): Promise<SnippetLibrary>;
    update(edit: (library: SnippetLibrary) => SnippetLibrary | void): Promise<SnippetLibrary>;
}
/** Mutations always start from disk, and publish only after the atomic rename succeeds. */
export class SnippetStore implements SnippetPersistence {
    private blocked = false;
    constructor(readonly filePath: string) {}
    private async read(): Promise<SnippetLibrary> {
        try {
            if ((await stat(this.filePath)).size > SNIPPET_LIMITS.payload) throw new Error('内容库文件过大。');
            return validateSnippetLibrary(JSON.parse(await readFile(this.filePath, 'utf8')));
        } catch (error) {
            if ((error as NodeJS.ErrnoException).code === 'ENOENT') return { version: 1, items: [] };
            this.blocked = true; throw error;
        }
    }
    load(): Promise<SnippetLibrary> { return serializeFileOperations([this.filePath], async () => {
        if (this.blocked) throw new Error('Content library is corrupt; repair and reload before editing.');
        return this.read();
    }); }
    reload(): Promise<SnippetLibrary> { return serializeFileOperations([this.filePath], async () => {
        const library = await this.read(); this.blocked = false; return library;
    }); }
    update(edit: (library: SnippetLibrary) => SnippetLibrary | void): Promise<SnippetLibrary> {
        return serializeFileOperations([this.filePath], async () => {
            if (this.blocked) throw new Error('Content library is corrupt; repair and reload before editing.');
            const disk = await this.read(), candidate = edit(disk) ?? disk;
            const next = validateSnippetLibrary(candidate);
            await this.write(next); return structuredClone(next);
        });
    }
    save(library: SnippetLibrary): Promise<void> {
        const next = validateSnippetLibrary(library);
        return this.update(() => next).then(() => undefined);
    }
    private async write(library: SnippetLibrary): Promise<void> {
        await mkdir(dirname(this.filePath), { recursive: true });
        const temporary = `${this.filePath}.${randomUUID()}.tmp`;
        try {
            const file = await open(temporary, 'wx', 0o600);
            try { await file.writeFile(`${JSON.stringify(library, null, 4)}\n`, 'utf8'); await file.sync(); }
            finally { await file.close(); }
            await rename(temporary, this.filePath);
        } finally { await unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
    }
}

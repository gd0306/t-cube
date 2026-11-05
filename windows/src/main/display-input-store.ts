import { open } from 'node:fs/promises';
import { atomicWriteJSON } from '../core/atomic-json';
import { normalizeIdentity, validMapping, type DisplayInputMapping } from '../shared/display-input';
interface InputData { version: 1; mappings: Record<string, DisplayInputMapping> }
export class DisplayInputStore {
    private queue: Promise<unknown> = Promise.resolve();
    private blocked = false;
    constructor(private readonly file: string, private readonly writeJSON: typeof atomicWriteJSON = atomicWriteJSON) {}
    private serialize<T>(fn: () => Promise<T>): Promise<T> { const result = this.queue.then(fn); this.queue = result.catch(() => {}); return result; }
    private async read(): Promise<InputData> {
        if (this.blocked) throw new Error('Display input settings are corrupt; repair the file before saving');
        try {
            const handle = await open(this.file, 'r');
            let bytes: Buffer;
            try {
                if ((await handle.stat()).size > 131072) throw new Error('Display input settings are too large');
                const buffer = Buffer.alloc(131073);
                const result = await handle.read(buffer, 0, buffer.length, 0);
                if (result.bytesRead > 131072) throw new Error('Display input settings are too large');
                bytes = buffer.subarray(0, result.bytesRead);
            } finally { await handle.close(); }
            const value: unknown = JSON.parse(bytes.toString('utf8'));
            if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid display input settings');
            const data = value as Record<string, unknown>;
            if (Object.keys(data).sort().join(',') !== 'mappings,version' || data.version !== 1 || !data.mappings || typeof data.mappings !== 'object' || Array.isArray(data.mappings)) throw new Error('Invalid display input settings');
            const entries = Object.entries(data.mappings); if (entries.length > 128) throw new Error('Too many displays');
            const mappings: Record<string, DisplayInputMapping> = Object.create(null);
            for (const [key, mapping] of entries) {
                const identity = normalizeIdentity(key);
                if (Object.hasOwn(mappings, identity) || !validMapping(mapping)) throw new Error('Invalid display input mapping');
                mappings[identity] = mapping;
            }
            return { version: 1, mappings };
        } catch (error) {
            if ((error as NodeJS.ErrnoException).code === 'ENOENT') return { version: 1, mappings: {} };
            this.blocked = true; throw new Error('Display input settings are corrupt or unreadable; repair the file before saving', { cause: error });
        }
    }
    load(): Promise<InputData> { return this.serialize(() => this.read()); }
    save(identity: string, mapping: DisplayInputMapping, cancelled: () => boolean = () => false): Promise<void> {
        return this.serialize(async () => {
            const key = normalizeIdentity(identity); if (!validMapping(mapping)) throw new Error('Input codes must be distinct integers from 0 to 65535');
            const data = await this.read();
            if (!Object.hasOwn(data.mappings, key) && Object.keys(data.mappings).length >= 128) throw new Error('Too many displays');
            if (cancelled()) throw new Error('Display operation cancelled');
            data.mappings[key] = { ...mapping }; await this.writeJSON(this.file, data, () => { if (cancelled()) throw new Error('Display operation cancelled'); });
        });
    }
}

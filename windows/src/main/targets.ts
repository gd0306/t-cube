import { stat as fileStat } from 'node:fs/promises';
import { win32 } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { LauncherItem } from '../shared/contracts';

/** Accept a local drive path only. UNC, device namespaces, URLs and drive-relative paths are excluded. */
export async function validateLocalTarget(value: string, kind?: LauncherItem['kind'], stat: (path: string) => Promise<{ isFile(): boolean; isDirectory(): boolean }> = fileStat): Promise<LauncherItem> {
    if (typeof value !== 'string' || value.length > 32767 || !/^[a-z]:[\\/]/i.test(value)
        || /[\0-\x1f"<>|?*]/.test(value) || value.slice(2).includes(':')) throw new Error('Choose a local executable or folder');
    const target = win32.normalize(value);
    const info = await stat(target);
    const actualKind = info.isDirectory() ? 'folder' : info.isFile() && /\.(exe|lnk)$/i.test(target) ? 'application' : null;
    if (!actualKind || (kind && actualKind !== kind)) throw new Error(`Choose a local ${kind ?? 'executable or folder'}`);
    return { id: randomUUID(), path: target, name: win32.basename(target) || target, kind: actualKind };
}

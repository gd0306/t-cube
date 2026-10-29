import { websiteURL, systemSettingsTarget } from '../shared/shortcut-targets';
import { stat as fileStat } from 'node:fs/promises';
import { win32 } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { LauncherItem } from '../shared/contracts';

/** Shell icon extraction must never touch remote or device namespace paths. */
export function isLocalIconPath(value: string, platform: string): boolean {
    if (typeof value !== 'string' || value.length > 32767 || /[\0-\x1f]/.test(value)) return false;
    if (platform === 'darwin') return value.startsWith('/') && !value.startsWith('//');
    return /^[a-z]:[\\/]/i.test(value) && !/["<>|?*]/.test(value) && !value.slice(2).includes(':');
}

/** Accept a local drive path only. UNC, device namespaces, URLs and drive-relative paths are excluded. */
export async function validateLocalTarget(value: string, kind?: LauncherItem['kind'], stat: (path: string) => Promise<{ isFile(): boolean; isDirectory(): boolean }> = fileStat): Promise<LauncherItem> {
    if (typeof value !== 'string' || value.length > 32767 || !/^[a-z]:[\\/]/i.test(value)
        || /[\0-\x1f"<>|?*]/.test(value) || value.slice(2).includes(':')) throw new Error('Choose a local executable or folder');
    const target = win32.normalize(value);
    const info = await stat(target);
    const actualKind = info.isDirectory() ? 'folder' : info.isFile() ? (kind === 'file' ? 'file' : /\.(exe|lnk)$/i.test(target) ? 'application' : 'file') : null;
    if (!actualKind || (kind && actualKind !== kind)) throw new Error(`Choose a local ${kind ?? 'executable or folder'}`);
    return { id: randomUUID(), path: target, name: win32.basename(target) || target, kind: actualKind };
}

/** URI kinds never reach filesystem or shell icon APIs. */
export async function validateTarget(value: string, kind?: LauncherItem['kind']): Promise<LauncherItem> {
    if (kind === 'website') {
        const url = websiteURL(value);
        return { id: randomUUID(), path: url.href, name: url.hostname, kind };
    }
    if (kind === 'systemSettings') {
        const page = systemSettingsTarget(value);
        return { id: randomUUID(), path: page.uri, name: page.name, kind };
    }
    return validateLocalTarget(value, kind);
}

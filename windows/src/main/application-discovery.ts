import { app, nativeImage, shell, type NativeImage } from 'electron';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { InstalledApplications, type ApplicationCandidate } from './applications';
import { validateLocalTarget } from './targets';
import { extractIconInWorker } from '../native/icon-service';

export function createApplicationCatalog(
    directory: string,
    userData: string,
): InstalledApplications {
    const images = new Map<string, Promise<NativeImage | null>>();
    async function loadImage(entry: ApplicationCandidate): Promise<NativeImage | null> {
        const target = entry.kind === 'shell' ? `shell:AppsFolder\\${entry.path}` : entry.path;
        try {
            if (entry.kind === 'file') return await app.getFileIcon(entry.path, { size: 'large' });
            const bitmap = await extractIconInWorker(target);
            if (bitmap) {
                const image = nativeImage.createFromBitmap(bitmap.pixels, {
                    width: bitmap.width,
                    height: bitmap.height,
                });
                if (!image.isEmpty()) return image;
            }
        } catch {
            /* Missing icons do not remove launchable applications. */
        }
        return null;
    }
    function image(entry: ApplicationCandidate): Promise<NativeImage | null> {
        let pending = images.get(entry.id);
        if (!pending) {
            pending = loadImage(entry);
            images.set(entry.id, pending);
        }
        return pending;
    }
    return new InstalledApplications({
        query: async () => {
            if (process.platform !== 'win32')
                throw new Error('已安装应用列表仅在 Windows 上可用，请使用浏览文件');
            const executable = path.join(
                process.env.SystemRoot ?? 'C:\\Windows',
                'System32',
                'WindowsPowerShell',
                'v1.0',
                'powershell.exe',
            );
            try {
                const { stdout } = await promisify(execFile)(
                    executable,
                    [
                        '-NoProfile',
                        '-NonInteractive',
                        '-STA',
                        '-ExecutionPolicy',
                        'Bypass',
                        '-File',
                        path.join(directory, 'assets', 'list-applications.ps1'),
                    ],
                    {
                        encoding: 'utf8',
                        windowsHide: true,
                        timeout: 20_000,
                        maxBuffer: 4 * 1024 * 1024,
                    },
                );
                images.clear();
                const records = JSON.parse(stdout.replace(/^\uFEFF/, '').trim() || '[]');
                if (!Array.isArray(records)) return records;
                await Promise.all(
                    records.map(async (record) => {
                        for (const [field, identity] of [
                            ['path', 'canonicalPath'],
                            ['target', 'canonicalTarget'],
                            ['workingDirectory', 'canonicalWorkingDirectory'],
                        ] as const) {
                            if (
                                typeof record[field] !== 'string' ||
                                !/^[a-z]:[\\/]/i.test(record[field])
                            )
                                continue;
                            try {
                                record[identity] = (await realpath(record[field])).replace(
                                    /^\\\\\?\\([a-z]:\\)/i,
                                    '$1',
                                );
                            } catch {
                                /* A removed target is revalidated when selected. */
                            }
                        }
                    }),
                );
                return records;
            } catch {
                throw new Error('无法读取 Windows 应用列表，请刷新或使用浏览文件');
            }
        },
        validate: (target) => validateLocalTarget(target, 'application'),
        icon: async (entry) => (await image(entry))?.toDataURL() ?? null,
        shortcut: async (entry) => {
            // Only catalog-owned IDs enter these arguments; never accept shell text from a renderer.
            const folder = path.join(userData, 'applications');
            await mkdir(folder, { recursive: true });
            const shortcut = path.join(folder, `${entry.id}.lnk`);
            const picture = await image(entry);
            let icon: string | undefined;
            if (picture && !picture.isEmpty()) {
                const resized = picture.resize({ width: 256, height: 256 });
                const png = resized.toPNG(),
                    header = Buffer.alloc(22);
                header.writeUInt16LE(1, 2);
                header.writeUInt16LE(1, 4);
                header.writeUInt16LE(1, 10);
                header.writeUInt16LE(32, 12);
                header.writeUInt32LE(png.length, 14);
                header.writeUInt32LE(22, 18);
                icon = path.join(folder, `${entry.id}.ico`);
                await writeFile(icon, Buffer.concat([header, png]));
            }
            const success = shell.writeShortcutLink(shortcut, 'create', {
                target: path.join(process.env.SystemRoot ?? 'C:\\Windows', 'explorer.exe'),
                args: `shell:AppsFolder\\${entry.path}`,
                description: entry.name,
                ...(icon ? { icon, iconIndex: 0 } : {}),
            });
            if (!success) throw new Error('无法创建应用入口，请重试');
            return shortcut;
        },
    });
}

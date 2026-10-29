import { isURLTarget } from '../shared/shortcut-targets';
import { extractIconInWorker } from '../native/icon-service';
import { FACES } from '../shared/contracts';
import type { Configuration } from '../shared/contracts';
import { isLocalIconPath } from './targets';

export class IconCache {
    private readonly cache = new Map<string, Promise<string | null>>();
    private async load(target: string): Promise<string | null> {
        const { app, nativeImage } = await import('electron');
        try {
            const bitmap = await extractIconInWorker(target);
            if (bitmap) {
                // Shell extraction provides top-down premultiplied BGRA, Electron's bitmap format.
                const image = nativeImage.createFromBitmap(bitmap.pixels, { width: bitmap.width, height: bitmap.height, scaleFactor: 1 });
                if (!image.isEmpty()) return image.toDataURL();
            }
        } catch { /* A failed shell extension must not block the launcher. */ }
        try {
            const fallback = await app.getFileIcon(target, { size: 'large' });
            return fallback.isEmpty() ? null : fallback.toDataURL();
        } catch { return null; }
    }
    async forConfiguration(configuration: Configuration): Promise<Record<string, string>> {
        const allItems = FACES.flatMap(face => configuration.groups[face].slots)
            .filter(item => item !== null);
        const items = allItems.filter(item => !isURLTarget(item.kind) && isLocalIconPath(item.path, process.platform));
        const active = new Set(items.map(item => item.path.toLowerCase()));
        for (const key of this.cache.keys()) if (!active.has(key)) this.cache.delete(key);
        const icons: Record<string, string> = {};
        for (const item of allItems) {
            if (isURLTarget(item.kind)) icons[item.id] = shortcutIcon(item.kind);
        }
        await Promise.all(items.map(async item => {
            const key = item.path.toLowerCase();
            let promise = this.cache.get(key);
            if (!promise) { promise = this.load(item.path); this.cache.set(key, promise); }
            const image = await promise;
            if (image) icons[item.id] = image;
        }));
        return icons;
    }
}

/** Bundled vector artwork: no favicon requests, shell extensions or filesystem lookups. */
function shortcutIcon(kind: string): string {
    const drawing = kind === 'website'
        ? '<circle cx="32" cy="32" r="19"/><ellipse cx="32" cy="32" rx="8" ry="19"/><path d="M13 32h38M17 22h30M17 42h30"/>'
        : '<path d="M27 12h10l2 7 7 4 7-2 5 9-5 5v8l-7 5-6-3-7 4-1 7H22l-2-7-7-4-6 3-5-9 5-5v-8l7-5 6 3 7-4z" transform="translate(4 -2) scale(.88)"/><circle cx="32" cy="32" r="8"/>';
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><rect x="2" y="2" width="60" height="60" rx="14" fill="${kind === 'website' ? '#247AC2' : '#58687C'}"/><g fill="none" stroke="white" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">${drawing}</g></svg>`;
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

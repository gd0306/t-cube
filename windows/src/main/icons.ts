import { app, nativeImage } from 'electron';
import { extractIconInWorker } from '../native/icon-service';
import { FACES } from '../shared/contracts';
import type { Configuration } from '../shared/contracts';
import { isLocalIconPath } from './targets';

export class IconCache {
    private readonly cache = new Map<string, Promise<string | null>>();
    private async load(target: string): Promise<string | null> {
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
        const items = FACES.flatMap(face => configuration.groups[face].slots)
            .filter(item => item !== null).filter(item => isLocalIconPath(item.path, process.platform));
        const active = new Set(items.map(item => item.path.toLowerCase()));
        for (const key of this.cache.keys()) if (!active.has(key)) this.cache.delete(key);
        const icons: Record<string, string> = {};
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

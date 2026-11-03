import type { HistoryImage } from '../core/clipboard-history';
import { CLIPBOARD_HISTORY_LIMITS, CLIPBOARD_IMAGE_LIMITS } from '../shared/clipboard-history';
export interface HistoryClipboardItem { types: string[]; getType(type: string): Promise<unknown> }
function formatName(type: string): string {
    return (/^electron application\/osclipboard;format="([^"]+)"$/i.exec(type)?.[1] ?? type).toLowerCase();
}
/** Electron 45 exposes native formats as ClipboardItem MIME entries.
 * Policy: https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats
 * Check every item's exclusions before requesting the first plain-text payload. */
async function formatsAllowed(items: HistoryClipboardItem[], canRead: () => boolean): Promise<boolean> {
    if (!canRead()) return false;
    for (const item of items) {
        for (const type of item.types) {
            const name = formatName(type);
            if (['excludeclipboardcontentfrommonitorprocessing', 'cf_hdrop'].includes(name)) return false;
            if (name === 'text/uri-list') {
                if (!canRead()) return false;
                const blob = await item.getType(type);
                if (!canRead()) return false;
                if (!(blob instanceof Blob) || blob.size > CLIPBOARD_HISTORY_LIMITS.itemBytes) return false;
                if (/^\s*file:/im.test(await blob.text())) return false;
            }
            if (name === 'canincludeinclipboardhistory') {
                if (!canRead()) return false;
                const blob = await item.getType(type);
                if (!canRead()) return false;
                if (!(blob instanceof Blob) || blob.size !== 4) return false;
                if (new DataView(await blob.arrayBuffer()).getUint32(0, true) !== 1) return false;
            }
        }
    }
    return canRead();
}
export async function readHistoryClipboardItems(items: HistoryClipboardItem[], canRead: () => boolean = () => true): Promise<string | null> {
    if (!await formatsAllowed(items, canRead)) return null;
    const item = items.find(item => item.types.includes('text/plain'));
    if (!item) return null;
    if (!canRead()) return null;
    const blob = await item.getType('text/plain');
    if (!canRead()) return null;
    if (!(blob instanceof Blob) || blob.size > CLIPBOARD_HISTORY_LIMITS.itemBytes) return null;
    return blob.text();
}

/** Prefer one normalized image when the clipboard contains both image and text representations. */
export async function readHistoryClipboardContent(items: HistoryClipboardItem[], canRead: () => boolean,
    normalize: (png: Buffer) => HistoryImage | null | Promise<HistoryImage | null>): Promise<string | HistoryImage | {skippedImage:string} | null> {
    if (!await formatsAllowed(items, canRead)) return null;
    const type = ['image/png', 'image/jpeg'].find(type => items.some(item => item.types.includes(type)));
    const item = type ? items.find(item => item.types.includes(type)) : undefined;
    if (!item || !type) return readHistoryClipboardItems(items, canRead);
    if (!canRead()) return null;
    const blob = await item.getType(type);
    if (!canRead() || !(blob instanceof Blob)) return null;
    if (blob.size > CLIPBOARD_IMAGE_LIMITS.itemBytes) return {skippedImage:'已跳过图片：源数据超过 8 MiB。'};
    const bytes = Buffer.from(await blob.arrayBuffer());
    if (!canRead()) return null;
    const image = await normalize(bytes);
    return canRead() ? image ?? {skippedImage:'已跳过图片：格式无效、超过 1600 万像素或压缩后超过 8 MiB。'} : null;
}

import { CLIPBOARD_HISTORY_LIMITS } from '../shared/clipboard-history';
export interface HistoryClipboardItem { types: string[]; getType(type: string): Promise<unknown> }
function formatName(type: string): string {
    return (/^electron application\/osclipboard;format="([^"]+)"$/i.exec(type)?.[1] ?? type).toLowerCase();
}
/** Electron 45 exposes native formats as ClipboardItem MIME entries.
 * Policy: https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats
 * Check every item's exclusions before requesting the first plain-text payload. */
export async function readHistoryClipboardItems(items: HistoryClipboardItem[], canRead: () => boolean = () => true): Promise<string | null> {
    if (!canRead()) return null;
    for (const item of items) {
        for (const type of item.types) {
            const name = formatName(type);
            if (['excludeclipboardcontentfrommonitorprocessing', 'cf_hdrop'].includes(name)) return null;
            if (name === 'text/uri-list') {
                if (!canRead()) return null;
                const blob = await item.getType(type);
                if (!canRead()) return null;
                if (!(blob instanceof Blob) || blob.size > CLIPBOARD_HISTORY_LIMITS.itemBytes) return null;
                if (/^\s*file:/im.test(await blob.text())) return null;
            }
            if (name === 'canincludeinclipboardhistory') {
                if (!canRead()) return null;
                const blob = await item.getType(type);
                if (!canRead()) return null;
                if (!(blob instanceof Blob) || blob.size !== 4) return null;
                if (new DataView(await blob.arrayBuffer()).getUint32(0, true) !== 1) return null;
            }
        }
    }
    const item = items.find(item => item.types.includes('text/plain'));
    if (!item) return null;
    if (!canRead()) return null;
    const blob = await item.getType('text/plain');
    if (!canRead()) return null;
    if (!(blob instanceof Blob) || blob.size > CLIPBOARD_HISTORY_LIMITS.itemBytes) return null;
    return blob.text();
}

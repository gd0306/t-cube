import koffi from 'koffi';
export interface HistoryFormatBindings {
    register(name: string): number;
    has(format: number): boolean;
    readDWORD(format: number): number | null;
}
/** Native format inspection precedes Electron reads, independent of MIME mappings.
 * https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats */
export function historyFormatsAllowed(native: HistoryFormatBindings): boolean {
    if (native.has(15)) return false; // CF_HDROP
    const exclude = native.register('ExcludeClipboardContentFromMonitorProcessing');
    const history = native.register('CanIncludeInClipboardHistory');
    if (!exclude || !history || native.has(exclude)) return false;
    return !native.has(history) || native.readDWORD(history) === 1;
}
let bindings: (HistoryFormatBindings & HistoryImageFormatBindings) | undefined;
function createBindings(): HistoryFormatBindings & HistoryImageFormatBindings {
    const user = koffi.load('user32.dll'), kernel = koffi.load('kernel32.dll');
    const register = user.func('uint32_t __stdcall RegisterClipboardFormatW(str16 name)');
    const has = user.func('int __stdcall IsClipboardFormatAvailable(uint32_t format)');
    const open = user.func('int __stdcall OpenClipboard(uintptr_t window)');
    const close = user.func('int __stdcall CloseClipboard()');
    const get = user.func('uintptr_t __stdcall GetClipboardData(uint32_t format)');
    const size = kernel.func('size_t __stdcall GlobalSize(uintptr_t memory)');
    const lock = kernel.func('void* __stdcall GlobalLock(uintptr_t memory)');
    const unlock = kernel.func('int __stdcall GlobalUnlock(uintptr_t memory)');
    const ids = new Map<string, number>();
    return {
        register: name => { let id = ids.get(name); if (!id) { id = register(name); if (id) ids.set(name, id!); } return id ?? 0; },
        has: format => Boolean(has(format)),
        readHeader: format => {
            if (!open(0)) return null;
            let memory: number | bigint = 0, locked = false;
            try {
                memory = get(format);
                if (!memory) return null;
                const length = Number(size(memory));
                if (!Number.isSafeInteger(length) || length < 1) return null;
                if (length > 65 * 1024 * 1024) return {size: length, bytes: Buffer.alloc(0)};
                const pointer = lock(memory); if (!pointer) return null; locked = true;
                return {size: length, bytes: Buffer.from(koffi.decode(pointer, 'uint8_t', Math.min(length,40)) as Uint8Array)};
            } finally { if (locked) unlock(memory); close(); }
        },
        readDWORD: format => {
            if (!open(0)) return null;
            let memory: number | bigint = 0, locked = false;
            try {
                memory = get(format);
                if (!memory || size(memory) < 4) return null;
                const pointer = lock(memory);
                if (!pointer) return null;
                locked = true;
                return koffi.decode(pointer, 'uint32_t') as number;
            } finally { if (locked) unlock(memory); close(); }
        },
    };
}
export function clipboardHistoryFormatsAllowed(): boolean {
    if (process.platform !== 'win32') return false;
    try { return historyFormatsAllowed(bindings ??= createBindings()); } catch { return false; }
}

export interface HistoryImageFormatBindings {register(name:string):number;has(format:number):boolean;readHeader(format:number):{size:number;bytes:Buffer}|null}
/** Native raw DIB metadata is bounded before Electron can encode/materialize its PNG representation. */
export function historyImageFormatsAllowed(native:HistoryImageFormatBindings):boolean {
    const png=native.register('PNG');
    if(!png)return false;
    if(native.has(png)){const payload=native.readHeader(png);if(!payload || payload.size>8*1024*1024)return false;}
    for(const format of [8,17]){
        if(!native.has(format))continue;
        const payload=native.readHeader(format);
        if(!payload || payload.size>65*1024*1024 || payload.bytes.length<12)return false;
        const header=payload.bytes.readUInt32LE(0);
        let width:number,height:number;
        if(header===12){width=payload.bytes.readUInt16LE(4);height=payload.bytes.readUInt16LE(6);}
        else {if(header<40 || payload.bytes.length<40)return false;width=payload.bytes.readInt32LE(4);height=Math.abs(payload.bytes.readInt32LE(8));}
        if(width<1 || height<1 || width*height>16_000_000)return false;
    }
    return true;
}
export function clipboardHistoryImageFormatsAllowed():boolean{
    if(process.platform!=='win32')return false;
    try{return historyImageFormatsAllowed(bindings??=createBindings());}catch{return false;}
}

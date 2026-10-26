import koffi from 'koffi';

export interface InputState { available: boolean; controlHeld: boolean; primaryDown: boolean; secondaryDown: boolean }
export interface ShellBitmap { width: number; height: number; pixels: Buffer }

export function inputFromKeys(read: (key: number) => number, swapped: boolean): InputState {
    const held = (key: number) => (read(key) & 0x8000) !== 0;
    return { available: true, controlHeld: held(0x11), primaryDown: held(swapped ? 2 : 1), secondaryDown: held(swapped ? 1 : 2) };
}

export function reducedMotionFromSetting(success: boolean, animations: number): boolean {
    return success && animations === 0;
}

function createInputBindings() {
    const library = koffi.load('user32.dll');
    return {
        key: library.func('int16_t __stdcall GetAsyncKeyState(int key)'),
        metric: library.func('int __stdcall GetSystemMetrics(int index)'),
        preference: library.func('int __stdcall SystemParametersInfoW(uint32_t action, uint32_t param, _Out_ int *value, uint32_t flags)')
    };
}
let input: ReturnType<typeof createInputBindings> | undefined;
function inputBindings() { return input ??= createInputBindings(); }

export function readInputState(): InputState {
    if (process.platform !== 'win32') return { available: false, controlHeld: false, primaryDown: false, secondaryDown: false };
    const native = inputBindings();
    return inputFromKeys(native.key, native.metric(23) !== 0);
}

export function readReducedMotion(): boolean {
    if (process.platform !== 'win32') return false;
    const value = [1];
    return reducedMotionFromSetting(Boolean(inputBindings().preference(0x1042, 0, value, 0)), value[0]);
}

/** Run in the icon worker: COM extraction may load third-party shell extensions. */
export function extractShellIcon(filePath: string): ShellBitmap | null {
    if (process.platform !== 'win32') return null;
    const ole = koffi.load('ole32.dll');
    const shell = koffi.load('shell32.dll');
    const gdi = koffi.load('gdi32.dll');
    const user = koffi.load('user32.dll');
    const initialize = ole.func('int32_t __stdcall CoInitializeEx(void *reserved, uint32_t flags)');
    const uninitialize = ole.func('void __stdcall CoUninitialize()');
    const create = shell.func('int32_t __stdcall SHCreateItemFromParsingName(str16 path, void *context, const void *iid, _Out_ void **result)');
    const deleteObject = gdi.func('int __stdcall DeleteObject(void *object)');
    const getObject = gdi.func('int __stdcall GetObjectW(void *object, int count, _Out_ void *data)');
    const getDC = user.func('void * __stdcall GetDC(void *window)');
    const releaseDC = user.func('int __stdcall ReleaseDC(void *window, void *dc)');
    const getBits = gdi.func('int __stdcall GetDIBits(void *dc, void *bitmap, uint32_t first, uint32_t lines, _Out_ void *pixels, _Inout_ void *info, uint32_t usage)');
    const size = koffi.struct({ cx: 'int32_t', cy: 'int32_t' });
    const getImage = koffi.proto('__stdcall', 'int32_t', ['void *', size, 'uint32_t', koffi.out('void **')]);
    const release = koffi.proto('__stdcall', 'uint32_t', ['void *']);
    const iid = Buffer.from('798bc1bc16ba2f4480c48a59c30c463b', 'hex');
    const initialized = initialize(null, 2) >= 0;
    let instance: unknown = null;
    let bitmap: unknown = null;
    let dc: unknown = null;
    try {
        const result = [null];
        if (create(filePath, null, iid, result) < 0 || !result[0]) return null;
        instance = result[0];
        const table = koffi.decode(instance, 'void *');
        const imageMethod = koffi.decode(table, 3 * koffi.sizeof('void *'), 'void *');
        const handle = [null];
        if (koffi.call(imageMethod, getImage, instance, { cx: 256, cy: 256 }, 0x05, handle) < 0 || !handle[0]) return null;
        bitmap = handle[0];
        const description = Buffer.alloc(32);
        if (!getObject(bitmap, description.length, description)) return null;
        const width = description.readInt32LE(4);
        const height = Math.abs(description.readInt32LE(8));
        if (width < 1 || height < 1 || width > 2048 || height > 2048) return null;
        const info = Buffer.alloc(44);
        info.writeUInt32LE(40, 0);
        info.writeInt32LE(width, 4);
        info.writeInt32LE(-height, 8);
        info.writeUInt16LE(1, 12);
        info.writeUInt16LE(32, 14);
        const pixels = Buffer.alloc(width * height * 4);
        dc = getDC(null);
        if (!dc || getBits(dc, bitmap, 0, height, pixels, info, 0) !== height) return null;
        return { width, height, pixels };
    } catch {
        return null; // Electron's file-icon service remains available as fallback.
    } finally {
        if (dc) releaseDC(null, dc);
        if (bitmap) deleteObject(bitmap);
        if (instance) {
            const table = koffi.decode(instance, 'void *');
            koffi.call(koffi.decode(table, 2 * koffi.sizeof('void *'), 'void *'), release, instance);
        }
        if (initialized) uninitialize();
    }
}

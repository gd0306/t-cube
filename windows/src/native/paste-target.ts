import koffi from 'koffi';
export interface PasteWindowInfo { processId: number; threadId: number; processIdentity: string }
export interface PasteTarget extends PasteWindowInfo { window: bigint; focus: bigint }
/** Boundary permits deterministic policy tests without sending input or launching apps. */
export interface PasteBindings {
    foreground(): bigint;
    windowInfo(window: bigint): PasteWindowInfo | null;
    focus(threadId: number): bigint;
    belongsTo(window: bigint, focus: bigint): boolean;
    restore(window: bigint): boolean;
    sendPaste(): boolean;
    ownProcessId: number;
}
export function createPasteController(native: PasteBindings, pause: (milliseconds: number) => Promise<void> = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds))) {
    let generation = 0;
    function same(target: PasteTarget): boolean {
        const info = native.windowInfo(target.window);
        return Boolean(info && info.processId === target.processId && info.threadId === target.threadId && info.processIdentity === target.processIdentity
            && info.processId !== native.ownProcessId && native.focus(info.threadId) === target.focus && native.belongsTo(target.window, target.focus));
    }
    return {
        capture(): PasteTarget | null {
            generation++;
            try {
                const window = native.foreground(), info = native.windowInfo(window);
                if (!window || !info || info.processId === native.ownProcessId) return null;
                const focus = native.focus(info.threadId);
                if (!focus || !native.belongsTo(window, focus)) return null;
                return { ...info, window, focus };
            } catch { return null; }
        },
        async paste(target: PasteTarget | null, canPaste: () => boolean = () => true): Promise<boolean> {
            const request = ++generation;
            try {
                if (!target || !canPaste() || !same(target) || !native.restore(target.window)) return false;
                for (let attempt = 0; attempt < 20; attempt++) {
                    if (request !== generation || !canPaste() || !same(target)) return false;
                    if (native.foreground() === target.window) {
                        // Recheck immediately before one batch. No Enter or submit event is generated.
                        return same(target) && native.foreground() === target.window && canPaste() && native.sendPaste();
                    }
                    await pause(25);
                }
            } catch { /* Clipboard remains available when Windows denies access. */ }
            return false;
        }
    };
}
function createWindowsBindings(): PasteBindings {
    const user = koffi.load('user32.dll'), kernel = koffi.load('kernel32.dll');
    const foreground = user.func('uintptr_t __stdcall GetForegroundWindow()');
    const isWindow = user.func('int __stdcall IsWindow(uintptr_t window)');
    const child = user.func('int __stdcall IsChild(uintptr_t parent, uintptr_t child)');
    const threadProcess = user.func('uint32_t __stdcall GetWindowThreadProcessId(uintptr_t window, _Out_ uint32_t *process)');
    const guiInfo = user.func('int __stdcall GetGUIThreadInfo(uint32_t thread, _Inout_ void *info)');
    const iconic = user.func('int __stdcall IsIconic(uintptr_t window)');
    const show = user.func('int __stdcall ShowWindow(uintptr_t window, int command)');
    const activate = user.func('int __stdcall SetForegroundWindow(uintptr_t window)');
    const key = user.func('int16_t __stdcall GetAsyncKeyState(int key)');
    const send = user.func('uint32_t __stdcall SendInput(uint32_t count, void *events, int size)');
    const openProcess = kernel.func('uintptr_t __stdcall OpenProcess(uint32_t access, int inherit, uint32_t process)');
    const close = kernel.func('int __stdcall CloseHandle(uintptr_t handle)');
    const times = kernel.func('int __stdcall GetProcessTimes(uintptr_t process, _Out_ void *created, _Out_ void *exit, _Out_ void *kernel, _Out_ void *user)');
    const pointerSize = koffi.sizeof('void *');
    const handle = (value: number | bigint): bigint => BigInt(value);
    return {
        ownProcessId: process.pid,
        foreground: () => handle(foreground()),
        windowInfo(window) {
            if (!window || !isWindow(window)) return null;
            const id = [0], threadId = threadProcess(window, id);
            if (!threadId || !id[0]) return null;
            const processHandle = openProcess(0x1000, 0, id[0]);
            if (!processHandle) return null;
            try {
                const created = Buffer.alloc(8);
                if (!times(processHandle, created, Buffer.alloc(8), Buffer.alloc(8), Buffer.alloc(8))) return null;
                return { processId: id[0], threadId, processIdentity: `${id[0]}:${created.toString('hex')}` };
            } finally { close(processHandle); }
        },
        focus(threadId) {
            const buffer = Buffer.alloc(pointerSize === 8 ? 72 : 48);
            buffer.writeUInt32LE(buffer.length);
            if (!guiInfo(threadId, buffer)) return 0n;
            return pointerSize === 8 ? buffer.readBigUInt64LE(16) : BigInt(buffer.readUInt32LE(12));
        },
        belongsTo: (window, focus) => Boolean(focus && isWindow(focus) && (window === focus || child(window, focus))),
        restore(window) {
            if (iconic(window)) show(window, 9);
            return Boolean(activate(window)) || handle(foreground()) === window;
        },
        sendPaste() {
            // Held modifiers can change Ctrl+V semantics; fall back to copied text.
            if ([0x10, 0x11, 0x12, 0x5b, 0x5c].some(code => (key(code) & 0x8000) !== 0)) return false;
            const size = pointerSize === 8 ? 40 : 28, offset = pointerSize === 8 ? 8 : 4;
            const events = Buffer.alloc(size * 4);
            [[0x11, 0], [0x56, 0], [0x56, 2], [0x11, 2]].forEach(([virtualKey, flags], index) => {
                events.writeUInt32LE(1, size * index);
                events.writeUInt16LE(virtualKey, size * index + offset);
                events.writeUInt32LE(flags, size * index + offset + 4);
            });
            return send(4, events, size) === 4;
        }
    };
}
let controller: ReturnType<typeof createPasteController> | undefined;
function windowsController() { return controller ??= createPasteController(createWindowsBindings()); }
export function capturePasteTarget(): PasteTarget | null {
    if (process.platform !== 'win32') return null;
    try { return windowsController().capture(); } catch { return null; }
}
export async function pasteToTarget(target: PasteTarget | null, canPaste?: () => boolean): Promise<boolean> {
    if (process.platform !== 'win32') return false;
    try { return await windowsController().paste(target, canPaste); } catch { return false; }
}

let clipboardSequence: (() => number) | undefined;
export function clipboardSequenceNumber(): number | null {
    if (process.platform !== 'win32') return null;
    try {
        clipboardSequence ??= koffi.load('user32.dll').func('uint32_t __stdcall GetClipboardSequenceNumber()');
        const sequence = clipboardSequence();
        return sequence || null;
    } catch { return null; }
}

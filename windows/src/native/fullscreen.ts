import koffi from 'koffi';
import { isFullscreenOnDisplay } from '../core/desktop-presentation';
import type { Rect } from '../shared/contracts';
export interface FullscreenWindow {window: bigint; processId: number; visible: boolean; minimized: boolean; className: string; style: number; extendedStyle?: number; cloaked?: boolean; frame: Rect}
/** A maximized, decorated window and the desktop/taskbar are not application fullscreen. */
export function fullscreenCandidate(window: FullscreenWindow | null, ownProcess: number): Rect | null {
    if (!window?.window || !window.processId || window.processId === ownProcess || !window.visible || window.minimized
        || ['Progman','WorkerW','Shell_TrayWnd','Shell_SecondaryTrayWnd'].includes(window.className) || (window.style & 0x00c00000) !== 0) return null;
    return window.frame;
}
function normalForeignWindow(window: FullscreenWindow, ownProcess: number): boolean {
    return Boolean(window.window && window.processId && window.processId !== ownProcess && window.visible && !window.minimized && !window.cloaked
        && !['Progman','WorkerW','Shell_TrayWnd','Shell_SecondaryTrayWnd'].includes(window.className) && ((window.extendedStyle ?? 0) & (0x80 | 0x08000000)) === 0);
}
/** Window order is native Z order. Activity on another display cannot mask this display's fullscreen app. */
export function fullscreenWindowOnDisplay(windows: FullscreenWindow[], display: Rect, ownProcess: number): Rect | null {
    const top = windows.find(window => normalForeignWindow(window, ownProcess) && window.frame.x < display.x + display.width && window.frame.x + window.frame.width > display.x
        && window.frame.y < display.y + display.height && window.frame.y + window.frame.height > display.y);
    const candidate = top ? fullscreenCandidate(top, ownProcess) : null;
    return isFullscreenOnDisplay(candidate, display) ? candidate : null;
}
function createBindings() {
    const user = koffi.load('user32.dll'), dwm = koffi.load('dwmapi.dll');
    return {
        top: user.func('uintptr_t __stdcall GetTopWindow(uintptr_t parent)'),
        next: user.func('uintptr_t __stdcall GetWindow(uintptr_t window, uint32_t command)'),
        cloaked: dwm.func('int32_t __stdcall DwmGetWindowAttribute(uintptr_t window, uint32_t attribute, _Out_ uint32_t *value, uint32_t size)'),
        process: user.func('uint32_t __stdcall GetWindowThreadProcessId(uintptr_t window, _Out_ uint32_t *process)'),
        visible: user.func('int __stdcall IsWindowVisible(uintptr_t window)'),
        minimized: user.func('int __stdcall IsIconic(uintptr_t window)'),
        rect: user.func('int __stdcall GetWindowRect(uintptr_t window, _Out_ void *rect)'),
        className: user.func('int __stdcall GetClassNameW(uintptr_t window, _Out_ void *name, int length)'),
        style: user.func('int32_t __stdcall GetWindowLongW(uintptr_t window, int index)'),
    };
}
let bindings: ReturnType<typeof createBindings> | undefined;
/** Public Z-order/window metadata only; unavailable information safely means no auto-hide. */
export function fullscreenFrameOnDisplay(display: Rect): Rect | null {
    if (process.platform !== 'win32') return null;
    try {
        const native = bindings ??= createBindings(), visited = new Set<bigint>();
        let window = BigInt(native.top(0));
        while (window && !visited.has(window) && visited.size < 512) {
            visited.add(window);
            const processId = [0], rect = Buffer.alloc(16), name = Buffer.alloc(512), cloaked = [0];
            if (native.visible(window) && !native.minimized(window) && native.process(window,processId) && processId[0] !== process.pid && native.rect(window,rect)) {
                const frame = {x:rect.readInt32LE(0),y:rect.readInt32LE(4),width:rect.readInt32LE(8)-rect.readInt32LE(0),height:rect.readInt32LE(12)-rect.readInt32LE(4)};
                if (frame.x < display.x + display.width && frame.x + frame.width > display.x && frame.y < display.y + display.height && frame.y + frame.height > display.y) {
                    const length = native.className(window,name,256);
                    if (length <= 0 || native.cloaked(window,14,cloaked,4) < 0) return null;
                    const info = {window,processId:processId[0],visible:true,minimized:false,cloaked:cloaked[0] !== 0,
                        className:name.toString('utf16le',0,length*2),style:native.style(window,-16),extendedStyle:native.style(window,-20),frame};
                    if (normalForeignWindow(info,process.pid)) return fullscreenWindowOnDisplay([info],display,process.pid);
                }
            }
            window = BigInt(native.next(window,2)); // GW_HWNDNEXT
        }
        return null;
    } catch { return null; }
}

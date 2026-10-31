import koffi from 'koffi';
import type { ElectronApplication, Page } from 'playwright';

/** Test-only event capture. Records element identity and coordinates, never text or window titles. */
export async function traceWidgetInput(widget: Page): Promise<void> {
    await widget.evaluate(() => {
        const events: unknown[] = [];
        (window as unknown as Record<string, unknown>).__tcubeInputTrace = events;
        for (const type of ['pointerdown', 'pointerup', 'pointercancel', 'pointermove', 'lostpointercapture', 'mousedown', 'mouseup', 'mousemove', 'click', 'mouseenter', 'mouseleave']) {
            document.addEventListener(type, event => {
                const mouse = event as MouseEvent, target = event.target instanceof Element ? event.target : null;
                events.push({ type, time: Date.now(), buttons: mouse.buttons, button: mouse.button, x: mouse.clientX, y: mouse.clientY,
                    trusted: event.isTrusted, target: target ? { tag: target.tagName, id: target.id, className: target.getAttribute('class') } : null });
                if (events.length > 80) events.shift();
            }, true);
        }
    });
}

export async function inputDiagnostics(application: ElectronApplication, widget: Page): Promise<unknown> {
    const electron = await application.evaluate(({ BrowserWindow, screen }) => ({
        cursorDIP: screen.getCursorScreenPoint(),
        windows: BrowserWindow.getAllWindows().map(window => ({
            id: window.id, role: /\/([^/]+)\.html$/.exec(window.webContents.getURL())?.[1] ?? 'unloaded',
            visible: window.isVisible(), focused: window.isFocused(), enabled: window.isEnabled(), modal: window.isModal(),
            bounds: window.getBounds(), handle: `0x${window.getNativeWindowHandle().readBigUInt64LE().toString(16)}`,
            parent: window.getParentWindow()?.id ?? null,
        })),
    }));
    const frame = electron.windows.find(window => window.role === 'widget')?.bounds;
    const point = frame ? { x: electron.cursorDIP.x - frame.x, y: electron.cursorDIP.y - frame.y } : { x: 0, y: 0 };
    const renderer = await widget.evaluate(point => {
        const hit = document.elementFromPoint(point.x, point.y), canvas = document.querySelector('canvas');
        return { localPoint: point, hidden: document.hidden, focused: document.hasFocus(), size: { width: innerWidth, height: innerHeight },
            hit: hit ? { tag: hit.tagName, id: hit.id, className: hit.getAttribute('class') } : null,
            canvas: canvas ? { rect: canvas.getBoundingClientRect().toJSON(), pointerEvents: getComputedStyle(canvas).pointerEvents } : null,
            events: (window as unknown as Record<string, unknown>).__tcubeInputTrace ?? [],
        };
    }, point);
    if (process.platform !== 'win32') return { electron, renderer };
    const user = koffi.load('user32.dll');
    const POINT = koffi.struct({ x: 'int32_t', y: 'int32_t' });
    const cursor = user.func('GetCursorPos', 'int', [koffi.out(koffi.pointer(POINT))]);
    const physicalCursor = user.func('GetPhysicalCursorPos', 'int', [koffi.out(koffi.pointer(POINT))]);
    const atPoint = user.func('WindowFromPoint', 'uintptr_t', [POINT]);
    const ancestor = user.func('uintptr_t __stdcall GetAncestor(uintptr_t window, uint32_t flags)');
    const foreground = user.func('uintptr_t __stdcall GetForegroundWindow()');
    const enabled = user.func('int __stdcall IsWindowEnabled(uintptr_t window)');
    const visible = user.func('int __stdcall IsWindowVisible(uintptr_t window)');
    const valid = user.func('int __stdcall IsWindow(uintptr_t window)');
    const owner = user.func('uintptr_t __stdcall GetWindow(uintptr_t window, uint32_t command)');
    const className = user.func('int __stdcall GetClassNameW(uintptr_t window, _Out_ void *name, int count)');
    const identity = user.func('uint32_t __stdcall GetWindowThreadProcessId(uintptr_t window, _Out_ uint32_t *pid)');
    const key = user.func('int16_t __stdcall GetAsyncKeyState(int key)');
    const metric = user.func('int __stdcall GetSystemMetrics(int index)');
    const style = user.func('intptr_t __stdcall GetWindowLongPtrW(uintptr_t window, int index)');
    function handle(value: number | bigint): string { return `0x${BigInt(value).toString(16)}`; }
    function windowInfo(value: number | bigint) {
        const pid = [0], text = Buffer.alloc(512);
        const exists = Boolean(value && valid(value));
        const thread = exists ? identity(value, pid) : 0;
        if (exists) className(value, text, 256);
        return { handle: handle(value), exists, enabled: exists && Boolean(enabled(value)), visible: exists && Boolean(visible(value)),
            pid: pid[0], thread, className: text.toString('utf16le').split('\0')[0], owner: exists ? handle(owner(value, 4)) : '0x0',
            style: exists ? handle(style(value, -16)) : '0x0', extendedStyle: exists ? handle(style(value, -20)) : '0x0' };
    }
    const nativePoint = { x: 0, y: 0 }, physicalPoint = { x: 0, y: 0 };
    cursor(nativePoint); physicalCursor(physicalPoint);
    const hit = atPoint(nativePoint), root = ancestor(hit, 2), rootOwner = ancestor(hit, 3), front = foreground();
    const swapped = Boolean(metric(23));
    return { electron, renderer, native: { cursor: nativePoint, physicalCursor: physicalPoint, hit: windowInfo(hit), root: windowInfo(root), rootOwner: windowInfo(rootOwner), foreground: windowInfo(front),
        input: { swapped, primaryDown: Boolean(key(swapped ? 2 : 1) & 0x8000), secondaryDown: Boolean(key(swapped ? 1 : 2) & 0x8000), controlHeld: Boolean(key(0x11) & 0x8000) },
        windows: electron.windows.map(window => ({ role: window.role, ...windowInfo(BigInt(window.handle)) })) } };
}

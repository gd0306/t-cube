import koffi from 'koffi';

/** Test-only native input: production reads OS state but never injects events. */
export function nativeInput() {
    if (process.platform === 'win32') {
        const user = koffi.load('user32.dll');
        const setCursor = user.func('int __stdcall SetCursorPos(int x, int y)');
        const send = user.func('uint32_t __stdcall SendInput(uint32_t count, const void *input, int size)');
        const metric = user.func('int __stdcall GetSystemMetrics(int index)');
        const dispatch = (packet: Buffer) => { if (send(1, packet, packet.length) !== 1) throw new Error('SendInput failed'); };
        return {
            move: (x: number, y: number) => { if (!setCursor(Math.round(x), Math.round(y))) throw new Error('SetCursorPos failed'); },
            control: (down: boolean) => {
                const packet = Buffer.alloc(40);
                packet.writeUInt32LE(1, 0); packet.writeUInt16LE(0x11, 8); packet.writeUInt32LE(down ? 0 : 2, 12);
                dispatch(packet);
            },
            button: (button: 0 | 2, down: boolean) => {
                const right = (button === 2) !== Boolean(metric(23));
                const packet = Buffer.alloc(40);
                packet.writeUInt32LE(right ? (down ? 8 : 16) : (down ? 2 : 4), 20);
                dispatch(packet);
            }
        };
    }
    if (process.platform === 'darwin') {
        const core = koffi.load('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
        const point = koffi.struct({ x: 'double', y: 'double' });
        const warp = core.func('CGWarpMouseCursorPosition', 'int32_t', [point]);
        return {
            move: (x: number, y: number) => { if (warp({ x, y }) !== 0) throw new Error('Cursor warp failed'); },
            control: (_down: boolean) => { throw new Error('Native Ctrl smoke is Windows-only'); },
            button: (_button: 0 | 2, _down: boolean) => { throw new Error('Native button smoke is Windows-only'); }
        };
    }
    throw new Error('Native input smoke requires Windows or a macOS preview session');
}

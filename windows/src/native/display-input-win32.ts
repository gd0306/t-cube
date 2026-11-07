import koffi from 'koffi';
import type { DisplayInputDriver, InputReading, PhysicalGroup } from './display-input';

type Handle = unknown;
function wide(buffer: Buffer, offset: number, length: number): string {
    const text = buffer.subarray(offset, offset + length * 2).toString('utf16le');
    return text.split('\0', 1)[0];
}
/** This driver must only be constructed inside a worker on Windows. */
export function createWindowsDisplayInputDriver(): DisplayInputDriver<Handle> {
    if (process.platform !== 'win32') throw new Error('Windows display input requires Windows');
    const user = koffi.load('user32.dll'); const dxva = koffi.load('dxva2.dll');
    const callback = koffi.proto('__stdcall', 'TCubeMonitorCallback', 'int', ['void *', 'void *', 'void *', 'void *']);
    const enumerate = user.func('EnumDisplayMonitors', 'int', ['void *', 'void *', koffi.pointer(callback), 'void *']);
    const info = user.func('int __stdcall GetMonitorInfoW(void *monitor, _Inout_ void *info)');
    const devices = user.func('int __stdcall EnumDisplayDevicesW(str16 device, uint32_t index, _Inout_ void *display, uint32_t flags)');
    const countPhysical = dxva.func('int __stdcall GetNumberOfPhysicalMonitorsFromHMONITOR(void *monitor, _Out_ uint32_t *count)');
    const getPhysical = dxva.func('int __stdcall GetPhysicalMonitorsFromHMONITOR(void *monitor, uint32_t count, _Out_ void *physical)');
    const destroy = dxva.func('int __stdcall DestroyPhysicalMonitor(void *monitor)');
    const destroyAll = dxva.func('int __stdcall DestroyPhysicalMonitors(uint32_t count, void *physical)');
    const get = dxva.func('int __stdcall GetVCPFeatureAndVCPFeatureReply(void *monitor, uint8_t code, _Out_ uint32_t *type, _Out_ uint32_t *current, _Out_ uint32_t *maximum)');
    const set = dxva.func('int __stdcall SetVCPFeature(void *monitor, uint8_t code, uint32_t value)');
    return createDisplayInputDriverFromBindings({ enumerate, info, devices, countPhysical, getPhysical, destroy, destroyAll, get, set, pointerSize: koffi.sizeof('void *'), decode: (buffer, offset) => koffi.decode(buffer, offset, 'void *') });
}
export interface Win32InputBindings {
    enumerate(dc: null, rect: null, callback: (monitor: Handle) => number, data: null): number;
    info(monitor: Handle, info: Buffer): number;
    devices(device: string, index: number, buffer: Buffer, flags: number): number;
    countPhysical(monitor: Handle, count: number[]): number;
    getPhysical(monitor: Handle, count: number, buffer: Buffer): number;
    destroy(handle: Handle): number; destroyAll(count: number, buffer: Buffer): number;
    get(handle: Handle, code: number, type: number[], current: number[], maximum: number[]): number;
    set(handle: Handle, code: number, value: number): number;
    pointerSize: number; decode(buffer: Buffer, offset: number): Handle;
}
/** Shared Win32 acquisition algorithm, with injectable bindings for ownership tests. */
export function createDisplayInputDriverFromBindings(bindings: Win32InputBindings): DisplayInputDriver<Handle> {
    const { enumerate, info, devices, countPhysical, getPhysical, destroy, destroyAll, get, set, pointerSize, decode } = bindings;
    return {
        enumerate(): PhysicalGroup<Handle>[] {
            const monitors: Handle[] = []; const groups: PhysicalGroup<Handle>[] = []; let overflow = false;
            if (!enumerate(null, null, (monitor: Handle) => { if (monitors.length < 32) monitors.push(monitor); else overflow = true; return 1; }, null) || overflow) throw new Error('Monitor enumeration failed or exceeded its limit');
            try {
                for (const monitor of monitors) {
                    const group: PhysicalGroup<Handle> = { identity: '', name: `显示器 ${groups.length + 1}`, handles: [] }; groups.push(group);
                    const monitorInfo = Buffer.alloc(104); monitorInfo.writeUInt32LE(104);
                    if (!info(monitor, monitorInfo)) continue;
                    const deviceName = wide(monitorInfo, 40, 32); group.name = deviceName || group.name; const found: string[] = [];
                    for (let index = 0; index <= 32; index++) {
                        const device = Buffer.alloc(840); device.writeUInt32LE(840);
                        if (!devices(deviceName, index, device, 1)) break;
                        if (index === 32) { found.push('overflow'); break; }
                        const identity = wide(device, 328, 128); if (identity) found.push(identity);
                    }
                    if (found.length === 1) group.identity = found[0];
                    const count = [0]; if (!countPhysical(monitor, count) || count[0] < 1 || count[0] > 16) continue;
                    const size = pointerSize + 256; const physical = Buffer.alloc(count[0] * size);
                    if (!getPhysical(monitor, count[0], physical)) continue;
                    const handles: Handle[] = [];
                    try { for (let i = 0; i < count[0]; i++) handles.push(decode(physical, i * size)); }
                    catch (error) { destroyAll(count[0], physical); throw error; }
                    group.handles = handles;
                    const name = wide(physical, pointerSize, 128);
                    if (name) group.name = `${name} · ${deviceName}`;
                }
                return groups;
            } catch (error) {
                for (const group of groups) for (const handle of group.handles) { try { destroy(handle); } catch {} }
                throw error;
            }
        },
        read(handle): InputReading | null { const type = [0], current = [0], maximum = [0]; return get(handle, 0x60, type, current, maximum) ? { current: current[0], maximum: maximum[0] } : null; },
        write(handle, value) { return Boolean(set(handle, 0x60, value)); },
        destroy(handle) { if (!destroy(handle)) throw new Error('Failed to release physical monitor handle'); },
        delay: () => new Promise(resolve => setTimeout(resolve, 1000))
    };
}

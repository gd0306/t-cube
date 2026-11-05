import test from 'node:test';
import assert from 'node:assert/strict';
import { createDisplayInputDriverFromBindings, type Win32InputBindings } from '../src/native/display-input-win32';
import { runDisplayInputJob } from '../src/native/display-input';
const identity = '\\\\?\\DISPLAY#IOCFFFF#instance#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}';
function bindings() {
    const released: number[] = []; const destroyedArrays: number[] = [];
    const native: Win32InputBindings = {
        enumerate: (_dc, _rect, callback) => { callback(1); callback(2); return 1; },
        info: (handle, buffer) => { assert.equal(buffer.readUInt32LE(), 104); buffer.write(`\\\\.\\DISPLAY${handle}\0`, 40, 'utf16le'); return 1; },
        devices: (name, index, buffer, flags) => { assert.equal(buffer.readUInt32LE(), 840); assert.equal(flags, 1); if (index) return 0; buffer.write(identity.replace('instance', name.endsWith('1') ? 'instance' : 'other') + '\0', 328, 'utf16le'); return 1; },
        countPhysical: (_handle, count) => { count[0] = 1; return 1; },
        getPhysical: (handle, count, buffer) => { assert.equal(count, 1); assert.equal(buffer.length, 264); buffer.writeBigUInt64LE(BigInt(handle as number)); buffer.write('Generic PnP\0', 8, 'utf16le'); return 1; },
        decode: (buffer, offset) => Number(buffer.readBigUInt64LE(offset)), pointerSize: 8,
        destroy: handle => { released.push(handle as number); return 1; }, destroyAll: count => { destroyedArrays.push(count); return 1; },
        get: (_h, _code, _type, current, maximum) => { current[0] = 5; maximum[0] = 14; return 1; }, set: () => 1, knownModel: () => false
    };
    return { native, released, destroyedArrays };
}
test('real acquisition algorithm extracts interface and logical display from Win32 buffers, then destroys every handle', async () => {
    const { native, released } = bindings(); const result = await runDisplayInputJob(createDisplayInputDriverFromBindings(native), { kind: 'list' });
    assert.equal(result.status, 'listed');
    if (result.status === 'listed') { assert.equal(result.displays.length, 2); assert.equal(result.displays[0].identity, identity.toLowerCase()); assert.match(result.displays[0].name, /DISPLAY1/); }
    assert.deepEqual(released, [1, 2]);
});
test('acquisition failures do not invent handles and decode failure releases full acquired array and earlier handles', () => {
    const first = bindings(); first.native.getPhysical = (handle) => Number(handle) === 1 ? 0 : 0;
    assert.deepEqual(createDisplayInputDriverFromBindings(first.native).enumerate(), []); assert.deepEqual(first.released, []);
    const second = bindings(); const decode = second.native.decode; let n = 0;
    second.native.decode = (buffer, offset) => { if (n++) throw new Error('decode failed'); return decode(buffer, offset); };
    assert.throws(() => createDisplayInputDriverFromBindings(second.native).enumerate(), /decode failed/);
    assert.deepEqual(second.released, [1]); assert.deepEqual(second.destroyedArrays, [1]);
});
test('multiple physical handles and duplicate interface paths are rejected with all handles released', async () => {
    const { native, released } = bindings();
    native.devices = (_name, index, buffer) => { if (index) return 0; buffer.write(identity + '\0', 328, 'utf16le'); return 1; };
    await assert.rejects(runDisplayInputJob(createDisplayInputDriverFromBindings(native), { kind: 'switch', identity, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' }), /ambiguous/);
    assert.deepEqual(released, [1, 2]);
});
test('one logical display with multiple physical handles is rejected and all handles are released', async () => {
    const { native, released } = bindings();
    native.enumerate = (_dc, _rect, callback) => { callback(1); return 1; };
    native.countPhysical = (_handle, count) => { count[0] = 2; return 1; };
    native.getPhysical = (_handle, count, buffer) => { assert.equal(count, 2); buffer.writeBigUInt64LE(10n, 0); buffer.writeBigUInt64LE(11n, 264); return 1; };
    await assert.rejects(runDisplayInputJob(createDisplayInputDriverFromBindings(native), { kind: 'switch', identity, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' }), /ambiguous/);
    assert.deepEqual(released, [10, 11]);
});

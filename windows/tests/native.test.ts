import assert from 'node:assert/strict';
import { test } from 'node:test';
import path from 'node:path';
import { inputFromKeys, reducedMotionFromSetting, readInputState, readReducedMotion, extractShellIcon } from '../src/native/win32.js';

test('Win32 button state respects high bit and swapped primary buttons', () => {
    const keys = new Map([[0x11, -32768], [0x01, 1], [0x02, -32767]]);
    const read = (key: number) => keys.get(key) ?? 0;
    assert.deepEqual(inputFromKeys(read, false), { available: true, controlHeld: true, primaryDown: false, secondaryDown: true });
    assert.deepEqual(inputFromKeys(read, true), { available: true, controlHeld: true, primaryDown: true, secondaryDown: false });
});

test('animation preferences invert correctly and failed query uses normal motion', () => {
    assert.equal(reducedMotionFromSetting(true, 0), true);
    assert.equal(reducedMotionFromSetting(true, 1), false);
    assert.equal(reducedMotionFromSetting(false, 0), false);
});

test('non-Windows preview does not load Win32 DLLs or return fabricated input', () => {
    if (process.platform === 'win32') return;
    assert.equal(readInputState().available, false);
    assert.equal(extractShellIcon('/nonexistent'), null);
});

test('Windows DLL input preferences and high resolution shell extraction work', { skip: process.platform !== 'win32' }, () => {
    assert.equal(readInputState().available, true);
    assert.equal(typeof readReducedMotion(), 'boolean');
    const icon = extractShellIcon(path.join(process.env.WINDIR!, 'explorer.exe'));
    assert.ok(icon, 'Explorer should supply a shell icon through IShellItemImageFactory');
    assert.ok(icon.width >= 48 && icon.height >= 48, 'Shell extraction should exceed the 32px Electron fallback');
    assert.equal(icon.pixels.length, icon.width * icon.height * 4);
    assert.ok(icon.pixels.some((value, index) => index % 4 === 3 && value > 0));
});

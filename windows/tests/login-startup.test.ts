import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LoginStartupController, LoginPreferenceStore, type LoginItemAdapter } from '../src/main/login-startup';

function fixture(saved: boolean | null = null, blocked = false) {
    let preference = saved, registered = blocked, enabled = false;
    const changes: boolean[] = [];
    const adapter: LoginItemAdapter = { get: () => ({ registered, enabled, blocked }), set: value => { changes.push(value); registered = value; enabled = value; } };
    const store = { read: async () => preference, write: async (value: boolean) => { preference = value; } };
    return { adapter, store, changes, get preference() { return preference; } };
}
test('new install enables once and a persisted opt-out never re-enables on a later launch', async () => {
    const h = fixture(); const first = new LoginStartupController(h.adapter, h.store);
    await Promise.all([first.start(), first.start()]); assert.equal(first.enabled, true); assert.equal(h.preference, true); assert.deepEqual(h.changes, [true]);
    await first.setEnabled(false); assert.equal(first.enabled, false); assert.equal(h.preference, false);
    await new LoginStartupController(h.adapter, h.store).start(); assert.deepEqual(h.changes, [true, false]);
});
test('system-disabled items and already initialized preferences never get an automatic enable write', async () => {
    for (const saved of [null, true, false]) {
        const h = fixture(saved, true), controller = new LoginStartupController(h.adapter, h.store);
        await controller.start(); assert.equal(controller.enabled, false); assert.deepEqual(h.changes, []);
        await assert.rejects(controller.setEnabled(true), /系统/); assert.deepEqual(h.changes, []); assert.match(controller.status, /系统/);
    }
});
test('an OS registration failure is visible and is not retried at every startup', async () => {
    const h = fixture(); let calls = 0;
    h.adapter.set = () => { calls++; throw Error('owned OS denied'); };
    const controller = new LoginStartupController(h.adapter, h.store);
    await controller.start(); assert.equal(controller.enabled, false); assert.match(controller.status, /owned OS denied/);
    await new LoginStartupController(h.adapter, h.store).start(); assert.equal(calls, 1);
});
test('unreadable preferences never touch login items and corrupt bytes are preserved', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-login-')), file = join(directory, 'login-startup.json');
    try {
        const store = new LoginPreferenceStore(file); assert.equal(await store.read(), null);
        await store.write(false); assert.equal(await new LoginPreferenceStore(file).read(), false);
        await writeFile(file, '{broken'); const corrupt = new LoginPreferenceStore(file), h = fixture();
        const controller = new LoginStartupController(h.adapter, corrupt); await controller.start();
        assert.deepEqual(h.changes, []); assert.match(controller.status, /设置/);
        await assert.rejects(controller.setEnabled(true)); assert.equal(await readFile(file, 'utf8'), '{broken');
    } finally { await rm(directory, { recursive: true, force: true }); }
});
